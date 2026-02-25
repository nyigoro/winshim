#!/usr/bin/env python3
import argparse
import json
import pathlib
import statistics
import sys
from typing import Dict, List, Optional

VALID_STRATEGIES = {"double-slash", "single-slash", "drive-letter"}
STRATEGY_LABELS = {
    "double-slash": "//<drive>/",
    "single-slash": "/<drive>/",
    "drive-letter": "<Drive>:/",
}


def load_rows(artifact_root: pathlib.Path, prefix: str) -> List[Dict]:
    rows: List[Dict] = []
    pattern = f"{prefix}-timing-*/*.json"
    for path in sorted(artifact_root.glob(pattern)):
        try:
            row = json.loads(path.read_text(encoding="utf-8"))
            scenario = row.get("scenario")
            if scenario not in (None, prefix):
                print(
                    f"warning: skipping {path}: scenario '{scenario}' does not match '{prefix}'",
                    file=sys.stderr,
                )
                continue
            rows.append(row)
        except Exception as exc:  # pragma: no cover
            print(f"warning: failed to parse {path}: {exc}", file=sys.stderr)
    rows.sort(key=lambda row: row.get("run_index", 0))
    return rows


def numeric_values(rows: List[Dict], key: str) -> List[float]:
    values: List[float] = []
    for row in rows:
        value = row.get(key)
        if isinstance(value, (int, float)):
            values.append(float(value))
    return values


def stats(values: List[float]) -> Dict[str, Optional[float]]:
    if not values:
        return {"mean": None, "median": None, "stddev": None, "min": None, "max": None}
    mean = sum(values) / len(values)
    median = statistics.median(values)
    stddev = statistics.pstdev(values) if len(values) > 1 else 0.0
    return {
        "mean": mean,
        "median": median,
        "stddev": stddev,
        "min": min(values),
        "max": max(values),
    }


def fmt(value: Optional[float]) -> str:
    return "N/A" if value is None else f"{value:.2f}"


def first_field(field: str, *rows_lists: List[Dict]) -> str:
    for rows in rows_lists:
        for row in rows:
            value = row.get(field)
            if value is not None and str(value) != "":
                return str(value)
    return "unknown"


def parse_optional_float(text: str) -> Optional[float]:
    if text is None:
        return None
    stripped = text.strip()
    if stripped == "":
        return None
    try:
        return float(stripped)
    except ValueError:
        return None


def render_report(
    baseline_rows: List[Dict],
    winshim_rows: List[Dict],
    expected_samples: int,
    shared_setup_override: Optional[float] = None,
) -> str:
    cache_state = first_field("cache_state", winshim_rows, baseline_rows)
    run_label = first_field("run_label", winshim_rows, baseline_rows)
    strategy_names = {
        str(row.get("volume_strategy"))
        for row in winshim_rows
        if row.get("volume_strategy") not in (None, "")
    }
    unknown_strategy_names = sorted(
        strategy_name
        for strategy_name in strategy_names
        if strategy_name not in VALID_STRATEGIES
    )
    volume_strategy_name = first_field("volume_strategy", winshim_rows)
    volume_strategy_label = STRATEGY_LABELS.get(volume_strategy_name, "unknown")

    excluded_fallback_rows: List[Dict] = []
    filtered_winshim_rows = list(winshim_rows)
    if cache_state == "warm":
        excluded_fallback_rows = [
            row for row in winshim_rows if row.get("load_source") == "registry-fallback"
        ]
        filtered_winshim_rows = [
            row for row in winshim_rows if row.get("load_source") != "registry-fallback"
        ]

    baseline_total = stats(numeric_values(baseline_rows, "total_s"))
    baseline_setup = stats(numeric_values(baseline_rows, "setup_s"))
    baseline_build = stats(numeric_values(baseline_rows, "build_only_s"))

    winshim_total = stats(numeric_values(filtered_winshim_rows, "total_s"))
    winshim_boot = stats(numeric_values(filtered_winshim_rows, "boot_s"))
    winshim_build = stats(numeric_values(filtered_winshim_rows, "build_only_s"))
    winshim_image_load = stats(numeric_values(filtered_winshim_rows, "image_load_s"))
    winshim_artifact_load = stats(numeric_values(filtered_winshim_rows, "artifact_load_s"))

    shared_setup_values = numeric_values(filtered_winshim_rows, "shared_setup_s")
    shared_setup = shared_setup_override
    if shared_setup is None and shared_setup_values:
        shared_setup = shared_setup_values[0]
    amortized_shared_setup = None
    if shared_setup is not None and len(filtered_winshim_rows) > 0:
        amortized_shared_setup = shared_setup / len(filtered_winshim_rows)

    ratio = "N/A"
    if baseline_total["mean"] and winshim_total["mean"] and winshim_total["mean"] > 0:
        ratio_value = baseline_total["mean"] / winshim_total["mean"]
        ratio = f"{ratio_value:.2f}x"

    warnings: List[str] = []
    if len(baseline_rows) < expected_samples:
        warnings.append(
            f"Baseline artifacts found: {len(baseline_rows)} of expected {expected_samples}."
        )
    if len(winshim_rows) < expected_samples:
        warnings.append(
            f"WinShim artifacts found: {len(winshim_rows)} of expected {expected_samples}."
        )
    if excluded_fallback_rows:
        warnings.append(
            "Excluded warm-cache fallback samples from WinShim averages: "
            f"{len(excluded_fallback_rows)} (load_source=registry-fallback)."
        )
    if unknown_strategy_names:
        warnings.append(
            "Unrecognized strategy names in timing data: "
            + ", ".join(f"`{name}`" for name in unknown_strategy_names)
            + "."
        )
    if shared_setup_values:
        unique_shared_setup = {round(value, 4) for value in shared_setup_values}
        if len(unique_shared_setup) > 1:
            warnings.append(
                "Inconsistent shared setup values in WinShim timing rows: "
                + ", ".join(f"{value:.2f}" for value in sorted(unique_shared_setup))
                + "."
            )

    lines: List[str] = []
    lines.append("## WinShim v0 Benchmark Results")
    lines.append("")
    lines.append(
        f"- Run label: `{run_label}` | Cache state: `{cache_state}` | Volume strategy: `{volume_strategy_label}` (`{volume_strategy_name}`)"
    )
    lines.append(
        f"- Sample count: baseline `{len(baseline_rows)}`, winshim total `{len(winshim_rows)}`, winshim used `{len(filtered_winshim_rows)}`"
    )
    if shared_setup is not None:
        lines.append(
            f"- WinShim shared setup (one-time): `{shared_setup:.2f}s` | Amortized per leg: `{fmt(amortized_shared_setup)}s`"
        )
    lines.append("")
    lines.append("### End-to-End Latency")
    lines.append("")
    lines.append("| Scenario | Mean (s) | Median (s) | Std Dev (s) | Min (s) | Max (s) |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    lines.append(
        f"| Baseline | {fmt(baseline_total['mean'])} | {fmt(baseline_total['median'])} | {fmt(baseline_total['stddev'])} | {fmt(baseline_total['min'])} | {fmt(baseline_total['max'])} |"
    )
    lines.append(
        f"| WinShim | {fmt(winshim_total['mean'])} | {fmt(winshim_total['median'])} | {fmt(winshim_total['stddev'])} | {fmt(winshim_total['min'])} | {fmt(winshim_total['max'])} |"
    )
    lines.append("")
    lines.append(f"**Baseline / WinShim mean ratio: {ratio}**")
    lines.append("")
    lines.append("### Phase Breakdown (Mean)")
    lines.append("")
    lines.append("| Phase | Baseline (s) | WinShim (s) |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| Shared setup (one-time) | N/A | {fmt(shared_setup)} |"
    )
    lines.append(
        f"| Shared setup amortized per leg | N/A | {fmt(amortized_shared_setup)} |"
    )
    lines.append(
        f"| Artifact load per leg | N/A | {fmt(winshim_artifact_load['mean'])} |"
    )
    lines.append(
        f"| Setup or boot | {fmt(baseline_setup['mean'])} | {fmt(winshim_boot['mean'])} |"
    )
    lines.append(
        f"| Image load only (setup job) | N/A | {fmt(winshim_image_load['mean'])} |"
    )
    lines.append(
        f"| Build execution only | {fmt(baseline_build['mean'])} | {fmt(winshim_build['mean'])} |"
    )
    lines.append("")
    lines.append("### Artifact Load (WinShim Per-Leg)")
    lines.append("")
    lines.append("| Mean (s) | Median (s) | Std Dev (s) | Min (s) | Max (s) |")
    lines.append("|---:|---:|---:|---:|---:|")
    lines.append(
        f"| {fmt(winshim_artifact_load['mean'])} | {fmt(winshim_artifact_load['median'])} | {fmt(winshim_artifact_load['stddev'])} | {fmt(winshim_artifact_load['min'])} | {fmt(winshim_artifact_load['max'])} |"
    )

    if warnings:
        lines.append("")
        lines.append("### Warnings")
        lines.append("")
        for warning in warnings:
            lines.append(f"- {warning}")

    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render WinShim benchmark summary markdown.")
    parser.add_argument("--artifacts", required=True, help="Path to downloaded artifacts directory")
    parser.add_argument(
        "--summary-file",
        required=True,
        help="Path to the GITHUB_STEP_SUMMARY file to append",
    )
    parser.add_argument(
        "--expected-samples",
        type=int,
        default=5,
        help="Expected sample count per scenario",
    )
    parser.add_argument(
        "--shared-setup-s",
        default="",
        help="Optional one-time shared setup seconds for WinShim.",
    )
    args = parser.parse_args()

    artifact_root = pathlib.Path(args.artifacts)
    baseline_rows = load_rows(artifact_root, "baseline")
    winshim_rows = load_rows(artifact_root, "winshim")
    shared_setup_override = parse_optional_float(args.shared_setup_s)
    report = render_report(
        baseline_rows,
        winshim_rows,
        args.expected_samples,
        shared_setup_override,
    )

    summary_file = pathlib.Path(args.summary_file)
    summary_file.parent.mkdir(parents=True, exist_ok=True)
    with summary_file.open("a", encoding="utf-8") as fh:
        fh.write(report)
        fh.write("\n")

    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
