# Development Notes

## Windows Container Constraint

WinShim v0 benchmarks use Windows Process Isolation. Process isolation requires container OS build compatibility with the host kernel.

- Local host example: Windows 10 22H2 (`10.0.19045`)
- Benchmark image: Nano Server LTSC 2022 (`10.0.20348`)
- Result: local process-isolated runtime tests fail by design on this host/image mismatch.

This is expected and does not indicate a WinShim defect.

## Local Testing Override

For local script validation on desktop Windows, use Hyper-V isolation override:

```powershell
$env:WINSHIM_LOCAL_DEV = "true"
```

Optional explicit override:

```powershell
$env:WINSHIM_ISOLATION = "hyperv"   # allowed: hyperv, process
```

Behavior:

- Default isolation: `process`
- `WINSHIM_LOCAL_DEV=true`: uses `hyperv`
- `WINSHIM_ISOLATION`: explicit override, validated at runtime

If Hyper-V isolation still fails with host/image compatibility errors, use a Windows Server 2022 VM for runtime tests.

## Two-Tier Validation Model

1. Local validation:
- PowerShell parse checks
- Python compile checks
- Optional Hyper-V isolated script smoke tests

2. Real integration validation:
- Run `.github/workflows/v0-benchmark.yml` on GitHub-hosted `windows-latest` (Server 2022)
- Publish output in `BENCHMARKS.md`

Only GitHub-hosted runs are authoritative for benchmark performance numbers.

## Self-Hosted Runner Setup (Windows Server 2022)

Use `scripts/selfhosted/setup-selfhosted-runner.ps1` on the VM to provision Docker preflight, pinned image preload, and runner service registration.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\selfhosted\setup-selfhosted-runner.ps1 `
  -RepoUrl "https://github.com/nyigoro/winshim" `
  -RunnerRoot "C:\actions-runner" `
  -RunnerLabels "self-hosted,windows,x64" `
  -RunnerToken "<repo-runner-registration-token>"
```

Notes:

- Use the exact pinned image from the workflow:
  - `mcr.microsoft.com/windows/nanoserver@sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6`
- If Docker is currently in Linux mode, pass `-SwitchWindowsEngine`.
- If you only want Docker/image preflight and not runner registration yet, pass `-SkipRunnerRegistration`.
- After completion, confirm the runner appears as idle in GitHub `Settings -> Actions -> Runners`.
