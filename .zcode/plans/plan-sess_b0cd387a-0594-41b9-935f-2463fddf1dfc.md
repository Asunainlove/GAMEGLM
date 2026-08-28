# 《星壤：余辉纪元》15-Agent 并行开发总体规划

## 一、现状结论（已探明）

- main（`29d9d49`）仅含治理文档；游戏代码在 `.worktrees/w000-g1`（分支 `feature/w000-g1` @ `e7f7328`）：P00/P01 已 VERIFIED，**P02（原子 GameState + Save v1，26/26 测试通过）SUBMITTED 待验收**；P03/P04 未开始，G2–G7 全部未开始。
- 缺口：ContentDB 不存在、无输入映射、无存档迁移/golden fixture、无 CI、worktree 元数据含改名前旧路径（GAME→GAMEGLM）、ops 状态落后于分支、`requirements-dev.txt`（jsonschema 4.25.1）与 TOOLCHAIN.md（4.25.0）版本失配。
- **技能声明**：godot-development-stack 技能已加载。其权威引擎技能 GodotPrompter 及伴侣技能（game-ai、dialogue-systems、save-systems 等）**未安装**，按技能自身的 Missing dependency 规则：明确声明此限制，以 Godot 4.x 最佳实践 + 本仓库 AGENTS.md 约束继续。

## 二、总体模式：契约先行 + 文件所有权隔离 + 15 分支同时启动

15 个 agent 之间有真实依赖（战斗需要内容 schema、内容数据需要 schema）。解法是**把依赖倒转**：派发前，协调者把所有跨模块契约（JSON Schema、API 签名、数据 ID、节点路径、输入 action 名）冻结并提交到 main；每个 agent 只实现"对照契约 + 本地 stub 测试"的自己模块，绝不引用其他 agent 未合并的代码（GameState/SaveService 两个既有 autoload 除外）。协调者按依赖序合并 15 个分支，每包合并即跑全量门禁。

## 三、Wave 0 — 协调者 Git 集成与契约预置（派发前完成）

1. `git worktree repair` 修正旧路径元数据；在 worktree 复跑 `scripts/Verify-Toolchain.ps1` 验收 **W000-P02 → 标 VERIFIED**（更新 backlog.json/evidence/state.json）。
2. 合并 `feature/w000-g1` → main（merge commit），打 tag `packet/w000-p02`。
3. 统一 jsonschema 版本（以 4.25.1 为准，更新 TOOLCHAIN.md）。
4. 预提交契约层到 main：
   - `docs/plans/2026-08-28-parallel-module-roadmap.md`（15 包详规、文件所有权表、合并顺序、agent 报告协议）
   - `docs/plans/contracts/`：输入 action 表（move_left/right/up/down、interact、mine、place、toggle_inventory、toggle_overlay、menu 等）、ContentDB API 签名、StatePatch 使用约束、关系 flag 命名（`rel_<char>_<dim>`）、战斗数据 schema 引用、场景路径契约（`res://scenes/player.tscn` 等）
   - `schemas/*.schema.json`：content-item / building-recipe / combat-unit / combat-action / event / encounter / save-envelope（Draft 2020-12）
   - `project.godot` `[input]` 段（固定 action 名，其余 agent 禁改 project.godot）
   - `.github/workflows/ci.yml`：windows runner + Godot 4.7.2 headless + Run-Gut + Python jsonschema 内容校验（push/PR 触发；无远程时本地不生效，如实声明）
5. 从 main 创建 15 个 worktree：`.worktrees/wp01`…`wp15`，分支 `feature/wp01-content-db` 等。
6. **单条消息并行派发 15 个 agent**（run_in_background 并行）。

## 四、15 个工作包（全部同时启动）

每包统一要求：隔离 worktree/分支、强类型 GDScript、TDD（先记录 RED 再 GREEN）、禁止改共享文件（project.godot、ops/**、scripts/Verify-Toolchain.ps1、docs/**、src/state/**、src/save/** 除非属于本包）、证据含精确命令+退出码+commit+限制+下一步、只能报 SUBMITTED 或 BLOCKED。

| # | 包名（里程碑） | 允许路径（所有权） | 核心交付与验收 |
|---|---|---|---|
| WP01 | ContentDB 核心（G2） | `src/content/**`、`project.godot`（仅 autoload 一行）、`scripts/Validate-Content.ps1`、`tests/unit/test_content_db*` | `ContentDB.bootstrap()` 加载 `data/content/**.json`、schema 校验、不可变、snake_case ID、交叉引用检查、content_hash；Validate-Content（python jsonschema）退出码 0 |
| WP02 | 玩家控制器（G1-P03） | `src/player/**`、`scenes/player.tscn`、`tests/unit/test_player*` | 8 向移动（预置 input action）、CharacterBody2D 碰撞、interact/mine/place 意图信号（不直接改状态）；移动确定性测试通过 |
| WP03 | 世界与 Chunk（G1/G3） | `src/world/**`、`scenes/world.tscn`、`tests/unit/test_world*` | 单 Chunk 灰盒 + 4×2 网格数据结构、TileMapLayer 渲染、破坏格同步 `set_destructible_cell`、矿脉覆盖层开关；实例化 `res://scenes/player.tscn`（路径契约） |
| WP04 | Save v2 迁移与 golden fixture（G2） | `src/save/**`、`tests/golden/**`、`schemas/save*`、`tests/unit/test_save_v2*` | 迁移注册表 v1→v2、content_hash 接线、golden fixture 加载比对、未来版本拒绝；全量 SaveService 测试 + golden 对比通过 |
| WP05 | 采集与背包逻辑（G3） | `src/gathering/**`、`tests/unit/test_gathering*` `test_inventory*` | 确定性挖掘规则（cell→材料映射注入）、工具次数、掉落经 StatePatch add_item、背包容量/堆叠纯逻辑 |
| WP06 | 建造与放置（G3） | `src/building/**`、`tests/unit/test_building*` | 放置合法性（相邻/占地/材料）、6 配方消费校验、经 `place_building` 提交；非法放置零修改 |
| WP07 | 房间与电力（G3） | `src/power/**`、`tests/unit/test_power*` | 房间闭合检测、电力供需模拟、锚居工坊规则（纯逻辑模块） |
| WP08 | 叙事事件与对话（G4） | `src/narrative/**`、`data/events/**`、`scenes/dialogue_box.tscn`、`tests/unit/test_narrative*` | 三类类型化事件（dialogue/effect/choice）运行器、数据驱动（符合 event schema）、效果经 GameState patch、选择落 set_flag |
| WP09 | 关系与立场（G4） | `src/relations/**`、`tests/unit/test_relations*` | affection/trust/ideology 三维、`rel_<char>_<dim>` flag 持久化、变化规则、政策门控 `policy_unlocked()` |
| WP10 | 战斗核心（G4） | `src/combat/**`、`schemas/combat*`、`tests/unit/test_combat*` | 确定性回合制引擎：3 槽队形轨道、稳定度/相位失稳、行动队列、种子 RNG、结算产出 StatePatch 描述；同种子同结果测试 |
| WP11 | UI 框架与 HUD（G3/G4） | `src/ui/**`、`scenes/ui_*.tscn`、`themes/**`、`tests/unit/test_ui*` | 简体中文 Theme、HUD、背包面板、对话面板、菜单；只读 snapshot 渲染、不写持久状态 |
| WP12 | 内容数据创作（G3/G4） | `data/content/**`、`data/encounters/**`、`data/events/story_*.json`、`tests/unit/test_content_data*` | 3 材料、1 剧情核心、6 配方/建筑、2 普通+1 精英+1 两阶段 Boss、洛弦/弥砂事件稿、3 场遭遇配置；全部通过 schema+交叉引用校验 |
| WP13 | 三场遭遇与 Boss（G4） | `src/encounters/**`、`scenes/battle.tscn`、`tests/unit/test_encounters*` | 遭遇编排器（flag 门控触发）、Boss 两阶段切换、沙盒道具入场接口、战斗场景接 WP10 引擎 |
| WP14 | 剧情推进与世界回应（G4/G5） | `src/progression/**`、`tests/unit/test_progression*` | station_mode/approach/policy 三次选择编排、世界/地图变化触发器、Boss 条件变化、角色回应触发、共生结局 trust 门控逻辑 |
| WP15 | 三结局与 RC 门禁（G5/G7） | `src/endings/**`、`scenes/ending.tscn`、`export_presets.cfg`、`scripts/Verify-Slice.ps1`、`docs/rc-checklist.md`、`tests/unit/test_endings*` | 开采/封存/共生三结局判定+灰盒结局场景、Verify-Slice（节奏冒烟+性能 smoke+干净导出检查+原创性清单跑批） |

**共享文件冲突预案**：`project.godot` 仅 WP01 触碰（autoload 行）；`scenes/world.tscn` 仅 WP03；跨包实例化一律走固定路径契约。`src/state/**` 无人触碰（v1 的 5 种 StatePatch 操作 + set_flag 已足够全部需求，冻结防冲突）。

## 五、合并与验收队列（协调者逐包执行）

合并顺序（依赖序）：`WP01 → WP04 → WP05 → WP06 → WP07 → WP03 → WP02 → WP11 → WP08 → WP09 → WP10 → WP12 → WP13 → WP14 → WP15`。
每包流程：审阅 diff（规格+代码质量双评审）→ merge（保留原子提交）→ 复跑该包测试 + `Run-Gut.ps1` 全套件 + `Verify-Toolchain.ps1` → 通过则标 VERIFIED、更新 `ops/backlog.json`/`state.json`/evidence、打 tag `packet/wp##`；失败则带着具体失败输出打回对应 agent 修复（可复活原 agent 继续其 worktree）。每个 checkpoint 记录确切命令、退出码、commit、限制、下一步。

最终交付：main 上 G1–G5 完整灰盒垂直切片（探索采集→建造锚居→剧情三选择→三场战斗→关系门控→三结局→存档重载全闭环）+ G7 RC 门禁脚本与 CI 文件就绪。**G6 正式美术不在本轮**（AGENTS.md 要求生成资产需溯源+人工审批，保持灰盒并预留管线）。

## 六、风险与缓解

- 15 分支同时跑的合并冲突 → 所有权表 + 契约先行 + 固定合并序；冲突点已知且机械（project.godot 一行）。
- 接口不匹配 → schemas 与 API 签名在派发前冻结进 main；agent 测试只依赖契约与本地 stub。
- Agent 上下文超限/失败 → 每包保持小而有界；BLOCKED 立即上报，协调者重派或收编为后续包。
- Godot 4.7.2 headless 行为差异 → 一切以 worktree 内真实命令输出为准，严禁无新鲜输出声称通过。

## 七、执行所需权限

git 操作（worktree/merge/tag/commit/branch）、运行 PowerShell 门禁脚本（Run-Gut/Verify-Toolchain/Validate-Content/Verify-Slice）、运行 Godot headless、并行派发 15 个 Agent（每波合并后按需复活修复）。