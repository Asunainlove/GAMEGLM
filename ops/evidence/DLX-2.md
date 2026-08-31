# DLX-2 — 事件链外置（DL1）+ 测试去硬编码（DL7）

- 分支：`feature/dlx2-chain`（worktree `.worktrees/dlx2`）
- 日期：2026-08-31
- 范围：`docs/plans/2026-08-31-dlc-readiness-and-pm-verdict.md` DLX-2 行
- 基线：`main` @ `33cff5c`，Run-Gut 538/538 全绿（DLX-1 合入后）

## 1. 目标

1. `Progression._event_chain()` 的 24 项有序硬编码数组 → `data/progression/event_chain.json` 声明式有序链（id / requires_all / requires_any_prefix / requires_ending_ready），新增事件 = 改 JSON，零代码改动。
2. DLX-1 过渡钩子 `GameSession._envoy_trust_due` / `ENVOY_TRUST_EVENT_ID` 并入外置链并删除（DLX-1 证据 §2 的既定交接）。
3. `test_integration.gd` 的 `EXPECTED_DEFINITION_COUNT` 精确断言 → 派生下限断言。
4. 修复 `test_progression.gd` 3 处 `if not assert_xxx(...): return` 空转守卫（GUT 断言返回 void，该写法恒真早退，后续断言从未执行）。
5. 新增链文件专项测试：JSON 加载、守卫四组合、坏文件拒绝、纯数据扩链、行为等价快照矩阵。

## 2. 等价性设计与裁决记录

**钩子并入的链位**：DLX-1 的 tick 过渡钩子在 `Progression.due_event` **之前**自检 `event_envoy_trust`，即旧系统中该事件对链上所有事件拥有绝对优先级（一旦 `approach_diplomatic` 置位且未 done，下一 tick 必先触发它）。为使删除钩子后**同一 state 的全局触发序列逐事件一致**（硬性规则"同一 state → 同一 due 序列"在系统级观测下成立），`event_envoy_trust` 迁移为外置链**链首**条目，守卫照搬 DLX-1 事件数据 `requires_flag: approach_diplomatic` → 链守卫 `requires_all: ["approach_diplomatic"]`（once/done 语义链内本就统一走 `event_%s_done` 模板；`available_events` 的 `completed_events` 检查与 `GameSession._finish_active_event` 的双写不产生观测差异）。若插在 `event_approach` 与 `event_policy` 之间，"approach 完成后才满足前置的更早链位事件"（如后建的工坊/后采的首矿）会插队到 envoy 之前，与旧钩子行为背离——链首是唯一精确复现钩子优先级的位置。链注释性表述见 `src/progression/progression.gd` 头注释。

**等价口径**：合并钩子必然改变 `due_event` 对"approach_diplomatic 已置"状态的返回值（这正是并入的目的），故等价性在两层分别证明：
- 纯迁移层（24 旧条目）：`due_event` 同 state 逐字节等价——矩阵 A-G + 既有 31 项 progression 测试零修改通过；
- 系统层（含钩子合并）：旧系统 = 钩子 + 链，新系统 = 链——矩阵 H 证明序列一致。

## 3. RED（先于实现）

**探针（改动前行为快照）**：临时测试 `test_dlx2_probe.gd`（提交前已删）导出旧 `_event_chain()` 的守卫字面量与固定 state 矩阵的 due 排干序列。命令与关键输出：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/test_dlx2_probe.gd -gexit
PROBE_SEQ_A=event_prologue_landing
PROBE_SEQ_B=event_prologue_landing,event_first_mining
PROBE_SEQ_C=event_prologue_landing,event_first_mining,event_drift_aftermath
PROBE_SEQ_D=…,event_first_anchor,event_workshop_guide,event_misa_campfire,event_dust_calamity,event_quiet_night
PROBE_SEQ_E=…,event_pylon_hum
PROBE_SEQ_F=…,event_husk_aftermath,event_station_mode,event_echo_resonance,event_approach,event_policy,event_lumen_wildfire,event_leviathan_pact_pre,event_leviathan_pact,event_leviathan_aftermath,…,event_final_ascent,event_ending_luoxian,event_ending_misa,event_epilogue_exploited
PROBE_SEQ_G=…,event_epilogue_sealed
PROBE_SEQ_H=event_prologue_landing,event_station_mode,event_echo_resonance,event_policy,event_diplomat_envoy
```

矩阵 H（`approach_diplomatic`+`diplomatic_stance`+`echo_chamber_active`）的旧 `due_event` 序列不含 envoy——旧系统下它由钩子**前置**触发，故新链期望序列 = `event_envoy_trust,` + PROBE_SEQ_H。

**RED 运行**（新增 `test_progression_chain.gd` 7 项 + 更新软锁断言，实现未写）：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/test_progression_chain.gd,res://tests/unit/test_progression.gd -gexit
Scripts 2  Tests 39  Passing 31  Failing 8
```

8 项失败逐一符合预期：7 项新测试（`bootstrap`/`load_chain_from` 不存在 → Nonexistent function）+ 1 项软锁断言（`[""] expected to equal ["event_envoy_trust"]`，旧链尚无 envoy）。

## 4. 实现（GREEN）

- `schemas/progression-chain.schema.json`（新建，Draft 2020-12，`$id: starsoil:schemas/progression-chain.schema.json`）：有序数组，条目 required `{id, requires_all, requires_any_prefix, requires_ending_ready}`，`additionalProperties: false`，稳定 ID 与前缀字段 pattern 约束，风格对齐 `endings.schema.json`。
- `data/progression/event_chain.json`（新建）：25 条 = 24 条旧链逐条迁移（id/守卫/顺序完全一致，字面量以探针导出为准，`event_quiet_night` 的双前缀 done flag `event_event_misa_campfire_done` 原样保留）+ 链首 `event_envoy_trust`。
- `src/progression/progression.gd`：
  - 新增 `EVENT_CHAIN_PATH` 常量与 `static` 链缓存（`_chain` / `_chain_bootstrapped` / `_chain_last_load`）；
  - 新增 `bootstrap()`（一次性幂等引导）与 `load_chain_from(path)`（加载 + 最小语义校验 + 归一化；坏文件/缺失 `push_error` 并把链回退为空，due_event 失败安全返回 ""；失败同样记为已引导，避免 tick 逐帧重读）；
  - 校验（`_chain_entry_error`）：对象形态、id 稳定 snake_case 且唯一、requires_all 为非空 string 数组、requires_any_prefix 非空 string 或 null、requires_ending_ready 为 bool；
  - `_event_chain()` 改为缓存访问器（未引导时惰性 bootstrap 兜底，直调 due_event 的既有测试路径零改动）；`due_event` 对外签名与判定循环不变；
  - `_prerequisites_met` 改为防御式 `.get` 读取（null prefix / 空数组 / false 语义与旧 `entry.has` 分支逐条等价）。
- `src/integration/game_session.gd`：删除 `ENVOY_TRUST_EVENT_ID` 常量、`_envoy_trust_due()` 与 tick 中的钩子分支（矿井入口检查保留）；`_ready` 显式 `Progression.bootstrap()`（幂等，失败仅 warning——Progression 侧已 push_error）。tick 事件判定收敛为单一来源：位置检查点 > 矿井入口（位置触发特例）> `Progression.due_event`（外置链，envoy 居链首）> 遭遇 > 结局。
- 测试：
  - 新增 `tests/unit/test_progression_chain.gd`（7 项）：默认链加载幂等、25 条目与迁移快照逐字段比对、守卫四组合（无守卫 / requires_all（含 done 模板 flag）/ requires_any_prefix（false 值不命中、异名同前缀命中）/ requires_ending_ready 两态）、11 类坏文件拒绝 + `push_error` 断言 + 失败安全、缺失文件 `push_error` + 空串、纯数据扩链（临时 JSON 增加两事件证明"加事件=改 JSON"）、A-H 等价矩阵；
  - `test_progression.gd`：3 处空转守卫修复（见 §6.3）+ 软锁断言更新（§6.1）；
  - `test_integration.gd`：定义计数下限化（§6.2）。

## 5. 行为等价证明（迁移前后矩阵对照）

期望值冻结自 §3 探针（旧硬编码链真实输出），由 `test_due_sequences_match_pre_migration_snapshot_matrix` 常驻断言：

| 矩阵 | state（guard flags） | 旧系统序列（钩子+链） | 新链序列 | 一致 |
|---|---|---|---|---|
| A | （空） | prologue | 同左 | ✓ |
| B | first_mining_done | prologue, first_mining | 同左 | ✓ |
| C | +first_drift_won | …, drift_aftermath | 同左 | ✓ |
| D | +first_anchor+workshop | …, misa_campfire, dust_calamity, quiet_night | 同左 | ✓ |
| E | +pylon_stabilized | …, pylon_hum | 同左 | ✓ |
| F | +husk/echo/exploit/direct/wildfire/mine/due/leviathan_won | 22 项主线至 epilogue_exploited | 同左 | ✓ |
| G | +station_mode_seal | F + epilogue_sealed | 同左 | ✓ |
| H | approach_diplomatic+diplomatic_stance+echo_chamber_active | **envoy_trust**, prologue, station_mode, echo_resonance, policy, diplomat_envoy | 同左 | ✓ |

A-G（无 approach_diplomatic，envoy 不到期）证明纯迁移逐字节等价；H 证明钩子并入后系统级触发序列一致（旧钩子先于链触发 envoy = 新链首）。旁证：既有 31 项 progression 测试与全部集成/信任经济/软锁/结局链测试在零逻辑修改下通过（仅 §6 两处合法断言更新），其中外交路线两条集成测试在删除钩子后仍按 `approach → envoy_trust → policy` 序列推进（tick 驱动，非测试直调）。

## 6. 合法断言更新逐条说明

1. **`test_progression.gd` 软锁路径（b）**：期望 `""` → `"event_envoy_trust"`（测试更名 `…yield_empty…` → `…stay_clear…`）。原因：DLX-2 把 envoy 并入外置链是任务 1.4 的既定行为变更；旧系统全局行为完全一致（DLX-1 钩子在本 state 同样先触发 envoy，见 §5 矩阵 H），仅断言目标从"链内不可见"改为"链首可见"。路径（a）结局门控（无 approach_diplomatic）断言不变仍为 `""`。
2. **`test_integration.gd` 定义计数**：`EXPECTED_DEFINITION_COUNT = 56` 精确断言 → `MIN_EXPECTED_DEFINITION_COUNT = 56` + `assert_gte`（测试更名 `…forty_definitions` → `…definition_floor`）。原因：DL7 任务本体——内容包增长是预期行为，精确值使每次内容扩充都要改测试；下限仅防"定义集合意外丢失"。历史计数注释（45→46→55→56）折叠进下限基线说明。
3. **`test_progression.gd` 3 处空转守卫修复**（缺陷修复，非语义变更）：`if not assert_not_null(x): return`（2 处）与 `if not assert_true(loaded.is_ok): return`（1 处）——GUT 断言返回 void，`not void` 恒真，三处早退使其后断言**从未执行**（`assert_true` 处甚至使整个链-包一致性检查空转）。改为显式断言 + 空值早退；复活后的断言（done 模板常量一致性、双前缀字面 flag、链-包一致性、deferred 桥接）全部通过，未暴露产品缺陷。

## 7. 钩子删除确认

- `grep -rn "_envoy_trust_due|ENVOY_TRUST_EVENT_ID" src/ tests/` → 无匹配（exit 1）。
- 外交路线信任经济断言在钩子删除后经外置链照常成立：`test_trust_economy_diplomatic_route_reaches_symbiosis_threshold`（approach 选项 1 → tick 启动 `event_envoy_trust` → trust 50→55）与 `test_trust_locked_option_is_disabled_and_choice_never_softlocks`（trust 0→5）全绿。
- `data/events/event_envoy_trust.json` 事件数据零改动（其 `requires_flag` 字段仍属 EventRunner 数据面；链守卫为其镜像）。

## 8. 验证记录

```
$ pwsh -NoProfile -File ./scripts/Run-Gut.ps1
Tests 545  Passing 545  Asserts 8621        # 538 基线 + 7 新增，exit 0

$ pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1
VERSION PASS 4.7.2.stable.official.ed1daf0bf / IMPORT PASS / MAIN_SCENE PASS /
GUT_DEFAULT PASS exit=0 / GUT_FAILURE_FIXTURE PASS exit=1        # exit 0

$ pwsh -NoProfile -File ./scripts/Verify-Slice.ps1
GATE1 GUT PASS exit=0 / GATE2 TOOLCHAIN PASS exit=0 /
GATE3 EXPORT_PRESETS PASS / GATE4 EXPORT_SMOKE PASS exit=0
VERIFY_SLICE_EXIT_CODE=0
```

## 9. 限制

1. `scripts/validate_content.py` 未纳入 `data/progression/event_chain.json` 的离线 schema 校验（`scripts/` 不在本包允许路径）；运行时由 `Progression.bootstrap` 最小校验 + 专项测试覆盖。DLX-3+ 可把链文件注册进 `SCHEMA_TARGETS`。
2. 坏链文件测试触发 `push_error`，在 GUT 输出中表现为预期 ERROR 行（经 `assert_push_error` 断言消费，不影响 exit code）；与 DLX-1 endings 坏 fixture 先例同风格。
3. `bootstrap()` 失败后缓存失败态（tick 每帧调用 due_event，不逐帧重读坏文件）；修复需显式 `load_chain_from` 重载——生产中该状态意味着内容包损坏，失败安全（空链）优于半链。
4. 导出冒烟（GATE4）在本机实际执行 export 并 PASS，属环境相关门（模板已装）；无模板环境按 Verify-Slice 既有约定 SKIP。

## 10. 下一步

- DLX-3：建造反应通用化（DL2）+ 目标链/提示外置（DL5）——`place_flag` 声明式字段、`objectives.json`/`hints.json`。
- 建议随 DLX-6 把 `event_chain.json` 纳入存档 content_hash 政策讨论（链改动对旧档语义的影响面）。
