# Evidence — wire title bg + Luoxian explore idle/walk

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-title-player-sprites`
- **Base**: `41ff3af` (origin/main)

## Scope

Wire already-approved main assets into title + overworld Player. No world env
atlas / soil_crack / rock_wall / mine-frame changes.

## Assets (exact `res://` paths)

| Role | Path |
|------|------|
| Title background | `res://assets/art/ui/title/bg_title.png` |
| Idle | `res://assets/art/characters/luoxian/actions/luoxian_action_idle_00.png` |
| Walk A | `res://assets/art/characters/luoxian/actions/luoxian_action_walk_00.png` |
| Walk B | `res://assets/art/characters/luoxian/actions/luoxian_action_walk_01.png` |

PNGs verified as real binaries (PNG magic), not LFS pointer stubs.

## Changes

- `scenes/title_screen.tscn`: `Root/Backdrop` ColorRect → TextureRect (`bg_title.png`, stretch keep-aspect-covered).
- `scenes/player.tscn`: `Sprite` ColorRect → AnimatedSprite2D with SpriteFrames `idle` (1) + `walk` (2); feet-anchored `position=(0,-24)`.
- `src/player/player_controller.gd`: `_sync_sprite()` idle/walk + `flip_h` from facing.x; controller API unchanged.
- Unit tests updated for TextureRect / AnimatedSprite2D contracts.
- `docs/plans/contracts/module-contracts.md`: player Sprite row updated.

## Verify

- `python scripts/validate_content.py` — see commit / PR notes
- GUT default suite (`addons/gut`, `-gdir=res://tests/unit`) — see commit / PR notes
- No `.import` flood-commit; Godot regenerates locally on `--import`

## Out of scope

World soil_crack / rock_wall atlas v3 / mine frames; battle units; audio.

## Local verify results

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **715/715 PASS**, 10954 asserts, 10.64s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-wire-title-player.log`
