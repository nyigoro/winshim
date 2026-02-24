param(
  [Parameter(Mandatory = $true)]
  [string]$Image
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/strategy-constants.ps1"
. "$PSScriptRoot/common.ps1"

$tempRoot = Get-RunnerTempPath
$isolation = Get-WinShimIsolationMode
$probeRoot = Join-Path $tempRoot "winshim-canary-$([guid]::NewGuid().ToString('N'))"
$probeInput = Join-Path $probeRoot "probe.in"
$probeOutput = Join-Path $probeRoot "probe.out"

New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
"probe-ok" | Set-Content -Path $probeInput -Encoding ASCII
Write-Host "Manifest probe isolation mode: $isolation"

$strategies = $STRATEGY_ALL
$errors = New-Object System.Collections.Generic.List[string]

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
    $containerCmd = "type C:\probe\probe.in > C:\probe\probe.out"

    docker run --rm `
      --isolation=$isolation `
      -v "${mountSource}:C:\probe" `
      $Image `
      cmd /c $containerCmd

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

    $label = Get-StrategyLabel -Strategy $strategy
    Write-GhaOutput -Name "strategy_mode" -Value $strategy
    Write-Host "Detected working mount strategy: $label"
    exit 0
  } catch {
    $errors.Add("$strategy failed: $($_.Exception.Message)")
  }
}

Write-Host "::error::Manifest validator failed. No working volume escaping strategy detected."
foreach ($err in $errors) {
  Write-Host "::error::$err"
}
exit 1
