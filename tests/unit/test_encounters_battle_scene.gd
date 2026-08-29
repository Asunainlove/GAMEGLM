extends GutTest

## WP13 战斗场景冒烟与行为测试（真实 CombatEngine + WP12 数据）。
## 契约：docs/plans/contracts/module-contracts.md §4（battle.tscn 节点路径）、
## §5（EncounterDirector/CombatEngine）、§7（遭遇 ID）。
## 场景/实现经运行时 load + has_method 守卫（绝不 preload 被测实现），
## 缺失时以失败断言暴露而非静默跳过。

const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"
const ENCOUNTERS_JSON_PATH: String = "res://data/encounters/encounters.json"
const COMBAT_UNITS_JSON_PATH: String = "res://data/content/combat_units.json"
const COMBAT_ACTIONS_JSON_PATH: String = "res://data/content/combat_actions.json"
const ITEMS_JSON_PATH: String = "res://data/content/items.json"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")

## 信号捕获容器：连接的是测试方法（Node 上的 Callable），实例字段保活。
var _finished_events: Array[Dictionary] = []


func before_each() -> void:
	_finished_events.clear()


func _on_encounter_finished(encounter_id: String, outcome: Dictionary) -> void:
	_finished_events.append({"id": encounter_id, "outcome": outcome})


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _fresh_game_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


# --- WP12 数据装载 --------------------------------------------------------------


func _load_json_array(path: String) -> Array:
	var text: String = FileAccess.get_file_as_string(path)
	assert_false(text.is_empty(), "数据文件必须可读：%s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(typeof(parsed) == TYPE_ARRAY, "数据文件必须是数组：%s" % path)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


func _encounter_def(encounter_id: String) -> Dictionary:
	for entry: Variant in _load_json_array(ENCOUNTERS_JSON_PATH):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == encounter_id:
			return entry
	fail_test("encounters.json 缺少遭遇 %s" % encounter_id)
	return {}


func _defs_from(path: String) -> Dictionary:
	var defs: Dictionary = {}
	for entry: Variant in _load_json_array(path):
		if typeof(entry) == TYPE_DICTIONARY:
			defs[str(entry.get("id", ""))] = entry
	return defs


func _content(
		inventory: Dictionary = {"sedative_mist": 3, "shock_trap": 2},
		hp_multiplier: float = 1.0
) -> Dictionary:
	return {
		"unit_defs": _defs_from(COMBAT_UNITS_JSON_PATH),
		"action_defs": _defs_from(COMBAT_ACTIONS_JSON_PATH),
		"item_defs": _defs_from(ITEMS_JSON_PATH),
		"inventory": inventory.duplicate(true),
		"hp_multiplier": hp_multiplier,
	}


# --- 场景构造与契约守卫 ----------------------------------------------------------


func _make_scene(store: Object) -> Node2D:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	if packed == null:
		fail_test("Missing required WP13 implementation: %s" % BATTLE_SCENE_PATH)
		return null
	var scene: Node2D = packed.instantiate() as Node2D
	if scene == null:
		fail_test("battle.tscn 根节点必须为 Node2D（契约 §4）。")
		return null
	add_child_autofree(scene)
	if not _require_scene(scene):
		return null
	scene.set("store", store)
	scene.connect("encounter_finished", Callable(self, "_on_encounter_finished"))
	return scene


func _require_scene(scene: Node2D) -> bool:
	if not scene.has_method("begin_encounter"):
		fail_test("BattleScene 缺少方法 begin_encounter。")
		return false
	if not scene.has_method("play_ally_action"):
		fail_test("BattleScene 缺少方法 play_ally_action。")
		return false
	if not scene.has_method("battle_state"):
		fail_test("BattleScene 缺少方法 battle_state。")
		return false
	if not ("store" in scene):
		fail_test("BattleScene 缺少可注入属性 store。")
		return false
	if not scene.has_signal("encounter_finished"):
		fail_test("BattleScene 缺少信号 encounter_finished。")
		return false
	return true


func _unit(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Dictionary in battle.get("units", []):
		if str(unit.get("key", "")) == unit_key:
			return unit
	return {}


func _actions_box(scene: Node2D) -> VBoxContainer:
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	return ui.get_node("ActionsBox") as VBoxContainer


func _turn_label(scene: Node2D) -> Label:
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	return ui.get_node("TurnLabel") as Label


# --- 场景契约（§4）---------------------------------------------------------------


func test_battle_scene_matches_module_contract_section_4() -> void:
	var scene: Node2D = _make_scene(null)
	if scene == null:
		return
	assert_eq(scene.name, "Battle", "根节点名必须为 Battle。")
	assert_true(scene is Node2D, "根节点必须为 Node2D。")
	assert_not_null(scene.get_node("Tracks") as Node2D, "Tracks 必须为 Node2D。")
	assert_not_null(scene.get_node("UI") as CanvasLayer, "UI 必须为 CanvasLayer。")
	assert_not_null(_turn_label(scene) as Label, "UI 内必须有 TurnLabel。")
	assert_not_null(_actions_box(scene) as VBoxContainer, "UI 内必须有 ActionsBox（VBoxContainer）。")


# --- begin_encounter：灰盒渲染 + UI ----------------------------------------------


func test_begin_encounter_renders_graybox_units_and_ui() -> void:
	var scene: Node2D = _make_scene(_fresh_game_state())
	if scene == null:
		return
	scene.call("begin_encounter", _encounter_def("encounter_first_drift"), _content())

	# 灰盒单位节点数 = 盟友 2 + 敌 2。
	var unit_nodes: Array = get_tree().get_nodes_in_group("battle_unit")
	assert_eq(unit_nodes.size(), 4, "每个战斗单位必须有一个灰盒节点。")
	for unit_node: Node in unit_nodes:
		assert_not_null(unit_node.get_node_or_null("Box"), "单位节点必须含 ColorRect Box。")
		assert_not_null(unit_node.get_node_or_null("Label"), "单位节点必须含 Label。")

	# 按 front/mid/rear 行排：front = 洛弦 + 2 幼群，mid = 弥砂。
	var tracks: Node2D = scene.get_node("Tracks") as Node2D
	var row_front: Node2D = tracks.get_node("Row_front") as Node2D
	var row_mid: Node2D = tracks.get_node("Row_mid") as Node2D
	var row_rear: Node2D = tracks.get_node("Row_rear") as Node2D
	assert_not_null(row_front, "front 行节点必须存在。")
	assert_not_null(row_mid, "mid 行节点必须存在。")
	assert_not_null(row_rear, "rear 行节点必须存在。")
	if row_front != null:
		assert_eq(row_front.get_child_count(), 3)
	if row_mid != null:
		assert_eq(row_mid.get_child_count(), 1)
	if row_rear != null:
		assert_eq(row_rear.get_child_count(), 0)

	# 单位 Label 展示中文名与血量。
	if row_mid != null and row_mid.get_child_count() == 1:
		var misa_label: Label = (row_mid.get_child(0) as Node).get_node("Label") as Label
		assert_not_null(misa_label)
		if misa_label != null:
			assert_true(misa_label.text.contains("弥砂"), "单位 Label 必须展示中文名。")

	# UI：回合文案 + 首行动者（洛弦，速度最高）的行动按钮。
	assert_eq(_turn_label(scene).text, "第 1 回合")
	var actions_box: VBoxContainer = _actions_box(scene)
	assert_eq(actions_box.get_child_count(), 3, "按钮数必须等于洛弦的 action_ids 数。")
	if actions_box.get_child_count() == 3:
		assert_eq((actions_box.get_child(0) as Button).text, "破尘击")
		assert_eq((actions_box.get_child(1) as Button).text, "定锚式")
		assert_eq((actions_box.get_child(2) as Button).text, "共鸣脉冲")


func test_begin_encounter_passes_hp_multiplier_through() -> void:
	var scene: Node2D = _make_scene(_fresh_game_state())
	if scene == null:
		return
	scene.call(
		"begin_encounter",
		_encounter_def("encounter_first_drift"),
		_content({"sedative_mist": 3, "shock_trap": 2}, 2.0)
	)
	var battle: Dictionary = scene.call("battle_state")
	var luoxian: Dictionary = _unit(battle, "a0|luoxian_fighter")
	assert_eq(int(luoxian.get("max_hp", 0)), 80, "hp_multiplier 必须经 director.start 透传进引擎。")


# --- 盟友行动 → 引擎自动结算敌方回合 ---------------------------------------------


func test_ally_action_submits_and_advances_to_next_ally() -> void:
	var scene: Node2D = _make_scene(_fresh_game_state())
	if scene == null:
		return
	scene.call("begin_encounter", _encounter_def("encounter_first_drift"), _content())

	scene.call("play_ally_action", "strike")
	var battle: Dictionary = scene.call("battle_state")

	# 洛弦破尘击打第一个活敌（e0 漂游幼群）：12 - 6 = 6。
	var swarm: Dictionary = _unit(battle, "e0|drift_swarmling")
	assert_eq(int(swarm.get("hp", 0)), 6)
	# 引擎自动推进到下一盟友（弥砂），盟友回合必须等待输入。
	var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(battle)
	assert_eq(str(active.get("key", "")), "a1|misa_weaver")
	# 按钮刷新为弥砂的 4 个行动。
	var actions_box: VBoxContainer = _actions_box(scene)
	assert_eq(actions_box.get_child_count(), 4)
	if actions_box.get_child_count() == 4:
		assert_eq((actions_box.get_child(0) as Button).text, "缚尘丝")


func test_ally_action_on_non_ally_turn_is_ignored() -> void:
	var scene: Node2D = _make_scene(_fresh_game_state())
	if scene == null:
		return
	scene.call("begin_encounter", _encounter_def("encounter_first_drift"), _content())
	scene.call("play_ally_action", "strike")
	# 现在轮到弥砂；弥砂没有 resonate_pulse → 提交应被引擎校验拒绝，回合不消耗。
	scene.call("play_ally_action", "resonate_pulse")
	var battle: Dictionary = scene.call("battle_state")
	assert_eq(str(COMBAT_ENGINE_SCRIPT.active_unit(battle).get("key", "")), "a1|misa_weaver")
	assert_eq(int(battle.get("turn", 0)), 1, "非法行动不得消耗回合。")


# --- 完整胜利：finish 经 store 落账 + 信号 ----------------------------------------


func test_leviathan_victory_finishes_via_store_and_emits_signal() -> void:
	var store: Node = _fresh_game_state()
	var scene: Node2D = _make_scene(store)
	if scene == null:
		return
	# 开局利维坦（速度 7）先手 → 场景自动结算敌方回合直到洛弦行动。
	scene.call("begin_encounter", _encounter_def("encounter_leviathan"), _content())
	var battle: Dictionary = scene.call("battle_state")
	assert_eq(
		str(COMBAT_ENGINE_SCRIPT.active_unit(battle).get("key", "")),
		"a0|luoxian_fighter",
		"敌方先手回合必须已被自动结算。"
	)

	# 测试造伤：把敌方单位 hp 造到 1（转瞬态战斗字典，非持久状态）。
	for unit: Dictionary in battle.get("units", []):
		if str(unit.get("side", "")) == "enemy":
			unit["hp"] = 1

	# 一击终结 → victory → director.finish 经 store 落账 → 信号。
	scene.call("play_ally_action", "strike")
	assert_eq(_finished_events.size(), 1, "战斗结束必须恰好发出一次 encounter_finished。")
	if _finished_events.size() != 1:
		return
	assert_eq(str(_finished_events[0].get("id", "")), "encounter_leviathan")
	var outcome: Dictionary = _finished_events[0].get("outcome", {})
	assert_eq(str(outcome.get("result", "")), "victory")
	assert_eq(int(outcome.get("turns", 0)), 1)
	assert_eq(
		_canonical(outcome.get("drops", [])),
		_canonical([{"item_id": "echo_seed", "amount": 1}, {"item_id": "resonant_core", "amount": 2}])
	)

	var finish_result: AppResult = scene.call("last_finish_result")
	assert_not_null(finish_result, "last_finish_result 必须记录 director.finish 的返回。")
	if finish_result != null:
		assert_true(finish_result.is_ok, finish_result.message)

	# 落账经真实 store：battle_outcomes + 掉落入 inventory + 胜利旗标。
	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		snapshot.get("battle_outcomes", {}).get("encounter_leviathan", {}),
		{"result": "victory", "turns": 1}
	)
	assert_eq(int(snapshot.get("inventory", {}).get("echo_seed", 0)), 1)
	assert_eq(int(snapshot.get("inventory", {}).get("resonant_core", 0)), 2)
	assert_eq(bool(snapshot.get("flags", {}).get("encounter_leviathan_won", false)), true)


# --- 确定性：同遭遇同操作序列两次 → outcome 一致 ----------------------------------


func test_same_encounter_same_action_sequence_yields_identical_outcome() -> void:
	var first: Dictionary = _play_to_completion("encounter_first_drift")
	var second: Dictionary = _play_to_completion("encounter_first_drift")
	assert_false(first.is_empty(), "第一次完整对局必须产生 outcome。")
	assert_eq(_canonical(first), _canonical(second), "同遭遇同操作序列的 outcome 必须完全一致。")
	assert_eq(str(first.get("result", "")), "victory", "标准操作序列下盟友必须获胜。")


func _play_to_completion(encounter_id: String) -> Dictionary:
	var store: Node = _fresh_game_state()
	var scene: Node2D = _make_scene(store)
	if scene == null:
		return {}
	_finished_events.clear()
	scene.call("begin_encounter", _encounter_def(encounter_id), _content())
	var guard := 0
	while guard < 200:
		var battle: Dictionary = scene.call("battle_state")
		if bool(battle.get("finished", false)):
			break
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(battle)
		if active.is_empty():
			break
		if str(active.get("side", "")) != "ally":
			break
		scene.call("play_ally_action", _deterministic_action(battle, active))
		guard += 1
	assert_eq(_finished_events.size(), 1, "完整对局必须恰好发出一次 encounter_finished。")
	if _finished_events.is_empty():
		return {}
	return _finished_events[0].get("outcome", {})


func _deterministic_action(battle: Dictionary, active: Dictionary) -> String:
	## 确定性操作策略：按 action_ids 声明序取第一个 power > 0 的行动，否则第一个。
	var action_defs: Dictionary = battle.get("action_defs", {})
	var fallback := ""
	for action_id: String in active.get("action_ids", []):
		var action: Dictionary = action_defs.get(action_id, {})
		if action.is_empty():
			continue
		if fallback == "":
			fallback = action_id
		if int(action.get("power", 0)) > 0:
			return action_id
	return fallback
