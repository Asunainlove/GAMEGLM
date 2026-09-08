# Evidence — Pack P0 World Presence skeleton (P0-B / P0-D / P0-E)

- **Date**: 2026-09-08 (Asia/Shanghai)
- **Branch**: `feat/p0-world-presence-skeleton`
- **Base**: `e13abb7` (`origin/main` — visual refactor audit plan #49)
- **Scope**: engineering presentation skeleton only — **no gameplay expand**

## Goal

Make the sandbox loop look inhabited under 余辉 light without waiting on missing building art:

| ID | Work | Status |
|---|---|---|
| P0-B | `$Buildings` sync from `placed_buildings` + powered/unpowered skin | Done (graybox fallback) |
| P0-D | Ore atlas regions ↔ gathering hardness / destroy | Done |
| P0-E | BuildBar icon + name hooks | Done (placeholder icons) |
| P0-A / P0-C | Building + soil/ore art | **Out of scope** (美术) |

## Changes

- `src/world/building_presenter.gd` (new): spawn/despawn/update under `$Buildings`; probe `world/buildings/<id>_powered.png` / `_unpowered.png`; graybox ColorRect when absent; PowerGrid-ordered powered map.
- `src/world/world.gd`: `_sync_buildings` on snapshot refresh; `mining_progress_provider` + `sync_ore_presentation` for mid-mine frames (no revision bump).
- `src/world/world_renderer.gd`: register ore atlas tiles beyond (0,0); `ore_atlas_coords(hardness_total, hardness_left)`; `set_ore_frame`.
- `src/ui/hud.gd`: BuildBar `IconSlot`/`Icon`/`NameLabel`/`CostLabel`; tokenised `UnpoweredPip` (node name still `UnpoweredDot`).
- `src/integration/game_session.gd`: wire `mining_progress_snapshot` → World; nudge ore frames after mine strikes.
- Tests: `test_world_building_sync.gd`, `test_world_ore_frames.gd`, BuildBar structure assert in `test_ui_gap4.gd`; updated ore atlas strip expect 5 tiles.
- `docs/plans/contracts/module-contracts.md`: Buildings / OreOverlay / BuildBar presentation notes.

## Graybox vs real

| Surface | State |
|---|---|
| Building world sprites | **Graybox** 48×48 ColorRect (ENV-21..26 absent on disk) |
| Building powered skin | Graybox color swap (powered warmer / unpowered dimmer); path-only drop-in when art arrives |
| Ore atlas s0..s2 | **Real** `env_ore_*_set.png` frames wired; damage uses s1/s2 |
| BuildBar icons | **Placeholder** gray ColorRect until `ui/icons/ui_bld_*.png` approved |
| BuildBar names/costs | Real text (unchanged catalog) |
| Unpowered pip | Tokenised red ColorRect (compat name `UnpoweredDot`) |

## Non-goals / blockers

- No new Autoload buses; SFX hooks unchanged.
- No `.import` flood; no Terraria/Stardew UI terms.
- **Blocker for full P0 acceptance**: P0-A building art + P0-C soil/ore retarget still outstanding (美术).
- Glint tile animation on s0 (ENV contract R2 optional half) not enabled this packet.

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **735/735 PASS**, 11182 asserts, 10.74s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-p0-world-presence-full.log`
