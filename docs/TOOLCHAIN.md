# Toolchain Lock

- Engine: Godot `4.7.2-stable` Standard Win64
- Script: strongly typed GDScript
- Renderer: GL Compatibility
- Test framework: GUT `9.7.1`
- Content schema: JSON Schema Draft 2020-12
- Python validator: Python `3.13.x`, `jsonschema==4.25.0`
- Git LFS: enabled for PNG, WebP, WAV, and OGG

The engine is stored locally under `.tools/godot/` and is not committed. Minor engine upgrades require a dedicated ADR and full regression. Patch upgrades require import, test, save compatibility, and export smoke checks.

