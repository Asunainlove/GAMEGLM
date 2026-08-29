[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path

$pythonExe = $env:STARSOIL_PYTHON
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    $pythonExe = 'python'
}

$validatorScript = Join-Path $PSScriptRoot 'validate_content.py'
& $pythonExe $validatorScript
exit $LASTEXITCODE
