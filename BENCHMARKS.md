# WinShim Benchmarks

Canonical benchmark record for WinShim.

## Environment

- Workflow: `.github/workflows/v0-benchmark.yml`
- Runner class: `windows-latest` (GitHub-hosted)
- Repetitions per scenario: `5`
- Scenario order: `baseline` then `winshim` (sequential isolation)
- Cache modes: `force-miss`, `warm`
- Floating source tag: `mcr.microsoft.com/windows/nanoserver:ltsc2022`
- Pinned image: `mcr.microsoft.com/windows/nanoserver@sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6`
- Digest monitor workflow: `.github/workflows/nano-digest-check.yml`

## Planned First Publication Sequence

1. `cache_state: force-miss`, `run_label: v0-cold-baseline`
2. `cache_state: warm`, `run_label: v0-warm-baseline`
3. `cache_state: warm`, `run_label: v0-warm-day2` (run ~48h later)

## Run Ledger

| Date (UTC) | Run URL | Run Label | Cache State | Samples (B/W) | Baseline Mean (s) | WinShim Mean (s) | Ratio (B/W) | WinShim StdDev (s) | Excluded Warm Fallbacks | Volume Strategy | Image Digest | Notes |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|---|---|
| _TBD_ | _TBD_ | `v0-cold-baseline` | `force-miss` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | First cold run; initializes cache |
| _TBD_ | _TBD_ | `v0-warm-baseline` | `warm` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | Primary warm benchmark |
| _TBD_ | _TBD_ | `v0-warm-day2` | `warm` | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | `sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6` | Warm recheck after ~48h |

## Aggregate Comparison Slots

| Comparison | Value | Notes |
|---|---:|---|
| Cold (`v0-cold-baseline`) Baseline/WinShim mean ratio | _TBD_ | Measures full cold-path improvement |
| Warm (`v0-warm-baseline`) Baseline/WinShim mean ratio | _TBD_ | Primary README figure |
| Warm day-1 vs day-2 WinShim mean delta (s) | _TBD_ | Between-run stability indicator |
| Warm day-1 vs day-2 WinShim stddev delta (s) | _TBD_ | Runner pool variance check |

## Notes

- Warm-cache means should exclude rows where `load_source=registry-fallback`.
- If digest pin changes, record the new digest and mark first run using it.
- Link each run URL to the corresponding GitHub Actions run page.
