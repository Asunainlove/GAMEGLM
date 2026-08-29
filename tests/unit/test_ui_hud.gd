extends GutTest

## WP11：HUD 场景契约与只读渲染逻辑测试（先于实现编写，RED → GREEN）。
## 关键约束：HUD 是只读表现层——只消费注入的快照，绝不修改持久状态。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"
const THEME_PATH: String = "res://themes/starsoil_theme.tres"

## Godot 4 教训：Callable 只持 ObjectID，临时 RefCounted 会被立即释放导致注入静默失效。
## 因此替身必须保存在测试实例字段中保活。
var _fake: FakeSnapshotProvider = null

var _fake_names: Dictionary = {
	"starsoil_dust": "星壤尘",
	"lumen_shard": "辉砂晶片",
	"resonant_core": "共鸣核",
	"echo_seed": "余辉之种",
	"sedative_mist": "定神雾",
	"shock_trap": "震颤陷阱",
}


class FakeSnapshotProvider:
	var calls: int = 0
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		calls += 1
		return payload


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	_fake = null


# ---------------------------------------------------------------- helpers

func _resolve_fake_name(item_id: String) -> String:
	if _fake_names.has(item_id):
		return _fake_names[item_id] as String
	return item_id


func _make_hud(payload: Dictionary) -> Hud:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = payload
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must exist and load.")
	if scene == null:
		return null
	var hud: Hud = scene.instantiate() as Hud
	assert_not_null(hud, "ui_hud.tscn must instantiate as Hud.")
	if hud == null:
		return null
	hud.snapshot_provider = _fake.get_snapshot
	hud.name_resolver = _resolve_fake_name
	add_child_autofree(hud)
	return hud


func _basic_payload() -> Dictionary:
	return {
		"revision": 1,
		"inventory": {"starsoil_dust": 5, "lumen_shard": 2},
		"flags": {},
		"placed_buildings": [],
	}


func _snap(flags: Dictionary, building_ids: Array) -> Dictionary:
	var placed: Array = []
	for building_id: String in building_ids:
		placed.append({
			"building_id": building_id,
			"chunk_id": "chunk_0_0",
			"cell_x": 0,
			"cell_y": 0,
		})
	return {
		"revision": 1,
		"inventory": {},
		"flags": flags,
		"placed_buildings": placed,
	}


func _action_event(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in node.get_children():
		if child is Label:
			texts.append((child as Label).text)
	return texts


func _buttons_under(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in node.get_children():
		if child is Button:
			buttons.append(child)
		buttons.append_array(_buttons_under(child))
	return buttons


# ---------------------------------------------------------------- scene contract

func test_hud_scene_matches_contract() -> void:
	assert_true(ResourceLoader.exists(HUD_SCENE_PATH), "scenes/ui_hud.tscn must exist.")
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene)
	if scene == null:
		return

	var hud: Hud = scene.instantiate() as Hud
	add_child_autofree(hud)
	assert_not_null(hud)
	if hud == null:
		return

	assert_eq(hud.name, "Hud")
	assert_true(hud is CanvasLayer, "Hud root must be a CanvasLayer.")
	var script: Script = hud.get_script()
	assert_not_null(script)
	if script != null:
		assert_eq(script.resource_path, "res://src/ui/hud.gd", "Hud root must use src/ui/hud.gd.")
	assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS, "Hud must keep processing while paused.")
	assert_true(hud.has_signal("menu_resumed"), "Hud must declare menu_resumed signal.")

	assert_true(hud.get_node("InventoryBar") is HBoxContainer, "InventoryBar must be an HBoxContainer.")
	assert_true(hud.get_node("ObjectiveLabel") is Label, "ObjectiveLabel must be a Label.")
	assert_true(hud.get_node("InventoryPanel") is PanelContainer, "InventoryPanel must be a PanelContainer.")
	assert_true(hud.get_node("MenuPanel") is PanelContainer, "MenuPanel must be a PanelContainer.")

	assert_false((hud.get_node("InventoryPanel") as Control).visible, "InventoryPanel starts hidden.")
	assert_false((hud.get_node("MenuPanel") as Control).visible, "MenuPanel starts hidden.")
	assert_true((hud.get_node("InventoryBar") as Control).visible, "InventoryBar starts visible.")
	assert_true((hud.get_node("ObjectiveLabel") as Control).visible, "ObjectiveLabel starts visible.")


func test_hud_children_use_starsoil_theme() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return

	for node_name: String in ["InventoryBar", "ObjectiveLabel", "InventoryPanel", "MenuPanel"]:
		var control: Control = hud.get_node(node_name) as Control
		assert_not_null(control, node_name + " must exist.")
		if control != null:
			assert_eq(control.theme, theme, node_name + " must carry themes/starsoil_theme.tres.")


func test_hud_polls_snapshot_every_quarter_second() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var timer: Timer = hud.get_node_or_null("PollTimer") as Timer
	assert_not_null(timer, "Hud must build a PollTimer for snapshot polling.")
	if timer == null:
		return
	assert_eq(timer.wait_time, 0.25, "Poll interval must be 0.25 seconds.")
	assert_false(timer.one_shot, "Poll timer must repeat.")
	assert_false(timer.is_stopped(), "Poll timer must be running for periodic polling.")


func test_hud_menu_panel_has_resume_and_help_buttons() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var buttons: Array[Button] = _buttons_under(hud.get_node("MenuPanel"))
	assert_eq(buttons.size(), 2, "MenuPanel must contain exactly two buttons.")
	if buttons.size() == 2:
		assert_eq(buttons[0].text, "继续")
		assert_eq(buttons[1].text, "说明")


# ---------------------------------------------------------------- snapshot rendering

func test_refresh_renders_inventory_bar_with_injected_names() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	var texts: Array[String] = _label_texts(bar)
	var expected: Array[String] = ["辉砂晶片 ×2", "星壤尘 ×5"]
	assert_eq(texts, expected, "InventoryBar slots must use injected Chinese names, sorted by item id.")
	assert_true(_fake.calls >= 1, "Injected snapshot_provider must actually be called.")


func test_refresh_sets_non_empty_objective_label() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var label: Label = hud.get_node("ObjectiveLabel") as Label
	assert_ne(label.text, "", "ObjectiveLabel must render a non-empty objective.")
	assert_eq(label.text, Hud.objective_for(_fake.payload), "ObjectiveLabel must render objective_for(snapshot).")


func test_inventory_bar_summarizes_overflow_as_plus_n() -> void:
	var inventory: Dictionary = {}
	for index: int in 10:
		inventory["item_%02d" % (index + 1)] = index + 1
	var payload: Dictionary = {"revision": 3, "inventory": inventory, "flags": {}, "placed_buildings": []}
	var hud: Hud = _make_hud(payload)

	var texts: Array[String] = _label_texts(hud.get_node("InventoryBar"))
	assert_eq(texts.size(), 9, "InventoryBar must show 8 slots plus one overflow summary.")
	if texts.size() == 9:
		assert_eq(texts[0], "item_01 ×1")
		assert_eq(texts[7], "item_08 ×8")
		assert_eq(texts[8], "+2", "The 9th slot must summarize the remaining item kinds as +n.")


func test_inventory_panel_lists_all_items_when_toggled() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	hud._unhandled_input(_action_event("toggle_inventory"))
	var panel: Control = hud.get_node("InventoryPanel")
	assert_true(panel.visible, "toggle_inventory must reveal InventoryPanel.")

	var texts: Array[String] = _label_texts(hud.get_node("InventoryPanel/Content/ItemsBox"))
	var expected: Array[String] = ["辉砂晶片 ×2", "星壤尘 ×5"]
	assert_eq(texts, expected, "InventoryPanel must list every item row.")

	hud._unhandled_input(_action_event("toggle_inventory"))
	assert_false(panel.visible, "Second toggle_inventory must hide InventoryPanel.")


func test_refresh_always_rerenders_ignoring_revision_cache() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	_fake.payload["inventory"] = {"starsoil_dust": 7}
	hud.refresh()
	var texts: Array[String] = _label_texts(hud.get_node("InventoryBar"))
	var expected: Array[String] = ["星壤尘 ×7"]
	assert_eq(texts, expected, "refresh() must re-render even when the revision is unchanged.")


func test_poll_renders_only_when_revision_changes() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	var timer: Timer = hud.get_node("PollTimer") as Timer
	timer.stop()

	var expected_first: Array[String] = ["辉砂晶片 ×2", "星壤尘 ×5"]
	assert_eq(_label_texts(bar), expected_first)

	timer.timeout.emit()
	assert_eq(_label_texts(bar), expected_first, "Same revision must not re-render.")

	_fake.payload["inventory"] = {"starsoil_dust": 9}
	timer.timeout.emit()
	assert_eq(_label_texts(bar), expected_first, "Changed payload with same revision must not re-render.")

	_fake.payload["revision"] = 2
	timer.timeout.emit()
	var expected_second: Array[String] = ["星壤尘 ×9"]
	assert_eq(_label_texts(bar), expected_second, "New revision must trigger re-render.")


func test_refresh_never_mutates_injected_snapshot() -> void:
	var payload: Dictionary = {
		"revision": 7,
		"inventory": {"starsoil_dust": 5, "lumen_shard": 2},
		"flags": {"event_prologue_landing_done": true},
		"placed_buildings": [
			{"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 3, "cell_y": 4}
		],
		"relationships": {"luoxian": {"trust": 10}},
		"ideology": {"stewardship": 1, "continuity": 0, "agency": -1},
		"completed_events": [],
	}
	var hud: Hud = _make_hud(payload)
	var before: Dictionary = _fake.payload.duplicate(true)

	hud.refresh()
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud._unhandled_input(_action_event("menu"))

	assert_true(_fake.calls >= 1, "Injected snapshot_provider must be used.")
	assert_eq(_fake.payload, before, "HUD rendering must never mutate the injected snapshot.")


# ---------------------------------------------------------------- panel toggles and pause

func test_menu_action_toggles_menu_panel_and_pause() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var menu: Control = hud.get_node("MenuPanel")
	assert_false(menu.visible)
	assert_false(get_tree().paused)

	hud._unhandled_input(_action_event("menu"))
	assert_true(menu.visible, "First menu action must open MenuPanel.")
	assert_true(get_tree().paused, "Opening the menu must pause the tree.")

	hud._unhandled_input(_action_event("menu"))
	assert_false(menu.visible, "Second menu action must close MenuPanel.")
	assert_false(get_tree().paused, "Closing the menu must unpause the tree.")


func test_resume_button_closes_menu_unpauses_and_emits_signal() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	hud._unhandled_input(_action_event("menu"))
	assert_true(get_tree().paused)

	watch_signals(hud)
	var buttons: Array[Button] = _buttons_under(hud.get_node("MenuPanel"))
	var resume: Button = buttons[0]
	assert_eq(resume.text, "继续")
	resume.pressed.emit()

	assert_signal_emitted(hud, "menu_resumed", "Resume press must emit menu_resumed.")
	assert_false((hud.get_node("MenuPanel") as Control).visible, "Resume must close MenuPanel.")
	assert_false(get_tree().paused, "Resume must unpause the tree.")


func test_help_button_toggles_help_text() -> void:
	var hud: Hud = _make_hud(_basic_payload())
	var help_text: Label = hud.get_node("MenuPanel/Content/HelpText") as Label
	var buttons: Array[Button] = _buttons_under(hud.get_node("MenuPanel"))
	var help_button: Button = buttons[1]
	assert_eq(help_button.text, "说明")

	assert_false(help_text.visible)
	help_button.pressed.emit()
	assert_true(help_text.visible, "说明 button must reveal the help text.")
	help_button.pressed.emit()
	assert_false(help_text.visible, "说明 button must hide the help text again.")


# ---------------------------------------------------------------- objective_for table

func test_objective_for_walks_progression_table() -> void:
	var flags: Dictionary = {}
	var buildings: Array = []
	var table: Array = []

	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "探索世界"])

	flags["event_event_prologue_landing_done"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "勘探琉砂海，采集星壤尘"])

	flags["event_event_first_mining_done"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "放置第一座锚块"])

	buildings.append("anchor_block")
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "建立锚居工坊"])

	buildings.append("anchor_workshop")
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "应对漂移群威胁"])

	flags["encounter_first_drift_won"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "做出驻地抉择"])

	flags["station_mode_seal"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "推进方法与政策抉择"])

	flags["approach_direct"] = true
	flags["policy_sanctuary"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "面对辉砂巨兽"])

	flags["encounter_leviathan_won"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "见证余辉结局"])

	flags["event_event_ending_luoxian_done"] = true
	table.append([_snap(flags.duplicate(true), buildings.duplicate()), "探索世界"])

	assert_eq(table.size(), 10, "Progression table must cover every milestone.")
	for row: Array in table:
		var snapshot: Dictionary = row[0] as Dictionary
		assert_eq(Hud.objective_for(snapshot), row[1], "objective_for must match the progression table.")


func test_objective_for_flags_due_encounters_as_immediate_threats() -> void:
	assert_eq(
		Hud.objective_for(_snap({"encounter_first_drift_due": true}, [])),
		"应对漂移群威胁",
		"Any due encounter must surface the threat objective."
	)
	assert_eq(
		Hud.objective_for(_snap({"encounter_leviathan_due": true}, [])),
		"面对辉砂巨兽",
		"A due leviathan encounter must surface the boss objective."
	)
	assert_eq(
		Hud.objective_for(_snap({"encounter_husk_ambush_due": true, "encounter_husk_ambush_won": true}, [])),
		"勘探琉砂海，采集星壤尘",
		"Already-won encounters must not resurface as threats and fall back to the progression chain."
	)


func test_objective_for_returns_fallback_for_empty_state() -> void:
	assert_eq(Hud.objective_for({}), "探索世界")
	assert_eq(Hud.objective_for({"revision": 0, "inventory": {}, "flags": {}, "placed_buildings": []}), "探索世界")
