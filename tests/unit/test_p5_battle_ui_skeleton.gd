extends GutTest

## VISUAL-REFACTOR-P5: battle action icons + banner skins.
## Production tip binds REAL P5-A art (#73); user:// inject still covers graybox fallback.

const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"

var _temp_dir: String = ""


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


func before_each() -> void:
	_temp_dir = "user://p5_battle_ui_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir_recursive(_temp_dir)
	_temp_dir = ""


func _write_png(rel_dir: String, file_name: String, size: Vector2i, color: Color) -> void:
	var dir := _temp_dir.path_join(rel_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	assert_eq(image.save_png(dir.path_join(file_name)), OK)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		if dir.current_is_dir():
			_remove_dir_recursive(path.path_join(entry))
		else:
			DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	DirAccess.remove_absolute(path)


func _make_scene() -> Node2D:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	var scene: Node2D = packed.instantiate() as Node2D
	scene.set("store", null)
	scene.set("engine_script", StubEngine)
	scene.set("asset_base_dir", _temp_dir)
	add_child_autofree(scene)
	return scene


func _ally_battle() -> Dictionary:
	return {
		"id": "p5_probe",
		"turn": 1,
		"finished": false,
		"result": "",
		"order": ["a0|hero"],
		"active_index": 0,
		"units": [
			{
				"key": "a0|hero",
				"unit_id": "probe_hero",
				"side": "ally",
				"kind": "ally",
				"track": "front",
				"name_zh": "探针",
				"hp": 10,
				"max_hp": 10,
				"alive": true,
				"action_ids": ["strike", "guard", "mist_calm"],
			}
		],
		"action_defs": {
			"strike": {"name_zh": "破尘击", "kind": "attack", "targeting": "single_enemy"},
			"guard": {"name_zh": "定锚式", "kind": "guard", "targeting": "self"},
			"mist_calm": {"name_zh": "定神雾息", "kind": "item", "targeting": "single_ally"},
		},
		"log": [],
	}


func test_banner_skins_graybox_when_art_missing() -> void:
	var scene: Node2D = _make_scene()
	scene.call("apply_p5_banner_hooks")
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	assert_true(bool(ui.get_meta("phase_banner_graybox")), "Missing uia_bat_bnr_phase → graybox.")
	assert_true(bool(ui.get_meta("turn_banner_graybox")), "Missing uia_bat_bnr_turn → graybox.")
	var phase_skin: TextureRect = ui.get_node("PhaseBannerSkin") as TextureRect
	var round_skin: TextureRect = ui.get_node("RoundBannerSkin") as TextureRect
	assert_not_null(phase_skin)
	assert_not_null(round_skin)
	assert_true(phase_skin.texture == null)
	assert_true(round_skin.texture == null)
	var finish: Control = ui.get_node("FinishBanner") as Control
	assert_true(bool(finish.get_meta("finish_banner_graybox")), "Finish banner starts graybox.")
	assert_false(finish.has_theme_stylebox_override("panel"), "Graybox keeps theme PanelDimOverlay.")


func test_banner_skins_swap_on_drop_in() -> void:
	_write_png("ui/battle", "uia_bat_bnr_phase.png", Vector2i(96, 48), Color(0.85, 0.15, 0.15))
	_write_png("ui/battle", "uia_bat_bnr_turn.png", Vector2i(64, 32), Color(0.05, 0.08, 0.12))
	_write_png("ui/battle", "uia_bat_bnr_result_victory.png", Vector2i(96, 48), Color(0.91, 0.78, 0.47))
	var scene: Node2D = _make_scene()
	scene.call("apply_p5_banner_hooks")
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	assert_false(bool(ui.get_meta("phase_banner_graybox")))
	assert_false(bool(ui.get_meta("turn_banner_graybox")))
	var phase_skin: TextureRect = ui.get_node("PhaseBannerSkin") as TextureRect
	assert_not_null(phase_skin.texture)
	scene.call("_show_finish_banner", "victory")
	var finish: Control = ui.get_node("FinishBanner") as Control
	assert_false(bool(finish.get_meta("finish_banner_graybox")))
	var banner_skin: TextureRect = finish.get_node("BannerSkin") as TextureRect
	assert_not_null(banner_skin.texture)
	assert_true(banner_skin.visible)
	var plate: Panel = finish.get_node_or_null("BannerPlate") as Panel
	assert_not_null(plate)
	assert_true(plate.visible)
	var style: StyleBox = plate.get_theme_stylebox("panel")
	assert_true(style is StyleBoxTexture, "Result art binds StyleBoxTexture plate.")


func test_action_icons_graybox_then_drop_in() -> void:
	StubEngine.battle_template = _ally_battle()
	var scene: Node2D = _make_scene()
	scene.call("begin_encounter", {"id": "p5_probe"}, {})
	var box: VBoxContainer = scene.get_node("UI/ActionsBox") as VBoxContainer
	assert_gt(box.get_child_count(), 0, "Ally actions must render buttons.")
	assert_true(bool(box.get_meta("action_icons_graybox")), "Missing icons → graybox text buttons.")
	for child: Node in box.get_children():
		var button := child as Button
		assert_not_null(button)
		assert_true(button.icon == null, "Graybox buttons have no icon texture.")

	_write_png("ui/battle", "uia_bat_ico_attack.png", Vector2i(16, 16), Color(0.91, 0.78, 0.47))
	_write_png("ui/battle", "uia_bat_ico_guard.png", Vector2i(16, 16), Color(0.42, 0.79, 0.72))
	_write_png("ui/battle", "uia_bat_ico_item.png", Vector2i(16, 16), Color(0.86, 0.90, 0.92))
	scene.call("_refresh_actions")
	assert_false(bool(box.get_meta("action_icons_graybox")))
	var icons_bound := 0
	for child2: Node in box.get_children():
		var btn := child2 as Button
		if btn != null and btn.icon != null:
			icons_bound += 1
	assert_eq(icons_bound, 3, "Attack/guard/item icons bind on drop-in.")


func test_production_binds_real_p5_art() -> void:
	# Default res://assets/art after #73 — action icons + banner skins REAL.
	StubEngine.battle_template = _ally_battle()
	var scene: Node2D = _make_scene()
	scene.set("asset_base_dir", "res://assets/art")
	scene.call("apply_p5_banner_hooks")
	var ui: CanvasLayer = scene.get_node("UI") as CanvasLayer
	assert_false(bool(ui.get_meta("phase_banner_graybox")), "Production must bind uia_bat_bnr_phase (#73).")
	assert_false(bool(ui.get_meta("turn_banner_graybox")), "Production must bind uia_bat_bnr_turn (#73).")
	var phase_skin: TextureRect = ui.get_node("PhaseBannerSkin") as TextureRect
	var round_skin: TextureRect = ui.get_node("RoundBannerSkin") as TextureRect
	assert_not_null(phase_skin.texture)
	assert_not_null(round_skin.texture)
	for asset_id: String in [
		"uia_bat_ico_attack",
		"uia_bat_ico_guard",
		"uia_bat_ico_item",
		"uia_bat_bnr_phase",
		"uia_bat_bnr_turn",
		"uia_bat_bnr_result",
		"uia_bat_bnr_result_victory",
		"uia_bat_bnr_result_defeat",
	]:
		var path := "res://assets/art/ui/battle/%s.png" % asset_id
		assert_true(
			FileAccess.file_exists(path),
			"P5-A art must be present on tip: %s" % path
		)
	scene.call("begin_encounter", {"id": "p5_probe"}, {})
	var box: VBoxContainer = scene.get_node("UI/ActionsBox") as VBoxContainer
	assert_false(bool(box.get_meta("action_icons_graybox")), "Production must bind action icons (#73).")
	var icons_bound := 0
	for child: Node in box.get_children():
		var btn := child as Button
		if btn != null and btn.icon != null:
			icons_bound += 1
	assert_eq(icons_bound, 3, "Attack/guard/item icons bound on production tip.")
	scene.call("_show_finish_banner", "victory")
	var finish: Control = ui.get_node("FinishBanner") as Control
	assert_false(bool(finish.get_meta("finish_banner_graybox")), "Production must bind result victory banner.")
	var banner_skin: TextureRect = finish.get_node("BannerSkin") as TextureRect
	assert_not_null(banner_skin.texture)
	assert_true(banner_skin.visible)
	# Track floor from P2 remains real.
	assert_true(FileAccess.file_exists("res://assets/art/ui/battle/uia_bat_tracks.png"))


func test_finish_banner_keeps_theme_dim_when_graybox() -> void:
	var scene: Node2D = _make_scene()
	scene.call("_show_finish_banner", "defeat")
	var finish: PanelContainer = scene.get_node("UI/FinishBanner") as PanelContainer
	assert_true(finish.visible)
	assert_true(bool(finish.get_meta("finish_banner_graybox")))
	assert_eq(str(finish.theme_type_variation), "PanelDimOverlay")
	assert_false(finish.has_theme_stylebox_override("panel"))
	var label: Label = finish.get_node("FinishLabel") as Label
	assert_eq(label.text, "败北……")
