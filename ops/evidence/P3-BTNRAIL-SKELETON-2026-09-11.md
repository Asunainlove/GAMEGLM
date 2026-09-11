# Evidence — VISUAL-REFACTOR-P3 title btnrail wire (P3-B)

- **Date**: 2026-09-11 (Asia/Shanghai)
- **Branch**: `feat/visual-refactor-p3-btnrail`
- **Base**: `62b5d2b` (`origin/main` — #63 ops P3 activate + #64 P3-A art)
- **Scope**: presentation-only — bind `uia_ttl_btnrail`; graybox fallback if missing; light Rule residual. **No gameplay expand.**

## ops/state.json

| Field | Value |
|---|---|
| `visual_refactor_packet` | `p2_closed` |
| `active_packet` | `VISUAL-REFACTOR-P3` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P3"]` |
| `window_status` | `visual_refactor_p3` |
| `resume_from` | `visual_refactor_p3_btnrail` |
| `p3_status` | `skeleton` |
| `p3_a_btnrail` | `done` |
| `last_verified_commit` | `1188bf0` (lift after merge if 测试 stamps) |
| `known_blockers` | look not owner-passed; G7 shelved |
| `known_residuals` | place_chain flaky; btnrail **wired real** (no longer pending art) |

## Bound probe path (exact)

| Hook | Asset id | Contract path | When missing |
|---|---|---|---|
| Title button rail | `uia_ttl_btnrail` | `res://assets/art/ui/title/uia_ttl_btnrail.png` | `ButtonRailGraybox` ColorRect; `ButtonRailScrim` hidden |
| Optional companion | `uia_ttl_btnrail_320` | `assets/art/ui/title/uia_ttl_btnrail_320.png` | probed after id, before explicit path |

Probe order mirrors LOGO: `AssetAdapter.texture(id)` → `texture(id_320)` → `texture_at(<contract path>)` (FileAccess.exists inside `texture_at`).

## Changes

- `title_screen.gd`: harden `_apply_btnrail_probe` to LOGO convention; bind REAL #64 art
- Light audit residual: hide `Layout/Rule` ColorRect when real LOGO present (§7.1 hairline already on wordmark)
- Tests: production asserts btnrail **not** graybox; graybox/drop-in paths still covered via `user://`
- `ops/state.json`: `p3_status=skeleton`, `p3_a_btnrail=done`; residuals updated

## Graybox vs real (this tip)

| Surface | State |
|---|---|
| Title LOGO | **REAL** `uia_ttl_logo.png` |
| Title button rail | **REAL** `uia_ttl_btnrail.png` (#64) |
| Title decorative Rule | **hidden** when LOGO real (residual clear) |
| Inventory slot frames | **REAL** (unchanged) |
| Battle track floor | **REAL** (unchanged) |

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| GUT `-gdir=res://tests/unit` | **752/752 PASS**, 11325 asserts, 11.362s (Godot 4.7.2 / GUT 9.7.1) |

No `.import` flood committed.

Log: `/workspace/gut-logs/gut-p3-btnrail-unit-final3.log`
