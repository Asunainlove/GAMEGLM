# P2-A UI Assets QC Report

- Generated: 2026-09-11 (Asia/Shanghai)
- True source: `/workspace/gameglm-art/v2-polish/ui/p2`
- Staging: `/workspace/GAMEGLM/ops/art-staging/v2-polish/ui/p2`
- Flat mirrors: `/workspace/gameglm-art/v2-polish/ui` + `/workspace/GAMEGLM/ops/art-staging/v2-polish/ui`
- **NO writes to `/workspace/GAMEGLM/assets/`** (asserted)
- Logo method: path (b): Noto Sans CJK SC Bold (OFL) glyphs drawn, then systematically reshaped — crystal bevel ends, prism facet highlights, stroke-end 30° cuts, inner gold.bright / outer gold.dark bevel. No Microsoft YaHei. Original 永暮余辉 mark.
- Contrast gold.main `#E8C878` on bg.deep `#0B111C`: **11.67:1** (need ≥7:1)
- Logo gold.main/bright / full canvas: 0.0518 (≤15% rule)
- Tracks crystal veins area: 0.0053 (≤5%)
- Tracks gold.mainish / canvas: 0.0000

## Files

| file | bytes | mode/size | md5 |
|---|---|---|---|
| `p2a_contact.jpg` | 85199 | RGB 1400×980 | `144abeae314b4dd24e3fde01e76ce8aa` |
| `ui_bat_track_div.png` | 138 | RGBA 1120×4 | `1698f6d536b68e9b2a89c7fe3924eda3` |
| `ui_bat_track_div_back.png` | 138 | RGBA 1120×4 | `1698f6d536b68e9b2a89c7fe3924eda3` |
| `ui_bat_track_div_front.png` | 138 | RGBA 1120×4 | `1698f6d536b68e9b2a89c7fe3924eda3` |
| `ui_bat_track_div_mid.png` | 138 | RGBA 1120×4 | `1698f6d536b68e9b2a89c7fe3924eda3` |
| `ui_bat_tracks.png` | 40116 | RGBA 1280×560 | `9020f7841ac7e4132c1f9a61a9ddbfa7` |
| `ui_hud_overflow_badge.png` | 193 | RGBA 24×16 | `12635da37bca23a574e2984f772f02a0` |
| `ui_hud_slotframe.png` | 192 | RGBA 40×40 | `fa65c6caed4f6dfe9f21a1894fe84242` |
| `ui_inv_qty.png` | 172 | RGBA 20×14 | `7b6705509178d5fbad152fc82ee6408b` |
| `ui_inv_slot.png` | 202 | RGBA 48×48 | `e978117cecc72211313d76e6df221081` |
| `ui_inv_slot_hover.png` | 199 | RGBA 48×48 | `0f04879f467d66677ccfb5605f7791d1` |
| `ui_ttl_logo.png` | 10563 | RGBA 1280×320 | `444c8342229c208f9af2fe5a1702e4d6` |
| `ui_ttl_logo.svg` | 14655 | .svg | `611c693ee0bd43f5b15e522f385a7114` |
| `ui_ttl_logo_640.png` | 25373 | RGBA 640×160 | `636b12ba1520b87523feb1b79ff904b7` |

## Byte-identical true ↔ staging ↔ flats
- `p2a_contact.jpg`: OK
- `ui_bat_track_div.png`: OK
- `ui_bat_track_div_back.png`: OK
- `ui_bat_track_div_front.png`: OK
- `ui_bat_track_div_mid.png`: OK
- `ui_bat_tracks.png`: OK
- `ui_hud_overflow_badge.png`: OK
- `ui_hud_slotframe.png`: OK
- `ui_inv_qty.png`: OK
- `ui_inv_slot.png`: OK
- `ui_inv_slot_hover.png`: OK
- `ui_ttl_logo.png`: OK
- `ui_ttl_logo.svg`: OK
- `ui_ttl_logo_640.png`: OK

## Assets path guard
- Leaked into assets/: none

## Deliverable checklist
- [x] ui_ttl_logo.png
- [x] ui_ttl_logo_640.png
- [x] ui_hud_slotframe.png
- [x] ui_hud_overflow_badge.png
- [x] ui_inv_slot.png
- [x] ui_inv_slot_hover.png
- [x] ui_inv_qty.png
- [x] ui_bat_tracks.png
- [x] ui_bat_track_div.png
- [x] p2a_contact.jpg

## Notes
- Capsule badges (`ui_hud_overflow_badge`, `ui_inv_qty`) use 1px `gold.dark` outline per spec; on 20×14 / 24×16 canvases perimeter naturally exceeds 15% if counting gold.dark — chrome fill is bg.deep; gold.main/bright area is 0%.
- `ui_inv_slot_hover` gold.main is 1px outer stroke only (~8% of 48×48).
- Optional SVG `ui_ttl_logo.svg` embeds PNG wordmark (vector accents optional); PNG is required deliverable.

## Overall: PASS
