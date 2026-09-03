extends GutTest

## W003-A4 战斗表现增强测试（缺口报告 C2：Boss 相位切换无可感知表现）。
## 以本地桩引擎 StubEngine（static 签名与 CombatEngine 一致，不含任何引擎
## 结算逻辑）注入 BattleScene.engine_script 注入缝，按预设步骤剧本驱动
## log 序列后断言表现层：
## - 相位/回合/胜负横幅的文本、可见性与颜色语义；
## - 战报面板：最近 3 条中文摘要（行动名+目标+伤害/治疗数字）、error 暗色；
## - 失稳/防护标签与失稳色块闪紫基色；
## - 胜负横幅期间行动禁用窗口，且 encounter_finished 信号时序不变
##   （finish 当帧同步发出一次，game_session 卸载流程依赖此时序）。
## 场景经运行时 load + get/has_method 守卫（绝不 preload 被测实现），
## 缺失时以失败断言暴露而非静默跳过。

const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const STUB_ENCOUNTER_ID: String = "stub_encounter"

## 信号捕获容器：连接的是测试方法（Node 上的 Callable），实例字段保活。
var _finished_events: Array[Dictionary] = []


func before_each() -> void:
	_finished_events.clear()
	StubEngine.battle_template = {}
	StubEngine.submit_calls = 0


# --- 桩引擎（仅表现层测试使用）-----------------------------------------------------


## 桩战斗引擎：static 签名与 CombatEngine 一致（create_battle/submit_action/
## is_finished/active_unit/outcome）。create_battle 返回 battle_template 副本；
## 每次 submit_action 消耗一条内嵌 stub_steps 步骤：log 追加（log）、顶层字段
## 改写（set）、单位字段覆盖（units）、行动单位指定（active_key）。
class StubEngine:
	static var battle_template: Dictionary = {}
	static var submit_calls: int = 0

	static func create_battle(_config: Dictionary) -> Dictionary:
		return battle_template.duplicate(true)

	static func submit_action(
			battle: Dictionary, _unit_key: String, _action_id: String, _target_key: String
	) -> Dictionary:
		submit_calls += 1
		var state: Dictionary = battle.duplicate(true)
		var steps: Array = state.get("stub_steps", [])
		if steps.is_empty():
			return state
		var step: Dictionary = steps.pop_front()
		for entry: Variant in step.get("log", []):
			if not state.has("log") or typeof(state["log"]) != TYPE_ARRAY:
				state["log"] = []
			(state["log"] as Array).append(entry)
		var fields: Dictionary = step.get("set", {})
		for field: Variant in fields:
			state[str(field)] = fields[field]
		var overrides: Dictionary = step.get("units", {})
		for unit: Dictionary in state.get("units", []):
			var override: Dictionary = overrides.get(str(unit.get("key", "")), {})
			for field: Variant in override:
				unit[str(field)] = override[field]
		var active_key := str(step.get("active_key", ""))
		if active_key != "":
			var order: Array = state.get("order", [])
			var index := order.find(active_key)
			if index >= 0:
				state["active_index"] = index
		return state

	static func is_finished(battle: Dictionary) -> bool:
		return bool(battle.get("finished", false))

	static func active_unit(battle: Dictionary) -> Dictionary:
		var order: Array = battle.get("order", [])
		var index := int(battle.get("active_index", 0))
		if index < 0 or index >= order.size():
			return {}
		for unit: Dictionary in battle.get("units", []):
			if str(unit.get("key", "")) == str(order[index]):
				return unit.duplicate(true)
		return {}

	static func outcome(battle: Dictionary) -> Dictionary:
		return {
			"result": str(battle.get("result", "")),
			"turns": int(battle.get("turn", 0)),
			"drops": [],
		}


# --- 信号与夹具 -------------------------------------------------------------------


func _on_encounter_finished(encounter_id: String, outcome: Dictionary) -> void:
	_finished_events.append({"id": encounter_id, "outcome": outcome})


func _fresh_game_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _make_scene(store: Object = null) -> Node2D:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	if packed == null:
		fail_test("Missing required W003-A4 implementation: %s" % BATTLE_SCENE_PATH)
		return null
	var scene: Node2D = packed.instantiate() as Node2D
	if scene == null:
		fail_test("battle.tscn 根节点必须为 Node2D。")
		return null
	add_child_autofree(scene)
	if scene.get("engine_script") == null:
		fail_test("BattleScene 缺少可注入属性 engine_script（W003-A4 桩注入缝）。")
		return null
	scene.set("store", store)
	scene.set("engine_script", StubEngine)
	scene.connect("encounter_finished", Callable(self, "_on_encounter_finished"))
	return scene


func _banner_label(scene: Node2D, node_name: String) -> Label:
	var ui: CanvasLayer = scene.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		fail_test("battle.tscn 缺少 UI CanvasLayer。")
		return null
	var label: Label = ui.get_node_or_null(node_name) as Label
	if label == null:
		fail_test("battle.tscn 缺少 UI/%s（W003-A4 横幅节点）。" % node_name)
		return null
	return label


func _report_panel(scene: Node2D) -> VBoxContainer:
	var ui: CanvasLayer = scene.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		fail_test("battle.tscn 缺少 UI CanvasLayer。")
		return null
	var panel: VBoxContainer = ui.get_node_or_null("ReportChrome/ReportPanel") as VBoxContainer
	if panel == null:
		fail_test("battle.tscn 缺少 UI/ReportChrome/ReportPanel（W003-A4 战报面板）。")
		return null
	return panel


func _actions_box(scene: Node2D) -> VBoxContainer:
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	return ui.get_node("ActionsPanel/ActionsBox") as VBoxContainer


## 桩战斗剧本：洛弦（盟友）+ 灰喉岩主（Boss），全部原创中文文案。
func _stub_battle() -> Dictionary:
	return {
		"battle_id": "battle_stub",
		"seed": 0,
		"turn": 1,
		"units": [
			{
				"key": "a0|vanguard", "unit_id": "vanguard", "side": "ally", "kind": "ally",
				"name_zh": "洛弦", "track": "front", "hp": 30, "max_hp": 30, "speed": 6,
				"action_ids": ["strike"], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "e0|boss", "unit_id": "boss", "side": "enemy", "kind": "boss",
				"name_zh": "灰喉岩主", "track": "front", "hp": 40, "max_hp": 80, "speed": 4,
				"action_ids": ["crush"], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
		],
		"order": ["a0|vanguard", "e0|boss"],
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"action_defs": {
			"strike": {"name_zh": "破尘击", "targeting": "single_enemy", "power": 6},
			"crush": {"name_zh": "碎岩压击", "targeting": "single_enemy", "power": 7},
			"soothe_mist": {"name_zh": "定神雾息", "targeting": "single_ally", "heal": 12},
		},
		"stub_steps": [],
	}


func _begin_stub_encounter(scene: Node2D) -> void:
	scene.call("begin_encounter", {"id": STUB_ENCOUNTER_ID}, {})


# --- 相位横幅（C2 核心缺口）--------------------------------------------------------


func test_phase_banner_shows_on_phase_change_log() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [{
		"log": [{"type": "phase_change", "unit": "e0|boss", "phase": "boss_unbound"}],
		"active_key": "a0|vanguard",
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var banner: Label = _banner_label(scene, "PhaseBanner")
	assert_false(banner.visible, "无 phase_change 日志时相位横幅必须隐藏。")

	scene.call("play_ally_action", "strike")
	assert_true(banner.visible, "phase_change 日志必须点亮相位横幅。")
	assert_eq(banner.text, "⚠ 相位失稳！灰喉岩主变了样子！")
	var color: Color = banner.get_theme_color("font_color")
	assert_true(
		color.r > 0.8 and color.g < 0.6 and color.b < 0.6,
		"相位横幅必须为红橙色调。"
	)


# --- 回合横幅 ---------------------------------------------------------------------


func test_round_banner_shows_for_each_round_start() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [{
		"log": [{"type": "round_start", "turn": 3}],
		"set": {"turn": 3},
		"active_key": "a0|vanguard",
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var banner: Label = _banner_label(scene, "RoundBanner")
	assert_true(banner.visible, "开局第 1 回合必须点亮回合横幅。")
	assert_eq(banner.text, "第 1 回合")

	scene.call("play_ally_action", "strike")
	assert_true(banner.visible, "round_start 日志必须点亮回合横幅。")
	assert_eq(banner.text, "第 3 回合")


# --- 战报面板 ---------------------------------------------------------------------


func test_report_panel_summarizes_action_with_target_and_numbers() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [{
		"log": [
			{"type": "action", "unit": "a0|vanguard", "action": "strike", "targets": ["e0|boss"]},
			{"type": "damage", "source": "a0|vanguard", "target": "e0|boss", "amount": 6},
		],
		"active_key": "a0|vanguard",
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var panel: VBoxContainer = _report_panel(scene)
	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 1, "单次行动+伤害必须聚合为一条摘要。")
	assert_eq((panel.get_child(0) as Label).text, "洛弦 → 灰喉岩主：破尘击 6 伤害")


func test_report_panel_summarizes_heal() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["units"][0]["key"] = "a0|weaver"
	battle["units"][0]["name_zh"] = "弥砂"
	battle["order"] = ["a0|weaver", "e0|boss"]
	battle["stub_steps"] = [{
		"log": [
			{"type": "action", "unit": "a0|weaver", "action": "soothe_mist", "targets": ["a0|weaver"]},
			{"type": "heal", "source": "a0|weaver", "target": "a0|weaver", "amount": 12},
		],
		"active_key": "a0|weaver",
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var panel: VBoxContainer = _report_panel(scene)
	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 1)
	assert_eq((panel.get_child(0) as Label).text, "弥砂 → 弥砂：定神雾息 12 治疗")


func test_report_panel_keeps_latest_three_lines() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [
		{
			"log": [
				{"type": "action", "unit": "a0|vanguard", "action": "strike", "targets": ["e0|boss"]},
				{"type": "damage", "source": "a0|vanguard", "target": "e0|boss", "amount": 6},
			],
			"active_key": "a0|vanguard",
		},
		{
			"log": [
				{"type": "action", "unit": "a0|vanguard", "action": "strike", "targets": ["e0|boss"]},
				{"type": "damage", "source": "a0|vanguard", "target": "e0|boss", "amount": 4},
				{"type": "destabilized", "unit": "e0|boss"},
			],
			"active_key": "a0|vanguard",
		},
		{
			"log": [{"type": "error", "code": "insufficient_cost", "unit": "a0|vanguard", "action": "strike", "target": ""}],
			"active_key": "a0|vanguard",
		},
	]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var panel: VBoxContainer = _report_panel(scene)

	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 1)
	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 3, "战报面板最多保留最近 3 条摘要。")
	assert_eq((panel.get_child(0) as Label).text, "洛弦 → 灰喉岩主：破尘击 6 伤害")
	assert_eq((panel.get_child(1) as Label).text, "洛弦 → 灰喉岩主：破尘击 4 伤害")
	assert_eq((panel.get_child(2) as Label).text, "灰喉岩主：失稳！")

	# 第 4 条入列 → 滑动窗口挤掉最旧一条。
	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 3)
	assert_eq((panel.get_child(0) as Label).text, "洛弦 → 灰喉岩主：破尘击 4 伤害")
	assert_eq((panel.get_child(1) as Label).text, "灰喉岩主：失稳！")
	assert_eq((panel.get_child(2) as Label).text, "⚠ 费用不足")


func test_report_panel_renders_error_entries_in_dark_color() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [
		{
			"log": [
				{"type": "action", "unit": "a0|vanguard", "action": "strike", "targets": ["e0|boss"]},
				{"type": "damage", "source": "a0|vanguard", "target": "e0|boss", "amount": 6},
			],
			"active_key": "a0|vanguard",
		},
		{
			"log": [{"type": "error", "code": "invalid_target", "unit": "a0|vanguard", "action": "strike", "target": "e0|boss"}],
			"active_key": "a0|vanguard",
		},
	]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)
	var panel: VBoxContainer = _report_panel(scene)
	scene.call("play_ally_action", "strike")
	scene.call("play_ally_action", "strike")
	assert_eq(panel.get_child_count(), 2)
	var normal_color: Color = (panel.get_child(0) as Label).get_theme_color("font_color")
	var error_label: Label = panel.get_child(1) as Label
	assert_eq(error_label.text, "⚠ 无效目标")
	var error_color: Color = error_label.get_theme_color("font_color")
	assert_true(
		error_color.v < normal_color.v,
		"error 摘要必须以暗色显示（亮度低于普通摘要）。"
	)


# --- 胜负横幅 + 行动禁用窗口 + 信号时序 ---------------------------------------------


func test_victory_banner_blocks_actions_and_keeps_signal_timing() -> void:
	var store: Node = _fresh_game_state()
	var scene: Node2D = _make_scene(store)
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [{
		"log": [{"type": "battle_end", "result": "victory"}],
		"set": {"finished": true, "result": "victory"},
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)

	scene.call("play_ally_action", "strike")
	# 信号时序不变：finish 当帧同步发出恰好一次（game_session 卸载流程依赖）。
	assert_eq(_finished_events.size(), 1, "胜负横幅不得延迟 encounter_finished 信号。")
	if _finished_events.size() == 1:
		assert_eq(str(_finished_events[0]["id"]), STUB_ENCOUNTER_ID)
		assert_eq(str(_finished_events[0]["outcome"]["result"]), "victory")

	var overlay: Control = (scene.get_node("UI") as CanvasLayer).get_node("FinishBanner") as Control
	assert_not_null(overlay, "battle.tscn 缺少 UI/FinishBanner（W003-A4 胜负横幅遮罩）。")
	if overlay != null:
		assert_true(overlay.visible, "胜利必须显示全屏横幅遮罩。")
		var label: Label = overlay.get_node("FinishLabel") as Label
		assert_eq(label.text, "胜利！")
		var color: Color = label.get_theme_color("font_color")
		assert_true(
			color.r > 0.8 and color.g > 0.6 and color.b < 0.6,
			"胜利横幅必须为金色调。"
		)

	# 行动禁用窗口：横幅期间按钮清空、重复提交不得触达引擎。
	assert_eq(_actions_box(scene).get_child_count(), 0, "胜负横幅期间必须清空行动按钮。")
	var calls_before: int = StubEngine.submit_calls
	scene.call("play_ally_action", "strike")
	assert_eq(StubEngine.submit_calls, calls_before, "胜负横幅期间禁止再提交行动。")

	# finish 仍同步经 director 落账（时序不变的一部分）。
	var snapshot: Dictionary = store.snapshot()
	assert_has(
		snapshot.get("battle_outcomes", {}) as Dictionary, STUB_ENCOUNTER_ID,
		"finish 必须照常把战果落账到 store。"
	)


func test_defeat_banner_shows_dark_purple_text() -> void:
	var store: Node = _fresh_game_state()
	var scene: Node2D = _make_scene(store)
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	battle["stub_steps"] = [{
		"log": [{"type": "battle_end", "result": "defeat"}],
		"set": {"finished": true, "result": "defeat"},
	}]
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)

	scene.call("play_ally_action", "strike")
	assert_eq(_finished_events.size(), 1)
	var overlay: Control = (scene.get_node("UI") as CanvasLayer).get_node("FinishBanner") as Control
	if overlay == null:
		fail_test("battle.tscn 缺少 UI/FinishBanner（W003-A4 胜负横幅遮罩）。")
		return
	assert_true(overlay.visible, "败北必须显示全屏横幅遮罩。")
	var label: Label = overlay.get_node("FinishLabel") as Label
	assert_eq(label.text, "败北……")
	var color: Color = label.get_theme_color("font_color")
	assert_true(
		color.b > color.r and color.b > color.g and color.v < 0.8,
		"败北横幅必须为暗紫色调。"
	)


# --- 失稳 / 防护标记 ----------------------------------------------------------------


func _front_unit_node(scene: Node2D, unit_key: String) -> Node2D:
	var sanitized := unit_key.replace("|", "_")
	return scene.get_node_or_null("Tracks/Row_front/%s" % sanitized) as Node2D


func test_destabilized_and_guard_tags_render_on_unit_nodes() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var battle: Dictionary = _stub_battle()
	(battle["units"][0] as Dictionary)["destabilized"] = true
	(battle["units"][1] as Dictionary)["guard_ratio"] = 0.5
	StubEngine.battle_template = battle
	_begin_stub_encounter(scene)

	var ally: Node2D = _front_unit_node(scene, "a0|vanguard")
	var boss: Node2D = _front_unit_node(scene, "e0|boss")
	assert_not_null(ally)
	assert_not_null(boss)
	if ally == null or boss == null:
		return
	assert_true((ally.get_node("Label") as Label).text.contains("失稳"), "失稳单位必须带失稳标签。")
	assert_true(bool(ally.get_meta("destabilized", false)), "失稳单位节点必须带 destabilized 元数据。")
	var ally_box: ColorRect = ally.get_node("Box") as ColorRect
	assert_true(
		ally_box.color.r > ally_box.color.g and ally_box.color.b > ally_box.color.g,
		"失稳单位色块必须立即呈紫色（此后按帧闪紫）。"
	)
	assert_true((boss.get_node("Label") as Label).text.contains("防护"), "防护中单位必须带防护标签。")
	assert_false(bool(boss.get_meta("destabilized", true)), "非失稳单位不得带 destabilized 元数据。")


func test_destabilized_flash_oscillates_between_base_and_purple() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	var script: Script = scene.get_script()
	var base := Color(0.42, 0.52, 0.66)
	var midpoint: Color = script.destabilized_box_color(base, 0.0)
	var peak: Color = script.destabilized_box_color(base, PI / 12.0)
	var trough: Color = script.destabilized_box_color(base, PI / 4.0)
	assert_true(midpoint != base and midpoint != peak, "闪紫中间态必须介于基色与紫色之间。")
	assert_true(midpoint.g > peak.g and midpoint.b < peak.b, "闪紫必须朝紫色方向振荡。")
	assert_true(
		trough.is_equal_approx(base),
		"振荡低谷必须回到基色（脉冲周期内全幅摆动）。"
	)
	assert_true(peak.b > base.b and peak.g < base.g, "振荡峰值必须为紫色。")


# --- 表现层时序默认值 ---------------------------------------------------------------


func test_banner_durations_default_to_spec() -> void:
	var scene: Node2D = _make_scene()
	if scene == null:
		return
	assert_eq(float(scene.get("phase_banner_seconds")), 2.0, "相位横幅默认 2s。")
	assert_eq(float(scene.get("round_banner_seconds")), 1.0, "回合横幅默认 1s。")
	assert_eq(float(scene.get("finish_banner_seconds")), 2.0, "胜负横幅默认 2s。")
