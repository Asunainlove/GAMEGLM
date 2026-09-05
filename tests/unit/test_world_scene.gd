extends GutTest

## WP03 RED/GREEN smoke + behavior tests for scenes/world.tscn (contract section 4).

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")
const DEFAULT_WORLD_SEED: int = 0
const RENDERED_CHUNK_ID: String = "chunk_0_0"
const GRID_CHUNK_IDS: Array[String] = [
	"chunk_0_0",
	"chunk_1_0",
	"chunk_2_0",
	"chunk_3_0",
	"chunk_0_1",
	"chunk_1_1",
	"chunk_2_1",
	"chunk_3_1",
]

var world_scene: PackedScene
var _snapshot_store: SnapshotStore


class SnapshotStore:
	## Minimal injectable snapshot provider double for presentation-layer tests.
	var data: Dictionary = {}

	func _init(initial_data: Dictionary) -> void:
		data = initial_data

	func snapshot() -> Dictionary:
		return data.duplicate(true)


func before_each() -> void:
	world_scene = load(WORLD_SCENE_PATH) as PackedScene
	if world_scene == null:
		fail_test("res://scenes/world.tscn must exist and load.")


func _instantiate_world(player_scene_path: String = "") -> Node2D:
	if world_scene == null:
		return null
	var world: Node2D = world_scene.instantiate() as Node2D
	if world == null:
		fail_test("world.tscn must instantiate to a Node2D root.")
		return null
	if player_scene_path != "":
		world.set("player_scene_path", player_scene_path)
	_snapshot_store = SnapshotStore.new({
		"revision": 0,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {},
	})
	world.set("snapshot_provider", Callable(_snapshot_store, "snapshot"))
	add_child_autofree(world)
	return world


func _ore_cell(cells: Dictionary, ore_type: String = "") -> Vector2i:
	for cell: Vector2i in cells:
		if ore_type == "" or cells[cell] == ore_type:
			return cell
	fail_test("No cell of type '%s' available in fixture chunk." % ore_type)
	return Vector2i(-1, -1)


func _child_named(world: Node, child_name: String) -> Node:
	for child: Node in world.get_children():
		if child.name == child_name:
			return child
	return null


func test_world_scene_matches_module_contract_section_4() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	assert_eq(world.name, "World")
	assert_true(world is Node2D, "World root must be a Node2D.")
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var decals: Node2D = world.get_node("Decals") as Node2D
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var buildings: Node2D = world.get_node("Buildings") as Node2D
	var player_spawn: Marker2D = world.get_node("PlayerSpawn") as Marker2D
	assert_not_null(ground, "Ground must be a TileMapLayer.")
	assert_not_null(decals, "Decals must be a Node2D (visual soil density).")
	assert_not_null(ore_overlay, "OreOverlay must be a TileMapLayer.")
	assert_not_null(buildings, "Buildings must be a Node2D.")
	assert_not_null(player_spawn, "PlayerSpawn must be a Marker2D.")
	if player_spawn != null:
		assert_eq(player_spawn.position, Vector2(64, 64))


func test_world_builds_runtime_tileset_and_renders_initial_chunk() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	assert_not_null(ground.tile_set, "Ground must receive a runtime-built TileSet.")
	assert_not_null(ore_overlay.tile_set, "OreOverlay must receive a runtime-built TileSet.")
	# W002-GAP3：world._ready 现在渲染全部 8 个 chunk（8 x 32 x 32 = 8192 格），
	# 原断言 1024 只覆盖 chunk_0_0，随 GAP3 全量渲染合法更新。
	assert_eq(
		ground.get_used_cells().size(),
		8192,
		"All 8 chunks must be fully rendered at ready (8 x 1024 cells)."
	)
	assert_gt(ore_overlay.get_used_cells().size(), 0, "chunk_0_0 ore veins must be rendered.")


func test_world_generates_full_4x2_chunk_grid() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ids: Array = world.call("chunk_ids")
	assert_eq(ids.size(), 8, "World must generate the 4x2 chunk grid.")
	for chunk_id: String in GRID_CHUNK_IDS:
		assert_has(ids, chunk_id, "Missing grid chunk: %s" % chunk_id)


func test_cell_def_at_matches_chunk_data_contract() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDERED_CHUNK_ID, DEFAULT_WORLD_SEED)["cells"]

	var ore_cell: Vector2i = _ore_cell(cells, "ore_core")
	assert_eq(
		world.call("cell_def_at", RENDERED_CHUNK_ID, ore_cell),
		CHUNK_DATA_SCRIPT.cell_def(cells, ore_cell),
		"cell_def_at must agree with ChunkData.cell_def for generated chunks."
	)

	var soil_cell := Vector2i(0, -1)
	assert_eq(
		world.call("cell_def_at", RENDERED_CHUNK_ID, soil_cell),
		CHUNK_DATA_SCRIPT.cell_def(cells, soil_cell),
		"Non-ore cells must map to the soil def."
	)
	assert_eq(
		world.call("cell_def_at", "chunk_9_9", soil_cell)["type"],
		"soil",
		"Unknown chunks must degrade to soil, not crash."
	)


func test_missing_player_scene_is_skipped_with_warning_not_crash() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	assert_true(is_instance_valid(world), "World must stay alive when player.tscn is absent.")
	if not ResourceLoader.exists("res://scenes/player.tscn"):
		assert_null(
			_child_named(world, "Player"),
			"Missing player scene must not spawn a player node."
		)


func test_injectable_player_scene_path_handles_missing_resource() -> void:
	var world: Node2D = _instantiate_world("res://scenes/does_not_exist_player.tscn")
	if world == null:
		return
	assert_null(_child_named(world, "Player"))
	assert_true(is_instance_valid(world))


func test_refresh_from_snapshot_with_injected_store_erases_destroyed_cells() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDERED_CHUNK_ID, DEFAULT_WORLD_SEED)["cells"]
	var destroyed_cell: Vector2i = _ore_cell(cells, "ore_dust")
	var surviving_cell: Vector2i = _ore_cell(cells, "ore_shard")

	var store: SnapshotStore = SnapshotStore.new({
		"revision": 5,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {
			RENDERED_CHUNK_ID: [
				{"cell_x": destroyed_cell.x, "cell_y": destroyed_cell.y, "destroyed": true},
			],
		},
	})
	world.set("snapshot_provider", Callable(store, "snapshot"))

	assert_eq(ore_overlay.get_cell_source_id(destroyed_cell), WorldRenderer.SOURCE_ORE_DUST)
	world.call("refresh_from_snapshot")

	assert_eq(
		ground.get_cell_source_id(destroyed_cell),
		-1,
		"refresh_from_snapshot must erase destroyed cells from Ground."
	)
	assert_eq(
		ore_overlay.get_cell_source_id(destroyed_cell),
		-1,
		"refresh_from_snapshot must erase destroyed cells from OreOverlay."
	)
	assert_eq(
		ore_overlay.get_cell_source_id(surviving_cell),
		WorldRenderer.SOURCE_ORE_SHARD,
		"Surviving ore cells must stay rendered."
	)


func test_snapshot_poll_timer_applies_new_revision_deltas() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDERED_CHUNK_ID, DEFAULT_WORLD_SEED)["cells"]
	var destroyed_cell: Vector2i = _ore_cell(cells, "ore_core")

	var store: SnapshotStore = SnapshotStore.new({
		"revision": 1,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {
			RENDERED_CHUNK_ID: [
				{"cell_x": destroyed_cell.x, "cell_y": destroyed_cell.y, "destroyed": true},
			],
		},
	})
	world.set("snapshot_provider", Callable(store, "snapshot"))

	var timer: Timer = world.get_node("SnapshotPollTimer") as Timer
	assert_not_null(timer, "World must poll the snapshot on a Timer.")
	if timer != null:
		assert_eq(timer.wait_time, 0.5, "Poll interval must follow the 0.5s contract.")
		assert_false(ore_overlay.get_cell_source_id(destroyed_cell) == -1)
		timer.timeout.emit()
		assert_eq(
			ore_overlay.get_cell_source_id(destroyed_cell),
			-1,
			"Polling a higher revision must erase newly destroyed cells."
		)


func test_toggle_overlay_action_flips_ore_overlay_visibility() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	assert_true(ore_overlay.visible, "Ore overlay starts visible.")

	var press: InputEventAction = InputEventAction.new()
	press.action = "toggle_overlay"
	press.pressed = true
	world._unhandled_input(press)
	assert_false(ore_overlay.visible, "toggle_overlay press must hide the overlay.")
	world._unhandled_input(press)
	assert_true(ore_overlay.visible, "Second toggle_overlay press must show the overlay.")

	var unrelated: InputEventAction = InputEventAction.new()
	unrelated.action = "menu"
	unrelated.pressed = true
	world._unhandled_input(unrelated)
	assert_true(ore_overlay.visible, "Unrelated actions must not flip the overlay.")


func test_world_places_sparse_soil_decals_when_art_present() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var decals: Node2D = world.get_node("Decals") as Node2D
	assert_not_null(decals)
	# Art lands on main (#31); production base dir should yield sparse sprites.
	assert_gt(decals.get_child_count(), 0, "Decals layer should receive sparse soil sprites.")
	var renderer: Node = world.get_node_or_null("WorldRenderer")
	assert_not_null(renderer)
	if renderer != null:
		var report: Dictionary = renderer.get("last_decal_report")
		assert_gt(int(report.get("placed", 0)), 0)
		var by_kind: Dictionary = report.get("by_kind", {})
		assert_true(by_kind.has("damage") or by_kind.has("ore_fleck"), "Expected damage/fleck kinds.")

