param(
  [string]$ProjectDirectory = "benchmark-app"
)

Set-StrictMode -Version Latest

$projectRoot = Join-Path $PWD $ProjectDirectory
$projectFile = Join-Path $projectRoot "benchmark-app.csproj"
$programFile = Join-Path $projectRoot "Program.cs"

if (-not (Test-Path $projectRoot)) {
  New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
}

if (-not (Test-Path $projectFile)) {
  @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
'@ | Set-Content -Path $projectFile -Encoding UTF8
}

if (-not (Test-Path $programFile)) {
  @'
Console.WriteLine("winshim benchmark");
'@ | Set-Content -Path $programFile -Encoding UTF8
}

Write-Host "Prepared benchmark workload at $projectRoot"
