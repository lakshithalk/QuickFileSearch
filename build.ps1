# Builds dist\QuickFileSearch.exe from QuickFileSearch.ps1 using the ps2exe module.
# Usage:  powershell -ExecutionPolicy Bypass -File .\build.ps1 [-Version 1.0.0.0]
param([string]$Version = '1.0.0.0')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host 'Installing ps2exe module (current user)...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

New-Item -ItemType Directory -Force (Join-Path $root 'dist') | Out-Null
$out = Join-Path $root 'dist\QuickFileSearch.exe'

Invoke-ps2exe -inputFile (Join-Path $root 'QuickFileSearch.ps1') -outputFile $out `
    -noConsole -STA -x64 `
    -title 'Quick File Search' `
    -description 'Small Windows file search tool with basic file type filters' `
    -product 'Quick File Search' `
    -version $Version

Write-Host "Built: $out"
