param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("baseline", "winshim")]
  [string]$Scenario,
  [Parameter(Mandatory = $true)]
  [int]$RunIndex,
  [Parameter(Mandatory = $true)]
  [string]$CacheState,
  [Parameter(Mandatory = $true)]
  [string]$RunLabel,
  [Parameter(Mandatory = $true)]
  [string]$TotalSeconds,
  [string]$SetupSeconds = "",
  [string]$BootSeconds = "",
  [Parameter(Mandatory = $true)]
  [string]$BuildSeconds,
  [string]$ImageLoadSeconds = "",
  [string]$ArtifactLoadSeconds = "",
  [string]$SharedSetupSeconds = "",
  [string]$LoadSource = "",
  [string]$CacheIntegrityReason = "",
  [string]$VolumeStrategy = "",
  [string]$OutputPath = "$env:RUNNER_TEMP\timing.json"
)

Set-StrictMode -Version Latest

function Parse-Number {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }
  return [double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

$total = Parse-Number -Value $TotalSeconds
$build = Parse-Number -Value $BuildSeconds
$setup = Parse-Number -Value $SetupSeconds
$boot = Parse-Number -Value $BootSeconds
$imageLoad = Parse-Number -Value $ImageLoadSeconds
$artifactLoad = Parse-Number -Value $ArtifactLoadSeconds
$sharedSetup = Parse-Number -Value $SharedSetupSeconds

$payload = [ordered]@{
  scenario = $Scenario
  run_index = $RunIndex
  cache_state = $CacheState
  run_label = $RunLabel
  total_s = $total
  build_only_s = $build
  runner_os = $env:RUNNER_OS
  timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

if ($null -ne $setup) {
  $payload["setup_s"] = $setup
}

if ($null -ne $boot) {
  $payload["boot_s"] = $boot
}

if ($null -ne $imageLoad) {
  $payload["image_load_s"] = $imageLoad
}

if ($null -ne $artifactLoad) {
  $payload["artifact_load_s"] = $artifactLoad
}

if ($null -ne $sharedSetup) {
  $payload["shared_setup_s"] = $sharedSetup
}

if (-not [string]::IsNullOrWhiteSpace($LoadSource)) {
  $payload["load_source"] = $LoadSource
}

if (-not [string]::IsNullOrWhiteSpace($CacheIntegrityReason)) {
  $payload["cache_integrity_reason"] = $CacheIntegrityReason
}

if (-not [string]::IsNullOrWhiteSpace($VolumeStrategy)) {
  $payload["volume_strategy"] = $VolumeStrategy
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$payload | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Timing JSON written to $OutputPath"
