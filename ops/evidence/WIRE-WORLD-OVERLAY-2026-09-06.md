# Evidence — wire world overlay decals + Luoxian explore action frames

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-world-overlay-actions`
- **Base**: `f3bdbbd` (origin/main — art tip #31)

## Scope (观感 only)

Wire already-approved main assets into world Decals overlay + Player explore
action SpriteFrames. No new gameplay systems, mining/crack mechanics, content
schema, battle unit frames, or invented place/talk extra frames.

## Assets (exact `res://` paths)

| Role | Path |
|------|------|
| Idle 0/1 | `res://assets/art/characters/luoxian/actions/luoxian_action_idle_00.png` / `_idle_01.png` |
| Walk | `…/luoxian_action_walk_00.png` / `_walk_01.png` (already) |
| Mine 0..3 | `…/luoxian_action_mine_00.png` … `_mine_03.png` |
| Place | `…/luoxian_action_place_00.png` (single frame; no ART-019 invent) |
| Talk | `…/luoxian_action_talk_00.png` (single frame) |
| Soil damage | `res://assets/art/world/decals/env_world_soil_damage.png` |
| Ore fleck | `res://assets/art/world/decals/env_world_soil_ore_fleck.png` |
| Soil crack | `res://assets/art/world/decals/env_world_soil_crack.png` (visual-only sparse) |
| Rock wall | probe already prefers `world/tiles/env_world_rock_wall.png` (#29); verified + unit test |

## Changes

- `scenes/world.tscn`: add flat `Decals` Node2D between `Ground` and `OreOverlay`.
- `src/world/world.gd`: inject `Decals` into `WorldRenderer.decal_layer`.
- `src/world/world_renderer.gd`: sparse deterministic soil decals (damage/fleck/crack)
  via cell hash thresholds; `clear_layers` clears decals; no gameplay flags.
- `scenes/player.tscn`: extend SpriteFrames — idle×2, walk×2, mine×4, place×1, talk×1.
- `src/player/player_controller.gd`: one-shot action anim lock synced from existing
  `mine` / `place` / `interact` signals (`talk` ← interact). No new systems.
- Unit tests + `docs/plans/contracts/module-contracts.md` updated for Decals / frames.
- Rock-wall prefer probe covered by unit test (green path already on main).

## Out of scope

`.import` flood commits; LFS pointer junk; battle units; soil_crack mining logic;
inventing missing place/talk frames; content-schema / gameplay flags for decals.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **723/723 PASS**, 10991 asserts, 12.33s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-world-overlay.log`
