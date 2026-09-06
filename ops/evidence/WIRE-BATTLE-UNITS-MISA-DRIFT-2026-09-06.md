# Evidence — wire battle SpriteFrames: luoxian_fighter + misa_weaver + drift_swarmling

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-battle-units-misa-drift`
- **Base**: `a8eaf9c` (origin/main — #37 luoxian_fighter v2 + #36 misa/drift v2)

## Scope

Wire already-approved v2 full 8-frame battle sets into `BattleScene` presentation
for three units only. No gameplay expand; no content-schema invent; no `.import`
flood.

## Units wired (production allowlist)

| unit_id | Frames (flat contract paths) | Source tip |
|---------|------------------------------|------------|
| `luoxian_fighter` | `assets/art/battle/units/luoxian_fighter/luoxian_fighter_{idle_00,idle_01,attack_00,attack_01,attack_02,hit_00,death_00,death_01}.png` | #37 `a8eaf9c` |
| `misa_weaver` | `assets/art/battle/units/misa_weaver/misa_weaver_{same 8}.png` | #36 `61a27e6` |
| `drift_swarmling` | `assets/art/battle/units/drift_swarmling/drift_swarmling_{same 8}.png` | #36 `61a27e6` |

## Not wired (remain graybox even if PNGs exist)

- `shard_husk`
- `veinwarden_echo`
- `lumen_leviathan` (phase1/phase2)

## Architecture

Follows G6P-1 `AssetAdapter.sprite_frames("battle_<unit_id>", …)` drop-in:

- Frame contract: idle×2 / attack×3 / hit×1 / death×2 (A8 §2 / §7.1 flat names).
- Production gate: `BattleScene.WIRED_BATTLE_UNIT_IDS` — only the three ids above
  replace graybox under `res://assets/art`.
- Injected `asset_base_dir` (unit tests) skips the allowlist so existing flat-path
  fixtures keep working.
- Enemy sprites `flip_h = true` (A8 facing).
- Intentional non-wired units do **not** count as “missing” for partial-asset warnings.

## Changes

- `src/encounters/battle_scene.gd` — allowlist + enemy flip_h + warning gate.
- `tests/unit/test_encounters_battle_assets.gd` — production 8-frame + allowlist tests.
- `docs/plans/contracts/module-contracts.md` — battle Tracks presentation note.

## Out of scope

`.import` commits; attack/hit/death one-shot playback choreography; Boss phase2
swap; swarmling hue-offset variants; schema/gameplay.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **725/725 PASS**, 11035 asserts, 10.28s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-battle-assets-only.log`
