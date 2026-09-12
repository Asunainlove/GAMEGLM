# Evidence — VISUAL-REFACTOR-P5 battle action icons + banner skins wire

- **Date**: 2026-09-12 (Asia/Shanghai)
- **Branch**: `feat/visual-refactor-p5-battle-ui-wire`
- **Base**: `675af60` (`origin/main` — #73 P5-A art after #72 P5-B skeleton)
- **Scope**: presentation-only — bind approved P5-A UIA-BAT icons/banners; graybox fallback retained when missing. **No gameplay expand.** Residuals untouched (recipe rows, parallax ENV-18..20, ENV-28, Boss arena).

## ops/state.json

| Field | Value |
|---|---|
| `visual_refactor_packet` | `p4_closed` |
| `active_packet` | `VISUAL-REFACTOR-P5` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P5"]` |
| `window_status` | `visual_refactor_p5` |
| `resume_from` | `visual_refactor_p5_battle_icons_banners` |
| `p5_status` | `wiring` |
| `p5_a_battle_chrome` | `done` |
| `last_verified_commit` | `9634010` (unchanged until 测试 stamps) |
| `known_blockers` | look not owner-passed; G7 shelved |
| `known_residuals` | place_chain flaky; P5-A chrome **wired real** (no longer pending art); Post-P5 residuals |

## Bound probe paths (exact)

| Hook | Asset id | Contract path | When missing |
|---|---|---|---|
| Action icon attack | `uia_bat_ico_attack` | `res://assets/art/ui/battle/uia_bat_ico_attack.png` | Text-only Button (`action_icons_graybox`) |
| Action icon guard | `uia_bat_ico_guard` | `assets/art/ui/battle/uia_bat_ico_guard.png` | ditto |
| Action icon item | `uia_bat_ico_item` | `assets/art/ui/battle/uia_bat_ico_item.png` | ditto |
| Phase banner | `uia_bat_bnr_phase` | `assets/art/ui/battle/uia_bat_bnr_phase.png` | `PhaseBanner` Label only; skin empty |
| Turn banner | `uia_bat_bnr_turn` | `assets/art/ui/battle/uia_bat_bnr_turn.png` | `RoundBanner` Label only |
| Result victory | `uia_bat_bnr_result_victory` | `assets/art/ui/battle/uia_bat_bnr_result_victory.png` | FinishBanner theme `PanelDimOverlay` + Label |
| Result defeat | `uia_bat_bnr_result_defeat` | `assets/art/ui/battle/uia_bat_bnr_result_defeat.png` | ditto |
| Result fallback | `uia_bat_bnr_result` | `assets/art/ui/battle/uia_bat_bnr_result.png` | probed after victory/defeat id |

Probe order mirrors prior UIA: `AssetAdapter.texture(id)` → `texture_at(<contract path>)` (`FileAccess.exists` inside `texture_at`).

Kind → icon map: `attack`/`destabilize`/`skill` → attack; `guard` → guard; `item` → item.

## Changes

- `src/encounters/battle_scene.gd`: P5-B probes already bind when files exist (no gameplay expand)
- Tests: production asserts icons/banners **not** graybox; graybox/drop-in paths still covered via `user://`
- `ops/state.json`: `p5_status=wiring`, `p5_a_battle_chrome=done`; residuals updated
- Handoff §1 one-liner aligned

## Graybox vs real (this tip)

| Surface | State |
|---|---|
| Battle track floor | **REAL** `uia_bat_tracks.png` (P2) |
| Action icons | **REAL** `uia_bat_ico_{attack,guard,item}.png` (#73) |
| Phase / turn / result banners | **REAL** `uia_bat_bnr_{phase,turn,result_*}.png` (#73) |

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| GUT `-gtest=…/test_p5_battle_ui_skeleton.gd` | **5/5 PASS**, 61 asserts, 0.453s |
| GUT `-gdir=res://tests/unit` | **760/760 PASS**, 11417 asserts, 11.426s (Godot 4.7.2 / GUT 9.7.1) |

No `.import` flood committed.

Log: `/workspace/gut-logs/gut-p5-wire-full.log`
