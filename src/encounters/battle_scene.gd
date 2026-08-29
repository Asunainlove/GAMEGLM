class_name BattleScene
extends Node2D

## WP13 战斗场景（灰盒）：契约 docs/plans/contracts/module-contracts.md §4/§5。
## begin_encounter 经 EncounterDirector.start 组装 config、用真实 CombatEngine
## create_battle 建局；每个战斗单位渲染为 ColorRect+Label 灰盒节点并按
## front/mid/rear 行排（盟友居左、敌人居右）。轮到盟友时 ActionsBox 为其
## action_ids 生成 Button（中文文案来自 action_defs）；按下后自动选目标并
## submit_action——引擎内置的敌方回合循环随后自动结算，直到轮到下一位盟友
## 或战斗结束。结束时经 EncounterDirector.finish（store 注入，null → GameState）
## 落账并发出 encounter_finished。表现层不直接改持久状态，全部经 store 注入路径。

signal encounter_finished(encounter_id: String, outcome: Dictionary)

const DIRECTOR_SCRIPT: Script = preload("res://src/encounters/encounter_director.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")

const TRACK_ROWS: Array[String] = ["front", "mid", "rear"]
const ROW_SPACING: float = 96.0
const ALLY_ORIGIN: Vector2 = Vector2(96.0, 120.0)
const ENEMY_ORIGIN: Vector2 = Vector2(560.0, 120.0)
const UNIT_SPACING: float = 120.0
const ALLY_COLOR: Color = Color(0.42, 0.52, 0.66)
const ENEMY_COLOR: Color = Color(0.62, 0.4, 0.38)
const BOSS_COLOR: Color = Color(0.72, 0.5, 0.2)
const MAX_AUTO_TURNS: int = 64

## 契约 §0 注入模式：落账 store，null → GameState autoload。
var store: Object = null

var _encounter_def: Dictionary = {}
var _battle: Dictionary = {}
var _last_finish_result: AppResult = null


# --- 对外流程 --------------------------------------------------------------------


## 开局：director.start 组装 config → 引擎 create_battle → 灰盒渲染 + UI；
## 若先手为敌方单位（如 Boss 速度更高），自动结算敌方回合直到轮到盟友或结束。
func begin_encounter(encounter_def: Dictionary, content: Dictionary) -> void:
	_encounter_def = encounter_def.duplicate(true)
	var config: Dictionary = DIRECTOR_SCRIPT.start(_encounter_def, content)
	_battle = COMBAT_ENGINE_SCRIPT.create_battle(config)
	_resolve_enemy_turns()


## 当前战斗状态（转瞬态 Dictionary，非持久状态；供观察者与测试读取）。
func battle_state() -> Dictionary:
	return _battle


func last_finish_result() -> AppResult:
	return _last_finish_result


## 盟友行动入口（ActionsBox 按钮按下同样走这里）：自动选目标并提交；
## 引擎在结算后自动推进并连续结算敌方回合，直到轮到下一位盟友或战斗结束。
func play_ally_action(action_id: String) -> void:
	if COMBAT_ENGINE_SCRIPT.is_finished(_battle):
		return
	var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(_battle)
	if active.is_empty() or str(active.get("side", "")) != "ally":
		return
	var action := str(action_id)
	var target_key := _auto_target(_battle, active, action)
	_battle = COMBAT_ENGINE_SCRIPT.submit_action(_battle, str(active.get("key", "")), action, target_key)
	_resolve_enemy_turns()


# --- 内部回合推进 -----------------------------------------------------------------


## 引擎的 submit_action 已内置"敌方回合连续自动结算"；此循环兜底处理
## 开局先手为敌方、以及任何返回时 active 仍为敌方的边界（带安全上限）。
func _resolve_enemy_turns() -> void:
	var guard := 0
	while not COMBAT_ENGINE_SCRIPT.is_finished(_battle) and guard < MAX_AUTO_TURNS:
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(_battle)
		if active.is_empty() or str(active.get("side", "")) != "enemy":
			break
		_battle = COMBAT_ENGINE_SCRIPT.submit_action(_battle, str(active.get("key", "")), "", "")
		guard += 1
	if COMBAT_ENGINE_SCRIPT.is_finished(_battle):
		_finish_battle()
	else:
		_refresh_view()


## 目标自动选择：single_enemy → 第一活敌（order 序）；single_ally → 最低 hp
## 活友（平局取 order 靠前，与引擎 AI 规则一致）；self / all_enemies → 空目标。
func _auto_target(battle: Dictionary, actor: Dictionary, action_id: String) -> String:
	var action_defs: Dictionary = _as_dictionary(battle.get("action_defs", {}))
	var action: Dictionary = _as_dictionary(action_defs.get(action_id, {}))
	match str(action.get("targeting", "")):
		"single_enemy":
			return _first_living_key(battle, "enemy")
		"single_ally":
			return _lowest_hp_living_key(battle, "ally")
		_:
			return ""


func _first_living_key(battle: Dictionary, side: String) -> String:
	for key: Variant in _as_array(battle.get("order", [])):
		var unit: Dictionary = _find_unit(battle, str(key))
		if not unit.is_empty() and bool(unit.get("alive", false)) and str(unit.get("side", "")) == side:
			return str(unit.get("key", ""))
	return ""


func _lowest_hp_living_key(battle: Dictionary, side: String) -> String:
	var best_key := ""
	var best_hp := 0
	for key: Variant in _as_array(battle.get("order", [])):
		var unit: Dictionary = _find_unit(battle, str(key))
		if unit.is_empty() or not bool(unit.get("alive", false)):
			continue
		if str(unit.get("side", "")) != side:
			continue
		var hp := int(unit.get("hp", 0))
		if best_key == "" or hp < best_hp:
			best_key = str(unit.get("key", ""))
			best_hp = hp
	return best_key


func _finish_battle() -> void:
	var outcome: Dictionary = COMBAT_ENGINE_SCRIPT.outcome(_battle)
	# finish 是 EncounterDirector 的实例方法（check_triggers/start 才是静态），
	# 因此这里实例化纯逻辑 director 再落账（无状态，用完即释）。
	var director: EncounterDirector = DIRECTOR_SCRIPT.new()
	_last_finish_result = director.finish(_snapshot_state(), _encounter_def, outcome, store)
	_refresh_view()
	encounter_finished.emit(str(_encounter_def.get("id", "")), outcome)


func _snapshot_state() -> Dictionary:
	if store == null:
		return GameState.snapshot()
	if store.has_method("snapshot"):
		var value: Variant = store.call("snapshot")
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {}


# --- 灰盒渲染 ---------------------------------------------------------------------


func _refresh_view() -> void:
	_rebuild_tracks()
	_refresh_turn_label()
	_refresh_actions()


func _track_row(track: String) -> Node2D:
	var tracks: Node2D = get_node_or_null("Tracks") as Node2D
	if tracks == null:
		return null
	var row_name := "Row_%s" % track
	var row: Node2D = tracks.get_node_or_null(row_name) as Node2D
	if row == null:
		row = Node2D.new()
		row.name = row_name
		tracks.add_child(row)
	return row


func _rebuild_tracks() -> void:
	var tracks: Node2D = get_node_or_null("Tracks") as Node2D
	if tracks == null:
		return
	for track: String in TRACK_ROWS:
		var existing_row: Node2D = _track_row(track)
		if existing_row != null:
			_clear_children(existing_row)
	var ally_columns: Dictionary = {}
	var enemy_columns: Dictionary = {}
	for unit: Dictionary in _as_array(_battle.get("units", [])):
		var track := str(unit.get("track", "front"))
		var row: Node2D = _track_row(track)
		if row == null:
			continue
		var columns: Dictionary = ally_columns if str(unit.get("side", "")) == "ally" else enemy_columns
		var column := int(columns.get(track, 0))
		columns[track] = column + 1
		var unit_node: Node2D = _build_unit_node(unit, column)
		row.add_child(unit_node)
		unit_node.add_to_group("battle_unit")


func _build_unit_node(unit: Dictionary, column: int) -> Node2D:
	var side := str(unit.get("side", ""))
	var track := str(unit.get("track", "front"))
	var row_index := TRACK_ROWS.find(track)
	if row_index < 0:
		row_index = 0
	var origin := ALLY_ORIGIN if side == "ally" else ENEMY_ORIGIN
	var unit_node := Node2D.new()
	unit_node.name = _unit_node_name(str(unit.get("key", "")))
	unit_node.position = origin + Vector2(float(column) * UNIT_SPACING, float(row_index) * ROW_SPACING)

	var color := ENEMY_COLOR
	if str(unit.get("kind", "")) == "boss":
		color = BOSS_COLOR
	elif side == "ally":
		color = ALLY_COLOR
	var box := ColorRect.new()
	box.name = "Box"
	box.position = Vector2(-28.0, -20.0)
	box.size = Vector2(56.0, 40.0)
	box.color = color
	unit_node.add_child(box)

	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(-36.0, -42.0)
	label.size = Vector2(72.0, 18.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "%s %d/%d" % [
		str(unit.get("name_zh", "")),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
	]
	unit_node.add_child(label)
	return unit_node


func _unit_node_name(unit_key: String) -> String:
	var sanitized := unit_key.replace("|", "_")
	return sanitized if sanitized != "" else "unit"


func _clear_children(node: Node) -> void:
	# 立即释放（而非 remove_child + queue_free）：树外节点 queue_free 无效会泄漏；
	# 灰盒与按钮都不被外部引用，同步 free 保持同帧节点计数准确。
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


# --- UI 刷新 ---------------------------------------------------------------------


func _refresh_turn_label() -> void:
	var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var label: Label = ui.get_node_or_null("TurnLabel") as Label
	if label == null:
		return
	label.text = "第 %d 回合" % int(_battle.get("turn", 0))


func _refresh_actions() -> void:
	var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var actions_box: VBoxContainer = ui.get_node_or_null("ActionsBox") as VBoxContainer
	if actions_box == null:
		return
	_clear_children(actions_box)
	if COMBAT_ENGINE_SCRIPT.is_finished(_battle):
		return
	var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(_battle)
	if active.is_empty() or str(active.get("side", "")) != "ally":
		return
	var action_defs: Dictionary = _as_dictionary(_battle.get("action_defs", {}))
	for action_id: Variant in _as_array(active.get("action_ids", [])):
		var action := str(action_id)
		var button := Button.new()
		button.text = str(_as_dictionary(action_defs.get(action, {})).get("name_zh", action))
		button.pressed.connect(_on_action_button_pressed.bind(action))
		actions_box.add_child(button)


func _on_action_button_pressed(action_id: String) -> void:
	# 延迟到空闲帧执行：refresh 会同步 free 发出 pressed 信号的按钮本身，
	# 信号发射过程中立即 free 发射者不安全，因此先让发射完成。
	play_ally_action.call_deferred(action_id)


# --- 内部工具 ---------------------------------------------------------------------


func _find_unit(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Dictionary in _as_array(battle.get("units", [])):
		if str(unit.get("key", "")) == unit_key:
			return unit
	return {}


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
