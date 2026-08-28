[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$candidates = [System.Collections.Generic.List[string]]::new()
if ($env:STARSOIL_GODOT_EXE) {
    $candidates.Add($env:STARSOIL_GODOT_EXE)
}

$cursor = [System.IO.DirectoryInfo](Resolve-Path -LiteralPath $ProjectRoot).Path
for ($level = 0; $level -lt 5 -and $null -ne $cursor; $level += 1) {
    $candidates.Add((Join-Path $cursor.FullName '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'))
    $cursor = $cursor.Parent
}

foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        (Resolve-Path -LiteralPath $candidate).Path
        exit 0
    }
}

throw 'Godot 4.7.2 console executable not found. Set STARSOIL_GODOT_EXE to its absolute path.'
