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

# Precondition: input paths must be absolute Windows drive-letter paths.
# Convert-ToDockerSourcePath throws loudly if this precondition is violated.
$sdkMountSource = Convert-ToDockerSourcePath -WindowsPath $DotnetRoot -Strategy $StrategyMode
$workspaceMountSource = Convert-ToDockerSourcePath -WindowsPath $WorkspacePath -Strategy $StrategyMode
$projectPathInContainer = "C:\workspace\" + ($ProjectPath -replace "/", "\")

$buildCmd = "if not exist `"$projectPathInContainer`" (echo Missing project file: $projectPathInContainer & exit /b 3) && C:\hostdotnet\dotnet.exe build `"$projectPathInContainer`" -c Release"

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
