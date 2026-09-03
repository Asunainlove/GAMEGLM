# 资产审批登记表（ops/art-approval.md）

> 用途：AGENTS.md 强制的资产溯源与人工审批关卡。方案 A 生产每一批资产时逐行登记；
> 状态列 `pending` → `approved` 仅可由项目所有者人工改写。方案 B（灰盒授权）时，
> 在本文件追加一条"灰盒交付授权"记录并经所有者确认。

| 资产 ID | 批次 | 来源工具 | 提示词文件 | 生成日期 | 生成者 | 人工审批人 | 审批日期 | 状态 | 落位路径 |
|---|---|---|---|---|---|---|---|---|---|
| （示例行，正式登记时替换） | env | <工具名> | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1-1 | YYYY-MM-DD | <生成者> | <审批人> | YYYY-MM-DD | pending | assets/art/world/tiles/env_world_soil_base.png |

| env_world_soil_base | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/tiles/env_world_soil_base.png |
| env_ore_dust_set | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/tiles/env_ore_dust_set.png |
| env_ore_shard_set | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/tiles/env_ore_shard_set.png |
| env_ore_core_set | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/tiles/env_ore_core_set.png |
| env_mine_wall_atlas | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/tiles/env_mine_wall_atlas.png |
| env_boss_sigil_dormant | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/decals/env_boss_sigil_dormant.png |
| env_boss_sigil_active | 1-env | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 幕僚长/GenerateImage | Asunainlove | 2026-09-03 | approved | assets/art/world/decals/env_boss_sigil_active.png |

## 灰盒交付授权记录（方案 B 专用，待所有者明示后填写）

- 授权语句：（由项目所有者提供，例："授权保持灰盒交付为 G6 交付形态"）
- 授权日期：
- 授权人：
- 协调者处置：G6 标记 `accepted_greybox`，直接进入 G7 真人门禁（docs/g6-g7-human-gates-guide.md §2）。
