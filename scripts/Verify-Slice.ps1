[CmdletBinding()]
param()

# WP15 RC slice gate (milestone G5/G7 preparation). Four gates, in order:
#   1. GUT unit suite (tests/unit) must pass.
#   2. Verify-Toolchain full gates must pass.
#   3. export_presets.cfg must exist and target Windows.
#   4. Best-effort headless export smoke: only attempted when the Godot
#      4.7.2.stable export templates are installed; otherwise SKIP and continue
#      (missing templates are an expected local limitation, not a gate failure).

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$powerShellExe = (Get-Process -Id $PID).Path
$exportPresetsPath = Join-Path $projectRoot 'export_presets.cfg'
$templatesDir = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable'

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-Gut.ps1')
$gutExitCode = $LASTEXITCODE
if ($gutExitCode -ne 0) {
    Write-Output "GATE1 GUT FAIL exit=$gutExitCode"
    Write-Output "VERIFY_SLICE_EXIT_CODE=$gutExitCode"
    exit $gutExitCode
}
Write-Output 'GATE1 GUT PASS exit=0'

& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-Toolchain.ps1')
$toolchainExitCode = $LASTEXITCODE
if ($toolchainExitCode -ne 0) {
    Write-Output "GATE2 TOOLCHAIN FAIL exit=$toolchainExitCode"
    Write-Output "VERIFY_SLICE_EXIT_CODE=$toolchainExitCode"
    exit $toolchainExitCode
}
Write-Output 'GATE2 TOOLCHAIN PASS exit=0'

if (-not (Test-Path -LiteralPath $exportPresetsPath -PathType Leaf)) {
    Write-Output 'GATE3 EXPORT_PRESETS FAIL export_presets.cfg is missing.'
    Write-Output 'VERIFY_SLICE_EXIT_CODE=1'
    exit 1
}
$presetsContent = (Get-Content -LiteralPath $exportPresetsPath -Raw)
if (-not $presetsContent.Contains('Windows')) {
    Write-Output 'GATE3 EXPORT_PRESETS FAIL no Windows preset found in export_presets.cfg.'
    Write-Output 'VERIFY_SLICE_EXIT_CODE=1'
    exit 1
}
Write-Output 'GATE3 EXPORT_PRESETS PASS Windows preset found in export_presets.cfg'

if (-not (Test-Path -LiteralPath $templatesDir)) {
    Write-Output "GATE4 EXPORT_SMOKE SKIP export templates not installed at '$templatesDir'."
    Write-Output 'GATE4 SKIP is an accepted expected limitation: install Godot 4.7.2.stable Win64 export templates to enable the export smoke.'
    Write-Output 'VERIFY_SLICE_EXIT_CODE=0'
    exit 0
}

$godotExe = & (Join-Path $PSScriptRoot 'Resolve-Godot.ps1') -ProjectRoot $projectRoot
$exportTarget = Join-Path $projectRoot 'build\starsoil\starsoil.exe'
$exportDir = Split-Path -Parent $exportTarget
if (-not (Test-Path -LiteralPath $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
}
& $godotExe --headless --path $projectRoot --export-release 'Windows' $exportTarget
$exportExitCode = $LASTEXITCODE
if ($exportExitCode -ne 0) {
    Write-Output "GATE4 EXPORT_SMOKE FAIL exit=$exportExitCode"
    Write-Output "VERIFY_SLICE_EXIT_CODE=$exportExitCode"
    exit $exportExitCode
}
Write-Output "GATE4 EXPORT_SMOKE PASS exit=0 target=$exportTarget"

Write-Output 'VERIFY_SLICE_EXIT_CODE=0'
exit 0
