# 冻结模块契约 v1（2026-08-28）

本文件是 15 个并行工作包之间的**冻结接口**。实现必须逐字匹配此处签名；契约变更只能由协调者提交新版本。所有并行包的测试只允许依赖本契约 + 本地测试替身，不得引用其他包尚未合并的文件。

## 0. 通用规则

- 稳定 ID 正则：`^[a-z][a-z0-9_]*$`（与 `GameState._is_stable_id` 一致：全小写、合法标识符）。
- 全部强类型 GDScript（参数与返回值类型标注）；Godot 4.7 API；GL Compatibility。
- 除 ContentDB（WP01 添加）外**禁止新增 Autoload**；禁止全局事件总线；模块间通过注入/参数传递协作。
- 表现层节点不得直接改持久状态，一律经 `GameState.begin_patch(source_id, expected_revision)` + `StatePatch` + `GameState.commit(patch) -> AppResult`。
- `AppResult`（`res://src/core/app_result.gd`）已存在：`is_ok: bool`、`code: String`、`message: String`、`value: Variant`。
- 每个 patch 的 `source_id` 必须唯一且幂等（重复 source_id 返回 `already_applied`），命名建议 `<模块>_<行为>_<序号或目标>`。
- **WP04 依赖规避模式**：WP04 的新操作在并行开发时尚未存在于 main。依赖这些操作的模块（WP08/WP09/WP13/WP14）必须把持久层设计为**可注入 store**（构造/调用参数 `store: Object = null`，null 时用 `GameState`），并自带本地 `DuckPatch` 测试替身（记录操作字典、模拟 commit 语义）。禁止对 `StatePatch` 类型化变量调用 main 上不存在的方法；对新操作的调用经 store 注入路径完成，合并后自然生效，提交时由 `GameState` 统一校验全部操作。
- **并行场景引用模式**：WP03 的 world 不得硬依赖 `res://scenes/player.tscn` 存在——经 `ResourceLoader.exists()` 守卫 + 可注入场景路径，缺失时优雅跳过（合并集成后生效）。同理 WP13 的 battle 场景对 WP10 引擎经契约类型（Dictionary 状态）交互，引擎类在包内以本地最小替身联调。

## 1. 输入映射（已预置于 project.godot，任何 agent 禁改 project.godot）

| action | 默认键 | 用途 |
|---|---|---|
| `move_left` / `move_right` / `move_up` / `move_down` | A/D/W/S + 方向键 | 8 向移动 |
| `interact` | E | 交互（对话/建筑/事件点） |
| `mine` | 鼠标左键 / Space | 采集瞄准格 |
| `place` | 鼠标右键 / F | 放置建筑 |
| `toggle_inventory` | I / Tab | 背包面板 |
| `toggle_overlay` | O | 矿脉覆盖层 |
| `menu` | Esc | 菜单/暂停 |

## 2. 既有 Autoload 与 StatePatch（存在，只读引用）

- `GameState.snapshot() -> Dictionary`（深拷贝；含 `revision/inventory/flags/chunk_deltas/placed_buildings/relationships/ideology/completed_events/battle_outcomes/content_hash/player` 等）。
- `GameState.begin_patch(source_id: String, expected_revision: int) -> StatePatch`；`GameState.commit(patch) -> AppResult`。
- 既有 5 操作：`add_item(item_id, amount)`、`remove_item(item_id, amount)`、`set_destructible_cell(chunk_id, cell_x, cell_y, destroyed)`、`place_building(building_id, chunk_id, cell_x, cell_y)`、`set_flag(flag_id, enabled: bool)`（**布尔值**）。
- **WP04 将追加 5 操作**（增量、不改 payload 形状、save_version 仍为 1）：
  - `set_relationship(char_id: String, dim: String, value: int)` → `relationships[char_id][dim]`，dim ∈ {affection, trust, ideology}，value 钳制 0..100；
  - `adjust_ideology(axis: String, delta: int)` → `ideology[axis]`，axis ∈ {stewardship, continuity, agency}，总和钳制 -100..100；
  - `complete_event(event_id: String)` → 幂等追加 `completed_events`；
  - `record_battle_outcome(battle_id: String, result: String, turns: int)` → `battle_outcomes[battle_id] = {"result": "victory"|"defeat", "turns": int}`，result 仅限 victory/defeat；
  - `set_player_position(cell_x: int, cell_y: int)` → `player.position = {"x": int, "y": int}`（仅在检查点事件调用：进 POI、战斗开始、结局前）。

## 3. ContentDB（WP01 交付；其他包仅按本契约编程，勿引用其文件）

`class_name ContentDB extends Node`，Autoload `res://src/content/content_db.gd`。

- `bootstrap(content_dir: String = "res://data") -> AppResult`：递归加载 `content/**/*.json`、`encounters/*.json`，按 `schemas/*.schema.json` 语义校验（Godot 内校验字段/ID/交叉引用；jsonschema 严格校验由 `scripts/Validate-Content.ps1` 离线执行），bootstrap 后内容不可变。重复调用返回失败 `already_bootstrapped`。
- `is_bootstrapped() -> bool`；`content_hash() -> String`（全部定义 canonical JSON 的 SHA-256，空内容时 `""`）。
- 取用接口（缺失返回 `{}` / 空数组，并 `push_warning`）：`get_item(id) -> Dictionary`、`get_building(id) -> Dictionary`（含内嵌配方）、`get_combat_unit(id) -> Dictionary`、`get_combat_action(id) -> Dictionary`、`get_event(id) -> Dictionary`、`get_encounter(id) -> Dictionary`。
- 枚举：`ids_of(kind: String) -> Array[String]`（kind ∈ item 定义 `kind` 字段值 / building / combat_unit / event / encounter）。
- 交叉引用：`validate_refs() -> AppResult`（配方输入、事件效果、遭遇单位/行动、建筑配方全部必须指向存在的定义）。
- 返回的字典一律为副本，调用方不得假定可回写。

## 4. 场景与节点路径契约

| 路径 | 根节点（name/type） | 关键子节点 |
|---|---|---|
| `res://scenes/player.tscn` | `Player` (CharacterBody2D, group `player`, script `res://src/player/player_controller.gd`) | `Sprite` (ColorRect/Polygon2D 灰盒), `Collision` (CollisionShape2D), `InteractionProbe` (Area2D) |
| `res://scenes/world.tscn` | `World` (Node2D) | `Ground` (TileMapLayer), `OreOverlay` (TileMapLayer), `Buildings` (Node2D), `PlayerSpawn` (Marker2D)；实例化 `res://scenes/player.tscn` |
| `res://scenes/battle.tscn` | `Battle` (Node2D, script `res://src/encounters/battle_scene.gd`) | `Tracks` (Node2D), `UI` (CanvasLayer) |
| `res://scenes/dialogue_box.tscn` | `DialogueBox` (CanvasLayer, script `res://src/narrative/dialogue_box.gd`) | `Panel/NameLabel/TextLabel/OptionsBox` |
| `res://scenes/ui_hud.tscn` | `Hud` (CanvasLayer, script `res://src/ui/hud.gd`) | `InventoryBar`, `ObjectiveLabel`, `MenuPanel` |
| `res://scenes/ending.tscn` | `Ending` (Node2D, script `res://src/endings/ending_scene.gd`) | `TitleLabel`, `SummaryLabel` |

- `app.tscn` 既有 `WorldHost` / `UILayer` / `ModalLayer` 不改结构；新 UI 场景实例挂在 `UILayer` 下，模态挂 `ModalLayer`。

## 5. 模块纯逻辑 API（class_name，全部静态或可实例化纯逻辑，不依赖场景树）

- **采集** `class_name Gathering`（WP05）：`mining_result(cell_def: Dictionary, tool_tier: int) -> Dictionary`（确定性：返回 `{"item_id": String, "amount": int, "hardness_left": int}` 或 `{"item_id": "", "amount": 0}`）；`apply_mining(state: Dictionary, chunk_id: String, cell: Vector2i, cell_def: Dictionary, tool_tier: int) -> AppResult`（内部 begin_patch/commit：`set_destructible_cell` + `add_item`）。
- **背包** `class_name InventoryModel`（WP05）：`stack_counts(inventory: Dictionary) -> Array[Dictionary]`、`can_carry(inventory: Dictionary, item_id: String, amount: int, stack_limit: int, capacity: int) -> bool`、`total_slots(inventory: Dictionary, stack_limits: Dictionary) -> int`。
- **建造** `class_name BuildingRules`（WP06）：`validate_placement(state: Dictionary, building_def: Dictionary, chunk_id: String, cell: Vector2i) -> AppResult`（占地/占位/相邻锚块规则）；`try_build(state: Dictionary, building_def: Dictionary, chunk_id: String, cell: Vector2i) -> AppResult`（材料足够则一次性 patch：`remove_item*` + `place_building`，任一不足零修改）。
- **房间与电力** `class_name PowerGrid`（WP07）：`find_rooms(buildings: Array) -> Array[Dictionary]`（房间 = 建筑 footprint 的最大 4 连通组，返回 `{"building_ids": Array[String], "cells": Array[Vector2i]}`；`requires_room` 的建筑仅在位于任一房间内时视为有效）；`evaluate(buildings: Array) -> Dictionary`（返回 `{"supply": int, "demand": int, "satisfied": bool, "powered_ids": Array[String], "rooms": Array[Dictionary]}`，供给按 placed_buildings 顺序分配，未获电建筑排除在 powered_ids 外）。
- **叙事** `class_name EventRunner`（WP08）：`load_events_from(dir: String) -> AppResult`；`available_events(events: Array, state: Dictionary) -> Array[String]`；`start_event(event_def: Dictionary) -> Dictionary`（游标状态）；`choose_option(state: Dictionary, event_def: Dictionary, step: Dictionary, option: Dictionary) -> AppResult`（写 flag/effect patch + `complete_event`）。
- **对话 UI 数据**（WP08 提供、WP11 消费）：`DialogueBox.show_lines(lines: Array[Dictionary])` / `signal option_chosen(option_id: String)`。
- **关系** `class_name Relations`（WP09）：`get_dim(state: Dictionary, char_id: String, dim: String) -> int`（缺省 0）；`change(state: Dictionary, char_id: String, dim: String, delta: int, reason: String) -> AppResult`（patch `set_relationship`）；`policy_unlocked(state: Dictionary, policy_id: String) -> bool`（门控表见 §7）。
- **战斗** `class_name CombatEngine`（WP10，纯逻辑无节点）：
  - `create_battle(config: Dictionary) -> Dictionary`（config=encounter 定义展开：`{"allies": [...], "enemies": [...], "seed": int}`；返回完整战斗状态字典，含 `battle_id/turn/seed/units[]/log[]/finished/outcome`）；
  - `submit_action(battle: Dictionary, unit_id: String, action_id: String, target_id: String) -> Dictionary`（**纯函数**：返回新战斗状态，不改入参；含敌方按种子确定性应答；`stability` 归零进入 `destabilized`，跳过一回合且受伤 +50%）；
  - `is_finished(battle: Dictionary) -> bool`；`outcome(battle: Dictionary) -> Dictionary`（`{"result": "victory"|"defeat", "turns": int, "drops": [{"item_id","amount"}]}`）。
  - 3 槽轨道：前/中/后排；同一轨道内先手序 = 速度 desc，平局按单位 id 字典序。沙盒道具（`sedative_mist`/`shock_trap`）作为 item 类行动。
- **遭遇** `class_name EncounterDirector`（WP13）：`check_triggers(state: Dictionary, encounters: Array) -> String`（返回应触发的 encounter id 或 `""`，flag 门控）；`start(encounter_def: Dictionary, content: Dictionary) -> Dictionary`（组装 CombatEngine config； allies 装备沙盒道具）；`finish(state: Dictionary, encounter_def: Dictionary, outcome: Dictionary) -> AppResult`（patch：`record_battle_outcome` + 掉落 `add_item` + `set_flag(on_victory_flag)`）。
- **推进** `class_name Progression`（WP14）：`advance(state: Dictionary, trigger: String) -> AppResult`（按 §7 状态机编排三次选择、世界回应、Boss 条件、结局门控）；`world_response_ops(state: Dictionary, trigger: String) -> Array[Dictionary]`（纯函数：返回应执行的 patch 操作描述）。
- **结局** `class_name Endings`（WP15）：`evaluate(state: Dictionary) -> String`（返回 `ending_mining` / `ending_seal` / `ending_symbiosis` / `""` 未定）。

## 6. 数据文件布局（WP12 拥有数据内容；WP01 拥有 schema 与加载）

```
data/content/items.json            # kind=material|story_core|sandbox_item
data/content/buildings.json        # 6 建筑（含内嵌配方 inputs/recipe）
data/content/combat_units.json     # 盟友 2 + 普通 2 + 精英 1 + Boss 1（两阶段）
data/content/combat_actions.json   # 行动池（含 Boss 行动与道具行动）
data/events/*.json                 # 叙事事件（dialogue/choice/effect 混合步骤）
data/encounters/encounters.json    # 三场遭遇配置
```

## 7. 冻结的游戏内容 ID（跨包引用只能用这些）

- 材料/物品：`starsoil_dust`（星壤尘）、`lumen_shard`（辉砂晶片）、`resonant_core`（共鸣核）、`echo_seed`（余辉之种，剧情核心）、`sedative_mist`（定神雾，沙盒战斗道具）、`shock_trap`（震颤陷阱，沙盒战斗道具）。
- 建筑（6）：`anchor_block`（锚块）、`anchor_workshop`（锚居工坊，power_supply=10）、`dust_refiner`（尘精炼器，power_draw=4，配方 3×starsoil_dust→1×resonant_core）、`stabilizer_pylon`（稳定塔，power_draw=6，effect_flag=`pylon_stabilized`）、`resonance_loom`（共鸣织机，power_draw=5，配方 2×lumen_shard→1×sedative_mist 与 2×lumen_shard+1×resonant_core→1×shock_trap）、`echo_chamber`（回响舱，power_draw=8，requires_room=true，effect_flag=`echo_chamber_active`）。
- 角色：`luoxian`（洛弦）、`misa`（弥砂）；关系维度 `affection/trust/ideology`，flag 形态 `rel_<char>_<dim>` 仅作显示名，数值存 `relationships`。
- 战斗单位：盟友 `luoxian_fighter`（front）、`misa_weaver`（mid）；普通 `drift_swarmling`（front）、`shard_husk`（mid）；精英 `veinwarden_echo`（mid）；Boss `lumen_leviathan`（front，两阶段 `leviathan_p1`/`leviathan_p2`，0.5 血量切换）。
- 遭遇：`encounter_first_drift`（trigger_flag `encounter_first_drift_due`）、`encounter_husk_ambush`（`encounter_husk_ambush_due`）、`encounter_leviathan`（`encounter_leviathan_due`）；胜利 flag `encounter_<id>_won`。
- 三次选择：`station_mode` → 选项 flag `station_mode_exploit` / `station_mode_seal` / `station_mode_symbiosis`；`approach` → `approach_direct` / `approach_diplomatic`；`policy` → `policy_extraction_quota` / `policy_sanctuary`（`policy_sanctuary` 需 Relations.policy_unlocked：trust(luoxian) ≥ 40）。
- 结局门控：`station_mode_exploit` → `ending_mining`；`station_mode_seal` → `ending_seal`；`station_mode_symbiosis` 且 `rel luoxian.trust ≥ 70` 且 `echo_chamber_active` → `ending_symbiosis`，否则回落 `ending_seal`。
- 事件：`event_prologue_landing`、`event_first_mining`、`event_first_anchor`、`event_workshop_guide`、`event_station_mode`、`event_approach`、`event_policy`、`event_leviathan_pact`、`event_ending_luoxian`、`event_ending_misa`；完成标记 `event_<id>_done`（由 `complete_event` 写入 `completed_events`）。
- Chunk：ID 格式 `chunk_<x>_<y>`；切片世界 4×2 个 chunk，每 chunk 32×32 格；初始 chunk `chunk_0_0`；矿脉格由 `world_seed` 确定性生成。

## 8. 验收命令（所有包统一）

```powershell
pwsh -NoProfile -File ./scripts/Run-Gut.ps1            # tests/unit 全套件，退出码必须 0
pwsh -NoProfile -File ./scripts/Verify-Toolchain.ps1   # 5 道全量门禁，退出码必须 0
```
