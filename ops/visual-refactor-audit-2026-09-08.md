# Visual + Structure Refactor Audit — 2026-09-08

Status: `PLANNED` (plan-only; no large refactors in this PR)  
Base tip audited: `origin/main` @ `2e87997` (`ops: tip 3b08960 — ART-019 wired, drop residual`)  
Product: 《星壤：余辉纪元》 / Starsoil afterglow aesthetic  
Hard constraints: `AGENTS.md` originality — **no Terraria / Stardew / named-commercial clones**; no living-artist style imitation; keep dual-resolution language (pixel world + high-fidelity plates) under **永暮余辉** colour script.

Prior closed work (still insufficient for owner taste):

| Packet | Evidence | Outcome |
|---|---|---|
| Visual polish HUD/theme/title | `ops/evidence/VISUAL-POLISH-2026-09-03.md` | Theme Noto + StyleBoxTexture panels/buttons; HUD/title/dialogue wired |
| Visual follow-up | `ops/evidence/VISUAL-FOLLOWUP-2026-09-03.md` | Global theme; battle FinishBanner; rock_wall probe order; z-order |
| G6A batches 1–4 | `ops/state.json` `g6a_batch_status=done` | Env tiles, battle units, UI chrome, audio dropped in |
| Unit wiring | PRs #36–#47 | Battle allowlist fully wired; ART-019 explore place/talk wired |

Owner residual (this audit): **still too ugly / crude** — assets exist but hierarchy, world presence, and structure still read as greybox + mismatched styles.

---

## 0. Executive summary — top 5 ugliness findings

1. **Buildings are invisible (structural greybox).** `scenes/world.tscn` has `Buildings` Node2D; `world.gd` holds `@onready var _buildings` but **never syncs `placed_buildings` into sprites**. ENV-21..27 (`assets/art/world/buildings/`) are **absent**. Core place/craft loop has no world silhouette — the slice looks unfinished regardless of unit art quality.
2. **World tile language fights the 余辉 bible.** Title plate `bg_title.png` (1920×1080) is cinematic dusk/crystal/ruin; soil `env_world_soil_base.png` (32×32) is salt-pepper noise; ore atlases (`env_ore_*_set.png` 160×32) read as generic survival-game crystal-on-dirt. Atlas damage frames are **never used** (`create_tile(Vector2i.ZERO)` only — comment: “态切换属后续接线包”).
3. **Explore player vs battle unit readability split.** Explore Luoxian is 48×48 dark/muddy (weapon merges into legs); battle `luoxian_fighter` is 128×128 high-contrast cyan-edge silhouette. Same character, two fidelity brands — dual-res is intentional, but explore half fails rim-light / silhouette acceptance in `docs/art/character-assets.md`.
4. **Theme tokens incomplete; scenes still hardcode chrome.** `themes/starsoil_theme.tres` only styles `Button` / `Label` / `Panel` / `PanelContainer`. Per-scene `StyleBoxTexture` duplicates; title subtitle still uses **teal** `Color(0.42, 0.79, 0.72)` as accent (contract: teal = power only; gold = sole interactive highlight). BuildBar is a text dump (`"1 锚居块\n成本…"`); Ending is two bare Labels; battle FinishBanner still `StyleBoxFlat`.
5. **Missing “stage dressing” assets leave empty depth.** No parallax BG (`ENV-18..20`), no battle track floor / banner skins (`UIA-BAT-*`), no LOGO wordmark (`UIA-TTL-LOGO` — title is plain 64px Label), no border wall atlas, boss sigil only as loose decal files (not authored mine-floor stage). HUD inventory is icon+text row, not slot grid.

**Recommended next dispatch:** **Pack P0 — World Presence (buildings + soil/ore hierarchy + Buildings sync)**. See §6.

---

## 1. Theme / HUD / panels / fonts / spacing / colour hierarchy

### 1.1 What works

- Global `project.godot` → `theme/custom="res://themes/starsoil_theme.tres"`.
- Embedded `NotoSansSC-Regular.subset.otf`, default size 14; Button hover/pressed gold font colours roughly match `gold.bright` / `gold.main` in `docs/art/ui-assets.md` §0.1.
- Approved panels/buttons: `panel_{dialog,inventory,menu,help}.png`, `btn_{normal,hover,pressed,disabled}.png` wired into theme + HUD/dialogue/title overrides.
- HUD z-order / layers: Hud `layer=20`, title `30`, dialogue raised in prior follow-up.

### 1.2 Gaps / crude spots

| Finding | Evidence | Severity |
|---|---|---|
| Theme type coverage thin | Only Button/Label/Panel(+Container); no font-size ladder (18/20/22), no CheckButton/OptionButton/ProgressBar/Tooltip, no shared gold focus ring | P0 structure |
| Gold vs teal hierarchy broken | Title subtitle + app startup accents still teal `Color(0.42, 0.79, 0.72)`; contract demotes teal to **power/energy only** | P0 art+eng |
| Spacing inconsistent | Per-scene content margins 12–18; BuildBar / Objective / Relations are floating Labels without panel chrome or safe-area scrim | P1 |
| Inventory UX still greybox | Icons 24–32px inline in `HBoxContainer`; no `UIA-INV` slot frames; recipes remain text lists | P1 |
| BuildBar readability | Text-only toggle buttons + 8×8 `ColorRect` unpowered dots (`hud.gd` `UNPOWERED_DOT_COLOR`) — no building icons | P0 (pairs with buildings pack) |
| Toast / objective | Plain Label; no banner 9-patch (`UIA-HUD-*` still outstanding) | P1 |
| Ending | `ending.tscn`: two Labels, no backdrop / panel / wordmark | P2 |

### 1.3 Acceptance anchors (theme)

- Single token table in theme (or `themes/starsoil_tokens.gd` constants) matching ui-assets §0.1 hex values ±2/255.
- Zero scene-level teal used as decorative accent; teal only on power cost / unpowered semantics.
- Font ladder: body 14 / panel title 18 / screen title 20 / banner 22 via theme types or named variations.
- New UI panels inherit theme StyleBoxTexture — no new `StyleBoxFlat` for chrome (dim overlays OK if tokenised).

---

## 2. World tiles, overlays, buildings, greybox leftovers

### 2.1 Present assets (`assets/art/world/`)

| Path | Size | Role |
|---|---|---|
| `tiles/env_world_soil_base.png` | 32×32 | Ground — **noisy / crude** vs title plate |
| `tiles/env_ore_{dust,shard,core}_set.png` | 160×32 (5×32) | Ore atlases — only **frame 0** wired |
| `tiles/env_world_rock_wall.png` / `env_mine_wall_atlas.png` | / 384×32 | Rock wall (+ atlas fallback) |
| `decals/env_world_soil_{crack,damage,ore_fleck}.png` | — | Sparse decals (~6.5% cells) — **working** |
| `decals/env_boss_sigil_{active,dormant}.png` | — | Files exist; mine-floor authored stage incomplete |
| `buildings/` | **MISSING** | ENV-21..27 |
| `background/` | **MISSING** | ENV-18..20 parallax |

### 2.2 Code behaviour

- `WorldRenderer` still documents itself as grey-box monochrome fallback; solid-colour `Image.fill` remains if probe misses.
- Ore/wall atlases: `texture_region_size=32`, **`create_tile(Vector2i.ZERO)` only** — damage / variant tiles dead weight on disk.
- `World._buildings` never populated from snapshot `placed_buildings` — **hard greybox leftover** (worse than coloured rectangles: *nothing*).
- No `WorldBorder` layer (ENV-28); boundaries are invisible `StaticBody2D` only.
- No parallax / sky under TileMaps — world reads as flat tile sheet against void.

### 2.3 Aesthetic risk (anti-clone)

Ore-node framing (crystal in rock ring on brown dirt) currently trends toward **generic survival/sandbox** readability language. Contract (`docs/art/environment-assets.md` §0.2) wants **永暮余辉**: cool deep soil, warm rim light from above, crystal glow as starsoil motif — not bright “harvest node” pop. Retarget must keep readability **without** Terraria/Stardew silhouette quotes (`AGENTS.md`).

---

## 3. Player / explore + battle unit readability

### 3.1 Explore (`scenes/player.tscn` + ART-019)

- Frames present: idle×2, walk×2, mine×4, place×4, talk×2 at **48×48**.
- Issues: low value range vs dark soil; weapon/legs merge; weak rim light; idle↔walk palette drift already noted in `ops/art-approval.md`.
- Acceptance target: readable at 1× on soil + rock_wall; silhouette ID without outline crayon; warm 1px top rim consistent with env light direction.

### 3.2 Battle units (wired allowlist)

`WIRED_BATTLE_UNIT_IDS`: luoxian_fighter, misa_weaver, drift_swarmling, shard_husk, veinwarden_echo, lumen_leviathan (P1+P2).

- Art quality generally **above** explore; cyan emissive accents aid focus.
- Runtime still builds **ColorRect+Label greybox first**, then swaps sprite when frames resolve (`battle_scene.gd`). Destabilize flash modulates sprite **or** leftover box — OK functionally, but failed probes expose coloured bricks.
- Anchor: bottom-align via `unit_sprite_anchor_height`; enemy `flip_h` — keep.
- Gaps: no HP bar chrome / status pip art; phase banners are coloured Labels not `UIA-BAT-BNR-*` panels; no track floor art.

### 3.3 Consistency rule for refactor

Dual-res stays: explore 48px “tool silhouette”, battle 128px “hero plate”. Shared **palette anchors** (Luoxian navy + copper/gold, cyan = lumen energy) must match within ±10% value (`character-assets.md` §1.3). Explore pass is a polish refresh, not a style reboot toward farm-sim characters.

---

## 4. Title / menus / battle UI

### 4.1 Title

- Strength: `bg_title.png` is the best on-disk expression of 余辉 — keep as north-star plate.
- Weakness: title string is Label 64px gold, not `UIA-TTL-LOGO` wordmark; subtitle teal; `ColorRect` rule; button rail lacks dark safety scrim (`UIA-TTL-BTNRAIL`); layout centered VBox instead of asymmetric card language in ui-assets §7.2.
- Help panel uses texture — good.

### 4.2 Menus / HUD panels

- Inventory / Menu / Help panels skinned — good.
- Content inside still greybox lists; craft rows lack icons / affordance colour beyond default Button.
- Startup (`app.tscn`): stacked ColorRects + teal rule + large Label — content scrubbed of “greybox” copy earlier, but **visual** still splash-placeholder.

### 4.3 Battle UI

| Node | State |
|---|---|
| TurnLabel / ActionsBox | Themed buttons; no action icons |
| Phase/Round banners | Hardcoded orange/gold Label colours |
| FinishBanner | `StyleBoxFlat` dim panel + 48px Label |
| Tracks | No floor art; units float on empty Node2D |
| Report log | Text colours hardcoded in `battle_scene.gd` |

---

## 5. Code / scene structure blocking polish

### 5.1 Hardcoded StyleBox / Color debt

| Location | Debt |
|---|---|
| `themes/starsoil_theme.tres` | Incomplete type set; panel texture = menu only (inventory/dialog/help duplicated in scenes) |
| `scenes/battle.tscn` | `StyleBoxFlat_finish_dim` |
| `scenes/title_screen.tscn` / `app.tscn` | ColorRect rules; teal / gold overrides |
| `src/encounters/battle_scene.gd` | ~12 colour consts + ColorRect unit boxes |
| `src/world/world_renderer.gd` | Fallback fill colours; atlas tile-0 only |
| `src/ui/hud.gd` | Unpowered ColorRect dots; text BuildBar |
| `src/world/world.gd` | **No building presentation sync** |

### 5.2 Unconnected / underused assets

- Ore atlas frames 1–4 (damage/deplete) — not selected by gathering state.
- Boss sigil PNGs — not driven by authored boss-floor + encounter state presentation contract.
- `icons/64/*` — HUD uses smaller probes; 64px set underused.
- Building / background / battle-UI / logo contracts — **zero files on disk**.

### 5.3 Structural blockers (must fix before “pretty”)

1. **BuildingPresenter** (or `World._sync_buildings`) reading snapshot → Sprite2D under `$Buildings`, powered texture swap via PowerGrid.
2. **Theme expansion** so scenes stop forking StyleBoxes.
3. **Atlas region map** soil/ore/wall variants keyed by cell damage / variant hash.
4. **Token module** shared by HUD/battle/title (stop hex drift).
5. Keep Autoload rules (`AGENTS.md`) — presentation-only; no new global buses.

---

## 6. Prioritized packs (P0 / P1 / P2)

Owners: **工程** = engineering/integration; **美术** = art production + approval (`ops/art-approval.md`).

### Pack P0 — World Presence (recommended next dispatch)

**Goal:** Make the sandbox loop *look inhabited* under 余辉 light; retire invisible buildings and crude soil/ore first impression.

| ID | Work | Owner | Key files / assets |
|---|---|---|---|
| P0-A | Produce ENV-21..26 (6× `_powered`/`_unpowered` 48×48) + ENV-27 dust×2 | 美术 | `assets/art/world/buildings/*`, staging under `ops/art-staging/` |
| P0-B | `World` building sync: spawn/despawn/update sprites from `placed_buildings` + power state; SFX hook unchanged | 工程 | `src/world/world.gd`, new `src/world/building_presenter.gd` (optional), tests `tests/unit/test_world_*` |
| P0-C | Retarget soil base + ore atlases to 永暮余辉 (cool soil, warm top rim, starsoil glow ≤5% gold) — **not** farm-sim harvest nodes | 美术 | replace `env_world_soil_base.png`, `env_ore_*_set.png` after approval |
| P0-D | Wire ore atlas regions to gathering damage / destroyed deltas (use frames beyond 0) | 工程 | `src/world/world_renderer.gd`, gathering apply path |
| P0-E | BuildBar: building icon + name; replace ColorRect dot with tokenised pip / theme icon | 工程+美术 | `src/ui/hud.gd`, `scenes/ui_hud.tscn`, optional `ui/icons/ui_bld_*.png` |

**Acceptance (P0):**

1. Place any of 6 buildings → visible 48×48 sprite centered on cell; unpowered variant within 1s of PowerGrid change.
2. Soil/ore screenshot vs `bg_title.png` shares hue family (cool ground, warm rim); owner visual OK (no Terraria/Stardew quote).
3. Mining damage advances ore atlas frame; destroyed cell clears overlay.
4. BuildBar shows icon+label; no raw multi-line cost as sole identity.
5. GUT world/HUD suites green; art-approval rows `approved` before engine paths change.

### Pack P1 — Theme tokens + HUD/Title/Battle chrome

| ID | Work | Owner | Files |
|---|---|---|---|
| P1-A | Expand `starsoil_theme.tres`: font ladder, shared panel variants (dialog/inv/menu/help as theme types), focus gold ring; purge duplicate scene StyleBoxes where possible | 工程 | `themes/starsoil_theme.tres`, `scenes/{ui_hud,dialogue_box,title_screen,battle}.tscn`, `tests/unit/test_ui_theme.gd` |
| P1-B | Kill decorative teal; power costs use `semantic.teal` only | 工程 | title/app/battle label overrides |
| P1-C | Inventory slot frames + recipe row icons | 美术+工程 | `UIA-INV-*`, `hud.gd` |
| P1-D | Title LOGO wordmark + button-rail scrim; keep `bg_title` | 美术+工程 | `UIA-TTL-LOGO`, `title_screen.tscn` |
| P1-E | Battle: track floor, action icons, banner panels; retire FinishBanner StyleBoxFlat | 美术+工程 | `UIA-BAT-*`, `battle.tscn`, `battle_scene.gd` |
| P1-F | Explore Luoxian readability refresh (rim light, weapon separation) aligned to battle palette | 美术 | `assets/art/characters/luoxian/actions/*` |

**Acceptance (P1):** Theme test asserts type coverage; title uses wordmark; battle has non-empty track art; explore idle readable on new soil; no new StyleBoxFlat chrome.

### Pack P2 — Depth & endings

| ID | Work | Owner | Files |
|---|---|---|---|
| P2-A | Parallax ENV-18..20 under world | 美术+工程 | `assets/art/world/background/*`, `world.tscn` |
| P2-B | Border wall ENV-28 + WorldBorder layer | 美术+工程 | env + `world.gd` |
| P2-C | Boss floor + sigil stage presentation | 美术+工程 | authored region + sigil state |
| P2-D | Ending backdrop / panel / bell staging polish | 美术+工程 | `ending.tscn` |
| P2-E | Startup splash replace ColorRect stack with themed plate | 工程 | `app.tscn` |
| P2-F | Optional Bold font subset + toast banner art | 美术+工程 | fonts + HUD |

**Acceptance (P2):** Visible horizon behind soil; border readable; ending not blank; startup matches title family.

---

## 7. Dispatch order & non-goals

**Order:** P0 (this audit’s recommended next) → P1 → P2.  
Do **not** parallelize P0-C art with unrelated style experiments that quote commercial farm/sandbox UIs.

**Non-goals for refactor PRs:**

- No G7 playthrough fabrication.
- No Autoload sprawl / event bus.
- No “make it look like Terraria/Stardew” prompts or silhouettes (`AGENTS.md`).
- This plan PR ships **docs + state note only** — no mass asset replace here.

---

## 8. State / residual

See `ops/state.json`:

- `visual_polish_packet`: `closed` (prior)
- `visual_refactor_packet`: `planned` (this audit)
- `known_residuals` includes pointer to this document

Resume / next packet id suggestion for coordinator: `VISUAL-REFACTOR-P0`.
