# DLX-6 — 存档内容政策（PM 计划 DL6）

- 分支：`feature/dlx6-save-policy`（worktree `.worktrees/dlx6`）
- 日期：2026-09-01
- 范围：`docs/plans/2026-08-31-dlc-readiness-and-pm-verdict.md` DLX-6 行
- 基线：`main` @ `13ee780`，Run-Gut 616/616 全绿（DLX-5 合入后）

## 1. 目标

1. 消除"content_hash 有记录无消费"缺口：读档时比对存档 `content_hash` 与当前内容总哈希，mismatch 走**声明式孤儿降级清理**（不炸玩家档）而非拒绝载入。
2. `content_hash` 语义扩展为"ContentDB 六类定义 + 进度配置文件（endings/event_chain/world_config）"的 canonical JSON 总哈希；三文件由各模块自身装载不变，`ContentDB` 只追加哈希贡献。
3. 新增 `StatePatch.set_content_hash` 专用回写 op：任何一次读档后持久状态总是收敛到当前哈希。
4. 政策文档化 `docs/save-content-policy.md`（三档 `hash_match` / `hash_superset` / `hash_divergent`、触发条件、日志行为、清理规则、维护契约）。
5. **payload 字段集不变，save_version 仍为 1**——政策是读档侧行为，非 schema 变更（AGENTS.md 版本迁移条款不触发）。

## 2. 设计裁决

**三档判定的操作性判据**：存档只记录哈希、不携带旧定义副本，无法先验区分"纯新增"与"删改"。以孤儿清理命中数为声明式判据：mismatch + 零命中 = `hash_superset`（当前内容相对旧档为纯新增，DLC 正常路径，接受）；mismatch + 有命中 = `hash_divergent`（定义被删改，接受但清理）。**修改类变更**（ID 集合不变、内容改）无孤儿，按 superset 接受——有意降级：无法重构旧定义时，接受"兼容漂移"优先于拒绝玩家档（政策文档 §3）。

**落点与注入**：`SaveCodec.sanitize_payload_against_content(payload, current_hash, content_defs) -> 报告`（static 纯函数，深拷贝执行、输入零修改）。defs 经参数注入（`{"items","events","encounters"}` 来自新增的 `ContentDB.content_defs_snapshot()`，`"chunk_ids"` 由集成层按 `WorldConfig.grid_size()` 派生注入）——save 层不依赖 ContentDB/WorldConfig 类型，保持可测。`GameSession._try_load_autosave` 在 `restore_snapshot` 之前执行 sanitize、成功之后回写哈希（`integration_content_hash_refresh_<revision>` patch，同 revision 同 source 重放由 `already_applied` 幂等短路；哈希已一致时零写入）。

**清理规则四条（政策文档 §4）**：inventory 未知物品条目；`event_*_done` 形态 flag 引用不存在事件；chunk_deltas 世界网格外 chunk；battle_outcomes 不存在遭遇。**有意不清理**：placed_buildings / completed_events / world_enums / 关系与意识形态 / 玩家位置（placed_buildings 由渲染与供电链防御处理；completed_events 为记账性字段，无门控消费者）。

**哈希贡献的缺省语义**：三配置文件缺失/空/坏 JSON 时该项贡献记为 `""`（缺省贡献）——既有 fixture 树（无这些文件）的哈希语义连续，哈希保持确定性；对应模块自身的失败安全路径照常兜底。

**开局不写哈希**：新开局（无可读档）不触发政策，初始存档 `content_hash` 为空串，首次重载按 superset 接受并收敛。不做"开局即写"：那会把全新状态 revision 推到 1，破坏"零修改不推进 revision"契约（政策文档 §7）。

## 3. RED（先于实现）

新增 `tests/unit/test_save_policy_dlx6.gd`（7）、`tests/unit/test_integration_dlx6.gd`（3）、`test_state_v2.gd` +3、`test_content_db.gd` +2。首跑命令与关键输出：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/unit/test_save_policy_dlx6.gd
SCRIPT ERROR: Parse Error: Static function "sanitize_payload_against_content()" not found in base "SaveCodec".
[GUT ERROR]: Nothing was run.

$ ... -gtest=res://tests/unit/test_state_v2.gd
SCRIPT ERROR: Invalid call. Nonexistent function 'set_content_hash' in base 'RefCounted (StatePatch)'.
Tests 17 / Passing 14 / Failing 3

$ ... -gtest=res://tests/unit/test_content_db.gd
[Failed] ["412224...5651"] expected to not equal ["412224...5651"]:  endings.json 变化必须改变总哈希。
   （event_chain.json / world_config.json 同——哈希未纳入三配置文件）
SCRIPT ERROR: Invalid call. Nonexistent function 'content_defs_snapshot' in base 'Node (content_db.gd)'.
Tests 23 / Passing 21 / Failing 2

$ ... -gtest=res://tests/unit/test_integration_dlx6.gd
[Failed] { "ghost_material": 2, "starsoil_dust": 6 } != { "starsoil_dust": 6 }  孤儿未被清理
[Failed] ["ffff...ffff"] expected to equal ["4c6017...6018"]:  读档政策落地后持久状态必须携带当前内容总哈希。
Tests 3 / Passing 1 / Failing 2
```

生产 API 全部缺失，新用例无一按预期语义通过。

## 4. GREEN 与测试证据（新鲜输出）

```
$ pwsh -NoProfile -File ./scripts/Run-Gut.ps1
Scripts 50 / Tests 631 / Passing 631（616 基线 + 15 新增，Asserts 10044）

$ pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1
VERSION PASS 4.7.2.stable.official.ed1daf0bf / IMPORT PASS / MAIN_SCENE PASS /
GUT_DEFAULT PASS exit=0 / GUT_FAILURE_FIXTURE PASS exit=1 → exit 0

$ pwsh -NoProfile -File ./scripts/Verify-Slice.ps1
GATE1 GUT PASS / GATE2 TOOLCHAIN PASS / GATE3 EXPORT_PRESETS PASS / GATE4 EXPORT_SMOKE PASS
→ VERIFY_SLICE_EXIT_CODE=0

$ python scripts/validate_content.py
Checked 32 content file(s), 57 definition(s) against 7 schema(s). RESULT: PASS
```

**既有 616 基线全绿，零断言改动**——既有测试文件的唯一变更是 `test_state_v2.gd`（+3）与 `test_content_db.gd`（+2、清理列表 +1 条目）的纯追加，无任何既有用例修改。基线哈希值变化的测试（`test_content_hash_*`）只断言性质（非空/稳定/敏感），不断言具体值，天然兼容。

## 5. golden fixture 重生成过程

1. `tests/golden/generate_golden_v1.gd` 的 `content_hash` 来源由固定串 `"starsoil-content-v1-vertical-slice".sha256_text()` 改为真实 `ContentDB.bootstrap("res://data").content_hash()`（新哈希语义下 fixture 成为 `hash_match` 样本；文件头注释写明维护契约）。
2. 重跑 `godot --headless --path . --script res://tests/golden/generate_golden_v1.gd`，打印单行原样写入 `tests/golden/save_v1_golden.json`（1061 字节，无尾换行，与原格式一致）。
3. 差异仅 `payload.content_hash`（`789d6dfa…ab04` → `44fc1742…`）与其驱动的 envelope `checksum`（`64c06479…eb397` → `6ed8cd21…ddb364`）；payload 其余字段逐字节不变（`git diff` 单行替换验证）。
4. `test_save_v2.gd` 的 golden 五连测（decode 断言/迁移恒等/重编码恒等/tamper 拒绝/未来版本拒绝）零改动通过；新增 `test_save_policy_dlx6.test_golden_fixture_content_hash_equals_bootstrapped_content_hash` 锁定"fixture 哈希 = 真实 bootstrap 总哈希"契约——`data/**` 任何改动不重生成 golden 即显式红灯。

## 6. 政策文本摘要（docs/save-content-policy.md）

- **三档**：`hash_match`（一致，原样，零写入）→ `hash_superset`（不一致但零孤儿 = 纯新增，接受，回写哈希）→ `hash_divergent`（不一致且有孤儿 = 删改，接受但清理，回写哈希）。superset/divergent 均输出 `push_warning` 摘要（档位 + 存档/当前哈希 + 清理明细）。
- **执行点**：`GameSession` boot 读档链 restore 前 sanitize、restore 后回写；ContentDB 未引导时失败安全跳过。
- **回写 op**：`StatePatch.set_content_hash`，GameState 校验 64 位小写十六进制（`SaveCodec.is_checksum_hex`，与 envelope checksum 同形，不适用稳定 ID 规则）。
- **维护契约**：`data/**` 定义或三配置文件改动 → 重跑 golden 生成器并同步 fixture。
- **已知边界**：新开局存档空哈希首次重载收敛；修改类变更按 superset 接受；政策保证孤儿降级、不承诺叙事连续性（缺失事件走"定义不存在即跳过"既有语义）。

## 7. 变更清单

- `src/save/save_codec.gd`：三档常量 + `sanitize_payload_against_content` 及四规则辅助（static）；`is_checksum_hex` 公共静态（`_is_checksum` 委托）。
- `src/state/state_patch.gd`：`OP_SET_CONTENT_HASH` + `set_content_hash`。
- `src/state/game_state.gd`：`_apply_set_content_hash`（专门 hash 校验，失败码 `invalid_content_hash`）。
- `src/content/content_db.gd`：`HASH_CONFIG_FILES` + `_content_dir` 记录 + `_hash_config_contribution`（哈希扩展）；`content_defs_snapshot()`（最小新增）。
- `src/integration/game_session.gd`：`_apply_content_policy` / `_content_defs_for_policy` / `_policy_report_summary` / `_refresh_content_hash_after_load`，`_try_load_autosave` 接入。
- `tests/golden/*`：生成器哈希来源 + fixture 重生成；新增测试文件 2 个、既有测试文件纯追加 2 个。

## 8. 决策与限制

- **schema 增量：无**。payload 字段集不变、save_version=1、schemas/ 未动；`set_content_hash` 是运行时 patch op（patch 不落盘），非持久 schema。无需 BLOCKED 裁决。
- `ContentDB` 现在读取其三棵装载树之外的三个配置文件（仅哈希计算）——DLX-5 限制"ContentDB 不装载 data/world/"的语义更新：定义装载边界不变，读边界为哈希扩展（本包裁决，政策文档 §2）。
- superset 判定的"修改类盲区"与"开局空哈希"为已记录的降级边界（政策文档 §3/§7），不阻塞"数据包即 DLC"验收。
- 孤儿清理粒度为 ID 集合级：定义存在但引用链悬空（如物品存在而配方被删）不在本政策范围（ContentDB.validate_refs 覆盖定义侧，存档侧仅存 ID 引用）。

## 9. 确切下一步

合并 main → 复审"六场景新增内容步骤数"全部 ≤ 1 个 JSON 文件 → PM 三问复评（目标：可复用性 3/5 → 4.5/5）→ 项目回到 G6 资产生产（人工审批门）与 G7 真人门禁。
