# Evidence — VISUAL-REFACTOR-P5-B battle action icons + banner skins skeleton

- **Date**: 2026-09-12 (Asia/Shanghai)
- **Branch**: `feat/visual-refactor-p5-battle-ui-skeleton`
- **Base**: `f7003da` (`origin/main` — #71 P5 resume/residuals after #70 activate / #69 p4_closed)
- **Scope**: presentation-only — UIA-BAT action icon + banner TextureRect/StyleBoxTexture probes with graybox fallback. **No gameplay expand.** Residuals untouched (recipe rows, parallax ENV-18..20, ENV-28, Boss arena).

## ops/state.json

| Field | Value |
|---|---|
| `visual_refactor_packet` | `p4_closed` |
| `active_packet` | `VISUAL-REFACTOR-P5` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P5"]` |
| `window_status` | `visual_refactor_p5` |
| `resume_from` | `visual_refactor_p5_battle_icons_banners` |
| `p5_status` | `skeleton` |
| `last_verified_commit` | `9634010` (unchanged until test stamps) |
| `known_blockers` | look not owner-passed; G7 shelved |
| `known_residuals` | place_chain flaky; P5 in progress note; Post-P5 residuals |

## Bound probe paths (exact)

| Hook | Asset id | Contract path | Graybox when missing |
|---|---|---|---|
| Action icon attack | `uia_bat_ico_attack` | `assets/art/ui/battle/uia_bat_ico_attack.png` | Text-only Button (`action_icons_graybox`) |
| Action icon guard | `uia_bat_ico_guard` | `assets/art/ui/battle/uia_bat_ico_guard.png` | ditto |
| Action icon item | `uia_bat_ico_item` | `assets/art/ui/battle/uia_bat_ico_item.png` | ditto |
| Phase banner | `uia_bat_bnr_phase` | `assets/art/ui/battle/uia_bat_bnr_phase.png` | `PhaseBanner` Label only; skin empty |
| Turn banner | `uia_bat_bnr_turn` | `assets/art/ui/battle/uia_bat_bnr_turn.png` | `RoundBanner` Label only |
| Result victory | `uia_bat_bnr_result_victory` | `assets/art/ui/battle/uia_bat_bnr_result_victory.png` | FinishBanner theme `PanelDimOverlay` + Label |
| Result defeat | `uia_bat_bnr_result_defeat` | `assets/art/ui/battle/uia_bat_bnr_result_defeat.png` | ditto |
| Result fallback | `uia_bat_bnr_result` | `assets/art/ui/battle/uia_bat_bnr_result.png` | probed after victory/defeat id |

Probe order mirrors P2/P3: `AssetAdapter.texture(id)` → `texture_at(<contract path>)` (`FileAccess.exists` inside `texture_at`). **No unapproved art committed.**

Kind → icon map: `attack`/`destabilize`/`skill` → attack; `guard` → guard; `item` → item.

## Changes

- `scenes/battle.tscn`: `PhaseBannerSkin` / `RoundBannerSkin` TextureRect; `FinishBanner/BannerSkin`
- `src/encounters/battle_scene.gd`: action Button.icon probes; banner skin + Finish `BannerPlate` StyleBoxTexture; graybox metas
- Tests: `tests/unit/test_p5_battle_ui_skeleton.gd`
- `ops/state.json`: kept from #70 (`p5_status=skeleton`, blockers unchanged)

## Graybox vs real (this tip)

| Surface | State |
|---|---|
| Battle track floor | **REAL** `uia_bat_tracks.png` (P2) |
| Action icons | **GRAYBOX** (awaiting 美术) |
| Phase / turn / result banners | **GRAYBOX** (awaiting 美术) |

## Acceptance target (when art lands)

1. Visible action icons on ActionsBox buttons
2. Banner skins not graybox (TextureRect / StyleBoxTexture bound)
3. GUT + validate_content green
4. Unapproved paths never required

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| GUT `-gtest=…/test_p5_battle_ui_skeleton.gd` | **5/5 PASS**, 54 asserts, 0.46s |
| GUT `-gdir=res://tests/unit` | **760/760 PASS**, 11410 asserts, 11.005s (Godot 4.7.2 / GUT 9.7.1) |

No `.import` flood committed.

Log: `/workspace/gut-logs/gut-p5-battle-ui-skeleton-full.log`
