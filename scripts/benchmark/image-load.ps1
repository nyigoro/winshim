param(
  [Parameter(Mandatory = $true)]
  [string]$Image,
  [Parameter(Mandatory = $true)]
  [ValidateSet("warm", "cold", "force-miss")]
  [string]$CacheState,
  [string]$CacheHit = "",
  [string]$LayerTarPath = "$env:RUNNER_TEMP\nano-layers\nano.tar",
  [string]$LayerChecksumPath = "$env:RUNNER_TEMP\nano-layers\nano.tar.sha256"
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/common.ps1"

function Test-LayerCacheIntegrity {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TarPath,
    [Parameter(Mandatory = $true)]
    [string]$ChecksumPath
  )

  if (-not (Test-Path $TarPath)) {
    return @{ Valid = $false; Reason = "file-missing" }
  }

  $sizeBytes = (Get-Item $TarPath).Length
  if ($sizeBytes -eq 0) {
    return @{ Valid = $false; Reason = "zero-byte" }
  }

  if (Test-Path $ChecksumPath) {
    $storedChecksum = (Get-Content $ChecksumPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($storedChecksum)) {
      return @{ Valid = $false; Reason = "checksum-empty" }
    }

    $computedChecksum = (Get-FileHash -Path $TarPath -Algorithm SHA256).Hash
    if ($storedChecksum -ne $computedChecksum) {
      return @{ Valid = $false; Reason = "checksum-mismatch" }
    }
  }

  return @{ Valid = $true; Reason = "ok" }
}

function Remove-LayerCacheArtifacts {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TarPath,
    [Parameter(Mandatory = $true)]
    [string]$ChecksumPath
  )

  Remove-Item -Path $TarPath -Force -ErrorAction SilentlyContinue
  Remove-Item -Path $ChecksumPath -Force -ErrorAction SilentlyContinue
}

function Pull-ImageFromRegistry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImageName
  )

  docker pull $ImageName
  if ($LASTEXITCODE -ne 0) {
    throw "docker pull failed for image: $ImageName"
  }
}

function Save-ImageToCache {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImageName,
    [Parameter(Mandatory = $true)]
    [string]$TarPath,
    [Parameter(Mandatory = $true)]
    [string]$ChecksumPath
  )

  $layerDir = Split-Path -Parent $TarPath
  New-Item -ItemType Directory -Path $layerDir -Force | Out-Null

  docker save $ImageName -o $TarPath
  if ($LASTEXITCODE -ne 0) {
    throw "docker save failed for image: $ImageName"
  }

  $hash = (Get-FileHash -Path $TarPath -Algorithm SHA256).Hash
  Set-Content -Path $ChecksumPath -Value $hash -Encoding ASCII
}

$loadSource = "registry"
$shouldSaveCache = "false"
$integrityReason = "not-applicable"
$usedCacheCandidate = $false
$canUseWarmCache = $CacheState -eq "warm" -and (Test-Path $LayerTarPath)
$loadStartMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

if ($canUseWarmCache) {
  $usedCacheCandidate = $true
  $integrity = Test-LayerCacheIntegrity -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath
  $integrityReason = $integrity.Reason

  if ($integrity.Valid) {
    docker load -i $LayerTarPath
    if ($LASTEXITCODE -eq 0) {
      $loadSource = "cache"
    } else {
      $integrityReason = "docker-load-failed"
      Write-Host "::warning::WinShim image cache corrupted ($integrityReason) - falling back to registry pull for this run."

      Remove-LayerCacheArtifacts -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath
      Pull-ImageFromRegistry -ImageName $Image
      Save-ImageToCache -ImageName $Image -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath

      $loadSource = "registry-fallback"
      $shouldSaveCache = "true"
    }
  } else {
    Write-Host "::warning::WinShim image cache corrupted ($integrityReason) - falling back to registry pull for this run."

    Remove-LayerCacheArtifacts -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath
    Pull-ImageFromRegistry -ImageName $Image
    Save-ImageToCache -ImageName $Image -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath

    $loadSource = "registry-fallback"
    $shouldSaveCache = "true"
  }
} else {
  if ($CacheState -in @("cold", "force-miss")) {
    docker image rm --force $Image 2>$null | Out-Null
  }

  Pull-ImageFromRegistry -ImageName $Image

  if ($CacheState -ne "force-miss") {
    Save-ImageToCache -ImageName $Image -TarPath $LayerTarPath -ChecksumPath $LayerChecksumPath

    $shouldSaveCache = "true"
  }
}

$loadEndMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$loadSeconds = [math]::Round(($loadEndMs - $loadStartMs) / 1000, 2)
$loadSecondsText = $loadSeconds.ToString("0.00", [System.Globalization.CultureInfo]::InvariantCulture)

Write-GhaOutput -Name "load_source" -Value $loadSource
Write-GhaOutput -Name "image_load_s" -Value $loadSecondsText
Write-GhaOutput -Name "should_save_cache" -Value $shouldSaveCache
Write-GhaOutput -Name "layer_tar_path" -Value $LayerTarPath
Write-GhaOutput -Name "layer_checksum_path" -Value $LayerChecksumPath
Write-GhaOutput -Name "cache_hit" -Value $CacheHit
Write-GhaOutput -Name "cache_integrity_reason" -Value $integrityReason
Write-GhaOutput -Name "cache_candidate_present" -Value $usedCacheCandidate

Write-Host "Image source: $loadSource"
Write-Host "Image load seconds: $loadSecondsText"
