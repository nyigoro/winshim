param(
  [Parameter(Mandatory = $true)]
  [string]$Image,
  [string]$ProbeRootPath = ""
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/strategy-constants.ps1"
. "$PSScriptRoot/common.ps1"

$basePath = if (-not [string]::IsNullOrWhiteSpace($ProbeRootPath)) { $ProbeRootPath } else { Get-RunnerTempPath }
$isolation = Get-WinShimIsolationMode
$probeRoot = Join-Path $basePath ".winshim-canary-$([guid]::NewGuid().ToString('N'))"
$probeInput = Join-Path $probeRoot "probe.in"
$probeOutput = Join-Path $probeRoot "probe.out"

New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
"probe-ok" | Set-Content -Path $probeInput -Encoding ASCII
Write-Host "Manifest probe isolation mode: $isolation"

$workspaceDriveMatch = [regex]::Match($basePath, "^(?<drive>[A-Za-z]):")
$workspaceDrive = if ($workspaceDriveMatch.Success) { $workspaceDriveMatch.Groups["drive"].Value.ToUpperInvariant() } else { "" }
$strategies = if ($workspaceDrive -eq "C") { $STRATEGY_PROBE_ORDER_C_DRIVE } else { $STRATEGY_PROBE_ORDER_NON_C_DRIVE }
Write-Host "Manifest probe strategy order: $($strategies -join ', ')"

$errors = New-Object System.Collections.Generic.List[string]
$selectedStrategy = $null

foreach ($strategy in $strategies) {
  if ($strategy -notin $STRATEGY_ALL) {
    Write-Error "Unknown strategy: $strategy. Update strategy-constants.ps1."
    exit 1
  }

  try {
    if (Test-Path $probeOutput) {
      Remove-Item -Path $probeOutput -Force
    }

    $mountSource = Convert-ToDockerSourcePath -WindowsPath $probeRoot -Strategy $strategy
    $containerCmd = "if (Test-Path 'C:\probe\probe.in') { Get-Content -Path 'C:\probe\probe.in' -Raw | Set-Content -Path 'C:\probe\probe.out' -Encoding ASCII; exit 0 } else { exit 4 }"

    docker run --rm `
      --isolation=$isolation `
      -v "${mountSource}:C:\probe" `
      $Image `
      powershell -NoLogo -NoProfile -Command $containerCmd

    if ($LASTEXITCODE -ne 0) {
      throw "docker run exited with code $LASTEXITCODE"
    }

    if (-not (Test-Path $probeOutput)) {
      throw "probe output was not written to the host bind-mount"
    }

    $output = Get-Content -Path $probeOutput -Raw
    if ($output -notmatch "probe-ok") {
      throw "probe output content mismatch"
    }

    $selectedStrategy = $strategy
    break
  } catch {
    $errors.Add("$strategy failed: $($_.Exception.Message)")
  }
}

if (Test-Path $probeRoot) {
  Remove-Item -Path $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($null -ne $selectedStrategy) {
  $label = Get-StrategyLabel -Strategy $selectedStrategy
  Write-GhaOutput -Name "strategy_mode" -Value $selectedStrategy
  Write-Host "Detected working mount strategy: $label"
  exit 0
}

Write-Host "::error::Manifest validator failed. No working volume escaping strategy detected."
foreach ($err in $errors) {
  Write-Host "::error::$err"
}
exit 1
