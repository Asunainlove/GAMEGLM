[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$godotExe = & (Join-Path $PSScriptRoot 'Resolve-Godot.ps1') -ProjectRoot $projectRoot
$powerShellExe = (Get-Process -Id $PID).Path

$version = (& $godotExe --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $version.StartsWith('4.7.2.stable')) {
    throw "Expected Godot 4.7.2.stable, received '$version'."
}
Write-Output "VERSION PASS $version"

& $godotExe --headless --path $projectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Headless import failed with exit code $LASTEXITCODE."
}
Write-Output 'IMPORT PASS exit=0'

& $godotExe --headless --path $projectRoot --quit-after 5
if ($LASTEXITCODE -ne 0) {
    throw "Headless main-scene smoke test failed with exit code $LASTEXITCODE."
}
Write-Output 'MAIN_SCENE PASS exit=0'

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-Gut.ps1')
$defaultTestsExitCode = $LASTEXITCODE
if ($defaultTestsExitCode -ne 0) {
    throw "Default GUT suite failed with exit code $defaultTestsExitCode."
}
Write-Output 'GUT_DEFAULT PASS exit=0'

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-Gut.ps1') -IntentionalFailure
$intentionalFailureExitCode = $LASTEXITCODE
if ($intentionalFailureExitCode -eq 0) {
    throw 'Intentional GUT failure unexpectedly returned exit code 0.'
}
Write-Output "GUT_FAILURE_FIXTURE PASS exit=$intentionalFailureExitCode"
