# S2 — Boss 门控链硬编码数据化

- 分支：`feature/s2-boss-gate`（worktree `.worktrees/s2`）
- 日期：2026-09-01
- 范围：复审遗留清单 S 级 S2 项（`docs/plans/2026-08-31-dlc-readiness-and-pm-verdict.md` 复审章节登记的复审报告遗留项）
- 基线：`main` @ `62e5ae3`，Run-Gut 700/700 全绿（G7P-2 全波合入后）

## 1. 目标

1. `Progression._react_leviathan_gate`（旧 progression.gd :419-444）的硬编码 Boss 门
   "encounter_first_drift_won + encounter_husk_ambush_won 双胜 + 任一 policy_* flag
   → set_flag encounter_leviathan_due" 外置到 `data/progression/boss_gate.json`；
   新增门控链（如 DLC 新遭遇进入 Boss 门）= 改 JSON，零代码改动。
2. 门语义泛化：门表为数组，每条各带 `requires_all` / `requires_any_prefix` /
   `set_flag`——现文件 1 条（迁移现值），结构支持 N 条（多条同时到期合并为一个
   patch，按条目顺序逐条 set_flag）。
3. 新增 schema `schemas/boss-gate.schema.json`（对齐 ending-gate/progression-chain
   风格 + `set_flag` 字段），并在 `validate_content.py` 注册。
4. TDD 全程：先 RED 后 GREEN；行为等价（双胜 + policy 前缀语义逐字节保留，既有
   测试为快照）；不破坏 700 基线。

## 2. 文件结构与迁移值的裁决记录

任务书第 1 条给出条目对象字面量，第 3 条要求"多条 boss gate 条目（数组）……现文件
1 条，结构支持 N 条"。两者合并裁决：**文件 = 条目数组，现含 1 条**，该条即任务书
字面量的迁移现值：

```json
[
  {
    "requires_all": ["encounter_first_drift_won", "encounter_husk_ambush_won"],
    "requires_any_prefix": "policy_",
    "set_flag": "encounter_leviathan_due"
  }
]
```

对齐先例：`event_chain.json` 为条目数组（N 条事件），`ending_gate.json` 为单门对象
（结局门只有一扇）。Boss 门按任务书要求支持 N 条，故取数组形态；单对象形态**不在
装载器接受范围内**（`not_an_array` 坏文件用例锁定），避免双形态维护面。

## 3. 等价性设计与裁决记录

**旧语义（硬编码）逐分支**：
- subject_id（encounter_id/policy_id）非 stable snake_case → 失败 `invalid_%s`；
- `encounter_leviathan_due` 已置 → 成功跳过 `already_set`；
- 缺任一双胜旗标 → 成功跳过 `conditions_unmet`；
- 无任一启用 `policy_*` → 成功跳过 `conditions_unmet`（值为 false 的 policy flag
  不算命中）；
- 其余 → 提交单条 `set_flag encounter_leviathan_due`。

**新语义（单条门表逐条评估）**：对每条门——set_flag 已置 → 该条跳过；requires_all
未全置或 requires_any_prefix（非 null 时）无命中 → 该条不置；其余到期条目按数组
顺序追加 set_flag 操作；操作集为空时，任一条 set_flag 已置 → `already_set`，否则
`conditions_unmet`。单条门下五种结果与旧分支**一一对应、逐字节一致**（含 skip 码与
错误消息文案）。

**唯一语义差分类（与链/结局门同款的既定契约）**：门表缺失/坏文件 → 空表兜底 →
react 恒 `conditions_unmet` 零写入。旧实现无外置文件、无此失败面；新实现把
"数据坏了"从"静默沿用硬编码值"改为"显式 push_error + 永不触发"（失败安全，不是
硬编码回退，不是空真置位）。生产好文件下该分支不可达。

**词汇表常量保留**：`LEVIATHAN_DUE_FLAG` / `FIRST_DRIFT_WON_FLAG` /
`HUSK_AMBUSH_WON_FLAG` / `POLICY_PREFIX` 保留为门数据所引词汇表的规范来源（与
DLX-2 保留 `station_mode_`/`approach_` 前缀常量同款先例）；行为判定不再经它们。
`POLICY_PREFIX` 另被 `game_session.gd`（policy 选项识别）引用，必须保留。

## 4. RED（先于实现）

**迁移前探针（行为快照）**：临时测试 `_tmp_s2_probe.gd`（提交前已删）对 20 行矩阵
导出旧 `_react_leviathan_gate` 的真实输出。命令：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/_tmp_s2_probe.gd -gexit
PROBE|E_empty|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_drift_only|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_husk_only|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_two_wins_no_policy|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_policy_only|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_all_met|ok=true|code=committed|commits=1|{"ops":[{"enabled":true,"flag_id":"encounter_leviathan_due","type":"set_flag"}]}
PROBE|E_due_already|ok=true|code=already_set|commits=0|{"ops":[]}
PROBE|E_due_plus_all|ok=true|code=already_set|commits=0|{"ops":[]}
PROBE|E_false_victory|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_false_policy|ok=true|code=conditions_unmet|commits=0|{"ops":[]}
PROBE|E_due_false_all_met|ok=true|code=committed|commits=1|{"ops":[{"…encounter_leviathan_due…}]}
PROBE|E_missing_id|ok=false|code=invalid_encounter_id|msg=encounter_won payload requires a stable snake_case encounter_id, got .|commits=0
PROBE|E_bad_id|ok=false|code=invalid_encounter_id|msg=…got Bad Encounter.|commits=0
PROBE|P_empty / P_two_wins_no_policy / P_false_policy = conditions_unmet（同 E 组）
PROBE|P_all_met|ok=true|code=committed|commits=1|{…encounter_leviathan_due…}
PROBE|P_due_already|ok=true|code=already_set|commits=0
PROBE|P_missing_id|ok=false|code=invalid_policy_id|msg=policy_chosen payload requires a stable snake_case policy_id, got .
PROBE|P_bad_id|ok=false|code=invalid_policy_id|msg=…got Policy X.
```

关键行为锚点：`E_due_false_all_met`（due 显式 false 不算已置，条件全齐照常提交）；
`E_due_plus_all`（已置优先于条件判定，即使条件也全齐仍 `already_set`）。

**RED 运行**（新增 `tests/unit/test_progression_boss_gate.gd` 8 项，实现未写）：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/test_progression_boss_gate.gd -gexit
Scripts 1  Tests 8  Passing none  Failing 8  Asserts 0/8
```

8 项失败逐一符合预期：全部因 `Progression.load_boss_gate_from` /
`_boss_gate_entries` 不存在（`Missing required S2 implementation` 显式断言）。

## 5. 实现（GREEN）

- `data/progression/boss_gate.json`（新建）：§2 的单条迁移条目。
- `schemas/boss-gate.schema.json`（新建，Draft 2020-12，`$id:
  starsoil:schemas/boss-gate.schema.json`）：`type: array`、`minItems: 1`；条目
  required `{requires_all, requires_any_prefix, set_flag}`、`additionalProperties:
  false`；`requires_all` 元素与 `set_flag` 用稳定 snake_case pattern
  `^[a-z][a-z0-9_]*$`（对齐 ending-gate），`requires_any_prefix` 为
  `["string","null"]` + 同 pattern（对齐 progression-chain）。`requires_all` 允许
  空数组（"仅前缀守卫"的门与链条目 `event_approach` 同款合法形态）。
- `src/progression/progression.gd`：
  - 新增 `BOSS_GATE_PATH` 常量与 static 门表缓存（`_boss_gate` /
    `_boss_gate_bootstrapped` / `_boss_gate_last_load`），加载语义与链缓存一致
    （失败记为已引导，避免逐帧重读坏文件）；
  - `bootstrap()` 扩为链 → 结局门 → Boss 门三表装载，任一失败按序返回首个失败
    结果，三者皆成功返回 Boss 门结果；
  - 新增 `load_boss_gate_from(path)`（装载 + 最小语义校验 `_boss_gate_entry_error`
    + 归一化 `_normalize_boss_gate_entry`；坏文件/缺失 `push_error("Progression:
    boss gate rejected …")` 并回退空表）；校验项：数组形态、至少 1 条、条目对象、
    requires_all 数组且元素为稳定 snake_case、requires_any_prefix 非空 string 或
    null、set_flag 稳定 snake_case、set_flag 跨条目不重复；
  - react 的 `encounter_won`/`policy_chosen` 分支改派 `_react_boss_gate`；删除
    `_react_leviathan_gate`；新增 `_boss_gate_conditions_met`（守卫判定，无
    ending_ready 维度）；
  - `_boss_gate_entries()` 惰性 bootstrap 兜底（直调 react 的既有测试路径自动装载）。
- `scripts/validate_content.py`（任务书允许的 scripts/ 唯一改动）：
  `SCHEMA_TARGETS` 注册 `"progression/boss_gate.json": "boss-gate"`。

## 6. 等价证明

1. **冻结矩阵**（`test_react_boss_gate_matches_pre_migration_frozen_matrix`）：
   20 行探针期望逐行断言（ok/code/commits/ops），GREEN 后逐行通过。
2. **既有测试零修改**：`test_progression.gd` 的 encounter_won/policy_chosen 组合
   测试（`test_react_encounter_won_requires_both_victories_and_policy`、
   `test_react_encounter_won_sets_leviathan_due_when_conditions_met`、
   `test_react_policy_chosen_sets_leviathan_due_when_conditions_met`、
   `test_react_policy_chosen_requires_both_victories`）、`test_integration*.gd`
   全套、`test_save_policy_dlx6.gd` golden 一致性——**700 基线 0 断言更新**，
   全绿为第二证。
3. **真实 store 端到端**：`test_react_encounter_won_all_met_commits_via_real_game_state`
   经真实 GameState 置位/revision+1/幂等重放。

## 7. 纯数据扩门证明

`test_pure_data_second_boss_gate_needs_no_code_change`：临时门表追加第二条 DLC 门
`{requires_all: [s2_dlc_encounter_won], requires_any_prefix: null, set_flag:
s2_dlc_boss_due}`（零代码改动）：
- 仅 DLC 前置满足 → 只置 `s2_dlc_boss_due`，旧门不置 due（门独立评估）；
- 两门同时到期 → 单 patch 按条目顺序双置位（一次提交）；
- 两门 set_flag 均已置 → `already_set` 零提交（幂等按条目生效）。

## 8. 失败安全证明

- 缺失文件 → `missing_boss_gate_file` + `push_error` + 空表兜底：旧条件全齐仍
  `conditions_unmet` 零写入（永不触发，不是空真置位）。
- 14 类坏文件（语法错/非数组/空数组/条目非对象/缺 requires_all/requires_all 形态
  与元素非法/前缀形态非法/缺 set_flag/set_flag 形态非法/重复 set_flag）全部拒绝
  （`invalid_boss_gate_file` + `push_error` + 零写入兜底）。

## 9. 防漂移同步

`test_boss_gate_flags_stay_in_sync_with_encounter_data`（对齐
`test_progression_ending_gate.gd` 同款模式，全部经数据文件校验）：
- 每条门 `requires_all` ⊆ `data/encounters/encounters.json` 的 `on_victory_flag`
  集合（门输入来自真实胜利旗标）；
- 每条门 `set_flag` ∈ 同文件 `trigger_flag` 集合（门产出真能触发已声明遭遇——
  迁移值 `encounter_leviathan_due` 即 encounter_leviathan 的 trigger_flag）。

## 10. 哈希裁决

**裁决：boss_gate.json 应纳入 `ContentDB.HASH_CONFIG_FILES`，本包不实施，登记为
交接项。**

- **先例对照（一致性口径）**：任务书提示"objectives/hints 未纳入的先例对照"——
  实查 `src/content/content_db.gd` G7P-2 S10 注释与
  `test_content_db.gd::test_content_hash_includes_progression_config_files`：
  objectives/hints **已**于 G7P-2 S10 入哈希，理由为"表内容改动影响运行行为，存档
  兼容性指纹必须覆盖"，至此进度配置全家桶（endings/characters/event_chain/
  ending_gate/world_config/objectives/hints）全部入 canonical 总哈希。
  boss_gate.json 属同一家族的第 8 个成员（门表改动直接改变 `encounter_leviathan_due`
  置位行为，与 event_chain/ending_gate 同类），按既定政策**应入哈希**。
- **本包不实施的原因**：`HASH_CONFIG_FILES` 位于 `src/content/content_db.gd`，
  在 S2 允许路径（`src/progression/**`、`data/progression/**`、`schemas/**`、
  `tests/unit/test_progression*.gd`、`ops/evidence/S2-BOSS-GATE.md`、
  `scripts/validate_content.py` 唯一例外）之外；AGENTS.md 工作包纪律禁止越权。
- **golden 无需重生成**：boss_gate.json 未入哈希时对 `content_hash` 零贡献，
  本次改动不改哈希——`test_save_policy_dlx6.gd::
  test_golden_fixture_content_hash_equals_bootstrapped_content_hash` 在 GREEN
  套件中原样通过（无 golden 重生成、无合法断言更新）。
- **交接项（S2b，一行改动）**：`HASH_CONFIG_FILES` 增 `"boss_gate":
  "progression/boss_gate.json"` + `content_db.gd` 注释一行 + golden 重生成
  （`scripts/generate_golden_v1.gd`）+ 在
  `test_content_hash_includes_progression_config_files` 增一条 boss_gate 突变
  断言。属 `src/content/**` + `tests/golden/**` 的工作包，需另行派发。

## 11. 门禁记录

| 门禁 | 命令 | 结果 |
|---|---|---|
| RED | `-gtest=res://tests/unit/test_progression_boss_gate.gd -gexit` | 8/8 fail（缺 S2 API），exit≠0 |
| S2 单文件 GREEN | 同上（实现后） | 8/8 pass，221 asserts |
| Run-Gut 连绿 #1 | `pwsh -NoProfile -File ./scripts/Run-Gut.ps1` | exit 0，**708/708**（700 基线 + 8 新增），10863 asserts |
| Run-Gut 连绿 #2 | 同上 | exit 0，708/708 |
| validate_content.py | `python scripts/validate_content.py` | exit 0，PASS：39 文件 / 64 定义 / **14 schema**（新增 boss-gate） |
| Verify-Toolchain | `pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1` | exit 0（VERSION/IMPORT/MAIN_SCENE/GUT_DEFAULT/GUT_FAILURE_FIXTURE 全 PASS） |
| Verify-Slice | `pwsh -NoProfile -File ./scripts/Verify-Slice.ps1` | exit 0（GATE1-4 全 PASS，含真实导出烟测 starsoil.exe） |

700 基线零破坏：61 个测试脚本中既有 60 个零修改（唯一新增 =
`test_progression_boss_gate.gd`），无任何合法断言更新需要说明。

## 12. 限制与下一步

**限制**：
1. boss_gate.json 暂未入 `content_hash`（§10 裁决：应入，但 `src/content/**` 越权，
   登记为 S2b 交接项；在 S2b 落地前，boss_gate.json 改动不触发读档 mismatch 检测
   ——与入哈希前的 objectives/hints 同状态，风险面一致且已被 G7P-2 S10 的政策
   判定覆盖为"应覆盖"，仅剩一行注册缺口）。
2. react 的 Boss 门分支在门表为空（坏文件兜底）时恒不触发——这是与链/结局门一致的
   失败安全契约，而非限制；生产路径 `GameSession` bootstrap 失败会阻断开局，坏门
   表不可静默入场。
3. `set_flag` 跨条目重复在运行时拒绝（schema 层无法表达跨条目字段唯一性，
   jsonschema 限制；由 `duplicate_set_flag` 用例与运行时校验双重兜底）。

**下一步**：
1. S2b（1 行 + golden 重生成）：boss_gate.json 入 `HASH_CONFIG_FILES`，见 §10。
2. 复审遗留其余 S 项（S6-S8 等）按同法（数据化 + 冻结矩阵等价证明）逐项派发。
3. G6 资产生产（人工审批门）与 G7 真人门禁按项目既定阶段推进。

## S2b 交接项完成（协调者，2026-08-31）

- `ContentDB.HASH_CONFIG_FILES` 注册 `boss_gate`（1 行，src/content/content_db.gd）；
- golden fixture 重生成（新 content_hash 9b58467b98b2…，尾行换行已剥离对齐既有契约）；
- validate_content.py PASS；全量套件两连 708/708 零失败（合并后首跑的 32 断言瞬态失败
  复现了已知的首跑预热/隔离模式，两连全绿后关闭）。
