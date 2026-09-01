extends GutTest

## G7P-2 M11：相机限界运行时化（TDD：先 RED 后 GREEN）。
##
## world.tscn 的 Camera2D limit_* 静态值保留为缺省（4x2 网格），World._ready
## 在世界构建后按 WorldConfig 配置网格尺寸运行时覆盖：
## limit_right = grid_x * CHUNK_PIXELS、limit_bottom = grid_y * CHUNK_PIXELS、
## limit_left/top = 0——grid 改非 4x2 时相机自动适配，零场景文件改动
## （scenes/world.tscn 禁改约束）。
## 行为等价：生产 4x2 配置的运行时覆盖值与 tscn 静态值逐字节一致。

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const CHUNK_DATA: Script = preload("res://src/world/chunk_data.gd")

## world.tscn 静态缺省（迁移前快照，禁止改场景文件——运行时覆盖必须与其
## 在生产配置下逐字节一致）。
const FROZEN_SCENE_LIMIT_RIGHT: int = 4096
const FROZEN_SCENE_LIMIT_BOTTOM: int = 2048

var _teardown_nodes: Array[Node] = []


func before_each() -> void:
	WorldConfig.reset_for_tests()


func after_each() -> void:
	for node: Node in _teardown_nodes:
		if is_instance_valid(node):
			node.free()
	_teardown_nodes.clear()
	WorldConfig.reset_for_tests()


func _chunk_pixels() -> int:
	return int(CHUNK_DATA.CHUNK_SIZE) * int(CHUNK_DATA.CELL_SIZE)


func _make_world_with_grid(grid: Vector2i) -> Camera2D:
	var config := {"grid_size": [grid.x, grid.y], "regions": []}
	var load_result: AppResult = WorldConfig.load_config_from(_write_temp_config(config))
	assert_true(load_result.is_ok, "临时网格配置必须装载成功：%s" % load_result.message)
	var world_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	assert_not_null(world_scene, "world.tscn must exist and load.")
	if world_scene == null:
		return null
	var world := world_scene.instantiate() as Node2D
	assert_not_null(world)
	if world == null:
		return null
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	world.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world)
	_teardown_nodes.append(world)
	# 相机在 _ready 内被挂到玩家节点下（或保留在 world 根）——统一深搜查找。
	var camera := world.find_child("Camera2D", true, false) as Camera2D
	assert_not_null(camera, "world 必须提供 Camera2D（含运行时 reparent 后仍可找到）。")
	return camera


func _write_temp_config(config: Dictionary) -> String:
	var path := "user://g7p2_camera_config_%d.json" % Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时 world config 必须可写：%s" % path)
	if file != null:
		file.store_string(JSON.stringify(config, "  "))
		file.close()
	return path


func test_camera_limits_follow_configured_grid_two_by_one() -> void:
	var camera: Camera2D = _make_world_with_grid(Vector2i(2, 1))
	if camera == null:
		return
	assert_eq(camera.limit_right, 2 * _chunk_pixels(), "limit_right 必须等于 grid_x * CHUNK_PIXELS。")
	assert_eq(camera.limit_bottom, 1 * _chunk_pixels(), "limit_bottom 必须等于 grid_y * CHUNK_PIXELS。")
	assert_eq(camera.limit_left, 0)
	assert_eq(camera.limit_top, 0)


func test_camera_limits_follow_configured_grid_six_by_three() -> void:
	var camera: Camera2D = _make_world_with_grid(Vector2i(6, 3))
	if camera == null:
		return
	assert_eq(camera.limit_right, 6 * _chunk_pixels())
	assert_eq(camera.limit_bottom, 3 * _chunk_pixels())


func test_production_grid_runtime_limits_equal_scene_defaults() -> void:
	# 行为等价：生产 4x2 配置下运行时覆盖值 = tscn 静态缺省值（迁移前后
	# 玩家可见行为零变化）。
	var camera: Camera2D = _make_world_with_grid(Vector2i(4, 2))
	if camera == null:
		return
	assert_eq(camera.limit_right, FROZEN_SCENE_LIMIT_RIGHT)
	assert_eq(camera.limit_bottom, FROZEN_SCENE_LIMIT_BOTTOM)
