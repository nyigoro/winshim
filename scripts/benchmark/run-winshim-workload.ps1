param(
  [Parameter(Mandatory = $true)]
  [string]$Image,
  [Parameter(Mandatory = $true)]
  [string]$StrategyMode,
  [Parameter(Mandatory = $true)]
  [string]$DotnetRoot,
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,
  [string]$ProjectPath = "benchmark-app\benchmark-app.csproj",
  [string]$Cpu = "2.0",
  [string]$Memory = "512m"
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/strategy-constants.ps1"
. "$PSScriptRoot/common.ps1"

$isolation = Get-WinShimIsolationMode
Write-Host "WinShim workload isolation mode: $isolation"
$normalizedWorkspace = $WorkspacePath -replace "\\", "/"
if ($normalizedWorkspace -match "^/[a-zA-Z]/") {
  Write-Host "::error::Linux-style workspace paths are out of scope in WinShim v0."
  exit 1
}

if ($normalizedWorkspace -match "^[A-Za-z]:/.+:.+") {
  Write-Host "::error::Unsupported colon detected in workspace path: $WorkspacePath"
  exit 1
}

if ($StrategyMode -notin $STRATEGY_ALL) {
  Write-Host "::error::Unknown strategy mode '$StrategyMode'. Update strategy-constants.ps1."
  exit 1
}

# Fail before container launch if the expected project is absent on host.
$projectRelativePath = $ProjectPath -replace "/", "\"
$hostProjectPath = Join-Path $WorkspacePath $projectRelativePath
if (-not (Test-Path $hostProjectPath)) {
  Write-Host "::error::Host project file not found: $hostProjectPath"
  Write-Host "::error::Workspace path: $WorkspacePath"
  if (Test-Path $WorkspacePath) {
    Write-Host "Workspace listing:"
    Get-ChildItem -Path $WorkspacePath | Select-Object -First 30 | ForEach-Object { " - $($_.Name)" } | Write-Host
  }
  exit 2
}

# Precondition: input paths must be absolute Windows drive-letter paths.
# Convert-ToDockerSourcePath throws loudly if this precondition is violated.
$sdkMountSource = Convert-ToDockerSourcePath -WindowsPath $DotnetRoot -Strategy $StrategyMode
$workspaceMountSource = Convert-ToDockerSourcePath -WindowsPath $WorkspacePath -Strategy $StrategyMode
$projectPathInContainer = "C:\workspace\" + $projectRelativePath
Write-Host "Host workspace mount source: $workspaceMountSource"
Write-Host "Host SDK mount source: $sdkMountSource"
Write-Host "Container project path: $projectPathInContainer"

$preflightCheckCmd = "dir /b `"$projectPathInContainer`" >nul"

docker run --rm `
  --isolation=$isolation `
  --cpus $Cpu `
  --memory $Memory `
  -v "${sdkMountSource}:C:\hostdotnet:ro" `
  -v "${workspaceMountSource}:C:\workspace" `
  -w C:\workspace `
  -e "DOTNET_ROOT=C:\hostdotnet" `
  -e "PATH=C:\hostdotnet;C:\Windows\System32;C:\Windows" `
  $Image `
  cmd /c $preflightCheckCmd

if ($LASTEXITCODE -ne 0) {
  $preflightDiagCmd = "echo project-missing: $projectPathInContainer & echo workspace-listing: & dir C:\workspace & if exist C:\workspace\benchmark-app (echo benchmark-app-listing: & dir C:\workspace\benchmark-app)"

  docker run --rm `
    --isolation=$isolation `
    --cpus $Cpu `
    --memory $Memory `
    -v "${sdkMountSource}:C:\hostdotnet:ro" `
    -v "${workspaceMountSource}:C:\workspace" `
    -w C:\workspace `
    -e "DOTNET_ROOT=C:\hostdotnet" `
    -e "PATH=C:\hostdotnet;C:\Windows\System32;C:\Windows" `
    $Image `
    cmd /c $preflightDiagCmd

  Write-Host "::error::Workspace bind-mount preflight failed. Project not visible inside container."
  Write-Host "::error::Check detected mount strategy and host path translation."
  exit 3
}

$buildCmd = "C:\hostdotnet\dotnet.exe build `"$projectRelativePath`" -c Release"

docker run --rm `
  --isolation=$isolation `
  --cpus $Cpu `
  --memory $Memory `
  -v "${sdkMountSource}:C:\hostdotnet:ro" `
  -v "${workspaceMountSource}:C:\workspace" `
  -w C:\workspace `
  -e "DOTNET_ROOT=C:\hostdotnet" `
  -e "PATH=C:\hostdotnet;C:\Windows\System32;C:\Windows" `
  $Image `
  cmd /c $buildCmd

if ($LASTEXITCODE -ne 0) {
  Write-Host "::error::WinShim workload failed. Check host SDK compatibility and mount strategy."
  exit $LASTEXITCODE
}
