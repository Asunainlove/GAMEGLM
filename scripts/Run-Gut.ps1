[CmdletBinding()]
param(
    [switch]$IntentionalFailure
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$godotExe = & (Join-Path $PSScriptRoot 'Resolve-Godot.ps1') -ProjectRoot $projectRoot

& $godotExe --headless --path $projectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot import failed before GUT with exit code $LASTEXITCODE."
}

$gutArguments = @(
    '--headless',
    '--path', $projectRoot,
    '-s', 'res://addons/gut/gut_cmdln.gd',
    '-gexit'
)

if ($IntentionalFailure) {
    $gutArguments += '-gtest=res://tests/fixtures_fail/test_intentional_failure.gd'
} else {
    $gutArguments += '-gdir=res://tests/unit'
}

& $godotExe @gutArguments
exit $LASTEXITCODE
