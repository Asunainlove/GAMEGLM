extends GutTest

## VISUAL-REFACTOR-P2 engineering skeleton (P2-B): title LOGO / button-rail,
## inventory slot frames, battle track floor. Art not approved yet — probes
## graybox until drop-in under assets/art/ui/{title,inventory,battle}/.

const TITLE_SCENE_PATH: String = "res://scenes/title_screen.tscn"
const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"
const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"

var _temp_dir: String = ""
var _fake: FakeSnapshotProvider = null


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


func before_each() -> void:
	_temp_dir = "user://p2_skeleton_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_fake = null
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


func _load_title() -> Node:
	var packed: PackedScene = load(TITLE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	var title: Node = packed.instantiate()
	add_child_autofree(title)
	return title


func test_title_logo_and_btnrail_graybox_when_art_missing() -> void:
	var title: Node = _load_title()
	title.set("asset_base_dir", _temp_dir)
	title.call("apply_p2_art_hooks")
	var root: Control = title.get_node("%Root") as Control
	assert_true(bool(root.get_meta("logo_graybox")), "Missing UIA-TTL-LOGO → logo graybox.")
	assert_true(bool(root.get_meta("btnrail_graybox")), "Missing UIA-TTL-BTNRAIL → rail graybox.")
	var logo: TextureRect = title.get_node("%Logo") as TextureRect
	var logo_gray: ColorRect = title.get_node("%LogoGraybox") as ColorRect
	assert_false(logo.visible)
	assert_true(logo_gray.visible)
	var label: Label = title.get_node("%TitleLabel") as Label
	assert_true(label.visible, "Graybox keeps TitleLabel text identity.")
	assert_eq(label.text, "星壤：余辉纪元")
	var backdrop: TextureRect = title.get_node("Root/Backdrop") as TextureRect
	assert_eq(backdrop.texture.resource_path, "res://assets/art/ui/title/bg_title.png")
	var rail: TextureRect = title.get_node("%ButtonRailScrim") as TextureRect
	var rail_gray: ColorRect = title.get_node("%ButtonRailGraybox") as ColorRect
	assert_false(rail.visible)
	assert_true(rail_gray.visible)


func test_title_logo_and_btnrail_swap_on_drop_in() -> void:
	_write_png("ui/title", "uia_ttl_logo.png", Vector2i(64, 32), Color(1, 0.8, 0.2))
	_write_png("ui/title", "uia_ttl_btnrail.png", Vector2i(32, 32), Color(0.05, 0.08, 0.12))
	var title: Node = _load_title()
	title.set("asset_base_dir", _temp_dir)
	title.call("apply_p2_art_hooks")
	var root: Control = title.get_node("%Root") as Control
	assert_false(bool(root.get_meta("logo_graybox")))
	assert_false(bool(root.get_meta("btnrail_graybox")))
	var logo: TextureRect = title.get_node("%Logo") as TextureRect
	assert_true(logo.visible)
	assert_not_null(logo.texture)
	var label: Label = title.get_node("%TitleLabel") as Label
	assert_false(label.visible, "Real LOGO replaces Label as sole identity.")
	var rail: TextureRect = title.get_node("%ButtonRailScrim") as TextureRect
	assert_true(rail.visible)
	assert_not_null(rail.texture)


func test_hud_inventory_slots_graybox_frames() -> void:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {
		"revision": 1,
		"inventory": {"starsoil_dust": 3, "lumen_shard": 1},
		"flags": {},
		"placed_buildings": [],
	}
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	var hud: Hud = scene.instantiate() as Hud
	hud.snapshot_provider = _fake.get_snapshot
	hud.asset_base_dir = _temp_dir
	add_child_autofree(hud)
	hud.refresh()
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	assert_eq(bar.get_child_count(), 2)
	for child: Node in bar.get_children():
		assert_true(str(child.name).begins_with("Slot_"))
		assert_true(bool(child.get_meta("inv_slot_graybox")), "No uia_inv_slot → graybox frame.")
		assert_not_null(child.get_node_or_null("Frame"))


func test_hud_inventory_slots_swap_on_drop_in() -> void:
	_write_png("ui/inventory", "uia_inv_slot.png", Vector2i(48, 48), Color(0.2, 0.2, 0.25))
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {
		"revision": 1,
		"inventory": {"starsoil_dust": 1},
		"flags": {},
		"placed_buildings": [],
	}
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	var hud: Hud = scene.instantiate() as Hud
	hud.snapshot_provider = _fake.get_snapshot
	hud.asset_base_dir = _temp_dir
	add_child_autofree(hud)
	hud.refresh()
	var slot: Control = hud.get_node("InventoryBar").get_child(0) as Control
	assert_false(bool(slot.get_meta("inv_slot_graybox")))
	var frame: TextureRect = slot.get_node("Frame") as TextureRect
	assert_not_null(frame)
	assert_not_null(frame.texture)


func test_battle_track_floor_graybox_then_drop_in() -> void:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	var battle: Node2D = packed.instantiate() as Node2D
	battle.set("asset_base_dir", _temp_dir)
	add_child_autofree(battle)
	# Force rebuild path without full encounter: call ensure via _rebuild_tracks internals.
	battle.call("_rebuild_tracks")
	var floor_root: Node2D = battle.get_node("Tracks/TrackFloor") as Node2D
	assert_not_null(floor_root, "Tracks/TrackFloor hook must exist.")
	assert_true(bool(floor_root.get_meta("track_floor_graybox")))
	var gray: ColorRect = floor_root.get_node("Graybox") as ColorRect
	assert_true(gray.visible)
	_write_png("ui/battle", "uia_bat_tracks.png", Vector2i(64, 32), Color(0.3, 0.25, 0.2))
	battle.call("_rebuild_tracks")
	assert_false(bool(floor_root.get_meta("track_floor_graybox")))
	var sprite: Sprite2D = floor_root.get_node("Floor") as Sprite2D
	assert_true(sprite.visible)
	assert_not_null(sprite.texture)


func test_no_new_styleboxflat_chrome_on_p2_hooks() -> void:
	var title: Node = _load_title()
	var rail_host: Control = title.get_node("Root/Layout/ButtonRailHost") as Control
	assert_false(rail_host is PanelContainer, "Button rail must not introduce Panel StyleBoxFlat chrome.")
	var logo_slot: Control = title.get_node("Root/Layout/LogoSlot") as Control
	assert_false(logo_slot is PanelContainer)
