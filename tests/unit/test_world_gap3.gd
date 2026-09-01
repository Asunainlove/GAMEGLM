extends GutTest

## W002-GAP3 RED/GREEN tests: multi-chunk world rendering, cross-chunk delta
## sync, world boundary walls, camera viewport, and saved player start position.

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")
const DEFAULT_WORLD_SEED: int = 0
const WORLD_PIXEL_SIZE: Vector2i = Vector2i(4096, 2048)
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
## 测试存根必须保存在实例字段：Callable 只持 ObjectID，临时 RefCounted 会被
## 立即释放导致 snapshot_provider 失效、world 静默回退 GameState autoload。
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


func _instantiate_world(initial_data: Dictionary = {}) -> Node2D:
	if world_scene == null:
		return null
	var world: Node2D = world_scene.instantiate() as Node2D
	if world == null:
		fail_test("world.tscn must instantiate to a Node2D root.")
		return null
	var data := initial_data
	if data.is_empty():
		data = {
			"revision": 0,
			"world_seed": DEFAULT_WORLD_SEED,
			"chunk_deltas": {},
		}
	_snapshot_store = SnapshotStore.new(data)
	world.set("snapshot_provider", Callable(_snapshot_store, "snapshot"))
	add_child_autofree(world)
	return world


func _ore_cell(chunk_id: String, ore_type: String) -> Vector2i:
	# W002-GAP2 合法断言更新：chunk_3_1 为手工 authored 矿井布局，实况矿格须取自
	# 布局数据（DLX-5：generate_authored + 外置 world_config 布局，程序 generate
	# 已不代表该 chunk）。
	var cells: Dictionary = {}
	if chunk_id == "chunk_3_1":
		cells = CHUNK_DATA_SCRIPT.generate_authored(
			chunk_id, WorldConfig.layout_for_chunk(chunk_id))["cells"]
	else:
		cells = CHUNK_DATA_SCRIPT.generate(chunk_id, DEFAULT_WORLD_SEED)["cells"]
	for cell: Vector2i in cells:
		if cells[cell] == ore_type:
			return cell
	fail_test("Generated %s has no %s cell." % [chunk_id, ore_type])
	return Vector2i(-1, -1)


func _world_cell(chunk_id: String, local_cell: Vector2i) -> Vector2i:
	var parts: PackedStringArray = chunk_id.split("_", false)
	return local_cell + Vector2i(int(parts[1]), int(parts[2])) * CHUNK_DATA_SCRIPT.CHUNK_SIZE


func _player_node(world: Node2D) -> Node2D:
	for candidate: Node in world.find_children("*", "", true, false):
		if candidate.is_in_group("player"):
			return candidate as Node2D
	return null


# ---------------------------------------------------------------- 任务 1：多 chunk 渲染


func test_world_renders_all_eight_chunks_with_world_offsets() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	assert_eq(
		ground.get_used_cells().size(), 8192,
		"All 8 chunks must paint ground (8 x 32 x 32 = 8192 cells)."
	)
	for chunk_id: String in GRID_CHUNK_IDS:
		var local_cell: Vector2i = _ore_cell(chunk_id, "ore_dust")
		var world_cell: Vector2i = _world_cell(chunk_id, local_cell)
		assert_eq(
			ore_overlay.get_cell_source_id(world_cell), WorldRenderer.SOURCE_ORE_DUST,
			"%s ore at world cell %s must be rendered at its chunk origin offset." % [chunk_id, world_cell]
		)


func test_refresh_from_snapshot_syncs_destroyed_delta_in_nonzero_chunk() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var local_cell: Vector2i = _ore_cell("chunk_2_1", "ore_dust")
	var world_cell: Vector2i = _world_cell("chunk_2_1", local_cell)
	var intact_cell: Vector2i = _world_cell("chunk_0_0", _ore_cell("chunk_0_0", "ore_shard"))
	assert_eq(
		ore_overlay.get_cell_source_id(world_cell), WorldRenderer.SOURCE_ORE_DUST,
		"Precondition: chunk_2_1 ore must be painted before the delta arrives."
	)

	var store: SnapshotStore = SnapshotStore.new({
		"revision": 7,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {
			"chunk_2_1": [
				{"cell_x": world_cell.x, "cell_y": world_cell.y, "destroyed": true},
			],
		},
	})
	world.set("snapshot_provider", Callable(store, "snapshot"))
	world.call("refresh_from_snapshot")

	assert_eq(
		ground.get_cell_source_id(world_cell), -1,
		"Nonzero-chunk destroyed delta must erase Ground at the world cell."
	)
	assert_eq(
		ore_overlay.get_cell_source_id(world_cell), -1,
		"Nonzero-chunk destroyed delta must erase OreOverlay at the world cell."
	)
	assert_eq(
		ore_overlay.get_cell_source_id(intact_cell), WorldRenderer.SOURCE_ORE_SHARD,
		"Other chunks must stay rendered."
	)


func test_cell_def_at_resolves_nonzero_chunk_world_cells() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ore_world_cell: Vector2i = _world_cell("chunk_2_1", _ore_cell("chunk_2_1", "ore_core"))
	var definition: Dictionary = world.call("cell_def_at", "chunk_2_1", ore_world_cell)
	assert_eq(
		str(definition.get("type", "")), "ore_core",
		"cell_def_at must translate world cells into chunk-local lookups."
	)
	var soil_world_cell: Vector2i = _world_cell("chunk_2_1", Vector2i(0, 0))
	assert_eq(
		str((world.call("cell_def_at", "chunk_2_1", soil_world_cell) as Dictionary).get("type", "")),
		"soil",
		"Non-ore world cells in nonzero chunks must resolve to soil."
	)


# ---------------------------------------------------------------- 任务 1：世界边界


func test_world_has_four_boundary_walls_enclosing_the_world() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var wall_names: Array[String] = ["BoundaryLeft", "BoundaryRight", "BoundaryTop", "BoundaryBottom"]
	assert_eq(
		_static_body_wall_count(world), 4,
		"World must carry exactly 4 boundary StaticBody2D walls."
	)
	for wall_name: String in wall_names:
		var wall: StaticBody2D = world.get_node_or_null(NodePath(wall_name)) as StaticBody2D
		assert_not_null(wall, "Missing boundary wall: %s" % wall_name)
		if wall == null:
			continue
		var shape_node: CollisionShape2D = null
		for child: Node in wall.get_children():
			shape_node = child as CollisionShape2D
			if shape_node != null:
				break
		assert_not_null(shape_node, "%s must carry a CollisionShape2D." % wall_name)
		if shape_node != null:
			assert_true(
				shape_node.shape is RectangleShape2D,
				"%s must use a RectangleShape2D." % wall_name
			)
	var left: StaticBody2D = world.get_node_or_null("BoundaryLeft") as StaticBody2D
	var right: StaticBody2D = world.get_node_or_null("BoundaryRight") as StaticBody2D
	var top: StaticBody2D = world.get_node_or_null("BoundaryTop") as StaticBody2D
	var bottom: StaticBody2D = world.get_node_or_null("BoundaryBottom") as StaticBody2D
	if left != null:
		assert_lt(left.position.x, 0.0, "Left wall must sit beyond x=0.")
	if right != null:
		assert_gt(right.position.x, float(WORLD_PIXEL_SIZE.x), "Right wall must sit beyond x=4096.")
	if top != null:
		assert_lt(top.position.y, 0.0, "Top wall must sit beyond y=0.")
	if bottom != null:
		assert_gt(bottom.position.y, float(WORLD_PIXEL_SIZE.y), "Bottom wall must sit beyond y=2048.")


func _static_body_wall_count(world: Node2D) -> int:
	var count := 0
	for child: Node in world.get_children():
		if child is StaticBody2D:
			count += 1
	return count


# ---------------------------------------------------------------- 任务 2：相机


func test_camera_exists_with_world_limits_and_follows_player() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var camera: Camera2D = world.find_child("Camera2D", true, false) as Camera2D
	assert_not_null(camera, "world.tscn must contain a Camera2D.")
	if camera == null:
		return
	assert_eq(camera.limit_left, 0, "Camera limit_left must clamp to world origin.")
	assert_eq(camera.limit_top, 0, "Camera limit_top must clamp to world origin.")
	assert_eq(camera.limit_right, WORLD_PIXEL_SIZE.x, "Camera limit_right must clamp to 4096.")
	assert_eq(camera.limit_bottom, WORLD_PIXEL_SIZE.y, "Camera limit_bottom must clamp to 2048.")
	assert_true(camera.position_smoothing_enabled, "Camera smoothing must be enabled.")
	var player: Node2D = _player_node(world)
	assert_not_null(player, "Default world must spawn a player.")
	if player != null:
		assert_eq(
			camera.get_parent(), player,
			"Camera must become a child of the spawned player."
		)


# ---------------------------------------------------------------- 任务 3：存档位置出生


func test_player_spawns_at_saved_snapshot_position() -> void:
	var world: Node2D = _instantiate_world({
		"revision": 3,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {},
		"player": {"position": {"x": 40, "y": 20}},
	})
	if world == null:
		return
	var player: Node2D = _player_node(world)
	assert_not_null(player, "World must spawn a player.")
	if player != null:
		assert_eq(
			player.position, Vector2(40, 20) * 32.0,
			"Player must spawn at snapshot.player.position mapped to pixels."
		)
