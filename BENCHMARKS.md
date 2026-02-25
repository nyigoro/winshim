# WinShim Benchmarks

Canonical benchmark record for WinShim.

## Environment

- Workflow: `.github/workflows/v0-benchmark.yml`
- Runner class: `windows-latest` (GitHub-hosted)
- Repetitions per scenario: `5`
- Scenario order: `baseline` then `winshim` (sequential isolation)
- Cache modes: `cold`, `warm`, `force-miss`
- Floating source tag: `mcr.microsoft.com/windows/nanoserver:ltsc2022`
- Pinned image: `mcr.microsoft.com/windows/nanoserver@sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6`
- Digest monitor workflow: `.github/workflows/nano-digest-check.yml`

## Run Ledger

| Date (UTC) | Run URL | Run Label | Cache State | Samples (B/W) | Baseline Mean (s) | WinShim Mean (s) | Ratio (B/W) | WinShim StdDev (s) | Excluded Warm Fallbacks | Volume Strategy | Image Digest | Notes |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|---|---|
| 2026-02-25 | [Run 12](https://github.com/nyigoro/winshim/actions/runs/22382207376) | `v0-cold-baseline` | `cold` | `5/5` | 24.49 | 55.85 | 0.44x | 13.72 | 0 | `drive-letter` | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | Controlled cold run; WinShim dominated by per-leg image load |
| 2026-02-25 | [Run 13](https://github.com/nyigoro/winshim/actions/runs/22382288112) | `v0-warm-baseline` | `warm` | `5/5` | 22.23 | 42.04 | 0.53x | 7.82 | 0 | `drive-letter` | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | Controlled warm run; cache-hit image load still dominant |
| _TBD_ | _TBD_ | `v0-warm-day2` | `warm` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | Warm recheck after ~48h |

## Aggregate Comparison Slots

| Comparison | Value | Notes |
|---|---:|---|
| Cold (`v0-cold-baseline`) Baseline/WinShim mean ratio | 0.44x | WinShim slower end-to-end in v0 architecture |
| Warm (`v0-warm-baseline`) Baseline/WinShim mean ratio | 0.53x | WinShim slower end-to-end in v0 architecture |
| Warm day-1 vs day-2 WinShim mean delta (s) | _TBD_ | Between-run stability indicator |
| Warm day-1 vs day-2 WinShim stddev delta (s) | _TBD_ | Runner pool variance check |

## Warm Image-Load Spread (Evidence of Contention)

| Run Label | Cache State | Per-leg `image_load_s` values | Mean (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| `v0-warm-baseline` | `warm` | `11.65, 12.40, 13.06, 13.50, 17.43` | 13.61 | 11.65 | 17.43 |

## Bottleneck Interpretation (v0)

WinShim v0 is currently net slower end-to-end on this workload because image load dominates total runtime.

- Image load: `13.61s` mean warm; dominant cost and amplified by five parallel cache reads.
- Container boot after load: implicit in warm boot total (`22.25s`); derived post-load boot is approximately `8.64s` (`22.25 - 13.61`). v1 should add a direct timer for this phase.
- Build execution: `19.80s` warm in WinShim versus `13.90s` warm in baseline (approximately `5.90s` overhead). This is acceptable as a process-isolation cost in v1 and a secondary optimization target in v2.

## v1 Hypothesis

Pre-load image once before matrix execution, then remove per-leg image load work from the timed path. Target improvement is to cut the dominant warm `image_load_s` component while keeping build execution behavior unchanged.

## Notes

- Warm-cache means should exclude rows where `load_source=registry-fallback`.
- If digest pin changes, record the new digest and mark first run using it.
- Link each run URL to the corresponding GitHub Actions run page.
