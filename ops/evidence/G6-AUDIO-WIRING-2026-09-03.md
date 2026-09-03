# G6 Audio Wiring Evidence — 2026-09-03

Status: `READY`

Base: `origin/main` tip `859a0d7` (branch `feat/g6-audio-wiring`)

## Scope

- Fix critical gap: App `_resolve_audio_director()` now injects `track_resolver` /
  `sfx_resolver` via `AudioCatalog` after assembling `AudioDirector`.
- Wire P0 call sites from `docs/art/audio-assets.md` §6 through GameSession /
  BattleScene / DialogueBox / Hud thin forwards.
- Add Master→BGM/SFX `default_bus_layout.tres` + `project.godot` audio buses entry.
- Extend GUT: `test_audio_wiring.gd`, `test_audio_catalog.gd`, bus-fallback tweak
  in `test_audio_director.gd`.
- **Not committed:** untracked `*.import` sidecars (local Godot reimport only).

## Gate

| Check | Result |
|---|---|
| GUT audio suite | `test_audio_wiring` + `test_audio_director` + `test_audio_catalog` → **23/23 PASS** |
| `python scripts/validate_content.py` | **PASS** (40 files / 65 defs / 14 schemas) |

## Wired hooks (summary)

| Site | Call |
|---|---|
| App title / continue / fresh | `bgm_title` / `bgm_explore` |
| App assemble | inject AudioCatalog resolvers; `GameSession.bind_audio_director` |
| GameSession mine / place / craft / save / restart | SFX + `stop_all` |
| prologue complete / encounter start / finish / ending | BGM + victory/defeat/ending SFX |
| BattleScene action / hit / boss phase | SFX + `bgm_boss_final` |
| DialogueBox page / choice | SFX |
| Hud menu/inventory toggle + button presses | `sfx_ui_toggle` / `sfx_ui_click` |
