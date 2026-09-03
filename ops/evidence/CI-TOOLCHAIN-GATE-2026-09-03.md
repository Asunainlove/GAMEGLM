# toolchain-gate failure diagnosis (2026-09-03)

## Symptom
Recent `main` pushes (batch1 env drop-in onward) fail `ci / toolchain-gate` with Default GUT suite exit code 1: **705/708** passing, **3 failing**.

Example runs: https://github.com/Asunainlove/GAMEGLM/actions/runs/33743513388

## Root cause (not LFS / Godot install)
Batch1 approved env art under `assets/art/world/` broke three **greybox-era** asserts that assumed the production tree had **no** formal art:

1. `tests/unit/test_asset_adapter.gd::test_texture_returns_null_for_missing_asset`
   - Asserted `ADAPTER.texture("env_world_soil_base")` is null (true only when asset absent).
2. `tests/unit/test_asset_adapter.gd::test_probe_reports_directory_existence`
   - Asserted `probe("res://assets/art")` is false.
3. `tests/unit/test_world_renderer.gd::test_build_tile_set_creates_five_32px_monochrome_sources`
   - Called `build_tile_set()` with default base dir; loaded atlas strips (160×32 / 384×32) instead of 32×32 monochrome fallbacks.

LFS for `assets/art/**/*.png` is working (pointers + objects). GUT vendor PNGs already excluded via `.gitattributes` (`addons/gut/**/*.png` as blobs). No missing LFS push was required for this failure mode.

## Fix
Isolate greybox contracts from production art presence:
- Missing-asset checks use unknown ids / empty `base_dir` / missing probe paths.
- Monochrome tileset test injects an empty `user://` `base_dir` so atlas art cannot leak in.

Shipped on branch `feat/ci-toolchain-fix` (same content as PR #6 `fix/gut-isolate-batch1-art`, which already went green on Actions).

## Status
Pending merge of this branch / PR #6 equivalent; expect 708/708 once merged to main.

## Follow-up (batch2 unit drop-in)
After merging greybox world isolation, batch2 `luoxian_fighter`/`misa_weaver` drop-in caused **707/708**:
`test_encounters_battle_scene.gd::test_begin_encounter_renders_graybox_units_and_ui` still required `ColorRect Box` on every unit. Allies with formal frames use `AnimatedSprite2D` (`Sprite`) instead. Fix: assert Box **or** Sprite; Label still required.
