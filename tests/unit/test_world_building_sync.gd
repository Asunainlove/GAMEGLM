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
	assert_true(bool(node.get_meta("graybox")), "Missing ENV-21 art must fall back to visible graybox.")
	assert_true(bool(node.get_meta("powered")), "anchor_block supply building uses powered skin.")
	var graybox: ColorRect = node.get_node("Graybox") as ColorRect
	assert_not_null(graybox)
	assert_true(graybox.visible)


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
	var graybox: ColorRect = refiner.get_node("Graybox") as ColorRect
	assert_eq(graybox.color, BuildingPresenter.GRAYBOX_UNPOWERED)
