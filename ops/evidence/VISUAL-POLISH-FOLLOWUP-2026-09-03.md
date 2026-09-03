# Visual Polish Follow-up (z-order / HUD chrome / env probes) — 2026-09-03

Status: `READY` (branch `feat/visual-polish-zorder-hud-panels-exec`)

Base: `origin/main` tip `71684b4` (PR #23 env/UI asset drop-in already merged)

Standing auth: squash-merge when CI green. No G7 fabrication.

## Goal

Land HUD/dialogue CanvasLayer z-order so world sprites never cover UI, densify
trust/objective chrome, and wire optional `env_world_rock_wall` probe safely.

## Shipped

| Area | What |
|---|---|
| `scenes/dialogue_box.tscn` | `CanvasLayer.layer = 50` |
| `scenes/ui_hud.tscn` | `CanvasLayer.layer = 20`; Inventory/Top(objective+relations)/Build chrome panels; `%` unique names |
| `src/ui/hud.gd` + unit tests | Node paths use `%` unique names |
| `src/world/world_renderer.gd` | `CELL_ASSET_PROBES` prefers `env_world_rock_wall.png`; atlas untouched fallback |
| player greybox TODO | ART-019 comments only |
| Assets (main via #23) | soil_base, panel_dialog, btn_*, soil_crack, rock_wall, art-approval |

## TODOs / non-goals

| Item | Why |
|---|---|
| Do not replace `env_mine_wall_atlas.png` | Atlas v2 rejected |
| `env_world_soil_crack` runtime | No DecalLayer yet — comment-only TODO |
| Unrelated `.import` | Not committed |

## Gates (local)

| Check | Result |
|---|---|
| `python scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--headless --import` | **PASS** exit 0 |
| Default GUT `-gdir=res://tests/unit` | **717/717 PASS** exit 0 (~24s) |
