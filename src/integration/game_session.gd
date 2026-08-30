class_name GameSession
extends Node

## W000-P04 app 层集成编排器（冻结契约 docs/plans/contracts/module-contracts.md）。
##
## 把 WP02-WP15 的模块在 app 层串成可玩闭环：
## - 采集链：player.mine_requested → chunk 解析 → Gathering.apply_mining
##   （tool_tier=2；中间敲击进度为暂态，由本节点按格暂存）→ 耗尽时
##   Progression.react(mined)。
## - 建造链：player.place_requested → BuildingRules.attempt_build（缺省
##   anchor_block，数字键 1-6 可选建筑）→ PowerGrid.evaluate 供电门控（新建筑
##   位于 placed_buildings 末尾，供给不足时最先断电；同 id 多实例按计数差判定
##   本次新建实例）→ Progression.react(built, powered)：只有供电的 effect_flag
##   建筑（stabilizer_pylon/echo_chamber）才置 effect_flag。effect_flag 单调：
##   断电不撤销已置位 flag，仅在新建时按供电判定置位（详见
##   ops/evidence/W001-P05.md）。
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
## - 存档链：每次 patch 提交后节流 SaveService.save_slot("auto")；启动时尝试
##   load → restore_snapshot。主菜单手动保存写 "manual" 槽并在 HUD 闪现提示；
##   重新开始删除 auto/manual 槽全部候选文件后重载当前场景。
##
## 表现层约束：本节点绝不直接改持久字典，一切变更经注入 store（契约 §0：
## null → GameState autoload）的各模块 API / patch 提交完成。

signal event_started(event_id: String)
signal encounter_started(encounter_id: String)
signal ending_shown

const TOOL_TIER: int = 2
const CHUNK_GRID_WIDTH: int = 4
const CHUNK_GRID_HEIGHT: int = 2
const DEFAULT_BUILDING_ID: String = "anchor_block"
const BUILDING_HOTBAR_SIZE: int = 6
const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"
const ENDING_SCENE_PATH: String = "res://scenes/ending.tscn"
const DEFAULT_SAVE_SLOT: String = "auto"
const DEFAULT_SAVE_THROTTLE_SECONDS: float = 2.0
const MAX_LINES_PER_BATCH: int = 32
const MANUAL_SAVE_SLOT: String = "manual"
const SAVE_NOTICE_TEXT: String = "已保存"
const SAVE_NOTICE_SECONDS: float = 1.5
## 存档槽候选文件后缀，与 SaveService._slot_paths 的命名约定保持镜像
## （SaveService 无删除 API 且 src/save 冻结，见 W001-P05 evidence）。
const SAVE_FILE_SUFFIXES: Array[String] = [".json", ".json.tmp", ".json.bak"]

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

## 存档根（user:// 路径）；空串回退 SaveService.DEFAULT_SAVE_ROOT。测试注入
## 与 SaveService.configure_root_for_tests 相同的路径以断言删档行为。
var save_root: String = ""

## 注入点：重新开始时的场景重载；缺省 get_tree().reload_current_scene()。
## 测试注入 spy 避免重载 GUT 测试场景。
var scene_reloader: Callable = Callable()

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


func _ready() -> void:
	_ensure_content_bootstrapped()
	_resolve_nodes()
	_bind_player()
	_bind_hud()
	_try_load_autosave()
	_reconcile_effect_flags()


func _process(_delta: float) -> void:
	tick()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if index < 0 or index >= BUILDING_HOTBAR_SIZE:
		return
	var ids: Array[String] = ContentDB.ids_of("building")
	if index < ids.size():
		select_building(ids[index])


# ---------------------------------------------------------------- 编排主循环


## 每帧（或测试手动）推进一条链路：事件优先，其次遭遇，最后结局。
func tick() -> void:
	if not ContentDB.is_bootstrapped():
		return
	if active_event_id != "" or battle != null or ending != null:
		return
	var state := _snapshot()
	if dialogue_box != null:
		var event_id := Progression.due_event(state)
		if event_id != "":
			_start_event(event_id)
			return
	var encounter_id := EncounterDirector.check_triggers(state, _encounter_defs())
	if encounter_id != "":
		_start_encounter(encounter_id)
		return
	if Progression.ending_ready(state):
		_show_ending()


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
	var result := building_rules.attempt_build(_snapshot(), building_def, chunk_id, cell, store)
	if not result.is_ok:
		return result
	var react_result := Progression.react(
		_snapshot(), "built",
		{"building_id": selected_building_id, "powered": _new_building_powered(selected_building_id)},
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
	return true


# ---------------------------------------------------------------- 存档链


## 立即保存当前快照到 save_slot。
func save_now() -> AppResult:
	return SaveService.save_slot(save_slot, _snapshot())


## 启动/恢复入口：尝试读取 save_slot 并 restore 进 store（仅新鲜状态可收）。
func try_load_autosave() -> bool:
	return _try_load_autosave()


# ---------------------------------------------------------------- 主菜单保存与重启链


## 主菜单"保存"：立即写 manual 槽，成功后在 HUD 闪现短暂提示。
func _on_save_requested() -> void:
	var result := SaveService.save_slot(MANUAL_SAVE_SLOT, _snapshot())
	if not result.is_ok:
		push_warning("GameSession: manual save failed: %s" % result.message)
		return
	if hud != null:
		hud.flash_notice(SAVE_NOTICE_TEXT, SAVE_NOTICE_SECONDS)


## 主菜单"重新开始"：删除 auto/manual 槽全部候选文件后重载当前场景。
## 重启后无档，GameSession._ready 的读档逻辑天然兼容（读档失败即初始状态）。
func _on_restart_requested() -> void:
	_delete_save_slots()
	_reload_current_scene()


## 删除存档槽候选文件（primary/tmp/backup）。文件命名与 SaveService._slot_paths
## 保持镜像；SaveService 无删除 API 且 src/save 冻结（W001-P05 evidence 记录）。
func _delete_save_slots() -> void:
	var root := save_root
	if root.is_empty():
		root = SaveService.DEFAULT_SAVE_ROOT
	var directory := DirAccess.open(root)
	if directory == null:
		push_warning("GameSession: cannot open save root '%s' for deletion." % root)
		return
	for slot: String in [save_slot, MANUAL_SAVE_SLOT]:
		for suffix: String in SAVE_FILE_SUFFIXES:
			var file_name := slot + suffix
			if directory.file_exists(file_name) and directory.remove(file_name) != OK:
				push_warning("GameSession: failed to remove save file '%s'." % file_name)


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
				dialogue_box.show_choice(step)
				return
			"effect":
				var result := event_runner.apply_effect_step(active_event_id, step, store)
				if not result.is_ok:
					push_warning("GameSession: effect step failed: %s" % result.message)
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
	_active_step_index += 1
	_pump_event_step()


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
	var target: Object = store
	if target == null:
		target = GameState
	var restore_result: Variant = target.call("restore_snapshot", loaded.value)
	if restore_result is AppResult:
		return (restore_result as AppResult).is_ok
	return false


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
	var grid_x := clampi(floori(float(cell.x) / float(ChunkData.CHUNK_SIZE)), 0, CHUNK_GRID_WIDTH - 1)
	var grid_y := clampi(floori(float(cell.y) / float(ChunkData.CHUNK_SIZE)), 0, CHUNK_GRID_HEIGHT - 1)
	return "chunk_%d_%d" % [grid_x, grid_y]


func _cell_def_for(chunk_id: String, cell: Vector2i) -> Dictionary:
	if world != null:
		var provided: Variant = world.call("cell_def_at", chunk_id, cell)
		if provided is Dictionary:
			return provided
		return {}
	var generated: Dictionary = ChunkData.generate(chunk_id, int(_snapshot().get("world_seed", 0)))
	return ChunkData.cell_def(generated["cells"], cell)


func _on_mine_requested(cell: Vector2i) -> void:
	var result := request_mine(cell)
	if not result.is_ok:
		push_warning("GameSession: mine request rejected: %s" % result.message)


func _on_place_requested(cell: Vector2i) -> void:
	var result := request_place(cell)
	if not result.is_ok:
		push_warning("GameSession: place request rejected: %s" % result.message)


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
