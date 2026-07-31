#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SourceDir = (Split-Path $PSScriptRoot -Parent),
    [string]$ArtifactDir = ""
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Read-Utf8([string]$relativePath) {
    return [System.IO.File]::ReadAllText(
        (Join-Path $SourceDir $relativePath),
        [System.Text.Encoding]::UTF8
    )
}

$cmake = Read-Utf8 'flutter\windows\CMakeLists.txt'
$runner = Read-Utf8 'flutter\windows\runner\main.cpp'
$nativeModel = Read-Utf8 'flutter\lib\models\native_model.dart'
$workflow = Read-Utf8 '.github\workflows\sakura-win.yml'

Assert-True ($cmake -match 'RENAME SAKURA-Remote-Core\.dll') `
    'Windows bundle must install the core as SAKURA-Remote-Core.dll'
Assert-True ($runner -match 'LoadLibraryA\("SAKURA-Remote-Core\.dll"\)') `
    'Windows runner must load SAKURA-Remote-Core.dll'
Assert-True ($nativeModel -match "isWindows\s*\?\s*DynamicLibrary\.open\('SAKURA-Remote-Core\.dll'\)") `
    'Flutter Windows FFI must load SAKURA-Remote-Core.dll'
Assert-True ($workflow -notmatch 'usbmmidd_v2\.zip|printer_driver_v4|printer_driver_adapter\.zip') `
    'Basic Windows workflow must not download external driver packages'
Assert-True ($workflow -match 'SAKURA-Remote-basic-windows-\$\{\{ matrix\.job\.arch \}\}') `
    'CI artifact name must use only the SAKURA-Remote product name'
Assert-True ($workflow -match 'Move-Item.*rustdesk\.exe.*SAKURA-Remote\.exe') `
    'CI workflow must rename the executable before distribution checks'

if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $ArtifactDir 'SAKURA-Remote.exe')) `
        'Artifact is missing SAKURA-Remote.exe'
    Assert-True (Test-Path -LiteralPath (Join-Path $ArtifactDir 'SAKURA-Remote-Core.dll')) `
        'Artifact is missing SAKURA-Remote-Core.dll'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $ArtifactDir 'drivers'))) `
        'Basic artifact must not contain printer drivers'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $ArtifactDir 'usbmmidd_v2'))) `
        'Basic artifact must not contain virtual-display drivers'

    $forbiddenPaths = @(
        Get-ChildItem -LiteralPath $ArtifactDir -Force -Recurse |
            Where-Object { $_.Name -match '(?i)rustdesk|purslane' } |
            Select-Object -ExpandProperty FullName
    )
    Assert-True ($forbiddenPaths.Count -eq 0) `
        "Customer artifact contains forbidden names: $($forbiddenPaths -join ', ')"
}

Write-Host 'Windows distribution profile tests passed' -ForegroundColor Green
exit 0
