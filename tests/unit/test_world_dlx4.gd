extends GutTest

## DLX-4 任务 3：世界回应感知（world_response_exploited → 矿脉富集）TDD 测试。
##
## 章程假设"选择改变地图"的最小可感版本：exploit 路线把世界回应 flag 置位后，
## 程序生成的 chunk 矿脉富集（10 → 14 矿脉种子）；实现要点：
## - 启动生成按快照 flags 决定 enriched（含读档：flag 已置的世界直接富集）；
## - 世界轮询检测 flag 跳变时，对无破坏记录（scar-free）的 chunk 重新
##   generate + 全层重渲染，随后重放 chunk_deltas——已破坏格保持擦除，
##   有破坏记录的 chunk 保留原始生成（破坏格不在富集数据中"复活"）；
## - 手工矿井 chunk（chunk_3_1）恒为 authored 布局，不受富集影响。

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const CHUNK_DATA: Script = preload("res://src/world/chunk_data.gd")
const EXPLOITED_FLAG: String = "world_response_exploited"
const WORLD_SEED: int = 1234
const SCAR_CHUNK_ID: String = "chunk_1_0"
const PROBE_CHUNK_ID: String = "chunk_0_0"


## 测试存根必须保存在实例字段：Callable 只持 ObjectID，临时 RefCounted 会被
## 立即释放导致 snapshot_provider 失效、world 静默回退 GameState autoload。
var _store: SnapshotStore = null


class SnapshotStore:
	var data: Dictionary = {}

	func _init(initial_data: Dictionary) -> void:
		data = initial_data

	func snapshot() -> Dictionary:
		return data.duplicate(true)


func _instantiate_world(initial_data: Dictionary) -> Node2D:
	var world_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	assert_not_null(world_scene, "world.tscn must exist and load.")
	if world_scene == null:
		return null
	var world: Node2D = world_scene.instantiate() as Node2D
	assert_not_null(world)
	if world == null:
		return null
	_store = SnapshotStore.new(initial_data)
	world.set("snapshot_provider", Callable(_store, "snapshot"))
	add_child_autofree(world)
	return world


func _base_data(flags: Dictionary) -> Dictionary:
	return {
		"revision": 0,
		"world_seed": WORLD_SEED,
		"flags": flags,
		"chunk_deltas": {},
	}


## 经 cell_def_at 扫描 chunk 的非土壤格集合（本地格坐标 → 矿/岩类型），
## 与 ChunkData.generate 输出同构，用于对比生成数据。cell_def_at 接收
## 世界格坐标（内部按 chunk 原点平移），本地格须先加原点。
func _observed_cells(world: Node2D, chunk_id: String) -> Dictionary:
	var observed: Dictionary = {}
	var origin := ChunkData.chunk_origin(chunk_id)
	for y: int in 32:
		for x: int in 32:
			var definition: Dictionary = world.call("cell_def_at", chunk_id, Vector2i(x, y) + origin)
			var cell_type := str(definition.get("type", "soil"))
			if cell_type != "soil":
				observed[Vector2i(x, y)] = cell_type
	return observed


func _ore_overlay_count(world: Node2D, chunk_id: String) -> int:
	var overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var parts: PackedStringArray = chunk_id.split("_", false)
	var origin := Vector2i(int(parts[1]), int(parts[2])) * 32
	var count := 0
	for y: int in range(origin.y, origin.y + 32):
		for x: int in range(origin.x, origin.x + 32):
			if overlay.get_cell_source_id(Vector2i(x, y)) != -1:
				count += 1
	return count


func _first_ore_world_cell(world: Node2D, chunk_id: String, ore_type: String) -> Vector2i:
	var observed: Dictionary = _observed_cells(world, chunk_id)
	for cell: Vector2i in observed:
		if observed[cell] == ore_type:
			var parts: PackedStringArray = chunk_id.split("_", false)
			return cell + Vector2i(int(parts[1]), int(parts[2])) * 32
	fail_test("chunk %s has no %s cell." % [chunk_id, ore_type])
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- 启动生成按 flag 富集


func test_world_boots_enriched_when_exploited_flag_preset() -> void:
	var world: Node2D = _instantiate_world(_base_data({EXPLOITED_FLAG: true}))
	if world == null:
		return
	assert_eq(
		_observed_cells(world, PROBE_CHUNK_ID),
		CHUNK_DATA.generate(PROBE_CHUNK_ID, WORLD_SEED, true)["cells"],
		"exploited flag 已置时启动生成必须产出富集 chunk 数据。"
	)
	# 手工矿井恒为 authored 布局，不受富集影响。
	assert_eq(
		_observed_cells(world, "chunk_3_1"),
		CHUNK_DATA.generate_mine("chunk_3_1")["cells"],
		"手工矿井 chunk 必须保持 authored 布局。"
	)


func test_world_boots_normal_without_flag() -> void:
	var world: Node2D = _instantiate_world(_base_data({}))
	if world == null:
		return
	assert_eq(
		_observed_cells(world, PROBE_CHUNK_ID),
		CHUNK_DATA.generate(PROBE_CHUNK_ID, WORLD_SEED, false)["cells"],
		"无 flag 时启动生成必须保持普通密度（冻结契约不回归）。"
	)


# ---------------------------------------------------------------- flag 跳变触发重生成


func test_flag_flip_regenerates_scar_free_chunks_and_preserves_scars() -> void:
	var world: Node2D = _instantiate_world(_base_data({}))
	if world == null:
		return
	# 步骤 A：制造破坏记录（chunk_1_0 一个 ore 格被采毁）并经轮询重放渲染。
	var scar_local := Vector2i.ZERO
	var normal_cells: Dictionary = CHUNK_DATA.generate(SCAR_CHUNK_ID, WORLD_SEED, false)["cells"]
	for cell: Vector2i in normal_cells:
		if normal_cells[cell] == "ore_dust":
			scar_local = cell
			break
	var parts: PackedStringArray = SCAR_CHUNK_ID.split("_", false)
	var scar_world := scar_local + Vector2i(int(parts[1]), int(parts[2])) * 32
	_store.data["chunk_deltas"] = {
		SCAR_CHUNK_ID: [{"cell_x": scar_world.x, "cell_y": scar_world.y, "destroyed": true}],
	}
	_store.data["revision"] = 1
	(world.get_node("SnapshotPollTimer") as Timer).timeout.emit()
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	assert_eq(ground.get_cell_source_id(scar_world), -1, "前置：破坏格在轮询后必须被擦除。")

	var probe_before := _ore_overlay_count(world, PROBE_CHUNK_ID)
	var scar_chunk_before := _ore_overlay_count(world, SCAR_CHUNK_ID)

	# 步骤 B：exploit 选择置位 world_response_exploited → 跳变重生成。
	_store.data["flags"] = {EXPLOITED_FLAG: true}
	_store.data["revision"] = 2
	(world.get_node("SnapshotPollTimer") as Timer).timeout.emit()

	assert_gt(
		_ore_overlay_count(world, PROBE_CHUNK_ID), probe_before,
		"flag 跳变后 scar-free chunk 必须重生成并渲染出更多矿格。"
	)
	assert_eq(
		_observed_cells(world, PROBE_CHUNK_ID),
		CHUNK_DATA.generate(PROBE_CHUNK_ID, WORLD_SEED, true)["cells"],
		"重生成后的 chunk 数据必须与同参数富集生成全等（确定性）。"
	)
	assert_eq(
		_ore_overlay_count(world, SCAR_CHUNK_ID), scar_chunk_before,
		"有破坏记录的 chunk 必须保留原始生成，不得随跳变重生成。"
	)
	assert_eq(
		ground.get_cell_source_id(scar_world), -1,
		"重渲染后破坏格必须经 delta 重放保持擦除。"
	)
	assert_eq(
		(world.get_node("OreOverlay") as TileMapLayer).get_cell_source_id(scar_world), -1,
		"重渲染后破坏格在矿层上必须保持擦除。"
	)


func test_flag_flip_without_revision_change_does_not_regenerate() -> void:
	var world: Node2D = _instantiate_world(_base_data({}))
	if world == null:
		return
	var probe_before := _ore_overlay_count(world, PROBE_CHUNK_ID)
	_store.data["flags"] = {EXPLOITED_FLAG: true}
	# revision 不变：轮询短路，不做任何重生成。
	(world.get_node("SnapshotPollTimer") as Timer).timeout.emit()
	assert_eq(
		_observed_cells(world, PROBE_CHUNK_ID),
		CHUNK_DATA.generate(PROBE_CHUNK_ID, WORLD_SEED, false)["cells"],
		"revision 未推进时不得重生成（与既有轮询契约一致）。"
	)
	assert_eq(_ore_overlay_count(world, PROBE_CHUNK_ID), probe_before)
