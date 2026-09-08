# Evidence — Pack P0 World Presence skeleton (P0-B / P0-D / P0-E)

- **Date**: 2026-09-08 (Asia/Shanghai)
- **Branch**: `feat/p0-world-presence-skeleton`
- **Base**: `4e1dc6d` (`origin/main` — VISUAL-REFACTOR-P0 buildings + soil/ore v3 #50)
- **Scope**: engineering presentation skeleton only — **no gameplay expand**

## Bound asset paths (exact)

### P0-B Buildings (powered / unpowered)
Probe order: `AssetAdapter.texture("env_bld_<id>_<suffix>")` →
`res://assets/art/world/buildings/env_bld_<id>_<suffix>.png` → legacy short name → graybox.

| building_id | powered | unpowered |
|---|---|---|
| anchor_block | `assets/art/world/buildings/env_bld_anchor_block_powered.png` | `…/env_bld_anchor_block_unpowered.png` |
| anchor_workshop | `…/env_bld_anchor_workshop_powered.png` | `…/env_bld_anchor_workshop_unpowered.png` |
| dust_refiner | `…/env_bld_dust_refiner_powered.png` | `…/env_bld_dust_refiner_unpowered.png` |
| stabilizer_pylon | `…/env_bld_stabilizer_pylon_powered.png` | `…/env_bld_stabilizer_pylon_unpowered.png` |
| resonance_loom | `…/env_bld_resonance_loom_powered.png` | `…/env_bld_resonance_loom_unpowered.png` |
| echo_chamber | `…/env_bld_echo_chamber_powered.png` | `…/env_bld_echo_chamber_unpowered.png` |

### P0-D Ore / soil tiles (renderer probes — v3 on tip)
| Role | Path |
|---|---|
| soil | `assets/art/world/tiles/env_world_soil_base.png` |
| ore_dust atlas | `assets/art/world/tiles/env_ore_dust_set.png` (160×32 → s0/s1/s2/glint) |
| ore_shard atlas | `assets/art/world/tiles/env_ore_shard_set.png` |
| ore_core atlas | `assets/art/world/tiles/env_ore_core_set.png` |
| rock_wall | `assets/art/world/tiles/env_world_rock_wall.png` (+ `env_mine_wall_atlas.png` fallback) |

Damage mapping: `WorldRenderer.ore_atlas_coords(hardness_total, hardness_left)` → atlas cols 0/1/2; destroy clears overlay.

### P0-E BuildBar icons
1. `ui_bld_<id>` under `assets/art/ui/icons/` (absent on tip)
2. Fallback: `env_bld_<id>_powered` (same building PNGs above)
3. Last resort: gray ColorRect placeholder

### Dust FX (present, not wired)
| Path | Note |
|---|---|
| `assets/art/world/fx/env_fx_build_dust_seq_f0.png` | On disk after #50 |
| `assets/art/world/fx/env_fx_build_dust_seq_f1.png` | No place-VFX hook in World/GameSession beyond `sfx_build_place` — **not wired** this PR (no invent) |

## Changes

- `BuildingPresenter`: sync `$Buildings`; real `env_bld_*` skins; graybox last resort
- `world.gd` / `world_renderer.gd`: building sync + ore s0/s1/s2 from mining progress
- `hud.gd`: BuildBar Icon/Name/Cost hooks; env_bld powered icon fallback
- `game_session.gd`: mining progress → World ore frames
- Tests + `module-contracts.md`

## Graybox vs real (post #50)

| Surface | State |
|---|---|
| Building world sprites | **REAL** `env_bld_*` (12 files) |
| Building powered skin | **REAL** powered/unpowered swap |
| Ore atlas s0..s2 | **REAL** v3 atlases + damage frames |
| Soil base | **REAL** v3 via existing WorldRenderer probe |
| BuildBar icons | **REAL** via `env_bld_*_powered` fallback (`ui_bld_*` still absent) |
| Build dust FX | **On disk, unwired** (no existing place VFX hooks) |
| Graybox | Last-resort only if a specific file missing |

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **737/737 PASS**, 11200 asserts, 10.66s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-p0-world-presence-full.log`
