# Evidence — wire battle SpriteFrames: shard_husk

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-battle-unit-shard-husk`
- **Base**: `9486b73` (origin/main — #41 shard_husk v2 full 8-frame drop-in)

## Scope

Wire already-approved v2 full 8-frame battle set into `BattleScene` presentation
for `shard_husk` only, matching the allowlist pattern from #38
(luoxian_fighter / misa_weaver / drift_swarmling). No gameplay expand; no
content-schema invent; no `.import` flood.

## Unit wired (production allowlist)

| unit_id | Frames (flat contract paths) | Source tip |
|---------|------------------------------|------------|
| `shard_husk` | `assets/art/battle/units/shard_husk/shard_husk_{idle_00,idle_01,attack_00,attack_01,attack_02,hit_00,death_00,death_01}.png` | #41 `9486b73` |

## Still wired (unchanged from #38)

- `luoxian_fighter`
- `misa_weaver`
- `drift_swarmling`

## Not wired (remain graybox even if PNGs exist)

- `veinwarden_echo`
- `lumen_leviathan` (phase1/phase2)

## Architecture

Follows G6P-1 `AssetAdapter.sprite_frames("battle_<unit_id>", …)` drop-in:

- Frame contract: idle×2 / attack×3 / hit×1 / death×2 (A8 §2 / §7.1 flat names).
- Production gate: `BattleScene.WIRED_BATTLE_UNIT_IDS` — add `shard_husk`.
- Injected `asset_base_dir` (unit tests) skips the allowlist so existing flat-path
  fixtures keep working.
- Enemy sprites `flip_h = true` (A8 facing).
- Intentional non-wired units do **not** count as “missing” for partial-asset warnings.

## Changes

- `src/encounters/battle_scene.gd` — add `shard_husk` to `WIRED_BATTLE_UNIT_IDS`.
- `tests/unit/test_encounters_battle_assets.gd` — production 8-frame includes
  shard_husk; allowlist test asserts husk Sprite + flip_h; graybox probe moved
  to `veinwarden_echo`.
- `docs/plans/contracts/module-contracts.md` — battle Tracks presentation note.
- `ops/evidence/WIRE-BATTLE-UNIT-SHARD-HUSK-2026-09-06.md` — this note.

## Out of scope

`.import` commits; attack/hit/death one-shot playback choreography; Boss phase2
swap; veinwarden_echo / lumen_leviathan wiring; schema/gameplay.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **725/725 PASS**, 11052 asserts, 9.93s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-shard-husk.log`
