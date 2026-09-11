# Evidence — ENV-27 build dust place wiring + ops/state VISUAL-REFACTOR-P0

- **Date**: 2026-09-11 (Asia/Shanghai)
- **Branch**: `feat/p0-build-dust-and-state`
- **Base**: `86dfa7c` (`origin/main` — #51 world-presence + #52 silhouette/ore overlay)
- **Tip**: `fa26336`
- **Scope**: presentation-only place VFX + product-aligned `ops/state.json` — **no gameplay expand**

## ENV-27 wiring

| Item | Detail |
|---|---|
| Frames | `res://assets/art/world/fx/env_fx_build_dust_seq_f0.png`, `…_f1.png` (64×64) |
| Hook | `GameSession.request_place` success → `_nudge_world_build_dust(cell)` after unchanged `sfx_build_place` |
| Presentation | `World.play_build_dust_at_cell` → `BuildingPresenter.play_build_dust` under `$Buildings` |
| Runtime | `AnimatedSprite2D` one-shot (`build_dust`, ~120 ms/frame, non-loop) → `queue_free` on `animation_finished` |
| Art overlay | #52 already landed silhouette lock + ore type split on main; **paths unchanged** this PR |

## ops/state.json (产品 draft)

| Field | Value |
|---|---|
| `active_packet` | `VISUAL-REFACTOR-P0` |
| `visual_refactor_packet` | `wiring_landed` |
| `window_status` | `visual_refactor_p0` |
| `resume_from` | `visual_refactor_p0_world_presence` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P0"]` |
| `known_blockers` | Visual look not owner-passed; G7 shelved until look passes |
| Dust residual | **omitted** (wired this PR) |
| Silhouette/ore residual | **closed by #52** (not re-listed) |
| Obsolete `visual_refactor_packet=planned…Pack P0 next` | **removed** |

Handoff: `ops/handoffs/GAMEGLM-PROJECT-TEAM.md` aligned (1–2 sentence status + next steps).

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **739/739 PASS**, 11211 asserts, 10.166s (Godot 4.7.2 / GUT 9.7.1) |
| Focused `test_world_building_sync.gd` | **8/8 PASS** (incl. ENV-27 dust spawn/free + World cell FX) |

Log: `/workspace/gut-logs/gut-p0-build-dust-full3.log`

