extends GutTest

## VISUAL-REFACTOR-P4: startup ColorRect stack → themed Panel; battle unit
## graybox flash → invisible placeholder when probe misses.

const APP_SCENE_PATH: String = "res://scenes/app.tscn"
const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"


class StubEngine:
	static var battle_template: Dictionary = {}

	static func create_battle(_config: Dictionary) -> Dictionary:
		return battle_template.duplicate(true)

	static func submit_action(
			battle: Dictionary, _unit_key: String, _action_id: String, _target_key: String
	) -> Dictionary:
		return battle.duplicate(true)

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


func test_startup_screen_is_themed_panel_not_colorrect_stack() -> void:
	var packed: PackedScene = load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	add_child_autofree(app)
	var startup: Node = app.get_node_or_null("UILayer/StartupScreen")
	assert_not_null(startup, "StartupScreen must exist.")
	assert_true(startup is PanelContainer, "P4: StartupScreen must be PanelContainer (not ColorRect).")
	assert_false(startup is ColorRect, "P4: bare ColorRect StartupScreen is banned.")
	if startup is PanelContainer:
		var style: StyleBox = (startup as PanelContainer).get_theme_stylebox("panel")
		assert_not_null(style, "StartupScreen must carry tokenised StyleBox panel.")
		assert_true(style is StyleBoxFlat, "Scrim uses tokenised StyleBoxFlat (StarsoilTokens.BG_DEEP α).")
		if style is StyleBoxFlat:
			var flat := style as StyleBoxFlat
			assert_almost_eq(flat.bg_color.r, 0.043, 0.01)
			assert_almost_eq(flat.bg_color.g, 0.067, 0.01)
			assert_almost_eq(flat.bg_color.b, 0.11, 0.01)
	var rule: Node = app.get_node_or_null("UILayer/StartupScreen/Layout/Rule")
	assert_not_null(rule, "Startup rule hairline must exist.")
	assert_true(rule is Panel, "P4: Rule must be Panel (not ColorRect).")
	assert_false(rule is ColorRect, "P4: bare ColorRect Rule is banned.")
	# No ColorRect descendants under StartupScreen.
	var color_rects: Array = []
	_collect_color_rects(startup, color_rects)
	assert_eq(color_rects.size(), 0, "P4: StartupScreen subtree must have zero ColorRect nodes.")
	var title: Label = app.get_node_or_null("UILayer/StartupScreen/Layout/Title") as Label
	assert_not_null(title)
	if title != null:
		assert_eq(title.text, "星壤：余辉纪元")


func test_battle_missing_assets_use_invisible_box_not_colored_brick() -> void:
	var temp := "user://p4_battle_graybox_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(temp)
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		_rm(temp)
		return
	var scene: Node2D = packed.instantiate() as Node2D
	add_child_autofree(scene)
	scene.set("store", null)
	scene.set("engine_script", StubEngine)
	scene.set("asset_base_dir", temp)
	StubEngine.battle_template = {
		"id": "p4_probe",
		"turn": 1,
		"units": [
			{
				"key": "a0|probe",
				"unit_id": "probe_unit",
				"side": "ally",
				"kind": "ally",
				"track": "front",
				"name_zh": "探针",
				"hp": 10,
				"max_hp": 10,
				"destabilized": false,
				"guard_ratio": 0.0,
				"action_ids": [],
			}
		],
		"order": ["a0|probe"],
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"action_defs": {},
	}
	scene.call("begin_encounter", {"id": "p4_probe"}, {})
	var unit: Node2D = scene.get_node_or_null("Tracks/Row_front/a0_probe") as Node2D
	assert_not_null(unit)
	if unit == null:
		_rm(temp)
		return
	assert_null(unit.get_node_or_null("Sprite"), "Empty inject dir → no Sprite.")
	var box: ColorRect = unit.get_node_or_null("Box") as ColorRect
	assert_not_null(box, "Placeholder Box remains for structure.")
	if box != null:
		assert_false(box.visible, "P4 acceptance: no unit graybox flash.")
		assert_eq(box.color.a, 0.0)
	assert_true(bool(unit.get_meta("unit_box_invisible", false)))
	_rm(temp)


func test_production_wired_units_have_sprite_not_box() -> void:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var scene: Node2D = packed.instantiate() as Node2D
	add_child_autofree(scene)
	scene.set("store", null)
	scene.set("engine_script", StubEngine)
	scene.set("asset_base_dir", "res://assets/art")
	StubEngine.battle_template = {
		"id": "p4_wire",
		"turn": 1,
		"units": [
			{
				"key": "a0|luoxian_fighter",
				"unit_id": "luoxian_fighter",
				"side": "ally",
				"kind": "ally",
				"track": "front",
				"name_zh": "洛弦",
				"hp": 30,
				"max_hp": 30,
				"destabilized": false,
				"guard_ratio": 0.0,
				"action_ids": ["strike"],
			}
		],
		"order": ["a0|luoxian_fighter"],
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"action_defs": {"strike": {"id": "strike", "name_zh": "破尘击"}},
	}
	scene.call("begin_encounter", {"id": "p4_wire"}, {})
	var unit: Node2D = scene.get_node_or_null("Tracks/Row_front/a0_luoxian_fighter") as Node2D
	assert_not_null(unit)
	if unit == null:
		return
	assert_not_null(unit.get_node_or_null("Sprite") as AnimatedSprite2D, "Production luoxian must be Sprite.")
	assert_null(unit.get_node_or_null("Box"), "Wired unit must not keep Box.")


func _collect_color_rects(node: Node, out: Array) -> void:
	if node is ColorRect:
		out.append(node)
	for child in node.get_children():
		_collect_color_rects(child, out)


func _rm(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				_rm(path.path_join(entry))
			else:
				DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	DirAccess.remove_absolute(path)
