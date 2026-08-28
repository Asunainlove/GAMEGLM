# 2026-08-28 并行模块路线图（15 工作包同时启动）

模式：**契约先行**。`docs/plans/contracts/module-contracts.md` 与 `schemas/*.schema.json` 在派发前冻结进 main；15 个包在独立 worktree/分支上对照契约实现，协调者按依赖序合并并逐包验收。

## 文件所有权表（越界 = 打回）

| 包 | 分支 | 允许路径 |
|---|---|---|
| WP01 ContentDB | `feature/wp01-content-db` | `src/content/**`、`project.godot`（仅 autoload 一行）、`scripts/Validate-Content.ps1`、`scripts/validate_content.py`、`tests/unit/test_content_db*.gd`、`tests/unit/test_p02_contract_files.gd`（仅更新 autoload 断言为含 ContentDB） |
| WP02 玩家控制器 | `feature/wp02-player` | `src/player/**`、`scenes/player.tscn`、`tests/unit/test_player*.gd` |
| WP03 世界与 Chunk | `feature/wp03-world` | `src/world/**`、`scenes/world.tscn`、`tests/unit/test_world*.gd` |
| WP04 状态扩展+存档迁移 | `feature/wp04-save-v2` | `src/state/**`、`src/save/**`、`tests/golden/**`、`tests/unit/test_state_v2*.gd`、`tests/unit/test_save_v2*.gd` |
| WP05 采集与背包 | `feature/wp05-gathering` | `src/gathering/**`、`tests/unit/test_gathering*.gd`、`tests/unit/test_inventory*.gd` |
| WP06 建造与放置 | `feature/wp06-building` | `src/building/**`、`tests/unit/test_building*.gd` |
| WP07 房间与电力 | `feature/wp07-power` | `src/power/**`、`tests/unit/test_power*.gd` |
| WP08 叙事与对话 | `feature/wp08-narrative` | `src/narrative/**`、`scenes/dialogue_box.tscn`、`tests/unit/test_narrative*.gd` |
| WP09 关系与立场 | `feature/wp09-relations` | `src/relations/**`、`tests/unit/test_relations*.gd` |
| WP10 战斗核心 | `feature/wp10-combat` | `src/combat/**`、`tests/unit/test_combat*.gd` |
| WP11 UI 框架与 HUD | `feature/wp11-ui` | `src/ui/**`、`scenes/ui_*.tscn`、`themes/**`、`tests/unit/test_ui*.gd` |
| WP12 内容数据 | `feature/wp12-content-data` | `data/**`、`tests/unit/test_content_data*.gd` |
| WP13 遭遇与 Boss | `feature/wp13-encounters` | `src/encounters/**`、`scenes/battle.tscn`、`tests/unit/test_encounters*.gd` |
| WP14 剧情推进 | `feature/wp14-progression` | `src/progression/**`、`tests/unit/test_progression*.gd` |
| WP15 结局与 RC 门禁 | `feature/wp15-endings-rc` | `src/endings/**`、`scenes/ending.tscn`、`export_presets.cfg`、`scripts/Verify-Slice.ps1`、`docs/rc-checklist.md`、`tests/unit/test_endings*.gd` |

全员共享只读：`AGENTS.md`、`docs/plans/contracts/**`、`schemas/**`、`src/core/app_result.gd`、既有 `GameState`/`SaveService`。`ops/**` 中仅允许创建 `ops/evidence/<包ID>.md`。

## 合并队列（依赖序，协调者逐包执行）

`WP01 → WP04 → WP05 → WP06 → WP07 → WP03 → WP02 → WP11 → WP08 → WP09 → WP10 → WP12 → WP13 → WP14 → WP15`

每包：双评审（规格符合 + 代码质量）→ merge → 复跑该包测试 + Run-Gut 全套件 + Verify-Toolchain → VERIFIED + tag `packet/<包ID>` + 更新 ops；失败则携输出打回原 agent 修复。

## Agent 报告协议

- 实施代理只能返回 `SUBMITTED`（附 commit SHA、测试统计、限制、下一步）或 `BLOCKED`（附阻塞原因与所需资源）。
- TDD 强制：先记录 RED（命令+输出），再实现至 GREEN（命令+输出）。禁止无新鲜命令输出声称通过。
- checkpoint 记录于 `ops/evidence/<包ID>.md`：目标、RED/GREEN 证据、决策与限制、确切下一步。

## 里程碑映射

- G1 收尾：WP02 + WP03（单 Chunk 行走骨架：移动/采矿/收集/放置锚块/存档重载）。
- G2：WP01（ContentDB）+ WP04（状态操作扩展、迁移注册表、golden fixture、content_hash 接线）。
- G3：WP03/WP05/WP06/WP07/WP11 + WP12 数据。
- G4：WP08/WP09/WP10/WP12/WP13/WP14。
- G5/G7 预备：WP14/WP15（三结局、Verify-Slice RC 门禁）。
- G6 正式美术**不在本轮**（生成资产需溯源 + 人工审批），保持灰盒。
