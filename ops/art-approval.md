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

| luoxian_fighter_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_idle_00.png |
| luoxian_fighter_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_idle_01.png |
| luoxian_fighter_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_attack_00.png |
| luoxian_fighter_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_attack_01.png |
| luoxian_fighter_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_attack_02.png |
| luoxian_fighter_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_hit_00.png |
| luoxian_fighter_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_death_00.png |
| luoxian_fighter_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/luoxian_fighter/luoxian_fighter_death_01.png |
| misa_weaver_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_idle_00.png |
| misa_weaver_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_idle_01.png |
| misa_weaver_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_attack_00.png |
| misa_weaver_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_attack_01.png |
| misa_weaver_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_attack_02.png |
| misa_weaver_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_hit_00.png |
| misa_weaver_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_death_00.png |
| misa_weaver_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/battle/units/misa_weaver/misa_weaver_death_01.png |



> Note (2026-09-03): batch2 `luoxian_fighter` + `misa_weaver` frames auto-approved by 幕僚长 standing auth and dropped into `assets/art/battle/units/`.

| drift_swarmling_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_idle_00.png |
| drift_swarmling_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_idle_01.png |
| drift_swarmling_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_attack_00.png |
| drift_swarmling_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_attack_01.png |
| drift_swarmling_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_attack_02.png |
| drift_swarmling_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_hit_00.png |
| drift_swarmling_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_death_00.png |
| drift_swarmling_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/drift_swarmling/drift_swarmling_death_01.png |
| shard_husk_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_idle_00.png |
| shard_husk_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_idle_01.png |
| shard_husk_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_attack_00.png |
| shard_husk_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_attack_01.png |
| shard_husk_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_attack_02.png |
| shard_husk_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_hit_00.png |
| shard_husk_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_death_00.png |
| shard_husk_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/shard_husk/shard_husk_death_01.png |
| veinwarden_echo_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_idle_00.png |
| veinwarden_echo_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_idle_01.png |
| veinwarden_echo_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_attack_00.png |
| veinwarden_echo_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_attack_01.png |
| veinwarden_echo_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_attack_02.png |
| veinwarden_echo_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_hit_00.png |
| veinwarden_echo_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_death_00.png |
| veinwarden_echo_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/veinwarden_echo/veinwarden_echo_death_01.png |
| lumen_leviathan_phase1_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_idle_00.png |
| lumen_leviathan_phase1_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_idle_01.png |
| lumen_leviathan_phase1_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_attack_00.png |
| lumen_leviathan_phase1_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_attack_01.png |
| lumen_leviathan_phase1_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_attack_02.png |
| lumen_leviathan_phase1_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_hit_00.png |
| lumen_leviathan_phase1_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_death_00.png |
| lumen_leviathan_phase1_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_death_01.png |
| lumen_leviathan_phase2_idle_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_idle_00.png |
| lumen_leviathan_phase2_idle_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_idle_01.png |
| lumen_leviathan_phase2_attack_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_attack_00.png |
| lumen_leviathan_phase2_attack_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_attack_01.png |
| lumen_leviathan_phase2_attack_02 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_attack_02.png |
| lumen_leviathan_phase2_hit_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_hit_00.png |
| lumen_leviathan_phase2_death_00 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_death_00.png |
| lumen_leviathan_phase2_death_01 | 2-units | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次2 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_death_01.png |
| panel_dialog | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/panels/panel_dialog.png |
| panel_inventory | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/panels/panel_inventory.png |
| panel_menu | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/panels/panel_menu.png |
| panel_help | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/panels/panel_help.png |
| btn_normal | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/buttons/btn_normal.png |
| btn_hover | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/buttons/btn_hover.png |
| btn_pressed | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/buttons/btn_pressed.png |
| btn_disabled | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/buttons/btn_disabled.png |
| ui_item_starsoil_dust_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_starsoil_dust.png |
| ui_item_starsoil_dust_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_starsoil_dust.png |
| ui_item_ore_shard_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_ore_shard.png |
| ui_item_ore_shard_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_ore_shard.png |
| ui_item_ore_core_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_ore_core.png |
| ui_item_ore_core_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_ore_core.png |
| ui_item_warm_seed_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_warm_seed.png |
| ui_item_warm_seed_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_warm_seed.png |
| ui_item_cyan_mist_vial_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_cyan_mist_vial.png |
| ui_item_cyan_mist_vial_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_cyan_mist_vial.png |
| ui_item_toothed_trap_32 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_toothed_trap.png |
| ui_item_toothed_trap_64 | 3-ui | Cursor GenerateImage | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长/GenerateImage | 幕僚长 (standing auth 2026-09-03) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_toothed_trap.png |

> Note (2026-09-03): batch2 remaining units (`drift_swarmling`, `shard_husk`, `veinwarden_echo`, `lumen_leviathan` phase1+phase2) + batch3 UI (panels/buttons/icons 32+64) auto-approved by 幕僚长 standing auth 2026-09-03 and dropped into `assets/art/`.

| ui_item_lumen_shard | 3-ui | alias of ui_item_ore_shard (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_lumen_shard.png |
| ui_item_lumen_shard_64 | 3-ui | alias of ui_item_ore_shard (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_lumen_shard.png |
| ui_item_resonant_core | 3-ui | alias of ui_item_ore_core (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_resonant_core.png |
| ui_item_resonant_core_64 | 3-ui | alias of ui_item_ore_core (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_resonant_core.png |
| ui_item_echo_seed | 3-ui | alias of ui_item_warm_seed (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_echo_seed.png |
| ui_item_echo_seed_64 | 3-ui | alias of ui_item_warm_seed (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_echo_seed.png |
| ui_item_sedative_mist | 3-ui | alias of ui_item_cyan_mist_vial (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_sedative_mist.png |
| ui_item_sedative_mist_64 | 3-ui | alias of ui_item_cyan_mist_vial (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_sedative_mist.png |
| ui_item_shock_trap | 3-ui | alias of ui_item_toothed_trap (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/ui_item_shock_trap.png |
| ui_item_shock_trap_64 | 3-ui | alias of ui_item_toothed_trap (contract item id) | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 幕僚长 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/art/ui/icons/64/ui_item_shock_trap.png |

> Note: contract-id icon aliases added for AssetAdapter `ui_item_<item_id>` wiring.


| font_noto_sans_sc_regular | 3-ui | notofonts/noto-cjk Sans2.004 + pyftsubset | docs/art/prompts/plan-a-p0-batch-prompts.md#批次3 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/fonts/NotoSansSC-Regular.subset.otf |


| bgm_title | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_title.ogg |
| bgm_explore | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_explore.ogg |
| bgm_build | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_build.ogg |
| bgm_battle | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_battle.ogg |
| bgm_boss | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_boss.ogg |
| bgm_boss_final | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/bgm/bgm_boss_final.ogg |
| sfx_mine_hit | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_mine_hit.ogg |
| sfx_mine_depleted | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_mine_depleted.ogg |
| sfx_build_place | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_build_place.ogg |
| sfx_build_denied | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_build_denied.ogg |
| sfx_craft_success | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_craft_success.ogg |
| sfx_ui_click | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_ui_click.ogg |
| sfx_ui_toggle | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_ui_toggle.ogg |
| sfx_dialogue_page | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_dialogue_page.ogg |
| sfx_dialogue_choice | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_dialogue_choice.ogg |
| sfx_battle_action | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_battle_action.ogg |
| sfx_battle_hit | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_battle_hit.ogg |
| sfx_power_unstable | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_power_unstable.ogg |
| sfx_boss_phase | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_boss_phase.ogg |
| sfx_victory | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_victory.ogg |
| sfx_defeat | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_defeat.ogg |
| sfx_save_notice | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_save_notice.ogg |
| sfx_ending_bell | 4-audio | ffmpeg lavfi procedural | docs/art/prompts/plan-a-p0-batch-prompts.md#批次4 | 2026-09-03 | 美术 | 幕僚长 (standing auth / auto-approve) | 2026-09-03 | approved | assets/audio/sfx/sfx_ending_bell.ogg |

## 灰盒交付授权记录（方案 B 专用，待所有者明示后填写）

- 授权语句：（由项目所有者提供，例："授权保持灰盒交付为 G6 交付形态"）
- 授权日期：
- 授权人：
- 协调者处置：G6 标记 `accepted_greybox`，直接进入 G7 真人门禁（docs/g6-g7-human-gates-guide.md §2）。

> Note (2026-09-03): `font_noto_sans_sc_regular` auto-approved by 幕僚长 standing auth; OFL + PROVENANCE under `assets/fonts/`.

> Note (2026-09-03): batch4 audio 23 clips auto-approved by 幕僚长 standing auth after ffprobe gate; explore trimmed to 120s, ending_bell to 1.8s.


> Note (2026-09-03): v2-polish style gate — env soil + panel_dialog + btn_normal approved/drop-in by 幕僚长; unit idle samples style_pass (pending full frame sets before drop-in). Constraints: luoxian keep blade+cloak silhouette per battle-assets; misa keep thread/spool language; swarmling body ≤64×64 center.
| env_world_soil_base_v2 | v2-polish | Cursor GenerateImage | docs/art/environment-assets.md#ENV-01 | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/world/tiles/env_world_soil_base.png |
| luoxian_fighter_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/luoxian_fighter/luoxian_fighter_idle_00.png |
| misa_weaver_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/misa_weaver/misa_weaver_idle_00.png |
| drift_swarmling_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/drift_swarmling/drift_swarmling_idle_00.png |
| shard_husk_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/shard_husk/shard_husk_idle_00.png |
| veinwarden_echo_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/veinwarden_echo/veinwarden_echo_idle_00.png |
| lumen_leviathan_phase1_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/lumen_leviathan/phase1/lumen_leviathan_idle_00.png |
| panel_dialog_v2 | v2-polish | Cursor GenerateImage | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/panels/panel_dialog.png |
| btn_normal_v2 | v2-polish | Cursor GenerateImage | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/buttons/btn_normal.png |

| lumen_leviathan_phase2_idle_00_v2 | v2-polish | Cursor GenerateImage | docs/art/battle-assets.md | 2026-09-03 | 美术 | 幕僚长-style_pass | 2026-09-03 | pending | assets/art/battle/units/lumen_leviathan/phase2/lumen_leviathan_idle_00.png |


> Note (2026-09-03): env contract pack — approved soil_base/crack/rock_wall + ui_panel_frame→panel_dialog; **rejected** env_mine_wall_atlas_v2 (black gutters at cols 96/224/352 destroy 32px TileSet cells). Redo atlas as contiguous 12×32 without separators.
| env_world_soil_crack_v2 | v2-polish | env_v2 draft resize | docs/art/environment-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/world/decals/env_world_soil_crack.png |
| env_world_rock_wall_v2 | v2-polish | env_v2 draft resize | docs/art/environment-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/world/tiles/env_world_rock_wall.png |
| env_mine_wall_atlas_v2 | v2-polish | env_v2 draft + flip variants | docs/art/prompts/plan-a-p0-batch-prompts.md#批次1 | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | rejected | assets/art/world/tiles/env_mine_wall_atlas.png |
| ui_panel_frame_v2 | v2-polish | env_v2 draft resize | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/panels/panel_dialog.png |

| btn_hover_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/buttons/btn_hover.png |
| btn_pressed_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/buttons/btn_pressed.png |
| btn_disabled_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/buttons/btn_disabled.png |
| panel_inventory_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/panels/panel_inventory.png |
| panel_menu_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/panels/panel_menu.png |
| panel_help_v2 | v2-polish | Cursor GenerateImage / env_v2 | docs/art/ui-assets.md | 2026-09-03 | 美术 | 幕僚长 | 2026-09-03 | approved | assets/art/ui/panels/panel_help.png |

> Note (2026-09-03): UI button states + panel_inventory/menu/help approved/drop-in (panel trio identical chrome OK for theme continuity; help contract still allows inset variant later).
