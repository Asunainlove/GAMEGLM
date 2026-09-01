# 存档内容政策（Save Content Policy）

- 版本：1（DLX-6 引入，2026-09-01）
- 适用范围：`save_version = 1` 的全部存档 payload；实现落在读档侧（`SaveCodec.sanitize_payload_against_content` + `GameSession._try_load_autosave`），**不改变存档 payload 字段集，`save_version` 保持 1**。
- 政策执行点：`GameSession` boot 读档链（`_ready → _try_load_autosave`）在 `GameState.restore_snapshot` 之前执行；`SaveService`/`GameState` 层不做内容判定（save 层经 `content_defs` 参数注入保持可测，state 层只负责 patch 语义）。

## 1. 背景与目标

存档 payload 携带 `content_hash`（随档记录的"内容包指纹"），此前**只有记录无消费**：删改内容后旧档的孤儿 flag / 静默残留无任何检测。本政策把 `content_hash` 变成读档时的显式契约，使"数据包即 DLC"（内容包 = `data/` 目录数据变更）在存档侧有确定性行为：

1. 新增内容（DLC 正常路径）必须无损载入旧档；
2. 删改内容不炸玩家档——以声明式孤儿降级清理代替载入失败；
3. 收敛：任何一次读档后，持久状态总是携带当前内容总哈希，下次读档回到 `hash_match`。

## 2. content_hash 语义（DLX-6 扩展）

`content_hash` = **"ContentDB 六类定义（items/buildings/combat_units/combat_actions/events/encounters）+ 进度配置文件（`data/content/endings.json`、`data/progression/event_chain.json`、`data/world/world_config.json`）"的 canonical JSON 总哈希**（SHA-256，64 位小写十六进制）。

- 三进度配置文件仍由各模块自身装载与校验（Endings / Progression / WorldConfig，装载路径与失败回退不变）；`ContentDB` 只在计算哈希时读取原文解析后作为 `progression_configs` 键的贡献参与 canonical 排序。
- 单文件缺失/空/坏 JSON 时该项贡献记为 `""`（缺省贡献，哈希保持确定性）；此时对应模块自身的失败安全路径照常兜底。
- `endings.json` 在 ContentDB 定义装载中仍是保留文件名（`RESERVED_DATA_FILENAMES`，不进六类定义），仅参与哈希。

## 3. 三档政策（声明式，无表达式求值）

读档时比对 `payload.content_hash` 与当前 `ContentDB.content_hash()`：

| 档位 | 触发条件 | 处置 | 日志 |
|---|---|---|---|
| `hash_match` | 两哈希完全一致 | payload 原样载入，零额外写入（revision 不变） | 无 |
| `hash_superset` | 哈希不一致，但孤儿清理**零命中**（当前内容相对旧档为纯新增） | 接受，payload 原样载入；restore 成功后把当前哈希经 patch 回写（revision +1） | `push_warning` 摘要（政策档位 + 清理报告"无孤儿（接受）"） |
| `hash_divergent` | 哈希不一致，且孤儿清理**有命中**（定义被删改） | 接受，载入清理后的 payload；restore 成功后把当前哈希经 patch 回写 | `push_warning` 摘要（政策档位 + 各非空清理类别明细） |

说明：

- **superset / divergent 的判定是操作性的**：存档只记录哈希、不记录旧定义副本，无法先验区分"纯新增"与"删改"；以孤儿清理是否命中作为声明式判据——引用的定义全部仍在 = superset，存在孤儿 = divergent。
- **修改类变更的已知边界**：若某定义只改内容不改 ID 集合（如调整数值/文案），哈希变化但无孤儿，按 `hash_superset` 接受。这是有意的降级裁决：无法重构旧定义时，接受"兼容漂移"优先于拒绝玩家档。
- `ContentDB` 未引导时（异常路径）政策整体跳过，原样载入（失败安全）。

## 4. 孤儿清理规则（hash_divergent 时执行）

四条规则彼此独立，对 payload 深拷贝执行，输入永不原地修改：

1. **inventory**：条目 id 不存在于 `defs["items"]` → 删除；
2. **flags**：形如 `event_<event_id>_done` 且 `<event_id>` 不存在于 `defs["events"]` → 删除（其余形态 flag 一律保留，包括里程碑/政策/提示/遭遇胜利 flag；`<event_id>` 为空视为不引用任何事件，保留）；
3. **chunk_deltas**：chunk id 不在 `defs["chunk_ids"]`（世界网格目录，由集成层按 `WorldConfig.grid_size()` 派生 `chunk_X_Y` 全集注入；键缺失时整条规则跳过）→ 删除；
4. **battle_outcomes**：battle id 不存在于 `defs["encounters"]` → 删除。

不清理（有意保留）：`placed_buildings`（引用未知建筑 id 的实例由渲染/供电链防御处理）、`completed_events`（记账性字段，无门控消费者）、`world_enums`、关系/意识形态数值、玩家位置。

`GameSession` 调用时传入 `content_defs = ContentDB.content_defs_snapshot() + {"chunk_ids": [...]}`——前三类来自 ContentDB 快照（items/events/encounters），`chunk_ids` 由集成层组装，save/content 两层不依赖世界模块。

## 5. content_hash 回写（收敛）

restore 成功后，若持久状态 `content_hash` ≠ 当前哈希，`GameSession` 经**专用 patch op** `StatePatch.set_content_hash(hash)`（`GameState` 校验：64 位小写十六进制，与 envelope checksum 同形，不适用稳定 ID 规则）以独立 integration patch（`integration_content_hash_refresh_<revision>`）回写。同 revision 同 source 重放由 `already_applied` 幂等短路；一致（含已收敛档）时零写入。

收敛路径：`hash_match` → 零写入；`superset`/`divergent`/空 hash（DLX-6 前的旧档均记录空串）→ 回写后 revision +1，下次读档即 `hash_match`。

## 6. 维护契约（golden fixture）

`tests/golden/save_v1_golden.json` 的 `content_hash` 取真实 `ContentDB.bootstrap("res://data")` 的总哈希，是政策下的 `hash_match` 样本。**任何对 `data/**` 定义或三进度配置文件的改动，必须重跑生成器并同步 fixture**：

```bash
godot --headless --path . --script res://tests/golden/generate_golden_v1.gd
# 将打印的单行输出原样写入 tests/golden/save_v1_golden.json
```

`test_save_policy_dlx6.test_golden_fixture_content_hash_equals_bootstrapped_content_hash` 锁定该契约（哈希漂移会显式红灯）。

## 7. 已知边界

- 新开局会话（无可读档）不触发政策，初始存档 `content_hash` 为空串；首次重载按 superset 接受并收敛。有意不做"开局即写哈希"：那会让全新状态的 revision 变为 1，破坏"零修改不推进 revision"的既有契约。
- 修改类内容变更（ID 集合不变）不可与纯新增区分，按 superset 接受（§3 说明）。
- 政策只保证"内容不炸玩家档"的孤儿降级；不承诺删改内容后的叙事连续性（缺失事件按 due 链"定义不存在即跳过"的既有失败安全语义处理）。
