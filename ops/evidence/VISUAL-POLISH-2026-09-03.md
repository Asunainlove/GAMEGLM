# Visual Polish (HUD / Theme / Title) — 2026-09-03

Status: `READY` (branch `feat/visual-polish-hud`)

Base: `origin/main` tip `732d34a`

Standing auth: 幕僚长 (2026-09-03) — layout/theme polish only; no G7 fabrication.

## Goal

Make the vertical slice look less greybox/crude while staying **original Starsoil / 余辉**
aesthetic: denser readable HUD, wired approved batch3 UI panels/buttons + Noto Sans SC
subset. Not copying Terraria / Stardew Valley UI/layout/icons/terms.

## Changes

| Area | What |
|---|---|
| `themes/starsoil_theme.tres` | Default font → `assets/fonts/NotoSansSC-Regular.subset.otf` (`FontFile`). Panel + Button styles → `StyleBoxTexture` from approved `panel_menu` / `btn_{normal,hover,pressed,disabled}`. Gold hover/pressed font colors per `docs/art/ui-assets.md` tokens. |
| `scenes/ui_hud.tscn` | Inventory/menu/help panel StyleBoxTexture overrides (`panel_inventory` / `panel_menu` / `panel_help`). Margins, separations, objective/relations/build-bar readability. Help footer no longer claims “正式美术尚未接入”. |
| `scenes/title_screen.tscn` | Title-first hierarchy, warmer gold title + shorter gold rule, taller buttons, help panel texture, same help footer polish. |
| `scenes/dialogue_box.tscn` | Attach theme + `panel_dialog` StyleBoxTexture; slight padding/separation. |
| `tests/unit/test_ui_theme.gd` | Contract updated: embedded Noto FontFile + StyleBoxTexture (replaces SystemFont / StyleBoxFlat greybox asserts). |
| `THIRD_PARTY_NOTICES.md` | Noto Sans SC OFL entry. |
| World | **No rewrite.** TileSet already probes denser env tiles via `WorldRenderer.CELL_ASSET_PROBES`; decals remain adapter-listed only. |

## Intentionally not done

- No mountains of `.import` commits (Godot `--import` regenerates; only gut vendor imports stay tracked).
- No world-gen changes / autotile rewrite.
- No G7 playtest claims.
- Startup `app.tscn` greybox splash copy left as-is (title screen is the player-facing entry).

## Gate

| Check | Result |
|---|---|
| HUD/theme/title/dialogue GUT subset | **62/62 PASS** (3.2s) |
| Default unit suite (`-gdir=res://tests/unit`) | **715/715 PASS** (22.0s) |
| `python scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |

Logs: `/workspace/gut-logs/gut-visual-polish-subset.log`, `/workspace/gut-logs/gut-visual-polish-full.log`

## Notes

Greybox isolation tests for missing icons / battle sprites remain injection-based and stayed green.
