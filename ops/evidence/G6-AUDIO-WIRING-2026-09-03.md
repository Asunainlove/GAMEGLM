# G6 Audio Wiring Evidence — 2026-09-03

Status: `MERGED` — https://github.com/Asunainlove/GAMEGLM/pull/18 (`3d6cd1c`)

Base: `origin/main` tip before merge `266fdf0` (PR #17 catalog resolvers); wiring landed as #18.

## Scope

- Fix critical gap: App `_resolve_audio_director()` injects `track_resolver` /
  `sfx_resolver` via `AudioCatalog` (`res://assets/audio/bgm|sfx/<id>.ogg`, null on miss).
- Bind same `AudioDirector` into GameSession (propagates to Hud / DialogueBox / BattleScene).
- Wire §6 P0 (+ reachable P1) call sites without breaking greybox.
- Add Master→BGM/SFX `default_bus_layout.tres` + `project.godot` buses entry.
- GUT: `test_audio_wiring.gd`, `test_audio_catalog.gd`, bus-fallback tweak in `test_audio_director.gd`.

## Gate

| Check | Result |
|---|---|
| Linux Godot 4.7.2 headless GUT (`-gdir=res://tests/unit`) | **715/715 PASS** (22.6s) |
| Audio subset (`-gprefix=test_audio`) | **23/23 PASS** |
| `python scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |
| CI `content-schema` on PR #18 | **pass** |
| CI `toolchain-gate` on PR #18 | **pass** (Windows-only GUT may differ; local Linux green) |

## Wired hooks

| Site | Call |
|---|---|
| App title / continue / fresh | `bgm_title` / `bgm_explore` (fade 2s into explore) |
| App assemble | inject AudioCatalog resolvers; `GameSession.bind_audio_director` |
| GameSession mine hit / depleted | `sfx_mine_hit` / `sfx_mine_depleted` |
| GameSession place ok / denied | `sfx_build_place` / `sfx_build_denied` (-3 dB) |
| GameSession craft success | `sfx_craft_success` |
| GameSession save / restart | `sfx_save_notice` (-3 dB) / `stop_all` |
| prologue `event_prologue_landing` complete | `bgm_explore` |
| encounter start | `bgm_battle` / `bgm_boss` (leviathan) |
| encounter finish | `sfx_victory` + delayed explore BGM / `sfx_defeat` |
| ending show | `sfx_ending_bell` |
| power reconcile new unpowered effect_flag | `sfx_power_unstable` (session-idempotent) |
| BattleScene ally/enemy action, damage, phase | `sfx_battle_action` / `sfx_battle_hit` / `sfx_boss_phase` + `bgm_boss_final` |
| DialogueBox page / choice | `sfx_dialogue_page` (-6) / `sfx_dialogue_choice` |
| Hud menu/inventory toggle + buttons / build / craft | `sfx_ui_toggle` / `sfx_ui_click` (-3) |

## Remaining unwired (§6)

- `bgm_build` on BuildBar focus (P1; no clean focus enter/exit hook without UX churn)
- Ending BGM 4s fade-out only (AudioDirector has no fade-out-without-replace API; bell plays, BGM left running)
- TitleScreen button `sfx_ui_click` (title uses App BGM only; Hud covers in-game UI clicks)
- Pitch jitter variants (±20 cents mine / ally-vs-enemy hit) — optional polish

## Note

Do not fabricate G7 playtest. Audio wiring is code/asset playback wiring only.
