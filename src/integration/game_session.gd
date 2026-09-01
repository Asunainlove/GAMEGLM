class_name GameSession
extends Node

## W000-P04 app 层集成编排器（冻结契约 docs/plans/contracts/module-contracts.md）。
##
## 把 WP02-WP15 的模块在 app 层串成可玩闭环：
## - 采集链：player.mine_requested → chunk 解析 → Gathering.apply_mining
##   （tool_tier=2；中间敲击进度为暂态，由本节点按格暂存）→ 耗尽时
##   Progression.react(mined)。
## - 建造链：player.place_requested → BuildingRules.attempt_build（缺省
##   anchor_block，数字键 1-N（N=min(max(6,建筑定义数),9)，DLX-3 泛化）或
##   HUD 建造热键栏可选建筑）→ PowerGrid.evaluate
##   供电门控（新建筑位于 placed_buildings 末尾，供给不足时最先断电；同 id 多
##   实例按计数差判定本次新建实例）→ Progression.react(built, powered)：只有
##   供电的 effect_flag 建筑（stabilizer_pylon/echo_chamber）才置 effect_flag。
##   effect_flag 单调：断电不撤销已置位 flag，仅在新建时按供电判定置位（详见
##   ops/evidence/W001-P05.md）。
## - 精炼链（W002-GAP4）：HUD 背包配方区 → craft_requested → CraftingService.craft
##   （单 patch：remove_item 输入 + add_item 输出，recipe_provider 只暴露已建成
##   且供电建筑的配方）。
## - 道具经济（W002-GAP4）：BattleScene 结束时把盟友实际道具消耗并入 outcome，
##   经 EncounterDirector.finish 的 remove_item 回写库存（victory/defeat 均回写）。
## - 事件链：每帧 tick 检查 Progression.due_event → EventRunner 驱动
##   DialogueBox（line 批量逐行、choice 交由玩家）→ choose_option +
##   apply_effect_step + complete_event；deferred_ops 经
##   Progression.deferred_to_patch 落账，world_response_ops 同 patch 落账，
##   completed_events 经 StatePatch.complete_event 记账。
## - 遭遇链：EncounterDirector.check_triggers → 实例化 battle.tscn 挂模态层
##   → begin_encounter（content 含 unit_defs/action_defs/item_defs/inventory/
##   hp_multiplier=Progression.boss_hp_multiplier）→ encounter_finished →
##   胜利时 Progression.react(encounter_won)；卸载战斗场景，战败保留 due flag。
## - 结局链：Progression.ending_ready 且 due_event 为空且无战斗 → ending.tscn。
## - 引导链（W003-A3 / DLX-3）：首次操作提示经 HUD HintToast 队列展示——开局
##   2s 总提示、首次选中建筑、首次材料不足建造失败、首次进入 authored 地区
##   （region entered flag 置位后，DLX-5）、遭遇触发前由本节点按触发点调用；
##   触发条件与文案读 data/progression/hints.json（_show_hints_for_trigger 按表
##   订阅），首次 O 覆盖层由 HUD 内部触发点读表。一次性标记 hint_<id>_seen 由
##   本节点注入 hud.hint_seen_callback 的回调经 patch 落账（表现层不直接写状态）。
## - 存档链：每次 patch 提交后节流 SaveService.save_slot("auto")；启动时尝试
##   load → restore_snapshot。主菜单手动保存写 "manual" 槽并在 HUD 闪现提示；
##   重新开始先经 GameState.reset_to_initial 归零持久状态（Autoload 或注入
##   store），再经 SaveService.delete_slot 删除 auto/manual 槽全部候选文件，
##   最后重载当前场景（W001-P06 修复 P05 两个缺陷：内存状态残留与镜像命名）。
## - 地区触发链（DLX-5）：矿井入口事件、entered flag、Boss 房检查带与网格尺寸
##   全部外置于 data/world/world_config.json（WorldConfig 装载缓存，坏文件
##   push_error 并兜底 4x2 无地区）。
##
## 表现层约束：本节点绝不直接改持久字典，一切变更经注入 store（契约 §0：
## null → GameState autoload）的各模块 API / patch 提交完成。

signal event_started(event_id: String)
signal encounter_started(encounter_id: String)
signal ending_shown

const TOOL_TIER: int = 2
const DEFAULT_BUILDING_ID: String = "anchor_block"
## DLX-3 热键泛化：常量 BUILDING_HOTBAR_SIZE 退役。热键上限 = 
## min(max(6, 建筑定义数), 9)——下限 6 保持既有布局承诺，上限 9 为备用数字键
## 1-9；新增建筑 = 改数据，第 7 个起自动获得热键（>9 走 HUD 建造热键栏点击）。
const BUILDING_HOTBAR_MIN_SIZE: int = 6
const BUILDING_HOTBAR_MAX_SIZE: int = 9
const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"
const ENDING_SCENE_PATH: String = "res://scenes/ending.tscn"
const DEFAULT_SAVE_SLOT: String = "auto"
const DEFAULT_SAVE_THROTTLE_SECONDS: float = 2.0
const MAX_LINES_PER_BATCH: int = 32
const MANUAL_SAVE_SLOT: String = "manual"
const SAVE_NOTICE_TEXT: String = "已保存"
const SAVE_NOTICE_SECONDS: float = 1.5

## W003-A3 开局总提示（hint_move）的延迟秒数。
const MOVE_HINT_DELAY_SECONDS: float = 2.0

## DLX-5 地区级触发链：入口事件/entered flag/Boss 检查带全部外置于
## world_config.json regions[]（WorldConfig 装载），新增手工地区 = 加一个
## JSON 条目，零代码改动（test_world_dlx5 纯数据扩区测试证明）。
## 事件经既有事件展示路径（start/pump/complete）驱动；entered_flag 与
## encounter_leviathan_due 由事件 effect 步骤经 EventRunner/Progression 既有
## 语义落账。MINE_HINT_TRIGGER 是提示表（hints.json）的触发点键——entered flag
## 置位后的深处提示仍按该触发点订阅，文案与去重由提示表/一次性标记承担。
const MINE_HINT_TRIGGER: String = "mine_entered"
const BOSS_ROOM_CHECKPOINT_REASON: String = "boss_room_enter"

## 契约 §0 注入模式：持久层 store，null → GameState autoload。
var store: Object = null

## 注入点：缺省在 _ready 从场景树解析（app.tscn 的 %World / %DialogueBox /
## %ModalLayer / %Hud 唯一名）。
var world: Node2D = null
var dialogue_box: DialogueBox = null
var modal_layer: CanvasLayer = null
var player: Node = null
var hud: Hud = null

var tool_tier: int = TOOL_TIER
var battle_scene_path: String = BATTLE_SCENE_PATH
var ending_scene_path: String = ENDING_SCENE_PATH
var save_slot: String = DEFAULT_SAVE_SLOT
var save_throttle_seconds: float = DEFAULT_SAVE_THROTTLE_SECONDS
var autosave_enabled: bool = true

## 注入点：重新开始时的场景重载；缺省 get_tree().reload_current_scene()。
## 测试注入 spy 避免重载 GUT 测试场景。
var scene_reloader: Callable = Callable()

## 注入点（W002-GAP3）：位置检查点取玩家所在格（世界格坐标）。缺省从绑定的
## player 节点读 position / CELL_SIZE（玩家节点 position 即世界像素坐标）。
var player_cell_provider: Callable = Callable()

## 注入点（DLX-3）：建筑 id 目录来源，缺省 ContentDB.ids_of("building")。
## 热键范围与放置提示的"数字键 1-N"据此派生；测试可注入扩充目录替身。
var building_ids_provider: Callable = Callable()

## 当前选中建筑（建造链缺省 anchor_block）。
var selected_building_id: String = DEFAULT_BUILDING_ID

## effect_flag 单调巡检最近结果（只读观察用）：当前断电的 effect_flag 建筑 id。
var unpowered_effect_flags: Array[String] = []

## 事件链运行态（只读观察用）。
var active_event_id: String = ""
var battle: BattleScene = null
var ending: Node = null

var event_runner: EventRunner = EventRunner.new()
var building_rules: BuildingRules = BuildingRules.new()

var _active_event_def: Dictionary = {}
var _active_step_index: int = 0
var _active_choice_step: Dictionary = {}
var _mining_progress: Dictionary = {}
var _cached_encounters: Array = []
var _last_save_msec: int = -1_000_000_000

## W003-A3 开局总提示延迟计时器（one_shot，仅注入 HUD 时创建）。
var _move_hint_timer: Timer = null


func _ready() -> void:
	_ensure_content_bootstrapped()
	# DLX-2：显式引导外置事件链（幂等；失败已由 Progression push_error，
	# due_event 会失败安全返回空串）。
	var chain_result: AppResult = Progression.bootstrap()
	if not chain_result.is_ok:
		push_warning("GameSession: progression chain unavailable: %s" % chain_result.message)
	_resolve_nodes()
	_bind_player()
	_bind_hud()
	_try_load_autosave()
	_reconcile_effect_flags()
	_start_move_hint_timer()


func _process(_delta: float) -> void:
	tick()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if index < 0 or index >= _building_hotbar_size():
		return
	var ids := _building_ids()
	if index < ids.size():
		select_building(ids[index])


## DLX-3 建筑目录来源：注入 provider 优先，缺省 ContentDB 全集（防御归一为
## String 数组，坏结果安全回退）。
func _building_ids() -> Array[String]:
	if building_ids_provider.is_valid():
		var provided: Variant = building_ids_provider.call()
		if provided is Array:
			var ids: Array[String] = []
			for value: Variant in provided:
				ids.append(str(value))
			return ids
		push_warning("GameSession.building_ids_provider returned %s, expected Array." % type_string(typeof(provided)))
	return ContentDB.ids_of("building")


## 热键上限：min(max(6, 建筑定义数), 9)（DLX-3 泛化，纯函数便于边界断言）。
static func hotbar_size_for(building_count: int) -> int:
	return mini(maxi(BUILDING_HOTBAR_MIN_SIZE, building_count), BUILDING_HOTBAR_MAX_SIZE)


func _building_hotbar_size() -> int:
	return hotbar_size_for(_building_ids().size())


# ---------------------------------------------------------------- 编排主循环


## 每帧（或测试手动）推进一条链路：位置检查点优先，其次事件（地区入口事件
## 按位置触发，优先级高于 due_event 链——入口台词应在踏进地区的第一时间呈现，
## 拖到 due 链之后会让玩家深入地区后才听到入口对话），再次遭遇，最后结局。
func tick() -> void:
	if not ContentDB.is_bootstrapped():
		return
	if active_event_id != "" or battle != null or ending != null:
		return
	var state := _snapshot()
	_record_boss_room_checkpoints()
	_show_mine_hints_if_due(state)
	if dialogue_box != null:
		var region_event_id := _region_entry_event_due(state)
		if region_event_id != "":
			_start_event(region_event_id)
			return
		# DLX-2：event_envoy_trust（DLX-1 tick 过渡钩子）已并入外置事件链
		# （data/progression/event_chain.json 链首条目），经 due_event 统一触发。
		var event_id := Progression.due_event(state)
		if event_id != "":
			_start_event(event_id)
			return
	var encounter_id := EncounterDirector.check_triggers(state, _encounter_defs())
	if encounter_id != "":
		# W003-A3：首次遭遇触发前先弹战斗提示（一次性）。
		# DLX-3：触发条件与文案读提示表（encounter_start 触发点）。
		_show_hints_for_trigger(state, "encounter_start")
		_start_encounter(encounter_id)
		return
	if Progression.ending_ready(state):
		_show_ending()


## DLX-5 Boss 房检查点（W002-GAP2 泛化）：遍历 world_config regions[]，玩家格
## 进入某地区声明带（chunk 本地 y >= boss_checkpoint_min_local_y）时调用既有
## set_player_position 检查点。幂等性由 patch 通道保证：同 revision 同 source
## 的重复提交经 GameState already_applied 短路，不产生额外持久变化。chunk 之间
## 互不重叠（装载期拒绝重复 chunk_id），一次 tick 至多命中一个地区。
func _record_boss_room_checkpoints() -> void:
	var cell := _player_cell()
	for region: Dictionary in WorldConfig.regions():
		if not region.has("boss_checkpoint_min_local_y"):
			continue
		var origin := ChunkData.chunk_origin(str(region.get("chunk_id", "")))
		var min_local_y := int(region.get("boss_checkpoint_min_local_y", 0))
		if cell.x < origin.x or cell.x >= origin.x + ChunkData.CHUNK_SIZE:
			continue
		if cell.y < origin.y + min_local_y or cell.y >= origin.y + ChunkData.CHUNK_SIZE:
			continue
		_checkpoint_player_position(BOSS_ROOM_CHECKPOINT_REASON)


## DLX-5 地区入口判定（W002-GAP2 泛化）：按 regions[] 声明顺序返回第一个满足
## 条件的入口事件 id（均不满足返回 ""）。条件与迁移前逐条一致：entered flag /
## 事件 done 均未置位、事件定义存在、玩家格位于该地区 chunk 内。不走
## Progression.due_event 链的原因不变：due_event 为 src/progression 冻结静态链
## （本包禁改），地区入口是位置触发事件，由本节点自检后走与 due 事件完全相同
## 的展示路径（_start_event → 步骤泵 → complete_event + completed_events 记账），
## 持久语义无差别。
func _region_entry_event_due(state: Dictionary) -> String:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	var cell := _player_cell()
	for region: Dictionary in WorldConfig.regions():
		var entry: Dictionary = region.get("entry", {}) as Dictionary
		var event_id := str(entry.get("event_id", ""))
		var entered_flag := str(entry.get("entered_flag", ""))
		if event_id.is_empty() or entered_flag.is_empty():
			continue
		if bool(flags.get(entered_flag, false)):
			continue
		if bool(flags.get(EventRunner.EVENT_DONE_FLAG_FORMAT % event_id, false)):
			continue
		if ContentDB.get_event(event_id).is_empty():
			continue
		if _is_in_region_chunk(cell, str(region.get("chunk_id", ""))):
			return event_id
	return ""


## 玩家格是否位于指定 chunk（世界格矩形）内。
func _is_in_region_chunk(cell: Vector2i, chunk_id: String) -> bool:
	var origin := ChunkData.chunk_origin(chunk_id)
	return (
		cell.x >= origin.x
		and cell.x < origin.x + ChunkData.CHUNK_SIZE
		and cell.y >= origin.y
		and cell.y < origin.y + ChunkData.CHUNK_SIZE
	)


# ---------------------------------------------------------------- 采集链


## 一次采集请求：解析 chunk → Gathering.apply_mining（带暂态硬度进度）→
## 耗尽时 Progression.react(mined)。
func request_mine(cell: Vector2i) -> AppResult:
	var chunk_id := _resolve_chunk_id(cell)
	var cell_def := _cell_def_for(chunk_id, cell)
	if cell_def.is_empty():
		return AppResult.failure("missing_world", "GameSession has no world to resolve cell definitions.")

	var progress_key := "%s|%d|%d" % [chunk_id, cell.x, cell.y]
	var effective_def := cell_def
	var hardness_total := int(cell_def.get("hardness", 0))
	if _mining_progress.has(progress_key) and int(_mining_progress[progress_key]) < hardness_total:
		effective_def = cell_def.duplicate()
		effective_def["hardness"] = int(_mining_progress[progress_key])

	var strike := Gathering.mining_result(effective_def, tool_tier)
	var result := Gathering.apply_mining(_snapshot(), chunk_id, cell, effective_def, tool_tier, store)
	if not result.is_ok:
		return result

	if bool(strike.get("depleted", false)):
		_mining_progress.erase(progress_key)
		var react_result := Progression.react(_snapshot(), "mined", {}, store)
		if not react_result.is_ok:
			push_warning("GameSession: Progression.react(mined) failed: %s" % react_result.message)
		_schedule_autosave()
	else:
		_mining_progress[progress_key] = int(strike.get("hardness_left", 0))
	return result


# ---------------------------------------------------------------- 建造链


## 一次放置请求：BuildingRules.attempt_build（含地形/邻接/材料校验，零修改
## 失败）→ PowerGrid.evaluate 供电门控 → Progression.react(built, powered)。
func request_place(cell: Vector2i) -> AppResult:
	var building_def := _selected_building_def()
	if building_def.is_empty():
		return AppResult.failure(
			"invalid_building",
			"Selected building id '%s' has no definition." % selected_building_id
		)
	var chunk_id := _resolve_chunk_id(cell)
	# W002-GAP2：手工矿井岩壁不可建（BuildingRules 地形缝只认 destroyed 标记，
	# rock_wall 的不可建语义在 app 层落刀——零修改失败，不产生任何持久变化）。
	if _is_rock_wall_cell(chunk_id, cell):
		return AppResult.failure(
			"rock_wall_cell",
			"Cell (%d, %d) in %s is authored rock_wall and cannot host buildings."
				% [cell.x, cell.y, chunk_id]
		)
	var result := building_rules.attempt_build(_snapshot(), building_def, chunk_id, cell, store)
	if not result.is_ok:
		# W003-A3：首次材料不足建造失败时引导去背包配方区合成；其他失败原因不提示。
		# DLX-3：触发条件与文案读提示表（craft_failed 触发点）。
		if result.code == "insufficient_item":
			_show_hints_for_trigger(_snapshot(), "craft_failed")
		return result
	var react_result := Progression.react(
		_snapshot(), "built",
		{
			"building_id": selected_building_id,
			"powered": _new_building_powered(selected_building_id),
			# DLX-3：建造反应通用规则的权威输入——选中建筑定义携带
			# place_flag / place_flag_powered / effect_flag。
			"building_def": building_def,
		},
		store)
	if not react_result.is_ok:
		push_warning("GameSession: Progression.react(built) failed: %s" % react_result.message)
	_reconcile_effect_flags()
	_schedule_autosave()
	return result


## 建造链供电门控：对建造后的全量 placed_buildings 评估 PowerGrid，判定本次
## 新建建筑（GameState._apply_place_building 保证追加在数组末尾）是否获电。
## 同 id 多实例时不能直接 `powered_ids.has(building_id)`——旧实例获电会掩盖新
## 实例断电；改用计数差判定：新建筑加入前后该 id 在 powered_ids 中的出现次数
## 只增不减（供给按输入序分配，尾部追加不会改变前缀分配），增量 > 0 当且仅当
## 本次新建实例获电。注意：power_draw == 0 的建筑按 PowerGrid 契约不会进入
## powered_ids（无需用电），而 Progression 只对 power_draw > 0 的 effect_flag
## 建筑（stabilizer_pylon/echo_chamber）检查 powered，语义自洽。
func _new_building_powered(building_id: String) -> bool:
	var snapshot := _snapshot()
	var buildings: Array = snapshot.get("placed_buildings", [])
	var post_count := _count_powered_instances(buildings, building_id)
	var pre_buildings := buildings.duplicate()
	if pre_buildings.is_empty():
		return false
	pre_buildings.pop_back()
	return post_count > _count_powered_instances(pre_buildings, building_id)


## PowerGrid.evaluate 结果中某建筑 id 的获电实例数。
func _count_powered_instances(buildings: Array, building_id: String) -> int:
	var evaluation := PowerGrid.evaluate(buildings, _building_power_defs())
	var powered_ids: Array = evaluation.get("powered_ids", [])
	return powered_ids.count(building_id)


## 从 ContentDB 全集构造 PowerGrid.evaluate 所需的 defs：
## building_id → {"power_draw", "power_supply", "requires_room"}。
func _building_power_defs() -> Dictionary:
	var defs := {}
	if not ContentDB.is_bootstrapped():
		return defs
	for building_id: String in ContentDB.ids_of("building"):
		var definition := ContentDB.get_building(building_id)
		defs[building_id] = {
			"power_draw": int(definition.get("power_draw", 0)),
			"power_supply": int(definition.get("power_supply", 0)),
			"requires_room": bool(definition.get("requires_room", false)),
		}
	return defs


## effect_flag 单调一致性巡检：_ready（读档后）与每次建造后各执行一次。
## 策略为单调保持——当前断电而 flag 已置位的建筑**不主动撤销**（撤销语义超出
## 本包冻结范围，见 ops/evidence/W001-P05.md 限制记录）；flag 置位只发生在
## 新建时按供电判定。本巡检仅把存在断电实例的 effect_flag 建筑记录到
## unpowered_effect_flags 供表现层与测试只读观察。判定按 id 计数比较（该 id
## 的 placed 实例数 > powered_ids 中的获电数 ⇒ 存在断电实例），避免同 id 旧
## 实例获电掩盖新实例断电。
func _reconcile_effect_flags() -> void:
	unpowered_effect_flags.clear()
	if not ContentDB.is_bootstrapped():
		return
	var snapshot := _snapshot()
	var buildings: Array = snapshot.get("placed_buildings", [])
	var evaluation := PowerGrid.evaluate(buildings, _building_power_defs())
	var powered_ids: Array = evaluation.get("powered_ids", [])
	var entry_totals: Dictionary = {}
	for building_value: Variant in buildings:
		var entry := building_value as Dictionary
		if entry == null:
			continue
		var entry_id := str(entry.get("building_id", ""))
		entry_totals[entry_id] = int(entry_totals.get(entry_id, 0)) + 1
	for building_value: Variant in buildings:
		var placed := building_value as Dictionary
		if placed == null:
			continue
		var building_id := str(placed.get("building_id", ""))
		if building_id.is_empty() or unpowered_effect_flags.has(building_id):
			continue
		var definition := ContentDB.get_building(building_id)
		if int(definition.get("power_draw", 0)) <= 0:
			continue
		if not str(definition.get("effect_flag", "")).is_empty():
			var powered_count := powered_ids.count(building_id)
			if powered_count < int(entry_totals.get(building_id, 0)):
				unpowered_effect_flags.append(building_id)


## 选择待放置建筑；定义不存在时保持原选择并返回 false。
func select_building(building_id: String) -> bool:
	if not ContentDB.is_bootstrapped():
		return false
	if ContentDB.get_building(building_id).is_empty():
		return false
	selected_building_id = building_id
	# W003-A3：首次选中建筑提示放置方式与数字键切换。DLX-3：触发条件与文案读
	# 提示表（built 触发点，built:* 通配任意建筑）；模板 {building} 按建筑中文名、
	# {hotkey_max} 按实际热键数展开（6 建筑场景输出与迁移前逐字节一致）。
	_show_hints_for_trigger(_snapshot(), "built", {
		"building_id": building_id,
		"building": str(ContentDB.get_building(building_id).get("name_zh", building_id)),
		"hotkey_max": str(_building_hotbar_size()),
	})
	return true


# ---------------------------------------------------------------- 精炼闭环（W002-GAP4）


## 当前可用配方（表现层 provider）：仅已建成且供电的配方建筑展开，
## 并附带 craftable 判定供 HUD 置灰。返回元素形如
## {building_id, recipe, craftable}。
func recipe_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not ContentDB.is_bootstrapped():
		return entries
	var state := _snapshot()
	var defs := {}
	for building_id: String in ContentDB.ids_of("building"):
		defs[building_id] = ContentDB.get_building(building_id)
	var powered: Array[String] = []
	var evaluation := PowerGrid.evaluate(state.get("placed_buildings", []), _building_power_defs())
	for powered_value: Variant in evaluation.get("powered_ids", []):
		powered.append(str(powered_value))
	for entry: Dictionary in CraftingService.available_recipes(state, defs, powered):
		entry["craftable"] = CraftingService.can_craft(state, entry["recipe"])
		entries.append(entry)
	return entries


## HUD"合成"回调：经 CraftingService 原子提交一次精炼；失败仅告警（玩家可重试），
## 成功后节流自动存档（revision 变化会驱动 HUD 轮询刷新背包与配方区）。
func _on_craft_requested(building_id: String, recipe: Dictionary) -> void:
	var result := CraftingService.craft(_snapshot(), building_id, recipe, store)
	if not result.is_ok:
		push_warning("GameSession: craft rejected: %s" % result.message)
		return
	_schedule_autosave()


# ---------------------------------------------------------------- 建造热键栏（W002-GAP4）


## BuildBar 目录：building_id → {name_zh, cost_text, affordable}。affordable 按
## 当前背包库存与建筑 inputs 判定；成本文案由集成层组装（HUD 不读 ContentDB）。
func _build_catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	if not ContentDB.is_bootstrapped():
		return catalog
	var inventory: Dictionary = _snapshot().get("inventory", {})
	for building_id: String in ContentDB.ids_of("building"):
		var definition := ContentDB.get_building(building_id)
		var cost_parts: Array[String] = []
		var affordable := true
		for input_value: Variant in definition.get("inputs", []):
			var input := input_value as Dictionary
			if input == null:
				continue
			var item_id := str(input.get("item_id", ""))
			var count := int(input.get("count", 0))
			cost_parts.append("%s×%d" % [str(ContentDB.get_item(item_id).get("name_zh", item_id)), count])
			if int(inventory.get(item_id, 0)) < count:
				affordable = false
		catalog.append({
			"building_id": building_id,
			"name_zh": str(definition.get("name_zh", building_id)),
			"cost_text": " ".join(cost_parts),
			"affordable": affordable,
		})
	return catalog


## BuildBar 选中态 provider。
func _current_building_selection() -> String:
	return selected_building_id


## 存在断电实例的耗电建筑 id 列表（BuildBar 小红点判定）：按 id 计数比较
## （placed 实例数 > powered_ids 获电数 ⇒ 有实例断电），与 effect_flag 巡检
## 同一口径，但覆盖全部 power_draw > 0 的建筑。
func unpowered_building_ids() -> Array[String]:
	var result: Array[String] = []
	if not ContentDB.is_bootstrapped():
		return result
	var snapshot := _snapshot()
	var buildings: Array = snapshot.get("placed_buildings", [])
	var evaluation := PowerGrid.evaluate(buildings, _building_power_defs())
	var powered_ids: Array = evaluation.get("powered_ids", [])
	var entry_totals: Dictionary = {}
	for building_value: Variant in buildings:
		var entry := building_value as Dictionary
		if entry == null:
			continue
		var entry_id := str(entry.get("building_id", ""))
		entry_totals[entry_id] = int(entry_totals.get(entry_id, 0)) + 1
	for building_value: Variant in buildings:
		var placed := building_value as Dictionary
		if placed == null:
			continue
		var building_id := str(placed.get("building_id", ""))
		if building_id.is_empty() or result.has(building_id):
			continue
		if int(ContentDB.get_building(building_id).get("power_draw", 0)) <= 0:
			continue
		if powered_ids.count(building_id) < int(entry_totals.get(building_id, 0)):
			result.append(building_id)
	return result


## BuildBar 槽位点击：走既有 select_building（定义缺失保持原选择）。
func _on_build_bar_selected(building_id: String) -> void:
	if not select_building(building_id):
		push_warning("GameSession: build bar selected unknown building '%s'." % building_id)


# ---------------------------------------------------------------- 存档链


## 立即保存当前快照到 save_slot。存档前执行位置检查点（W002-GAP3：存档前
## 玩家所在格必须已落账，读档才能恢复到离开时的位置）。
func save_now() -> AppResult:
	_checkpoint_player_position("save")
	return SaveService.save_slot(save_slot, _snapshot())


## 启动/恢复入口：尝试读取 save_slot 并 restore 进 store（仅新鲜状态可收）。
func try_load_autosave() -> bool:
	return _try_load_autosave()


# ---------------------------------------------------------------- 主菜单保存与重启链


## 主菜单"保存"：存档前位置检查点（W002-GAP3），立即写 manual 槽，成功后在
## HUD 闪现短暂提示。
func _on_save_requested() -> void:
	_checkpoint_player_position("manual_save")
	var result := SaveService.save_slot(MANUAL_SAVE_SLOT, _snapshot())
	if not result.is_ok:
		push_warning("GameSession: manual save failed: %s" % result.message)
		return
	if hud != null:
		hud.flash_notice(SAVE_NOTICE_TEXT, SAVE_NOTICE_SECONDS)


## 主菜单"重新开始"（W001-P06 修复 P05 两个缺陷）：
## 1. 先经 GameState.reset_to_initial 归零持久状态——reload_current_scene 不重置
##    Autoload，缺失此步会残留旧内存进度（P05 evidence "重启语义"限制）。
## 2. 再经 SaveService.delete_slot 删除 auto/manual 槽全部候选文件——复用
##    SaveService._slot_paths 同一私有路径构造，消除 P05 的镜像命名逻辑。
## 重启后无档，GameSession._ready 的读档逻辑天然兼容（读档失败即初始状态）。
func _on_restart_requested() -> void:
	_reset_persistent_state()
	_delete_save_slots()
	_reload_current_scene()


## 将持久层（注入 store 优先，否则 GameState autoload）归零为全新初始态。
## 与 _try_load_autosave 的目标解析保持同一注入契约。
func _reset_persistent_state() -> void:
	var target: Object = store
	if target == null:
		target = GameState
	target.call("reset_to_initial")


## 删除 auto/manual 槽全部候选文件（primary/tmp/backup），统一走
## SaveService.delete_slot；失败仅告警，不阻断场景重载。
func _delete_save_slots() -> void:
	for slot: String in [save_slot, MANUAL_SAVE_SLOT]:
		var result := SaveService.delete_slot(slot)
		if not result.is_ok:
			push_warning(
				"GameSession: failed to delete save slot '%s': %s" % [slot, result.message]
			)


func _reload_current_scene() -> void:
	if scene_reloader.is_valid():
		scene_reloader.call()
		return
	if get_tree() != null:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- 事件链内部


func _start_event(event_id: String) -> void:
	var event_def := ContentDB.get_event(event_id)
	if event_def.is_empty():
		push_warning("GameSession: due event '%s' has no definition." % event_id)
		return
	active_event_id = event_id
	_active_event_def = event_def
	_active_step_index = 0
	_active_choice_step = {}
	event_started.emit(event_id)
	_pump_event_step()


## 步骤泵：line 批量交给 DialogueBox 逐行播放；choice 交给玩家；
## effect 立即落账；步骤耗尽即完成事件。
func _pump_event_step() -> void:
	while active_event_id != "":
		var step := EventRunner.next_step(_active_event_def, _active_step_index)
		if step.is_empty():
			_finish_active_event()
			return
		match String(step.get("type", "")):
			"line":
				var lines: Array[Dictionary] = []
				while lines.size() < MAX_LINES_PER_BATCH:
					var line := EventRunner.next_step(_active_event_def, _active_step_index)
					if line.is_empty() or String(line.get("type", "")) != "line":
						break
					lines.append(line)
					_active_step_index += 1
				dialogue_box.show_lines(lines)
				return
			"choice":
				_active_choice_step = step
				# W002-GAP1 软锁死修复：展示前对 requires_trust 选项做预检，
				# 不足者传为禁用态，玩家从入口上就点不开会被拒绝的选项。
				dialogue_box.show_choice(step, _trust_locked_option_ids(step, _snapshot()))
				return
			"effect":
				var result := event_runner.apply_effect_step(active_event_id, step, store)
				if not result.is_ok:
					push_warning("GameSession: effect step failed: %s" % result.message)
				elif result.value is Dictionary:
					# W002-GAP1：effect 步骤的 relation_delta 沿 deferred_ops 通道
					# 返回，经独立 integration patch 落账（与 choice 通道同构）。
					_commit_deferred_relationship_ops(
						"event_%s_effect" % active_event_id,
						(result.value as Dictionary).get("deferred_ops", [])
					)
				_active_step_index += 1
			_:
				_active_step_index += 1


func _on_dialogue_finished() -> void:
	if active_event_id == "":
		return
	_pump_event_step()


func _on_option_chosen(option_id: String) -> void:
	if active_event_id == "" or _active_choice_step.is_empty():
		return
	var step := _active_choice_step
	_active_choice_step = {}
	var option := _find_option(step, option_id)
	if option.is_empty():
		push_warning("GameSession: unknown option '%s' for event %s." % [option_id, active_event_id])
		return
	var state := _snapshot()
	var result := event_runner.choose_option(state, _active_event_def, step, option, store)
	if not result.is_ok:
		push_warning("GameSession: option '%s' rejected: %s" % [option_id, result.message])
		# W002-GAP1 软锁死修复：拒绝只弹回选项（带最新禁用态），事件不得停摆。
		_active_choice_step = step
		if dialogue_box != null:
			dialogue_box.show_choice(step, _trust_locked_option_ids(step, state))
		return
	var deferred_ops: Array = []
	if result.value is Dictionary:
		deferred_ops = (result.value as Dictionary).get("deferred_ops", [])
	var patch: Variant = _begin_integration_patch("event_%s_choice_%s" % [active_event_id, option_id])
	if patch != null:
		Progression.deferred_to_patch(deferred_ops, patch)
		for op: Dictionary in Progression.world_response_ops(state, option_id):
			patch.set_flag(String(op.get("flag_id", "")), bool(op.get("enabled", true)))
		_commit_integration_patch(patch)
	# W002-GAP1：政策选项提交后发出 policy_chosen 信号，命中 Boss 门控
	# （两场胜利 + policy_* flag）时置 encounter_leviathan_due——否则正常流程
	# 中伏击胜利先于政策选择，Boss 遭遇永不到期，结局链死锁。
	if String(option.get("set_flag", "")).begins_with(Progression.POLICY_PREFIX):
		var policy_result := Progression.react(
			_snapshot(), "policy_chosen", {"policy_id": option_id}, store
		)
		if not policy_result.is_ok:
			push_warning("GameSession: policy_chosen react failed: %s" % policy_result.message)
	_active_step_index += 1
	_pump_event_step()


## 把 EventRunner 返回的 deferred relationship ops 落进独立 integration patch。
func _commit_deferred_relationship_ops(source_suffix: String, deferred_ops: Array) -> void:
	if deferred_ops.is_empty():
		return
	var patch: Variant = _begin_integration_patch(source_suffix)
	if patch == null:
		return
	Progression.deferred_to_patch(deferred_ops, patch)
	_commit_integration_patch(patch)


## trust 预检（W002-GAP1 / DLX-1）：requires_trust 未达标（含对象形态
## {char_id, dim, value}）的选项 id 列表，交给 DialogueBox 呈禁用态。
## 判定单一来源为 EventRunner.option_meets_trust——与 choose_option 的门控
## 同一实现，消除预检与判定的双实现漂移。
func _trust_locked_option_ids(step: Dictionary, state: Dictionary) -> Array[String]:
	var locked: Array[String] = []
	for option_variant: Variant in step.get("options", []):
		var option := option_variant as Dictionary
		if option == null:
			continue
		if not EventRunner.option_meets_trust(state, option):
			locked.append(String(option.get("id", "")))
	return locked


func _finish_active_event() -> void:
	var event_id := active_event_id
	active_event_id = ""
	_active_event_def = {}
	_active_step_index = 0
	_active_choice_step = {}
	if dialogue_box != null:
		dialogue_box.visible = false
	var complete_result := event_runner.complete_event(event_id, store)
	if not complete_result.is_ok:
		push_warning("GameSession: complete_event(%s) failed: %s" % [event_id, complete_result.message])
	var record_patch: Variant = _begin_integration_patch("event_%s_record" % event_id)
	if record_patch != null:
		record_patch.complete_event(event_id)
		_commit_integration_patch(record_patch)
	var react_result := Progression.react(_snapshot(), "event_completed", {"event_id": event_id}, store)
	if not react_result.is_ok:
		push_warning("GameSession: Progression.react(event_completed) failed: %s" % react_result.message)
	_checkpoint_player_position("event_complete")
	_schedule_autosave()


# ---------------------------------------------------------------- 遭遇链内部


func _start_encounter(encounter_id: String) -> void:
	var encounter_def := ContentDB.get_encounter(encounter_id)
	if encounter_def.is_empty():
		push_warning("GameSession: due encounter '%s' has no definition." % encounter_id)
		return
	if battle_scene_path == "" or not ResourceLoader.exists(battle_scene_path):
		push_warning("GameSession: battle scene '%s' missing; encounter skipped." % battle_scene_path)
		return
	var packed := load(battle_scene_path) as PackedScene
	var battle_node := packed.instantiate() as BattleScene
	if battle_node == null:
		push_warning("GameSession: battle scene '%s' did not instantiate a BattleScene." % battle_scene_path)
		return
	battle_node.store = store
	battle = battle_node
	battle_node.encounter_finished.connect(_on_encounter_finished)
	_modal_host().add_child(battle_node)
	encounter_started.emit(encounter_id)
	battle_node.begin_encounter(encounter_def, _battle_content())
	_checkpoint_player_position("battle_start")


func _battle_content() -> Dictionary:
	var state := _snapshot()
	var unit_defs := {}
	var action_defs := {}
	var item_defs := {}
	var unit_ids: Array[String] = ContentDB.ids_of("combat_unit")
	for unit_id: String in unit_ids:
		unit_defs[unit_id] = ContentDB.get_combat_unit(unit_id)
	var action_ids: Array[String] = ContentDB.ids_of("combat_action")
	for action_id: String in action_ids:
		action_defs[action_id] = ContentDB.get_combat_action(action_id)
	var item_ids: Array[String] = ContentDB.ids_of("item")
	for item_id: String in item_ids:
		item_defs[item_id] = ContentDB.get_item(item_id)
	return {
		"unit_defs": unit_defs,
		"action_defs": action_defs,
		"item_defs": item_defs,
		"inventory": (state.get("inventory", {}) as Dictionary).duplicate(true),
		"hp_multiplier": Progression.boss_hp_multiplier(state),
	}


func _on_encounter_finished(encounter_id: String, outcome: Dictionary) -> void:
	if battle != null:
		battle.queue_free()
		battle = null
	if String(outcome.get("result", "")) == "victory":
		var react_result := Progression.react(_snapshot(), "encounter_won", {"encounter_id": encounter_id}, store)
		if not react_result.is_ok:
			push_warning("GameSession: Progression.react(encounter_won) failed: %s" % react_result.message)
	_checkpoint_player_position("battle_end")
	_schedule_autosave()


# ---------------------------------------------------------------- 结局链内部


func _show_ending() -> void:
	if ending_scene_path == "" or not ResourceLoader.exists(ending_scene_path):
		push_warning("GameSession: ending scene '%s' missing; ending skipped." % ending_scene_path)
		return
	var packed := load(ending_scene_path) as PackedScene
	var ending_node: Node = packed.instantiate()
	if ending_node == null:
		return
	ending = ending_node
	ending_node.set("snapshot_provider", Callable(self, "_snapshot"))
	_modal_host().add_child(ending_node)
	ending_shown.emit()


# ---------------------------------------------------------------- 存档链内部


func _schedule_autosave() -> void:
	if not autosave_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_save_msec < int(save_throttle_seconds * 1000.0):
		return
	_last_save_msec = now
	var result := save_now()
	if not result.is_ok:
		push_warning("GameSession: autosave failed: %s" % result.message)


func _try_load_autosave() -> bool:
	var loaded := SaveService.load_slot(save_slot)
	if not loaded.is_ok:
		return false
	# DLX-6：读档内容政策（docs/save-content-policy.md）——restore 前比对存档
	# content_hash 与当前内容总哈希，mismatch 时声明式孤儿降级清理并告警摘要；
	# restore 成功后把当前 content_hash 经专用 patch op 回写（收敛）。
	var policy_report: Dictionary = _apply_content_policy(loaded.value)
	var target: Object = store
	if target == null:
		target = GameState
	var restore_result: Variant = target.call("restore_snapshot", policy_report["payload"])
	if restore_result is AppResult:
		if (restore_result as AppResult).is_ok:
			_refresh_content_hash_after_load()
			_place_player_from_saved_snapshot(policy_report["payload"])
		return (restore_result as AppResult).is_ok
	return false


## DLX-6 读档内容政策入口：ContentDB 未引导时失败安全跳过（原样载入，不做
## 政策判定）；否则执行三档 sanitize（hash_match 原样 / hash_superset 纯新增
## 接受 / hash_divergent 孤儿降级清理），非 hash_match 输出摘要告警。
func _apply_content_policy(loaded_snapshot: Dictionary) -> Dictionary:
	if not ContentDB.is_bootstrapped():
		return {
			"policy": SaveCodec.POLICY_HASH_MATCH,
			"hash_matches": false,
			"changed": false,
			"payload": loaded_snapshot,
		}
	var report: Dictionary = SaveCodec.sanitize_payload_against_content(
		loaded_snapshot, ContentDB.content_hash(), _content_defs_for_policy()
	)
	var policy := str(report.get("policy", ""))
	if policy != SaveCodec.POLICY_HASH_MATCH:
		push_warning(
			"GameSession: 存档内容政策 '%s'（存档 hash=%s / 当前 hash=%s）：%s" % [
				policy,
				str(loaded_snapshot.get("content_hash", "")),
				ContentDB.content_hash(),
				_policy_report_summary(report),
			]
		)
	return report


## sanitize defs 组装：ContentDB 三类定义快照 + 世界网格 chunk 目录
## （WorldConfig 网格尺寸派生 chunk_X_Y 全集；SaveCodec 不依赖世界模块，
## 由集成层注入）。
func _content_defs_for_policy() -> Dictionary:
	var defs := ContentDB.content_defs_snapshot()
	var grid := WorldConfig.grid_size()
	var chunk_ids: Array[String] = []
	for grid_x: int in grid.x:
		for grid_y: int in grid.y:
			chunk_ids.append("chunk_%d_%d" % [grid_x, grid_y])
	defs["chunk_ids"] = chunk_ids
	return defs


## 清理报告的日志摘要（只列非空类别）。
static func _policy_report_summary(report: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["removed_inventory", "removed_flags", "removed_chunk_deltas", "removed_battle_outcomes"]:
		var removed := report.get(key, []) as Array
		if removed.is_empty():
			continue
		var names: PackedStringArray = PackedStringArray()
		for entry: Variant in removed:
			names.append(str(entry))
		parts.append("%s=[%s]" % [key, ", ".join(names)])
	if parts.is_empty():
		return "无孤儿（接受）"
	return "清理 " + "; ".join(parts)


## DLX-6：读档 restore 成功后的收敛动作——当前 content_hash 与持久状态不一致
## 时经 set_content_hash 专用 op 回写（独立 integration patch，同 revision 同
## source 重放由 already_applied 幂等短路）。一致（含 hash_match 收敛态）时
## 零写入。新开局（无可读档）不触发本路径，初始存档的空 hash 在首次重载时
## 按 superset 接受并收敛（政策文档"已知边界"）。
func _refresh_content_hash_after_load() -> void:
	if not ContentDB.is_bootstrapped():
		return
	var current_hash := ContentDB.content_hash()
	if str(_snapshot().get("content_hash", "")) == current_hash:
		return
	var patch: Variant = _begin_integration_patch("content_hash_refresh")
	if patch == null:
		return
	patch.set_content_hash(current_hash)
	_commit_integration_patch(patch)


## 读档成功后（W002-GAP3）把 world 内玩家节点移到存档格。默认出生点 (0,0)
## 交给 world 的 PlayerSpawn marker 逻辑——初始存档不得把玩家复位到世界原点角。
func _place_player_from_saved_snapshot(loaded_snapshot: Dictionary) -> void:
	if world == null or not world.has_method("place_player_at_cell"):
		return
	var player_state := loaded_snapshot.get("player", {}) as Dictionary
	var position := player_state.get("position", {}) as Dictionary
	if position.is_empty():
		return
	var cell := Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
	if cell == Vector2i.ZERO:
		return
	world.call("place_player_at_cell", cell)


# ---------------------------------------------------------------- 位置检查点链（W002-GAP3）


## 位置检查点：把玩家当前所在格经独立 integration patch 写入 player.position
## （set_player_position，expected_revision 取当前快照 revision）。reason 参与
## source_id；同 revision 同原因的重复提交由 GameState 按 already_applied 幂等
## 处理。取不到玩家格（无 player / provider 结果无效）时静默跳过。
func _checkpoint_player_position(reason: String) -> void:
	var cell := _player_cell()
	if cell.x < 0 or cell.y < 0:
		return
	var patch: Variant = _begin_integration_patch("player_position_%s" % reason)
	if patch == null:
		return
	patch.set_player_position(cell.x, cell.y)
	_commit_integration_patch(patch)


## 玩家所在格（世界格坐标）：注入 player_cell_provider 优先，缺省从绑定的
## player 节点读 position（世界像素坐标）按 CELL_SIZE 取整。
func _player_cell() -> Vector2i:
	if player_cell_provider.is_valid():
		var provided: Variant = player_cell_provider.call()
		if provided is Vector2i:
			return provided
		if provided is Vector2:
			return Vector2i((provided as Vector2).floor())
		push_warning(
			"GameSession.player_cell_provider returned %s, expected Vector2i." % type_string(typeof(provided))
		)
		return Vector2i(-1, -1)
	var player_node := player as Node2D
	if player_node == null:
		return Vector2i(-1, -1)
	return Vector2i((player_node.position / float(ChunkData.CELL_SIZE)).floor())


# ---------------------------------------------------------------- 装配与工具


func _ensure_content_bootstrapped() -> void:
	if ContentDB.is_bootstrapped():
		return
	var result := ContentDB.bootstrap()
	if not result.is_ok:
		push_warning("GameSession: ContentDB bootstrap failed: %s" % result.message)


func _resolve_nodes() -> void:
	if world == null:
		world = get_node_or_null("%World") as Node2D
	if dialogue_box == null:
		dialogue_box = get_node_or_null("%DialogueBox") as DialogueBox
	if modal_layer == null:
		modal_layer = get_node_or_null("%ModalLayer") as CanvasLayer
	if world != null and not building_rules.cell_lookup.is_valid():
		building_rules.cell_lookup = Callable(world, "cell_def_at")
	if dialogue_box != null:
		if not dialogue_box.finished.is_connected(_on_dialogue_finished):
			dialogue_box.finished.connect(_on_dialogue_finished)
		if not dialogue_box.option_chosen.is_connected(_on_option_chosen):
			dialogue_box.option_chosen.connect(_on_option_chosen)


func _bind_player() -> void:
	if player == null:
		player = _find_player()
	if player == null:
		return
	if not player.is_connected("mine_requested", _on_mine_requested):
		player.connect("mine_requested", _on_mine_requested)
	if not player.is_connected("place_requested", _on_place_requested):
		player.connect("place_requested", _on_place_requested)


func _bind_hud() -> void:
	if hud == null:
		hud = get_node_or_null("%Hud") as Hud
	if hud == null:
		return
	if not hud.save_requested.is_connected(_on_save_requested):
		hud.save_requested.connect(_on_save_requested)
	if not hud.restart_requested.is_connected(_on_restart_requested):
		hud.restart_requested.connect(_on_restart_requested)
	# W002-GAP4：建造热键栏与背包配方区的只读 provider + 信号接线。
	hud.build_catalog = _build_catalog
	hud.selected_provider = _current_building_selection
	hud.unpowered_provider = unpowered_building_ids
	hud.recipe_provider = recipe_entries
	# W003-A3：一次性提示落账回调——表现层 show_hint 只上报 hint id，
	# patch 写入由本回调执行。
	hud.hint_seen_callback = _on_hint_seen
	if not hud.build_selected.is_connected(_on_build_bar_selected):
		hud.build_selected.connect(_on_build_bar_selected)
	if not hud.craft_requested.is_connected(_on_craft_requested):
		hud.craft_requested.connect(_on_craft_requested)


func _find_player() -> Node:
	if world == null:
		return null
	var candidates: Array[Node] = world.find_children("*", "", true, false)
	for candidate: Node in candidates:
		if candidate.is_in_group("player"):
			return candidate
	return null


func _modal_host() -> Node:
	if modal_layer != null:
		return modal_layer
	return self


func _encounter_defs() -> Array:
	if _cached_encounters.is_empty():
		var ids: Array[String] = ContentDB.ids_of("encounter")
		for encounter_id: String in ids:
			_cached_encounters.append(ContentDB.get_encounter(encounter_id))
	return _cached_encounters


func _selected_building_def() -> Dictionary:
	if not ContentDB.is_bootstrapped():
		return {}
	return ContentDB.get_building(selected_building_id)


func _resolve_chunk_id(cell: Vector2i) -> String:
	# DLX-5：网格尺寸读 world_config（WorldConfig 兜底 4x2）。
	var grid := WorldConfig.grid_size()
	var grid_x := clampi(floori(float(cell.x) / float(ChunkData.CHUNK_SIZE)), 0, grid.x - 1)
	var grid_y := clampi(floori(float(cell.y) / float(ChunkData.CHUNK_SIZE)), 0, grid.y - 1)
	return "chunk_%d_%d" % [grid_x, grid_y]


func _cell_def_for(chunk_id: String, cell: Vector2i) -> Dictionary:
	if world != null:
		var provided: Variant = world.call("cell_def_at", chunk_id, cell)
		if provided is Dictionary:
			return provided
		return {}
	var generated: Dictionary = ChunkData.generate(chunk_id, int(_snapshot().get("world_seed", 0)))
	return ChunkData.cell_def(generated["cells"], cell)


## W002-GAP2：格子是否为手工矿井岩壁（rock_wall）。world 缺席时按生成结果兜底。
func _is_rock_wall_cell(chunk_id: String, cell: Vector2i) -> bool:
	return str(_cell_def_for(chunk_id, cell).get("type", "")) == "rock_wall"


func _on_mine_requested(cell: Vector2i) -> void:
	var result := request_mine(cell)
	if not result.is_ok:
		push_warning("GameSession: mine request rejected: %s" % result.message)


func _on_place_requested(cell: Vector2i) -> void:
	var result := request_place(cell)
	if not result.is_ok:
		push_warning("GameSession: place request rejected: %s" % result.message)


# ---------------------------------------------------------------- 首次操作引导提示链（W003-A3）


## 开局总提示延迟计时器：_ready 时启动，MOVE_HINT_DELAY_SECONDS 后触发一次。
## 仅在注入了 HUD 时创建；读档带回来的 hint_move_seen 在触发时由 flag 检查拦截。
func _start_move_hint_timer() -> void:
	if hud == null:
		return
	_move_hint_timer = Timer.new()
	_move_hint_timer.name = "MoveHintTimer"
	_move_hint_timer.one_shot = true
	_move_hint_timer.wait_time = MOVE_HINT_DELAY_SECONDS
	_move_hint_timer.timeout.connect(_show_move_hint_if_due)
	add_child(_move_hint_timer)
	_move_hint_timer.start()


## 开局 2s 总提示（WASD/左键/右键/F）。测试直接调本方法驱动（可控 timer 等价物）。
## DLX-3：触发条件与文案读提示表（boot 触发点）。
func _show_move_hint_if_due() -> void:
	_show_hints_for_trigger(_snapshot(), "boot")


## 地区 entered flag 置位后（首次进入任一 authored 地区）的深处提示；tick 每帧
## 检查，开销为 regions 遍历。DLX-3：触发条件与文案读提示表；DLX-5：遍历
## regions[] 的 entered_flag，命中任一即按 MINE_HINT_TRIGGER 触发点订阅（提示
## id 去重保证多地区不重复展示）。
func _show_mine_hints_if_due(state: Dictionary) -> void:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	for region: Dictionary in WorldConfig.regions():
		var entered_flag := str((region.get("entry", {}) as Dictionary).get("entered_flag", ""))
		if not entered_flag.is_empty() and bool(flags.get(entered_flag, false)):
			_show_hints_for_trigger(state, MINE_HINT_TRIGGER)
			return


## DLX-3 通用触发点：按提示表订阅 trigger_point 命中的全部提示，逐条经
## _show_hint_if_due 展示（每条提示由自身 hint_<id>_seen 独立去重落账）。
## text_zh 中的 {token} 占位符按 context 键值做字面替换（如 {building} /
## {hotkey_max}），表内未出现的 token 保持原样。
func _show_hints_for_trigger(
		snapshot: Dictionary, trigger_point: String, context: Dictionary = {}) -> void:
	if hud == null:
		return
	for hint: Dictionary in Hud.hints_for_trigger(trigger_point, String(context.get("building_id", ""))):
		var text_value := String(hint["text_zh"])
		for key: String in context.keys():
			text_value = text_value.replace("{%s}" % key, str(context[key]))
		_show_hint_if_due(snapshot, String(hint["id"]), text_value)


## 通用触发点：HUD 在场且快照 flags 中 hint_<id>_seen 未置位时展示 text。
## 幂等由两层保证：本检查挡住跨会话重复（读档/重开后 flag 已置），HUD 内
## 一次性队列挡住同一会话内的重复触发。
func _show_hint_if_due(snapshot: Dictionary, hint_id: String, text_value: String) -> void:
	if hud == null:
		return
	var flags: Dictionary = snapshot.get("flags", {}) as Dictionary
	if bool(flags.get(Hud.HINT_FLAG_FORMAT % hint_id, false)):
		return
	# DLX-3：按表内稳定 hint id 展示与上报（旧入口 show_hint 以文案哈希派生
	# id，无法与 hint_<id>_seen 对齐）。
	hud.show_hint_with_id(hint_id, text_value)


## hud.hint_seen_callback 的实现（落账通道）：经独立 integration patch 把
## hint_<id>_seen 置位——表现层只回调，绝不直接写持久状态（契约 §0）。
## 回调在提示首次被接受时同步执行，此后 HUD 会话内去重保证同 id 只上报一次。
func _on_hint_seen(hint_id: String) -> void:
	var patch: Variant = _begin_integration_patch("hint_%s_seen" % hint_id)
	if patch == null:
		return
	patch.set_flag(Hud.HINT_FLAG_FORMAT % hint_id, true)
	_commit_integration_patch(patch)
	_schedule_autosave()


func _snapshot() -> Dictionary:
	if store == null:
		return GameState.snapshot()
	var provided: Variant = store.call("snapshot")
	if provided is Dictionary:
		return provided
	return {}


func _begin_integration_patch(suffix: String) -> Variant:
	var revision := int(_snapshot().get("revision", 0))
	var source_id := "integration_%s_%d" % [suffix, revision]
	if store == null:
		return GameState.begin_patch(source_id, revision)
	return store.call("begin_patch", source_id, revision)


func _commit_integration_patch(patch: Variant) -> void:
	var result: Variant
	if store == null:
		result = GameState.commit(patch)
	else:
		result = store.call("commit", patch)
	if result is AppResult and not (result as AppResult).is_ok:
		push_warning("GameSession: integration patch rejected: %s" % (result as AppResult).message)


static func _find_option(step: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {}
	var options: Array = step.get("options", [])
	for option_value: Variant in options:
		if typeof(option_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = option_value
		if String(candidate.get("id", "")) == option_id:
			return candidate.duplicate(true)
	return {}
