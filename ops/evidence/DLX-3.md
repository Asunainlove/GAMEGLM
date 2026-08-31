# DLX-3 建造反应通用化（DL2）+ 目标链/提示外置（DL5）

日期：2026-08-31 ｜ 分支：`feature/dlx3-reactions`（worktree `.worktrees/dlx3`）｜ 基线：main @ 0e0ba14（545 测试全绿）

## 0. 目标

- **任务 1（DL2）**：删除 `progression.gd _react_built` 的逐 id match，改为数据驱动的通用规则——`place_flag`（放置即置位）/ `place_flag_powered`（true 时需供电）/ `effect_flag`（供电门控，语义不变）；schema 与 buildings.json 声明式落地；`world_response_ops` 不动（选择的世界后果归 DLX-4）。
- **任务 2（DL5）**：`objective_for` 里程碑链 + `_CHOICE_FLAGS` 迁入 `data/progression/objectives.json`；A3 六条提示文案与触发条件迁入 `data/progression/hints.json`（触发点保留在集成层，按表订阅）；建筑热键泛化 `min(max(6, 建筑定义数), 9)`；"数字键 1-N" 模板化；两份新 schema。
- 硬约束：建造反应行为逐字节等价（既有测试为快照）；不破坏既有测试；文案全原创中文；TDD（先 RED 后 GREEN）。

## 1. RED 记录

| 步骤 | 命令（worktree 根） | 结果 |
|---|---|---|
| 任务 1 RED | `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/unit/test_progression_reactions.gd` | `Tests 9 / Passing none / Failing 9`（`load_building_reactions_from`/`_reactions_table`/place_flag 规则不存在；payload def 路径无效果） |
| 任务 2 RED | 同上 `-gtest=res://tests/unit/test_ui_objectives.gd,res://tests/unit/test_ui_hints.gd,res://tests/unit/test_integration_dlx3.gd` | 三文件解析期失败：`Static function "load_objectives_from()/load_hints_from()/_objective_entries()/_hint_entries()" not found in base "Hud"`、`hotbar_size_for`/`building_ids_provider` 不存在（静态 API 缺失即最强 RED） |

## 2. GREEN 记录

| 步骤 | 命令 | 结果 |
|---|---|---|
| 任务 1 GREEN | `pwsh -NoProfile -File ./scripts/Run-Gut.ps1` | `Scripts 41 / Tests 554 / Passing 554 / Asserts 8736`（545 基线零修改 + 9 新增） |
| 任务 2 GREEN | 同上 | `Scripts 44 / Tests 578 / Passing 578 / Asserts 8969`（新增 24：objectives 6 + hints 9 + integration_dlx3 9） |
| 内容 schema | `python scripts/validate_content.py` | `Checked 31 content file(s), 56 definition(s) against 6 schema(s). RESULT: PASS`（exit 0） |
| 门禁 | `Verify-Toolchain.ps1` | VERSION/IMPORT/MAIN_SCENE/GUT_DEFAULT/GUT_FAILURE_FIXTURE 全 PASS |
| 门禁 | `Verify-Slice.ps1` | GATE1-4 全 PASS，`VERIFY_SLICE_EXIT_CODE=0`（含导出冒烟） |

调试插曲（已恢复，不计入交付）：任务 2 期间 test_integration_dlx3 提示测试全空文案，经临时探针定位为**测试文件未隔离存档根**——`GameSession._ready → _try_load_autosave` 加载 user:// 残留 auto 存档（含 `hint_move_seen`），提示被跨会话去重跳过；补 `SaveService.configure_root_for_tests` 后消除（与 test_integration.gd 同一口径）。

## 3. 任务 1：建造反应通用规则（DL2）

### 3.1 数据/契约落地

- `schemas/building-recipe.schema.json`：新增可选 `place_flag`（`^[a-z][a-z0-9_]*$`）与 `place_flag_powered`（boolean）。
- `data/content/buildings.json`：`anchor_block` + `"place_flag": "first_anchor_placed"`；`anchor_workshop` + `"place_flag": "anchor_workshop_placed"`。**数值/配方/ID 零变化**；stabilizer_pylon/echo_chamber 的 `effect_flag` 原样（供电门控语义由通用规则继承）。
- `progression.gd`：`_react_built` 删除 match，规则为（输入 building_def）：
  - `place_flag` 存在 → set_flag；`place_flag_powered=true` 时需 `powered`（缺省 false = 放置即置）；
  - `effect_flag` 存在且 `powered` → set_flag；未供电不置（单调保持，现行为）；
  - 无反应字段 → `no_op` 成功零写入（与旧 default 分支一致）。
  - def 解析：`payload.building_def`（非空字典）权威采用（GameSession 传入 ContentDB 选中定义，支持纯数据扩展测试）；payload 无 def（旧直接调用形态）回退本模块自装载的建造反应表——直接读 `data/content/buildings.json` 提取三字段，最小校验，缺失/坏文件 `push_error` 并回退空表（built 失败安全恒 no_op）。
- 冻结模块最小改动（`src/content/content_db.gd`，**先例 ops/evidence/DLX-1.md §3**）：`BUILDING_FIELDS` 白名单加 `place_flag`/`place_flag_powered` + `_validate_building` 增可选稳定 ID/布尔校验。理由：不加白名单则 buildings.json 新字段被 `_reject_unknown_fields` 整包拒绝，`ContentDB.bootstrap` 失败连锁（DLX-1 实测同型事故）。`src/content/**` 在本包禁改清单，此处为使任务书 1.1/1.2 可落地的最小例外，共 +9 行含注释。

### 3.2 等价证明（四建筑放置行为对照）

冻结矩阵（tests/unit/test_progression_reactions.gd，期望值 = 旧 id-match 实现真实行为）：

| building_id | powered | 期望 ops |
|---|---|---|
| anchor_block | true/false | `set_flag first_anchor_placed`（与 powered 无关） |
| anchor_workshop | true/false | `set_flag anchor_workshop_placed`（与 powered 无关） |
| stabilizer_pylon | true | `set_flag pylon_stabilized` |
| stabilizer_pylon | false | no_op（零提交） |
| echo_chamber | true | `set_flag echo_chamber_active` |
| echo_chamber | false | no_op（零提交） |
| dust_refiner | true | no_op |

- **双路径对照**：无 def（回退表）与 payload def（生产 buildings.json 直读）两形态对全部 9 行输出逐字节一致（test_built_reactions_match_frozen_matrix_without_def / _with_payload_def）。
- **第二证**：既有 test_progression.gd 建造反应测试（anchor/workshop/pylon/echo/无关建筑/非法 id）与 test_integration.gd 建造链测试（供电门控、断电单调、revision 记账）**零修改通过**。
- **纯数据扩展**：临时 def `{place_flag: "dlx3_shrine_raised"}` 经 payload 注入 → 放置后 flag 置位（零代码扩展）；`place_flag_powered: true` 未供电 → 零提交；def 无反应字段时即使 id 为 anchor_block 也 no_op（def 权威）。
- 回退表失败安全：缺失/坏文件 push_error + 空表 → built 恒 no_op（9 组坏形态逐一拒绝）。

## 4. 任务 2：目标链与提示外置（DL5）

### 4.1 objectives.json（13 条，逐条迁移）

条目形状严格按任务书 `{text_zh, all_of, any_of_prefix, not_flags}`；选中 = all_of 全启用 ∧ not_flags 全未启用 ∧ any_of_prefix（非 null 时任一同前缀 flag 启用）；HUD 返回首个选中条目文案，全部未选中兜底"探索世界"。token 词汇表（声明式，非表达式）：

- 精确 flag id（如 `encounter_leviathan_won`、双前缀 done 标记 `event_event_first_mining_done`）；
- flag 前缀通配 `<prefix>*`（仅尾随一个 `*`，如 `event_*`）；
- 放置谓词 `placed_<building_id>` / `placed_*`（保留前缀 `placed_`，映射快照 placed_buildings，替代旧 `placed_ids.has` 特判）。

旧逻辑 → 表条目对照（顺序即判定序）：

| 旧 objective_for 分支 | 表条目（all_of / any_of_prefix / not_flags） |
|---|---|
| leviathan_due∧¬won → 面对辉砂巨兽 | `[leviathan_due] / null / [leviathan_won]` |
| (drift_due∧¬won)∨(husk_due∧¬won) → 应对漂移群威胁 | 拆两条同文案条目（drift、husk 各一） |
| ¬has_progress → 探索世界 | `not_flags = [event_*, encounter_*, placed_*, station_mode_*, approach_*, policy_*]`（_CHOICE_FLAGS 的 7 枚举由三个前缀通配等价覆盖，当前数据下逐 flag 一致，且未来新增前缀内选择 flag 自动被覆盖） |
| ¬(mining_done∨placed_anchor) → 勘探… | `not_flags = [event_event_first_mining_done, placed_anchor_block]` |
| ¬(placed_anchor∨first_anchor_done) → 放置第一座锚块 | 同构 |
| ¬(placed_workshop∨workshop_done) → 建立锚居工坊 | 同构 |
| ¬(drift_won∨husk_won) → 应对漂移群威胁 | `not_flags = [drift_won, husk_won]` |
| ¬(station_mode_×3∨station_done) → 做出驻地抉择 | `not_flags = [三枚举 + done]` |
| ¬(approach_done∧policy_done) → 推进方法与政策抉择 | 拆两条同文案：`¬approach_*∧¬approach_done` 与 `any_of_prefix=approach_ ∧ ¬(quota∨sanctuary∨policy_done)`（¬A∨¬P ≡ ¬A∨(A∧¬P)） |
| ¬(leviathan_won∨pact_done) → 面对辉砂巨兽 | 同构 |
| ¬(luoxian_done∨misa_done) → 见证余辉结局 | 同构 |
| 兜底 → 探索世界 | 查表无选中 → FALLBACK_OBJECTIVE |

等价证明：

- **第一证（既有快照零修改）**：test_ui_hud.gd 的 10 行里程碑矩阵、3 行威胁矩阵、空 state 兜底矩阵全部原样通过。
- **第二证（迁移矩阵）**：test_ui_objectives.gd 的 10 行补充矩阵（威胁回落、place_flag 等价放置判定、事件/建筑混合、approach/policy 窗口、单结局事件完成回落、提示 flag 非进度、全完成兜底），期望值冻结自迁移前 objective_for 真实输出。
- 文件缺失/坏文件：`push_error("Hud: objectives table rejected …")` + 兜底"探索世界"（14 组坏形态逐一拒绝并断言失败安全）。
- 纯数据扩展：临时目标表加 `dlx3_gate_open` 门控条目 → flag 置位后新目标句出现（新增目标 = 改 JSON）。

### 4.2 hints.json（6 条，文案逐字节迁移）

`{id, text_zh, trigger}`，trigger ∈ `boot / built:*（built:<building_id> 预留） / craft_failed / overlay / mine_entered / encounter_start`。触发点保留（game_session 的 boot 延迟计时器 / select_building / 建造失败 / tick 矿井检查 / tick 遭遇检查；HUD 的 O 键输入），触发订阅与文案读表（`Hud.hints_for_trigger` / `Hud.hint_text`）；落账机制不变（`hint_<id>_seen` + hint_seen_callback，经独立 integration patch）。API 变化：

- 新增 `show_hint_with_id(hint_id, text, seconds)`（生产路径，稳定 id 去重/上报）；旧 `show_hint(text)` 保留为兼容入口（文本哈希 id）；`hint_id_for` 退化为文本哈希（不再文案反查 id）。
- place 提示文案含 `{building}` / `{hotkey_max}` 占位符，由触发点上下文字面替换；6 建筑场景输出"右键/F 放置 锚居工坊 · 数字键 1-6 切换建筑"与迁移前逐字节一致。
- 提示/目标表静态缓存失败即记已引导（轮询/逐帧路径不重读坏文件），`load_hints_from`/`load_objectives_from` 支持测试注入与修复。

### 4.3 热键泛化

- `BUILDING_HOTBAR_SIZE` 常量退役 → `static func hotbar_size_for(count) = min(max(6, count), 9)`；`_unhandled_input` 上界与放置提示 `{hotkey_max}` 均由此派生；新增 `building_ids_provider` 注入点（缺省 `ContentDB.ids_of("building")`）。
- 断言：边界（0→6、6→6、7→7、9→9、12→9）；>6 建筑（注入 7 项目录）数字键 7 可选中第 7 项；6 建筑目录下键 7 被忽略（迁移前行为）。

## 5. 外置清单（新增内容步骤数对照）

| 场景 | 迁移前 | 迁移后 |
|---|---|---|
| 新建筑放置里程碑 | progression.gd 加 match 分支 | buildings.json 加 `place_flag` 字段 |
| 新供电效果建筑 | progression.gd 加 match 分支 | buildings.json 加 `effect_flag` 字段 |
| 新目标句 | hud.gd 改 objective_for 链 | objectives.json 加 1 条目 |
| 新引导提示 | hud.gd 加常量 + game_session 加触发点引用 | hints.json 加 1 条目（挂既有触发点） |
| 第 7+ 建筑热键 | 无（截断） | buildings.json 加定义即获得热键（≤9） |

## 6. 合法断言更新（逐条）

1. `tests/unit/test_ui_hud.gd` test_show_hint_templated_place_text_dedups_by_hint_id：`show_hint(模板文案)` → `show_hint_with_id("place", …)`×2。原因：文案反查 id 的常量/前后缀机制退役，稳定 id 改由提示表提供；去重语义（同 id 一次落账、换名不复播）不变。
2. `tests/unit/test_ui_hud.gd` test_show_hint_skips_when_flag_already_seen_in_snapshot / test_show_hint_reports_seen_once_via_injected_callback：`Hud.HINT_*_TEXT` → `Hud.hint_text("<id>")` + `show_hint_with_id`。原因：文案常量退役（外置单一来源），flag 对齐需稳定 id。
3. `tests/unit/test_ui_hud.gd` test_toggle_overlay_action_triggers_overlay_hint_once：文案断言 `Hud.HINT_OVERLAY_TEXT` → `Hud.hint_text("overlay")`（值相同）。
4. `tests/unit/test_integration.gd` 五处提示文案断言：`Hud.HINT_MOVE/CRAFT/MINE/BATTLE/OVERLAY_TEXT` → `Hud.hint_text("<id>")`。放置提示的字面文案断言（"右键/F 放置 锚块 · 数字键 1-6 切换建筑"）**未改**——模板按 6 建筑展开输出逐字节一致，保留为模板等价快照。

其余 545 基线测试零修改（含 test_progression.gd、test_integration.gd 建造链/事件链/存档链、test_content_data.gd、test_content_db.gd）。

## 7. 限制

1. **content_db.gd 冻结模块最小例外**（§3.1）：BUILDING_FIELDS 白名单 +2 字段校验。未做：把 place_flag 语义校验（如 place_flag_powered 不应单独出现）下沉 ContentDB。
2. **回退反应表二次读取 buildings.json**：Progression 自装载反应表与 ContentDB 同源同文件（FileAccess 直读，只读、失败安全）。生产路径优先 payload def，回退表仅服务旧直接调用形态；两源一致性由 schema/validate_content.py + 等价矩阵背书。未做：payload 携带 def 后彻底移除回退表（将破坏既有测试快照的调用形态）。
3. **目标 token 词汇表契约**：`event_*` 通配假设"event_ 前缀 flag 均为事件完成标记"、`encounter_*` 假设"encounter_ 前缀 flag 均为进度标记"——当前数据成立（due/won）；未来若引入不表进度的 encounter_ 前缀 flag，需在 objectives.json 相应条目显式化。
4. **通配覆盖取舍**：无进度条目以 `station_mode_*/approach_*/policy_*` 三前缀替代旧 _CHOICE_FLAGS 七枚举——当前数据逐 flag 等价；未来同前缀新选择 flag 自动计入进度（属预期泛化方向）。
5. **place 提示触发点语义**：任务书 trigger 词汇 "built:<building_id>" 落地为"建筑进入放置流（select_building）"——与 W003-A3 既有行为（首次选中提示）一致；若需改为"放置成功后"提示属行为变更，超出本包等价约束。
6. **热键上限 9**：>9 建筑仅前 9 个有数字键，其余走 HUD BuildBar 点击；未做滚动/翻页热键栏。
7. GodotPrompter 未安装（godot-development-stack 已声明限制），按 Godot 4.x 最佳实践执行。

## 8. 下一步

- DLX-4：world_response_ops 的 flag 消费者落地（矿脉富集世界变化）+ 信任可见面板；届时可将"选择的世界后果"也按本包模式外置。
- DLX-5 世界布局外置时，可复用本包的"触发点保留 + 条件/文案读表"订阅模式（entry_event/entered_flag）。
- 可选后续：place_flag_powered 与 effect_flag 双字段的组合案例补充内容侧示例数据；ContentDB 引导后向 Progression 推送反应表的单一装载入口。
