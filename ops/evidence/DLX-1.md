# DLX-1 — 结局/门控数据化（DL4）+ 信任经济均等（P0）

- 分支：`feature/dlx1-endings`（worktree `.worktrees/dlx1`）
- 日期：2026-08-31
- 范围：`docs/plans/2026-08-31-dlc-readiness-and-pm-verdict.md` DLX-1 行
- 基线：`main` @ `ffa427b`，Run-Gut 529/529 全绿（本包开工前实测）

## 1. 目标

1. 结局判定 100% 代码硬编码 → `data/content/endings.json` 声明式 all-of 门控读表求值（新增结局 = 加 JSON，零代码改动）。
2. `requires_trust` 标量写死洛弦 → 标量（兼容）/对象 `{char_id, dim, value}` 双形态，判定单一来源化。
3. 信任经济均等（P0 裁决）：外交路线满额 65 → 70，与直接路线对称可达共生结局。
4. 移除 `relations.policy_unlocked` 死 API。

## 2. 裁决记录

**信任经济（P0）**：采用任务书主案——`approach_diplomatic` 选项 delta 保持不变（`misa.affection +5`，查实现值），新增 `event_envoy_trust`（`requires_flag: approach_diplomatic`，effect 步 `luoxian.trust +5`）。未走"统一两选项 delta"替代方案：直接路线的 +5 是选完即得的Choice 内收益，把它复制给外交选项会抹掉"两条路线收益形状不同"的叙事差异；外交路线的对称补偿应是一次独立剧情事件（也让"选择改变结局"假设多一段可感内容）。验收：两路线完整正常流程 trust 均 ≥ 70，已写入集成测试。

**触发机制**：`src/progression` 事件链对本包冻结（允许路径不含 `src/progression/**`），`event_envoy_trust` 的到期检查按 W002-GAP2 矿井入口事件的同一先例放在 `GameSession.tick` 自检（`_envoy_trust_due`），门控语义不重复实现——复用 `EventRunner.available_events`（`requires_flag` 声明在事件数据内，once/done 语义与冻结链一致）。**DLX-2 事件链外置时必须把该触发并入 `data/progression/event_chain.json` 并删除钩子。**

## 3. 实现（按任务）

### 任务 1 — endings.json 数据化

- `schemas/endings.schema.json`（新建，Draft 2020-12）：条目 `{id, order, all_of_flags, any_of_prefix, trust{char_id,dim,threshold}, extra_flag, fallback_ending, title_zh, summary_zh}`；声明式 all-of，非表达式求值。
- `data/content/endings.json`（新建）：三条既有结局按原判定顺序（mining=0 / seal=1 / symbiosis=2）迁移，symbiosis 携带 `trust{luoxian,trust,70}` + `extra_flag echo_chamber_active` + `fallback_ending ending_seal`；标题/总结文案逐字迁移。
- `src/endings/endings.gd` 重写为读表求值：`bootstrap()`（FileAccess 装载 + 语义校验：结构/稳定 ID/重复 id/fallback 引用存在性；缺失或非法 → 失败并 `push_error`，判定退化为 `""`）；`evaluate` 按 order 升序逐条求值；`ending_title/ending_summary` 查表。对外签名 `evaluate/ending_title/ending_summary` 不变，`ending_scene.gd` 零改动；首次调用惰性 bootstrap，生产调用方零改动。`data_path` 可注入 + `reset_for_tests()` 支持替身表测试。
- 行为快照：既有 `_evaluate_cases()` 13 例（三分支/69-70 边界/extra 缺失回落/空 state）零修改通过。

### 任务 2 — requires_trust 对象化

- `schemas/event.schema.json`：`requires_trust` 改 `oneOf`（标量 int 0..100 兼容旧数据 | 对象 `{char_id, dim, value}`，additionalProperties false）。
- `src/narrative/event_runner.gd`：删除 `TRUST_CHAR_ID` 写死常量；新增 `static func option_meets_trust(state, option) -> bool`（归一化标量→`{luoxian, trust, v}`、对象→按字段；缺失/0/非法形态视为无门控）为**单一判定源**；`_check_trust_requirement` 改为其薄包装。`game_session._trust_locked_option_ids` 预检改调同一谓词，消除双实现漂移（边界 39/40/41 上谓词与 choose_option 结论一致性有专项断言）。
- `data/events/event_policy.json`：sanctuary 选项标量 40 → `{"char_id":"luoxian","dim":"trust","value":40}`（语义等价，对象形态生产示例）。

### 任务 3 — 信任经济均等

- `data/events/event_envoy_trust.json`（新建）：`requires_flag: approach_diplomatic`、3 行原创中文台词（弥砂借外交接触赢得洛弦对"另一种正确"的认可）+ effect 步 `luoxian.trust +5`。
- `GameSession`：`ENVOY_TRUST_EVENT_ID` 常量 + `_envoy_trust_due()` + tick 中矿井入口检查之后、`Progression.due_event` 之前触发（保证与直接路线同拍：policy 前 trust 同轨）。
- `src/relations/relations.gd`：删除 `policy_unlocked` 及 `POLICY_SANCTUARY`/`SANCTUARY_TRUST_THRESHOLD` 死常量（生产调用方为零，真实门控在事件数据 + `option_meets_trust`）；保留 `get_dim/trust/change`。

### 超出允许路径的说明（src/content/content_db.gd，冻结模块）

两处最小改动，均为本包目标无法绕开的硬依赖：

1. **保留数据文件名排除**（`RESERVED_DATA_FILENAMES = ["endings.json"]`，`_collect_json_files` 跳过）：ContentDB 会递归扫描 `data/content/` 并按 `kind` 分派校验，endings.json 条目无 `kind`，不排除则 `ContentDB.bootstrap()` 整包失败（实测引发 55 个测试失败，见 RED/GREEN 记录）。任务书推荐"endings.json 由 Endings 模块自身经 FileAccess 读取"，本改动是该推荐的落地前提。content_hash 由已装载定义派生，endings.json 天然不入 hash（DLX-6 存档内容政策应补覆盖）。
2. **requires_trust 双形态结构校验**（`_validate_requires_trust`）：原 `_optional_integer` 对对象形态直接判非法 → 任务 2.3 的对象形态生产数据会在 bootstrap 被拒。语义判定仍完全在 `EventRunner.option_meets_trust`，ContentDB 只做结构约束（char_id 稳定 ID / dim 枚举 / value 0..100），与 `schemas/event.schema.json` oneOf 对齐。

## 4. 信任经济逐事件累计表（luoxian.trust）

数据来源：`ContentDB.get_event` 定义（effect 步 relation_delta 全计，choice 步仅计被选选项），与测试内数据驱动交叉验证一致。

| # | 事件 | 收益来源 | 直接路线 | 外交路线 |
|---|------|----------|---------:|---------:|
| 1 | event_drift_aftermath | effect | +12 → 12 | +12 → 12 |
| 2 | event_misa_campfire | effect | +8 → 20 | +8 → 20 |
| 3 | event_husk_aftermath | effect | +12 → 32 | +12 → 32 |
| 4 | event_station_mode（共生选项） | choice | +10 → 42 | +10 → 42 |
| 5 | event_echo_resonance | effect | +8 → 50 | +8 → 50 |
| 6 | event_approach | choice | approach_direct +5 → **55** | approach_diplomatic +0（misa.affection +5）→ 50 |
| 7 | event_envoy_trust | effect | —（不触发） | **+5 → 55** |
| — | event_policy 时点 | sanctuary 门 40 | 55 ≥ 40 ✓ | 55 ≥ 40 ✓（禁用态消失，两路线等权） |
| 8 | event_leviathan_aftermath | effect | +15 → **70** | +15 → **70** |

结论：共生结局（trust ≥ 70 + echo_chamber_active）在两条 approach 路线下数学均可达。修复前外交路线满额 65，共生结局不可达且无解释（P0）。

集成测试：`test_trust_economy_diplomatic_route_reaches_symbiosis_threshold`（新）与 `test_trust_economy_curve_reaches_sanctuary_and_symbiosis`（既有直接路线快照）逐事件断言实况值；外交测试另含数据驱动交叉验证（从 ContentDB 定义累计 = 70 = 实况值，数据改动自动反映）。

## 5. TDD 记录

### RED（先于实现，实测输出）

命令：`godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/unit/test_endings.gd,res://tests/unit/test_narrative_event_runner.gd,res://tests/unit/test_integration.gd` → exit 1，**11 failing**：

- test_endings：5 项新测试失败（`bootstrap`/`reset_for_tests` 不存在）。
- test_narrative_event_runner：`test_choose_option_honors_object_requires_trust_shape`（对象形态被 `int()` 强转崩溃——门被绕过）；3 项 `option_meets_trust` 谓词测试失败（方法不存在）；`test_available_events_excludes_finished_once_events` 失败（守卫解封后暴露的既有测试缺陷，见 §6.6）。
- test_integration：`test_trust_economy_diplomatic_route_reaches_symbiosis_threshold`（`event_envoy_trust` 不存在；外交路线终局 65 ≠ 70；数据侧累计 65 ≠ 70）。

### GREEN（实现后）

| 命令 | 结果 |
|------|------|
| `pwsh -NoProfile -File ./scripts/Run-Gut.ps1` | exit 0，**538/538**（基线 529 + 净增 9：endings +5、narrative +5、integration +1、relations −2） |
| `pwsh -NoProfile -File ./scripts/Validate-Content.ps1` | exit 0，PASS（31 文件 / 56 定义 / 6 schema；含 event_envoy_trust.json 与 event_policy.json 对象形态） |
| `pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1` | exit 0（VERSION/IMPORT/MAIN_SCENE/GUT_DEFAULT/GUT_FAILURE_FIXTURE 全 PASS） |
| `pwsh -NoProfile -File ./scripts/Verify-Slice.ps1` | exit 0（GATE1 GUT / GATE2 TOOLCHAIN / GATE3 EXPORT_PRESETS / GATE4 EXPORT_SMOKE 全 PASS） |

## 6. 既有断言更新与既有缺陷处置（逐条）

**合法断言更新（数据/行为有意变更）：**

1. `test_integration.gd` `EXPECTED_DEFINITION_COUNT` 55 → 56：新增 `event_envoy_trust.json`（沿 W002-GAP2/W003-A1 先例逐条记录）。
2. `test_content_data.gd` sanctuary 断言：`requires_trust` 标量 40 → 对象形态三字段断言（语义等价迁移）。
3. `test_integration.gd` `test_trust_locked_option_is_disabled_and_choice_never_softlocks`：外交路线完成后新增 `_play_event("event_envoy_trust")`，policy 时 trust 0 → 5（仍 < 40，禁用态断言语义不变）。
4. `test_relations.gd`：`policy_unlocked` 两项测试随死 API 删除（覆盖转移到 `test_narrative_event_runner.gd` 谓词矩阵与 `test_integration.gd` 禁用态/ sanctuary 等权断言）。

**解封测试时发现并修复的既有缺陷（均为既有测试从未真正运行所致）：**

5. `if not assert_not_null(x): return` 守卫模式**永远提前返回**（GUT 断言函数返回 void，`not void` 恒真）——`test_endings.gd` 3 处、`test_narrative_event_runner.gd` 6 处（含本包新增 3 处，发现后一并改正）改为显式 `if x == null: fail_test(...); return`。解封后既有用例真实运行且通过（结局场景契约、available_events、next_step 等）。**`test_progression.gd` 尚存 3 处同型守卫（第 100/282/786 行附近），不在本包允许路径，留给协调者处置。**
6. `test_available_events_excludes_finished_once_events` 替身表自相矛盾：once=false 事件与已完成事件共用同一 id，"once=false 忽略完成记录"与"已完成事件隐藏"两条断言不可能同时成立。修正替身（独立 id `event_test_touchdown_repeatable`），测试意图保持。

**其他行为说明：**

7. `trust_insufficient` 失败 message 文案改为携带 `char_id/dim`（无任何测试或调用方依赖旧文案；code 不变）。
8. `Endings` 旧公开常量（`TITLE_*`/`SUMMARY_*`/`STATION_MODE_*`/`SYMBIOSIS_*`）随硬编码移除，全库 grep 无外部引用。

## 7. 限制

1. **`src/content/content_db.gd` 为冻结模块**，本包两处最小改动（见 §3），已按"evidence 说明 + 保持最小"纪律执行；如需回退需连同 endings.json 装载方案一并重议。
2. **`event_envoy_trust` 的 tick 钩子是过渡态**：src/progression 冻结所致，DLX-2 事件链外置时必须并入声明式链并删除 `_envoy_trust_due`。
3. **`Validate-Content.ps1`（scripts/validate_content.py）不感知 endings.json**（scripts/ 不在本包允许路径）：其门禁由 `schemas/endings.schema.json`（正式契约）+ `Endings.bootstrap` 语义校验 + `test_endings.gd`（装载/缺失/重复 id/悬空 fallback/纯数据扩展）承担。
4. **content_hash 不含 endings.json**（hash 由已装载定义派生）：DLX-6 存档内容政策应将其纳入 hash 与孤儿清理范围。
5. `test_progression.gd` 3 处失活守卫未修（路径禁改，见 §6.5）。

## 8. 下一步

1. DLX-2：事件链外置 `data/progression/event_chain.json`，吸收 `_envoy_trust_due` 钩子。
2. DLX-4：HUD 信任可见（trust 40/70 门提示），把本包的对称信任经济呈现给玩家。
3. DLX-6：content_hash 政策覆盖 endings.json；golden fixture 扩展。
4. 协调者：处置 `test_progression.gd` 3 处失活守卫（解封后逐一验证）。
