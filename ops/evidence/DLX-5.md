# DLX-5 — 世界布局外置（DL3）

- 分支：`feature/dlx5-world`（worktree `.worktrees/dlx5`）
- 日期：2026-09-01
- 范围：`docs/plans/2026-08-31-dlc-readiness-and-pm-verdict.md` DLX-5 行
- 基线：`main` @ `c2ee821`，Run-Gut 604/604 全绿（DLX-4 合入后）

## 1. 目标

1. `data/world/world_config.json`（网格尺寸 / seed 覆盖 / 岩壁色 / authored 地区声明：layout + entry 触发链 + Boss 检查带）替代 GDScript 布局常量与写死特判，新增手工地区 = 加一个 `regions[]` JSON 条目，零代码改动。
2. 删除 `chunk_data.gd` 的 `MINE_CHUNK_ID`/`MINE_WALL_RECTS`/`MINE_ORE_VEINS`/`MINE_BOSS_ROOM_RECT` 常量与 `generate_mine`，改为 `generate_authored(chunk_id, layout)`。
3. `world.gd` 读配置（authored chunk 分发、网格尺寸、seed 覆盖、岩壁色），DLX-4 enriched 重生成保持兼容。
4. `game_session.gd` 删除四常量（`MINE_CHUNK_ID`/`MINE_ENTRY_EVENT_ID`/`MINE_ENTERED_FLAG`/`MINE_BOSS_ROOM_LOCAL_MIN_Y`）与写死触发逻辑，泛化为遍历 `regions[]`；`_resolve_chunk_id` clamp 读配置网格。
5. schema 离线校验：`world_config.json` 纳入 `validate_content.py`（SCHEMA_TARGETS 结构允许，直接注册）。

## 2. 等价性设计与裁决记录

**world_seed 覆盖语义**：schema 的 `world_seed: int|null`，null（迁移值）= 沿用 GameState 快照 seed（`world.gd` 原 `int(snapshot.get("world_seed", 0))` 语义不变）；非 null 时覆盖快照（数据驱动覆盖，新增能力，不影响迁移等价）。解析集中于 `world.gd._resolve_world_seed`，启动生成与跳变重生成共用。

**enriched 与 authored 兼容裁决**（任务书指定，写进测试）：authored 布局不受 `world_response_exploited` 影响，仅程序生成 chunk 富集。实现两处落实——启动生成分发（authored 走 `generate_authored`，无 enriched 参数）与跳变重生成跳过（`region_for_chunk` 非空即 `continue`，与迁移前跳过 `MINE_CHUNK_ID` 等价）。

**触发链泛化保序**：`_region_entry_event_due` 按 `regions[]` 文件顺序遍历，单 region 内的守卫顺序与迁移前逐条一致（entered_flag → 事件 done → 事件定义存在 → 位置判定），返回第一个命中的 `entry.event_id`；`_record_boss_room_checkpoints` 与 `_show_mine_hints_if_due` 同序遍历。chunk 互不重叠由装载期"重复 chunk_id 拒绝"保证。入口事件仍先于 `Progression.due_event`（优先级不变）；提示触发点键 `mine_entered` 保留为 `MINE_HINT_TRIGGER` 常量（它是 hints.json 的触发点词汇，非地区数据）。

**坏配置兜底语义**：文件缺失/坏 JSON/结构非法 → `push_error` + 整体回退（4x2 网格、seed=null、冻结岩壁色、无 region ⇒ 全程序生成 + 触发链为空）。失败也记为已引导（每帧访问器不重读坏文件，先例 Progression 链装载）。整体回退优先于半配置运行（失败安全 > 局部降级）。

**Godot JSON 整数陷阱**：JSON 整数字面量解析为 float，WorldConfig 校验经 `_as_int` 归一（先例 `ContentDB._as_integral`）；schema（Python jsonschema）侧 `integer` 天然接受。测试内临时配置写法无需特判。

## 3. RED（先于实现）

新增 `tests/unit/test_world_dlx5.gd`（12 测试）。首跑命令与关键输出：

```
$ GODOT --headless --path . -s res://addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/unit/test_world_dlx5.gd
SCRIPT ERROR: Parse Error: Identifier "WorldConfig" not declared in the current scope.
   at: GDScript::reload (res://tests/unit/test_world_dlx5.gd:...)
ERROR: Failed to load script "res://tests/unit/test_world_dlx5.gd" with error "Parse error".
[GUT ERROR]: Nothing was run.
```

补注册仅含 class_name 的 stub 后复跑，逐方法报错（`Static function "reset_for_tests()" not found in base "WorldConfig"`、`bootstrap()`、`grid_size()`、`seed_override()`、`rock_wall_color()`、`regions()`、`layout_for_chunk()` 等）——生产 API 缺失，12 测试无一可通过。

## 4. GREEN 与测试证据（新鲜输出）

```
$ pwsh -NoProfile -File ./scripts/Run-Gut.ps1
Scripts 48 / Tests 616 / Passing 616（604 基线 + 12 新增）
$ pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1
VERSION PASS 4.7.2.stable.official.ed1daf0bf / IMPORT PASS / MAIN_SCENE PASS / GUT_DEFAULT PASS / GUT_FAILURE_FIXTURE PASS exit=1 → exit 0
$ pwsh -NoProfile -File ./scripts/Verify-Slice.ps1
GATE1 GUT PASS / GATE2 TOOLCHAIN PASS / GATE3 EXPORT_PRESETS PASS / GATE4 EXPORT_SMOKE PASS → VERIFY_SLICE_EXIT_CODE=0（连跑两遍确认）
$ python scripts/validate_content.py
Checked 32 content file(s), 57 definition(s) against 7 schema(s). RESULT: PASS
```

## 5. 行为等价证明

1. **布局逐字节迁移对照**（`test_shipped_config_migrates_frozen_values_byte_for_byte`）：测试内嵌旧常量冻结快照（8 块 `MINE_WALL_RECTS`、7 条矿脉矩形、`MINE_BOSS_ROOM_RECT(10,22,10,10)`、入口 `event_mine_threshold`/`mine_entered`、Boss 检查 `y>=22`、岩壁色 `0.24,0.2,0.16`、网格 4x2），与 JSON 装载结果逐一断言全等。
2. **生成逐格等价**（`test_generate_authored_matches_independent_json_rederivation`）：从 JSON 原始矩形**独立重导出** cells（不经过被测解析器）与 `generate_authored` 输出全等——87 格以上矿/墙逐格一致（总 790 格）。
3. **既有测试即快照**：`test_world_mine.gd`（布局/采样/比例 24:32:24/入口走廊/Boss 房无矿/渲染层）、`test_integration_mine.gd`（入口触发/幂等/rock_wall 采集建造拒绝/Boss 检查点 `y>=54` 序列）、`test_world_gap3.gd`、`test_world_dlx4.gd`、`test_world_chunk_data.gd` 全部零断言值改动通过（合法更新仅为数据源替换，见 §6）。
4. **seed 等价**：`world_seed: null` 时 `_resolve_world_seed` 返回快照 seed，与迁移前表达式逐字节一致（`test_world_boots_normal_without_flag` 等既有 seed 断言通过）。

## 6. 迁移对照表

| 迁移前（GDScript） | 迁移后（数据/泛化） | 消费方 |
|---|---|---|
| `world.gd CHUNK_GRID_SIZE=(4,2)`；`game_session CHUNK_GRID_WIDTH/HEIGHT` | `world_config.json grid_size:[4,2]`（兜底同值） | `world._grid_size`、`game_session._resolve_chunk_id` |
| `world.gd:136-139 chunk_3_1 特判 generate_mine` | `regions[].chunk_id` 分发 `generate_authored` | `world._generate_chunks`/`_regenerate_scar_free_chunks` |
| `chunk_data MINE_WALL_RECTS(8)/MINE_ORE_VEINS(7)/MINE_BOSS_ROOM_RECT` | `regions[].layout{wall_rects/ore_rects/boss_room_rect}` | `ChunkData.generate_authored` |
| `game_session MINE_ENTRY_EVENT_ID/MINE_ENTERED_FLAG` | `regions[].entry{event_id/entered_flag}` | `_region_entry_event_due`/`_show_mine_hints_if_due` |
| `game_session MINE_BOSS_ROOM_LOCAL_MIN_Y=22` | `regions[].boss_checkpoint_min_local_y` | `_record_boss_room_checkpoints` |
| `world_renderer ROCK_WALL_COLOR` | `mine_rock_wall_color:[0.24,0.2,0.16]`（兜底同值） | `WorldConfig.rock_wall_color()` |
| `game_session MINE_CHUNK_ID`（提示/触发链硬编码） | region 声明驱动（提示触发点键 `mine_entered` 保留为表词汇常量） | `GameSession.tick` |
| —（新增） | `world_seed` 数据覆盖、多地区触发链、坏配置整体兜底 | `WorldConfig` |

既有测试合法更新（逐条，断言值零改动）：
- `test_world_mine.gd`：`generate_mine` → `generate_authored` + `WorldConfig.layout_for_chunk`（数据源替换，`_mine_chunk()` 辅助）；方法名 `test_generate_mine_*` → `test_generate_authored_*`；3 处文案随之更新。
- `test_world_gap3.gd`：`_ore_cell` 同上数据源替换。
- `test_world_dlx4.gd`：矿井 authored 断言同上数据源替换。

## 7. 决策与限制

- **兜底粒度**：任一 region 非法 → 整包拒绝回退（非丢弃单 region）。理由：半配置（矿井布局在、触发链丢）比全程序生成更难排查；失败安全优先。
- **`world.tscn` 相机限界仍为静态 4096×2048**：scenes/ 不在允许路径，且迁移值 4x2 与场景一致；网格改动到非 4x2 时需同步场景限界（DLX-6 或后续包处理，已在 schema description 标注 region 语义不变）。
- `boss_room_rect` 当前仅作地区标记（生成不填格、触发链走 `boss_checkpoint_min_local_y`）——按任务书 schema 保留完整形状，供后续声明式检查矩形扩展。
- 首次 `Verify-Slice` 曾出现 GATE2 瞬时 FAIL（exit=1，无匹配断言输出），重跑两遍均全绿；判断为门禁进程并发导入锁瞬时抖动，已记录不掩盖。
- ContentDB 不装载 `data/world/`（只扫 content/events/encounters），`content_hash` 与存档 golden fixture 不受影响（604 基线测试零改动通过佐证）。

## 8. 确切下一步

合并 main → DLX-6 存档内容政策（content_hash 消费/mismatch 孤儿清理）→ 复审"六场景新增内容步骤数"全部 ≤ 1 个 JSON 文件 → PM 三问复评。
