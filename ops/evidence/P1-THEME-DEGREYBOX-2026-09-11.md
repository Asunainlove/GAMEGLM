# Evidence — VISUAL-REFACTOR-P1 Theme + Ending/FinishBanner/BuildBar degreybox

- **Date**: 2026-09-11 (Asia/Shanghai)
- **Branch**: `feat/visual-refactor-p1-theme-degreybox`
- **Base**: `c39effa` (`origin/main` — #56 P1-A explore Luoxian readability)
- **Scope**: presentation-only Theme expand + kill decorative teal + Ending/FinishBanner/BuildBar chrome tokens — **no gameplay expand**; no new LOGO / inventory-slot / battle-track art; Luoxian SpriteFrames untouched

## P1-B Theme

| Item | Detail |
|---|---|
| Theme | `themes/starsoil_theme.tres` — font ladder Label 14 / LabelPanelTitle 18 / LabelScreenTitle 20 / LabelBanner 22 |
| Panel variants | `PanelDialog` / `PanelInventory` / `PanelMenu` / `PanelHelp` / `PanelDimOverlay` |
| Focus | Gold ring `StyleBoxFlat` on `Button/styles/focus` (`gold.main`) |
| Tokens | `themes/starsoil_tokens.gd` (`StarsoilTokens`) matching ui-assets §0.1 ±2/255 |
| Scene purge | Removed per-scene `StyleBoxTexture` forks from `ui_hud`, `dialogue_box`, `title_screen`; scenes use `theme_type_variation` |

## P1-C Degreybox / teal

| Item | Detail |
|---|---|
| Teal | Removed decorative `Color(0.42, 0.79, 0.72)` from title subtitle + app splash eyebrow/rule → secondary text / gold rule |
| FinishBanner | Local `StyleBoxFlat` retired → theme `PanelDimOverlay` (tokenised dim) |
| Ending | Added themed `PanelMenu` chrome plate; labels use ladder variations (paths `$TitleLabel`/`$SummaryLabel` preserved) |
| BuildBar | Icon placeholder + HintToast use theme tokens / `PanelMenu`; no local StyleBoxFlat |
| Battle greybox | Ally/enemy/boss ColorRect fallbacks muted via `StarsoilTokens` (flash channel relationship kept) |

## ops/state.json

| Field | Value |
|---|---|
| `visual_refactor_packet` | `p0_closed` |
| `active_packet` | `VISUAL-REFACTOR-P1` |
| `window_status` | `visual_refactor_p1` |
| `resume_from` | `visual_refactor_p1_theme_hud` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P1"]` |
| `last_verified_commit` | `c39effa` (lift after merge) |
| `p1_a_explore_luoxian` | `done` |
| `known_blockers` | Visual look not owner-passed; G7 shelved |
| `known_residuals` | place_chain flaky only |

Handoff: `ops/handoffs/GAMEGLM-PROJECT-TEAM.md` §1 updated (P0 closed; P1 Theme+degreybox engineering; P1-A done @ c39effa).

## Art-blocked (not this PR)

- Title `UIA-TTL-LOGO` wordmark / button-rail scrim
- Inventory slot frames `UIA-INV-*` + recipe row icons
- Battle track floors / action icons (`UIA-BAT-*`)

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **744/744 PASS**, 11260 asserts, 10.028s (Godot 4.7.2 / GUT 9.7.1) |

Log: `/workspace/gut-logs/gut-p1-theme-full.log`
