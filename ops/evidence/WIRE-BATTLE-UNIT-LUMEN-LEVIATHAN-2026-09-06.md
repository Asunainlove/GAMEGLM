# Evidence — wire battle SpriteFrames: lumen_leviathan (Boss phase1 + phase2)

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-battle-unit-lumen-leviathan`
- **Base**: `61da131` (origin/main — #44 lumen_leviathan v2 P1+P2 drop-in)
- **PR**: (pending)

## Scope

Wire already-approved v2 Boss dual-set (phase1/ + phase2/, 8 frames each) into
`BattleScene` presentation for `lumen_leviathan`, matching the allowlist pattern
from #38/#43. Phase switch uses existing CombatEngine `phase_index` +
`_rebuild_tracks` — no gameplay expand; no content-schema invent; no `.import`
flood.

## Unit wired (production allowlist)

| unit_id | Frames | Size | Source tip |
|---------|--------|------|------------|
| `lumen_leviathan` phase1 | `assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_{idle_00,idle_01,attack_00,attack_01,attack_02,hit_00,death_00,death_01}.png` | 256×256 | #44 `61da131` |
| `lumen_leviathan` phase2 | `…/phase2/` same 8 names | 256×256 | #44 `61da131` |

## Still wired (unchanged from #43)

- `luoxian_fighter`, `misa_weaver`, `drift_swarmling`, `shard_husk`, `veinwarden_echo`

## Architecture

- Frame contract: idle×2 / attack×3 / hit×1 / death×2 (A8 §2 / §7.1).
- Production gate: `BattleScene.WIRED_BATTLE_UNIT_IDS` — add `lumen_leviathan`.
- `AssetAdapter.sprite_frames(..., phase_subdir)` — optional `phase2` (or `phase1`)
  directory preference; default still probes flat then `phase1/`.
- Presentation: `phase_index < 0` → default/phase1; `phase_index >= 0` (after
  engine `phase_change`) → `phase_subdir=phase2` on `_rebuild_tracks`.
- Boss 256×256: anchor via `unit_sprite_anchor_height` (same as elite 192).
- Enemy `flip_h = true` (A8 facing).

## Changes

- `src/assets/asset_adapter.gd` — optional `phase_subdir` on `sprite_frames`.
- `src/encounters/battle_scene.gd` — allowlist + phase_index → phase2.
- `tests/unit/test_encounters_battle_assets.gd` — both phases resolve; allowlist
  wires Boss; remove graybox/未接线 asserts for lumen_leviathan.
- `tests/unit/test_asset_adapter.gd` — phase2 via `phase_subdir`.
- `docs/plans/contracts/module-contracts.md` — Tracks presentation note.
- `ops/evidence/WIRE-BATTLE-UNIT-LUMEN-LEVIATHAN-2026-09-06.md` — this note.

## Out of scope

`.import` commits; attack/hit/death one-shot playback choreography;
`fx_phase_burst` white-flash timing polish; schema/gameplay.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **727/727 PASS**, 11118 asserts, 11.42s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-lumen-leviathan.log`

