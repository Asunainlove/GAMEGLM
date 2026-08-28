# Toolchain Lock

- Engine: Godot `4.7.2-stable` Standard Win64
- Script: strongly typed GDScript
- Renderer: GL Compatibility
- Test framework: GUT `9.7.1`
- Content schema: JSON Schema Draft 2020-12
- Python validator: Python `3.13.x`, `jsonschema==4.25.1`
- Git LFS: enabled for PNG, WebP, WAV, and OGG

The engine is stored locally under `.tools/godot-4.7.2/` and is not committed. Its upstream Win64 Standard archive SHA-256 is `731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953`. Minor engine upgrades require a dedicated ADR and full regression. Patch upgrades require import, test, save compatibility, and export smoke checks.

GUT is committed as an unmodified addon under `addons/gut/`. Its upstream `v9.7.1` archive SHA-256 is `14969AA46ADC84AA08CDD21B9F6D1A64ADDD92AE60B36F02D0521ED305AA4086`; provenance and license details are in `THIRD_PARTY_NOTICES.md`.

## Reproducible commands

Set `STARSOIL_GODOT_EXE` to the absolute path of the Godot console executable when the engine is not discoverable in an ancestor `.tools/godot-4.7.2/` directory.

```powershell
$env:STARSOIL_GODOT_EXE = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
pwsh -NoProfile -File .\scripts\Run-Gut.ps1
pwsh -NoProfile -File .\scripts\Verify-Toolchain.ps1
```

`Run-Gut.ps1` runs only `tests/unit/`. The deliberately failing fixture is isolated under `tests/fixtures_fail/` and runs only with `-IntentionalFailure`.

