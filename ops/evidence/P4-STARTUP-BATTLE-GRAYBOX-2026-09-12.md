# Evidence — VISUAL-REFACTOR-P4 startup + battle graybox (engineering)

- **Date**: 2026-09-12 (Asia/Shanghai)
- **Branch**: `feat/visual-refactor-p4-graybox`
- **Base**: `a24e67c` (`origin/main` — #67 ops P4 activate)
- **Scope**: presentation-only — degreybox app startup ColorRect stack; kill battle unit colored graybox flash. **No gameplay expand.** Non-blocking residuals untouched (action icons/banners, recipe rows, parallax ENV-18..20, ENV-28, Boss arena).

## ops/state.json

| Field | Value |
|---|---|
| `visual_refactor_packet` | `p3_closed` |
| `active_packet` | `VISUAL-REFACTOR-P4` |
| `next_packet_ids` | `["VISUAL-REFACTOR-P4"]` |
| `window_status` | `visual_refactor_p4` |
| `resume_from` | `visual_refactor_p4_startup_battle_graybox` |
| `p4_status` | `wiring` |
| `last_verified_commit` | `e83c9a3` (unchanged until test stamps) |
| `known_blockers` | look not owner-passed; G7 shelved |
| `known_residuals` | place_chain flaky; Post-P4 residuals listed (non-blocking) |

## Hard deliverables

### 1. Startup ColorRect stack → theme / tokens

| Before | After |
|---|---|
| `StartupScreen` `ColorRect` scrim | `PanelContainer` + tokenised `StyleBoxFlat` (`BG_DEEP` α 0.76) |
| `Layout/Rule` gold `ColorRect` | `Panel` + tokenised `StyleBoxFlat` (`GOLD_MAIN` α 0.7) |
| Label colours ad-hoc | Aligned to `StarsoilTokens` (TEXT_SECONDARY / GOLD_BRIGHT / TEXT_PRIMARY / TEXT_DISABLED) |

`app.gd`: `startup_screen` typed as `Control` (fade contract unchanged).

### 2. Battle unit graybox flash → invisible placeholder

| Before | After |
|---|---|
| Probe miss → visible coloured `Box` ColorRect | Probe miss → `Box` with `visible=false`, `color.a=0`, meta `unit_box_invisible` |
| Destabilize flash recolors visible Box | Flash skips invisible placeholders; sprite path unchanged |

Wired production units still get Sprite only (no Box).

## Changes

- `scenes/app.tscn`, `src/app/app.gd`
- `src/encounters/battle_scene.gd`
- Tests: `test_p4_startup_battle_graybox.gd` (new); updates to battle assets/presentation/scene + integration comment
- `ops/state.json`: `p4_status=wiring` (P4 activation fields kept)

## Acceptance

1. Startup has **no** bare ColorRect stack — **PASS** (`test_p4_startup_battle_graybox`)
2. Battle has **no** unit graybox flash — **PASS** (invisible placeholder / wired Sprite)
3. GUT + validate_content green — **PASS**

## Verify

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| GUT `-gdir=res://tests/unit` | **755/755 PASS**, 11356 asserts, 11.055s (Godot 4.7.2 / GUT 9.7.1) |

No `.import` flood committed.

Log: `/workspace/gut-logs/gut-p4-graybox-full.log`
