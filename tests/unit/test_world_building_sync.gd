extends GutTest

## P0-B：World `$Buildings` sync from placed_buildings + powered/unpowered skin.

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const PRESENTER_SCRIPT: Script = preload("res://src/world/building_presenter.gd")

var _snapshot_store: SnapshotStore
var _defs_host: DefsHost


class SnapshotStore:
	var data: Dictionary = {}

	func _init(initial_data: Dictionary) -> void:
		data = initial_data

	func snapshot() -> Dictionary:
		return data.duplicate(true)


class DefsHost:
	var defs: Dictionary = {
		"anchor_block": {"power_draw": 0, "power_supply": 2, "requires_room": false},
		"dust_refiner": {"power_draw": 4, "power_supply": 0, "requires_room": false},
	}

	func get_defs() -> Dictionary:
		return defs


func _instantiate_world(payload: Dictionary) -> Node2D:
	var scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "world.tscn must load.")
	var world: Node2D = scene.instantiate() as Node2D
	_snapshot_store = SnapshotStore.new(payload)
	_defs_host = DefsHost.new()
	world.set("player_scene_path", "")
	world.set("snapshot_provider", Callable(_snapshot_store, "snapshot"))
	world.set("building_defs_provider", Callable(_defs_host, "get_defs"))
	add_child_autofree(world)
	return world


func test_presenter_instance_key_and_cell_center() -> void:
	var entry := {"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 2, "cell_y": 3}
	assert_eq(BuildingPresenter.instance_key(entry), "chunk_0_0|2|3")
	assert_eq(BuildingPresenter.cell_center_pixels(entry), Vector2(80, 112))


func test_presenter_powered_map_marks_unpowered_draw_buildings() -> void:
	var buildings: Array = [
		{"building_id": "dust_refiner", "chunk_id": "chunk_0_0", "cell_x": 1, "cell_y": 1},
		{"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 2, "cell_y": 1},
	]
	var defs := {
		"anchor_block": {"power_draw": 0, "power_supply": 2, "requires_room": false},
		"dust_refiner": {"power_draw": 4, "power_supply": 0, "requires_room": false},
	}
	# Alone: refiner has no supply → unpowered; with adjacent anchor supply=2 ≥ draw=4? No, supply 2 < 4.
	var powered := BuildingPresenter.powered_by_instance(buildings, defs)
	assert_false(bool(powered["chunk_0_0|1|1"]), "Refiner must be unpowered when supply < draw.")
	assert_true(bool(powered["chunk_0_0|2|1"]), "Supply building always uses powered skin.")


func test_world_syncs_placed_buildings_into_buildings_node() -> void:
	var world: Node2D = _instantiate_world({
		"revision": 1,
		"world_seed": 0,
		"chunk_deltas": {},
		"placed_buildings": [
			{"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 4, "cell_y": 5},
		],
		"flags": {},
	})
	world.call("refresh_from_snapshot")
	var buildings: Node2D = world.get_node("Buildings") as Node2D
	assert_eq(buildings.get_child_count(), 1, "One placed building must spawn one presentation node.")
	var node: Node2D = buildings.get_child(0) as Node2D
	assert_eq(str(node.name), "chunk_0_0|4|5")
	assert_eq(node.position, Vector2(144, 176))
	# Tip 4e1dc6d ships ENV-21..26 — expect real sprites, not graybox.
	assert_false(bool(node.get_meta("graybox")), "Production env_bld art must replace graybox.")
	assert_true(bool(node.get_meta("powered")), "anchor_block supply building uses powered skin.")
	var sprite: Sprite2D = node.get_node("Sprite") as Sprite2D
	assert_not_null(sprite)
	assert_true(sprite.visible)
	assert_not_null(sprite.texture)


func test_world_despawns_removed_buildings_and_swaps_power_skin() -> void:
	var world: Node2D = _instantiate_world({
		"revision": 1,
		"world_seed": 0,
		"chunk_deltas": {},
		"placed_buildings": [
			{"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 4, "cell_y": 3},
			{"building_id": "dust_refiner", "chunk_id": "chunk_0_0", "cell_x": 3, "cell_y": 3},
		],
		"flags": {},
	})
	# Boost supply so refiner can power: use workshop-scale supply in defs.
	_defs_host.defs["anchor_block"] = {"power_draw": 0, "power_supply": 16, "requires_room": false}
	world.call("refresh_from_snapshot")
	var buildings: Node2D = world.get_node("Buildings") as Node2D
	assert_eq(buildings.get_child_count(), 2)
	var refiner: Node2D = buildings.get_node("chunk_0_0|3|3") as Node2D
	assert_true(bool(refiner.get_meta("powered")), "Refiner should be powered with supply 16.")

	_snapshot_store.data = {
		"revision": 2,
		"world_seed": 0,
		"chunk_deltas": {},
		"placed_buildings": [
			{"building_id": "dust_refiner", "chunk_id": "chunk_0_0", "cell_x": 3, "cell_y": 3},
		],
		"flags": {},
	}
	world.call("refresh_from_snapshot")
	assert_eq(buildings.get_child_count(), 1, "Removed buildings must despawn.")
	refiner = buildings.get_node("chunk_0_0|3|3") as Node2D
	assert_false(bool(refiner.get_meta("powered")), "Alone refiner must swap to unpowered skin.")
	assert_false(bool(refiner.get_meta("graybox")), "Unpowered skin still uses real env_bld_unpowered art.")
	var sprite: Sprite2D = refiner.get_node("Sprite") as Sprite2D
	assert_not_null(sprite.texture)

func test_presenter_prefers_env_bld_contract_art_over_graybox() -> void:
	var temp := "user://p0b_env_bld_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(temp.path_join("world/buildings"))
	var image := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.4, 1.0))
	assert_eq(
		image.save_png(temp.path_join("world/buildings/env_bld_anchor_block_powered.png")),
		OK
	)
	var presenter: BuildingPresenter = PRESENTER_SCRIPT.new()
	presenter.asset_base_dir = temp
	var texture := presenter.probe_texture("anchor_block", true)
	assert_not_null(texture, "Must resolve env_bld_anchor_block_powered.png")
	var parent := Node2D.new()
	add_child_autofree(parent)
	presenter.building_defs = {
		"anchor_block": {"power_draw": 0, "power_supply": 2, "requires_room": false},
	}
	presenter.sync(parent, [
		{"building_id": "anchor_block", "chunk_id": "chunk_0_0", "cell_x": 1, "cell_y": 1},
	])
	var node: Node2D = parent.get_child(0) as Node2D
	assert_false(bool(node.get_meta("graybox")), "Contract art must replace graybox.")
	assert_true((node.get_node("Sprite") as Sprite2D).visible)
	_remove_dir_recursive(temp)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func test_production_env_bld_assets_resolve_for_all_six_buildings() -> void:
	var ids: Array[String] = [
		"anchor_block", "anchor_workshop", "dust_refiner",
		"stabilizer_pylon", "resonance_loom", "echo_chamber",
	]
	var presenter: BuildingPresenter = PRESENTER_SCRIPT.new()
	presenter.asset_base_dir = BuildingPresenter.DEFAULT_ASSET_BASE_DIR
	for building_id: String in ids:
		var powered := presenter.probe_texture(building_id, true)
		var unpowered := presenter.probe_texture(building_id, false)
		assert_not_null(powered, "Missing powered art for %s" % building_id)
		assert_not_null(unpowered, "Missing unpowered art for %s" % building_id)

