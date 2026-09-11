class_name StarsoilTokens
extends RefCounted

## ui-assets.md §0.1 colour tokens (±2/255). Teal is power/energy only — never decorative chrome.

const BG_DEEP := Color(0.043, 0.067, 0.110, 1.0)
const BG_PANEL := Color(0.071, 0.102, 0.149, 0.96)
const BG_PANEL_RAISED := Color(0.094, 0.133, 0.184, 1.0)
const BG_PRESSED := Color(0.063, 0.086, 0.122, 1.0)

const GOLD_MAIN := Color(0.910, 0.784, 0.471, 1.0)
const GOLD_BRIGHT := Color(0.969, 0.902, 0.690, 1.0)
const GOLD_DARK := Color(0.604, 0.482, 0.247, 1.0)

const TEXT_PRIMARY := Color(0.859, 0.902, 0.922, 1.0)
const TEXT_SECONDARY := Color(0.576, 0.655, 0.706, 1.0)
const TEXT_DISABLED := Color(0.361, 0.420, 0.463, 1.0)

const SEMANTIC_TEAL := Color(0.420, 0.788, 0.722, 1.0)
const SEMANTIC_DANGER := Color(0.851, 0.149, 0.149, 1.0)
const TRUST_LOCK := Color(0.541, 0.353, 0.290, 1.0)

## Dim overlay for FinishBanner / modal scrims (tokenised StyleBoxFlat OK).
const DIM_OVERLAY := Color(0.043, 0.067, 0.110, 0.72)

## BuildBar missing-icon placeholder (raised panel, not decorative teal).
const BUILD_ICON_PLACEHOLDER := Color(0.094, 0.133, 0.184, 0.85)

## Battle unit greybox fallback (muted panel bricks; ally.g stays > DESTABILIZED.g for flash).
const BATTLE_ALLY_BOX := Color(0.28, 0.36, 0.48, 0.94)
const BATTLE_ENEMY_BOX := Color(0.42, 0.28, 0.28, 0.94)
const BATTLE_NEUTRAL_BOX := Color(0.18, 0.20, 0.24, 0.94)
const BATTLE_BOSS_BOX := Color(0.55, 0.40, 0.18, 0.94)
