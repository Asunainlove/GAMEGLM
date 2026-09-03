# Visual Follow-up (env / UI) — 2026-09-03

Status: `READY` (branch `feat/visual-followup-env-ui`)

Base: `origin/main` tip after PR22 + PR23 (`71684b4`)

Standing auth: 幕僚长 — layout/theme/env probe polish; merge if gates OK. **Not** amending #22.

## Prior

| PR | What |
|---|---|
| **#22** | Visual polish HUD — Noto SC + StyleBoxTexture panels (DONE / on main) |
| **#23** | v2 soil/UI polish asset drop-in |

## This PR

| Area | What |
|---|---|
| `project.godot` | Global GUI theme `gui/theme/custom = res://themes/starsoil_theme.tres`. Fixed broken duplicate `[display]` keys. Audio bus + physics + input preserved. |
| `scenes/battle.tscn` | Theme; TurnLabel/ActionsBox/ReportPanel wrapped in PanelContainers; FinishBanner → PanelContainer + dim StyleBoxFlat + FinishLabel. |
| `src/encounters/battle_scene.gd` | Nested UI paths; FinishBanner cast as `Control`. |
| `src/world/world_renderer.gd` | SOURCE_ROCK_WALL prefers `env_rock_wall.png` then tip `env_world_rock_wall.png` then tilesets then mine_wall last. `env_mine_wall_atlas.png` untouched. Soil crack path documented; no DecalLayer → runtime skipped. |
| `scenes/ui_hud.tscn` | InventoryPanel z=20, MenuPanel z=21; Dimmer z=19. |
| `src/ui/hud.gd` | Minimal `_sync_modal_dimmer()`. |
| `scenes/app.tscn` | StartupScreen Status/Hint: removed 灰盒 / 正式美术尚未接入 / 占位界面. |
| `scenes/dialogue_box.tscn` | `layer = 10`. |

## Assets notes

- Contract path `world/tiles/env_rock_wall.png` still awaiting exact-name drop-in; tip has `env_world_rock_wall.png` (PR23) as second probe.
- Soil crack file present; no DecalLayer in world.tscn.
- **mine_wall atlas untouched**.

## Do not (honored)

- No unit battle frame swaps; no gameplay/values/events; no invented binary art.
