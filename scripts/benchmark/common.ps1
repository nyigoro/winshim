Set-StrictMode -Version Latest

. "$PSScriptRoot/strategy-constants.ps1"

function Write-GhaOutput {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Write-Host "$Name=$Value"
    return
  }

  Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
}

function Get-RunnerTempPath {
  if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    return $env:RUNNER_TEMP
  }

  if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
    return $env:TEMP
  }

  throw "Unable to resolve a temporary directory. Set RUNNER_TEMP or TEMP."
}

function Get-WinShimIsolationMode {
  $override = $env:WINSHIM_ISOLATION
  if (-not [string]::IsNullOrWhiteSpace($override)) {
    $normalized = $override.Trim().ToLowerInvariant()
    if ($normalized -in @("process", "hyperv")) {
      return $normalized
    }
    throw "Invalid WINSHIM_ISOLATION value '$override'. Expected 'process' or 'hyperv'."
  }

  if ($env:WINSHIM_LOCAL_DEV -eq "true") {
    return "hyperv"
  }

  return "process"
}

function Convert-ToDockerSourcePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath,
    [Parameter(Mandatory = $true)]
    [string]$Strategy
  )

  $normalized = $WindowsPath -replace "\\", "/"
  if ($normalized -notmatch "^(?<drive>[A-Za-z]):/?(?<tail>.*)$") {
    throw (
      "Expected a drive-letter Windows path (e.g. C:\foo), got: '$WindowsPath'. " +
      "Paths from `$env:GITHUB_WORKSPACE or `$env:RUNNER_TEMP should always match. " +
      "If you are passing a custom path, ensure it is absolute. " +
      "See: https://github.com/nyigoro/winshim/blob/main/docs/path-requirements.md"
    )
  }

  if ($Strategy -notin $STRATEGY_ALL) {
    throw "Unknown strategy '$Strategy'. Update strategy-constants.ps1."
  }

  $driveLower = $Matches["drive"].ToLowerInvariant()
  $driveUpper = $Matches["drive"].ToUpperInvariant()
  $tail = $Matches["tail"].TrimStart("/")

  switch ($Strategy) {
    $STRATEGY_DOUBLE_SLASH {
      if ([string]::IsNullOrEmpty($tail)) {
        return "//$driveLower/"
      }
      return "//$driveLower/$tail"
    }
    $STRATEGY_SINGLE_SLASH {
      if ([string]::IsNullOrEmpty($tail)) {
        return "/$driveLower/"
      }
      return "/$driveLower/$tail"
    }
    $STRATEGY_DRIVE_LETTER {
      if ([string]::IsNullOrEmpty($tail)) {
        return "$($driveUpper):/"
      }
      return "$($driveUpper):/$tail"
    }
    default {
      throw "Unsupported strategy: $Strategy"
    }
  }
}

function Get-StrategyLabel {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Strategy
  )

  if ($Strategy -notin $STRATEGY_ALL) {
    throw "Unknown strategy '$Strategy'. Update strategy-constants.ps1."
  }

  if (-not $STRATEGY_LABELS.ContainsKey($Strategy)) {
    throw "No label configured for strategy '$Strategy'. Update strategy-constants.ps1."
  }

  return [string]$STRATEGY_LABELS[$Strategy]
}
