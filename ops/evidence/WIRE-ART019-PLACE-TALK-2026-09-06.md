# Evidence — wire ART-019 Luoxian place/talk multi-frames

- **Date**: 2026-09-06 (Asia/Shanghai)
- **Branch**: `feat/wire-art019-place-talk-frames`
- **Base**: `bf86def` (origin/main)

## Scope

Non-blocking residual ART-019: wire multi-frame explore animations already on
main under `assets/art/characters/luoxian/actions/` into `scenes/player.tscn`
SpriteFrames. Presentation only — no gameplay expand; no battle units / Misa.

## Assets (exact `res://` paths)

| Anim | Frames | Paths |
|------|--------|-------|
| place | 4 | `luoxian_action_place_00.png` … `place_03.png` |
| talk | 2 | `luoxian_action_talk_00.png`, `talk_01.png` |

Full prefix: `res://assets/art/characters/luoxian/actions/`.

PNGs verified as real binaries (PNG magic), not LFS pointer stubs. Assets were
already present on main; this PR only binds missing frames (place_00 / talk_00
were already wired).

## Changes

- `scenes/player.tscn`: extend SpriteFrames `place` 1→4 and `talk` 1→2 (same
  pattern as idle/mine/walk). Place speed aligned to mine one-shot rhythm (8.0);
  talk remains 3.0, loop false.
- `tests/unit/test_player_controller.gd`: frame-count asserts + path checks for
  place_00..03 / talk_00..01.
- No `player_controller.gd` API changes (anim names already wired).

## Verify

- `python3 scripts/validate_content.py` — PASS
- Godot `--import` — exit 0
- GUT default suite (`-gdir=res://tests/unit`) — PASS
- No `.import` flood-commit; Godot regenerates locally on `--import`

## Out of scope

Battle units; Misa explore; gameplay / input / building rules.

## Local verify results

| Gate | Result |
|------|--------|
| `python3 scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| Godot `--import` | exit 0 |
| GUT `-gdir=res://tests/unit` | **727/727 PASS**, 11130 asserts, 11.639s (Godot 4.7.2 / GUT) |

Log: `/workspace/gut-logs/gut-wire-art019-place-talk.log`
