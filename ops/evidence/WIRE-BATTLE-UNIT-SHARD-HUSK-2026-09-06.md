# Evidence — wire battle SpriteFrames: shard_husk + veinwarden_echo

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-battle-unit-shard-husk`
- **Base**: `367419f` (origin/main — #42 veinwarden_echo v2 + #41 shard_husk v2)
- **PR**: #43 (same PR expanded per 幕僚长 scope update)

## Scope

Wire already-approved v2 full 8-frame battle sets into `BattleScene` presentation
for `shard_husk` and `veinwarden_echo`, matching the allowlist pattern from #38
(luoxian_fighter / misa_weaver / drift_swarmling). No gameplay expand; no
content-schema invent; no `.import` flood. Boss `lumen_leviathan` stays unwired.

## Units wired (production allowlist)

| unit_id | Frames (flat contract paths) | Size | Source tip |
|---------|------------------------------|------|------------|
| `shard_husk` | `assets/art/battle/units/shard_husk/shard_husk_{idle_00,idle_01,attack_00,attack_01,attack_02,hit_00,death_00,death_01}.png` | 128×128 | #41 `9486b73` |
| `veinwarden_echo` | `assets/art/battle/units/veinwarden_echo/veinwarden_echo_{same 8}.png` | 192×192 elite | #42 `367419f` |

## Still wired (unchanged from #38)

- `luoxian_fighter`
- `misa_weaver`
- `drift_swarmling`

## Not wired (remain graybox even if PNGs exist)

- `lumen_leviathan` (phase1/phase2 Boss)

## Architecture

Follows G6P-1 `AssetAdapter.sprite_frames("battle_<unit_id>", …)` drop-in:

- Frame contract: idle×2 / attack×3 / hit×1 / death×2 (A8 §2 / §7.1 flat names).
- Production gate: `BattleScene.WIRED_BATTLE_UNIT_IDS` — add `shard_husk` + `veinwarden_echo`.
- Elite 192×192: no extra scale factor — `unit_sprite_anchor_height` reads texture
  height so bottom-center anchor stays correct vs 128×128 normals.
- Injected `asset_base_dir` (unit tests) skips the allowlist so existing flat-path
  fixtures keep working.
- Enemy sprites `flip_h = true` (A8 facing).
- Intentional non-wired units do **not** count as “missing” for partial-asset warnings.

## Changes

- `src/encounters/battle_scene.gd` — allowlist adds `shard_husk`, `veinwarden_echo`.
- `tests/unit/test_encounters_battle_assets.gd` — production 8-frame includes both;
  allowlist asserts Sprite + flip_h; elite height 192; graybox probe → `lumen_leviathan`.
- `docs/plans/contracts/module-contracts.md` — battle Tracks presentation note.
- `ops/evidence/WIRE-BATTLE-UNIT-SHARD-HUSK-2026-09-06.md` — this note.

## Out of scope

`.import` commits; attack/hit/death one-shot playback choreography; Boss phase2
swap; lumen_leviathan wiring; schema/gameplay.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **725/725 PASS**, 11070 asserts, 10.13s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-shard-vein.log`
