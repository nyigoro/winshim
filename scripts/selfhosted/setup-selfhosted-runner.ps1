param(
  [string]$RepoUrl = "https://github.com/nyigoro/winshim",
  [string]$RunnerRoot = "C:\actions-runner",
  [string]$RunnerName = "",
  [string]$RunnerLabels = "self-hosted,windows,x64",
  [string]$RunnerToken = "",
  [string]$NanoImage = "mcr.microsoft.com/windows/nanoserver@sha256:42f7526e855caf911bef2e05a3eb497497e4a6d431a37b216d7b345d5eee80c6",
  [string]$PreloadTag = "winshim-nano:preload",
  [switch]$SwitchWindowsEngine,
  [switch]$SkipRunnerRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
  param([string]$Text)
  Write-Host ""
  Write-Host "=== $Text ==="
}

function Ensure-DockerService {
  $service = Get-Service -Name docker -ErrorAction Stop
  if ($service.Status -ne "Running") {
    Write-Host "Starting Docker service..."
    Start-Service docker
  }

  $ready = $false
  for ($attempt = 1; $attempt -le 12; $attempt++) {
    docker version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      $ready = $true
      break
    }
    Start-Sleep -Seconds 5
  }

  if (-not $ready) {
    throw "Docker daemon is unavailable."
  }
}

function Ensure-WindowsDockerEngine {
  $dockerInfo = docker info 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "docker info failed:`n$($dockerInfo -join "`n")"
  }

  $osTypeLine = $dockerInfo | Where-Object { $_ -match "^\s*OSType:\s*" } | Select-Object -First 1
  if (-not $osTypeLine) {
    throw "Unable to determine Docker OSType from docker info output."
  }

  $osType = ($osTypeLine -split ":", 2)[1].Trim().ToLowerInvariant()
  Write-Host "Docker OSType: $osType"

  if ($osType -eq "windows") {
    return
  }

  if (-not $SwitchWindowsEngine) {
    throw "Docker is not in Windows container mode. Re-run with -SwitchWindowsEngine or switch manually."
  }

  $dockerCli = Join-Path $env:ProgramFiles "Docker\Docker\DockerCli.exe"
  if (-not (Test-Path $dockerCli)) {
    throw "DockerCli.exe not found at $dockerCli; cannot auto-switch engine."
  }

  Write-Host "Switching Docker to Windows engine..."
  & $dockerCli -SwitchWindowsEngine
  Start-Sleep -Seconds 8
  Ensure-DockerService

  $dockerInfoAfter = docker info 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "docker info failed after engine switch:`n$($dockerInfoAfter -join "`n")"
  }
  $osTypeAfterLine = $dockerInfoAfter | Where-Object { $_ -match "^\s*OSType:\s*" } | Select-Object -First 1
  $osTypeAfter = ($osTypeAfterLine -split ":", 2)[1].Trim().ToLowerInvariant()
  if ($osTypeAfter -ne "windows") {
    throw "Docker engine switch did not succeed. Current OSType: $osTypeAfter"
  }
}

function Validate-HostBuild {
  $build = (Get-ComputerInfo).OsBuildNumber
  Write-Host "Host OS build: $build"
  if ($build -ne "20348") {
    Write-Warning "Expected Windows Server 2022 build 20348 for ltsc2022 process isolation."
  }
}

function Prepare-PreloadedImage {
  param(
    [string]$ImageRef,
    [string]$Tag
  )

  Write-Host "Pulling pinned image: $ImageRef"
  docker pull $ImageRef
  if ($LASTEXITCODE -ne 0) {
    throw "docker pull failed for $ImageRef"
  }

  Write-Host "Tagging as $Tag"
  docker tag $ImageRef $Tag
  if ($LASTEXITCODE -ne 0) {
    throw "docker tag failed: $ImageRef -> $Tag"
  }

  $imageId = docker images -q $Tag
  if ([string]::IsNullOrWhiteSpace($imageId)) {
    throw "Tag verification failed. '$Tag' not found in local daemon."
  }

  Write-Host "Tagged image ID: $imageId"
  docker images $Tag

  $smoke = docker run --rm --isolation=process $Tag cmd /c "echo ok" 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Image smoke test failed:`n$($smoke -join "`n")"
  }

  if (-not ($smoke -join " " -match "\bok\b")) {
    Write-Warning "Smoke test did not print expected 'ok' token."
  } else {
    Write-Host "Image smoke test passed."
  }
}

function Get-LatestRunnerZipUrl {
  $release = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/actions/runner/releases/latest"
  $asset = $release.assets | Where-Object { $_.name -match "^actions-runner-win-x64-.*\.zip$" } | Select-Object -First 1
  if (-not $asset) {
    throw "Could not find Windows x64 runner asset in latest release."
  }
  return $asset.browser_download_url
}

function Install-RunnerService {
  param(
    [string]$Url,
    [string]$Root,
    [string]$Name,
    [string]$Labels,
    [string]$Token
  )

  if ([string]::IsNullOrWhiteSpace($Token)) {
    $secure = Read-Host "Enter GitHub runner registration token" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
      $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
  }

  if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "Runner registration token is required."
  }

  if (-not (Test-Path $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
  }

  $zipUrl = Get-LatestRunnerZipUrl
  $zipPath = Join-Path $Root "actions-runner-win-x64.zip"

  Write-Host "Downloading runner package..."
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

  Write-Host "Expanding runner package..."
  Expand-Archive -Path $zipPath -DestinationPath $Root -Force
  Remove-Item -Path $zipPath -Force

  Push-Location $Root
  try {
    if ([string]::IsNullOrWhiteSpace($Name)) {
      $Name = "winshim-" + $env:COMPUTERNAME.ToLowerInvariant()
    }

    Write-Host "Configuring runner '$Name' with labels '$Labels'..."
    & .\config.cmd `
      --unattended `
      --replace `
      --url $Url `
      --token $Token `
      --name $Name `
      --labels $Labels `
      --work "_work"
    if ($LASTEXITCODE -ne 0) {
      throw "config.cmd failed with exit code $LASTEXITCODE"
    }

    Write-Host "Installing runner service..."
    & .\svc.cmd install
    if ($LASTEXITCODE -ne 0) {
      throw "svc.cmd install failed with exit code $LASTEXITCODE"
    }

    Write-Host "Starting runner service..."
    & .\svc.cmd start
    if ($LASTEXITCODE -ne 0) {
      throw "svc.cmd start failed with exit code $LASTEXITCODE"
    }

    Write-Host "Runner service status:"
    & .\svc.cmd status
  } finally {
    Pop-Location
  }
}

Write-Section "Docker Preflight"
Ensure-DockerService
Ensure-WindowsDockerEngine
Validate-HostBuild

Write-Section "Pinned Image Preload"
Prepare-PreloadedImage -ImageRef $NanoImage -Tag $PreloadTag

if ($SkipRunnerRegistration) {
  Write-Section "Runner Registration Skipped"
  Write-Host "Docker and image preload setup completed."
  exit 0
}

Write-Section "GitHub Runner Registration"
Install-RunnerService `
  -Url $RepoUrl `
  -Root $RunnerRoot `
  -Name $RunnerName `
  -Labels $RunnerLabels `
  -Token $RunnerToken

Write-Section "Complete"
Write-Host "Self-hosted runner setup finished."
Write-Host "Verify the runner is idle in GitHub: Settings -> Actions -> Runners."
