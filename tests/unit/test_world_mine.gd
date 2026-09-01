extends GutTest

## W002-GAP2 RED/GREEN tests: the authored mine/Boss area in chunk_3_1.
##
## 章程 Locked scope 第 1 条要求 4x2 Chunk 琉砂海地区"和一个手工矿井/Boss 区"。
## 本文件覆盖：
## - ChunkData.generate_authored（DLX-5：布局数据外置 world_config.json，经
##   WorldConfig.layout_for_chunk 装载；语义与迁移前 generate_mine 完全一致）：
##   手工固定布局（无 RNG）、确定性、矿石总量 60..90、ore_dust/ore_shard/ore_core
##   比例 3:4:3、入口/走廊开阔、Boss 房 10x10 无矿；
## - rock_wall 新格型：cell_def 冻结值（hardness 0 / min_tier 9）+ Gathering
##   工具等级守卫（min_tier 9 现有工具永不满足）；
## - WorldRenderer：rock_wall 专用单色 source（深褐，DLX-5 起颜色读配置），
##   绘制在 Ground 层（随覆盖层切换隐藏的必须是矿，不是墙）；
## - world.tscn：chunk_3_1 按外置 region 声明用 generate_authored 覆盖程序生成，
##   其余 7 chunk 不变。

const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")
const GATHERING_SCRIPT: Script = preload("res://src/gathering/gathering.gd")
const WORLD_RENDERER_SCRIPT: Script = preload("res://src/world/world_renderer.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"

const DEFAULT_WORLD_SEED: int = 0
const MINE_CHUNK_ID: String = "chunk_3_1"
## chunk_3_1 的世界格原点（3*32, 1*32）。
const MINE_ORIGIN: Vector2i = Vector2i(96, 32)
## Boss 房（腔体南端 10x10 开阔区，chunk 本地坐标）。
const BOSS_ROOM_RECT: Rect2i = Rect2i(10, 22, 10, 10)
## 矿井入口（世界格 (96, 40) 附近，chunk_2_1 交界处）必须保持开阔。
const ENTRY_LOCAL_CELLS: Array[Vector2i] = [Vector2i(0, 8), Vector2i(0, 9), Vector2i(1, 8)]
## 走廊→竖井→矿脉腔→Boss 房的采样通路（chunk 本地格），必须全部可通行（soil）。
const CORRIDOR_PATH_SAMPLES: Array[Vector2i] = [
	Vector2i(2, 8),
	Vector2i(10, 9),
	Vector2i(12, 8),
	Vector2i(12, 11),
	Vector2i(12, 13),
	Vector2i(12, 21),
	Vector2i(14, 22),
	Vector2i(14, 27),
]
## 走廊与腔体两侧的墙格采样（rock_wall）。
const WALL_SAMPLES: Array[Vector2i] = [
	Vector2i(0, 7),
	Vector2i(5, 0),
	Vector2i(2, 10),
	Vector2i(15, 8),
	Vector2i(31, 15),
	Vector2i(3, 22),
	Vector2i(25, 28),
]
## 矿格采样（走廊尘矿 + 腔内晶簇/核心矿）。
const ORE_SAMPLES: Dictionary = {
	Vector2i(5, 8): "ore_dust",
	Vector2i(20, 13): "ore_dust",
	Vector2i(8, 16): "ore_shard",
	Vector2i(15, 16): "ore_shard",
	Vector2i(9, 20): "ore_core",
	Vector2i(21, 20): "ore_core",
	Vector2i(24, 17): "ore_core",
}

const CELL_DEF_ROCK_WALL: Dictionary = {
	"type": "rock_wall",
	"hardness": 0,
	"min_tier": 9,
	"yield_item_id": "",
	"yield_amount": 0,
}
const CELL_DEF_ORE_DUST: Dictionary = {
	"type": "ore_dust",
	"hardness": 2,
	"min_tier": 0,
	"yield_item_id": "starsoil_dust",
	"yield_amount": 2,
}

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


func _instantiate_world() -> Node2D:
	if world_scene == null:
		return null
	var world: Node2D = world_scene.instantiate() as Node2D
	if world == null:
		fail_test("world.tscn must instantiate to a Node2D root.")
		return null
	_snapshot_store = SnapshotStore.new({
		"revision": 0,
		"world_seed": DEFAULT_WORLD_SEED,
		"chunk_deltas": {},
	})
	world.set("snapshot_provider", Callable(_snapshot_store, "snapshot"))
	add_child_autofree(world)
	return world


func _count_type(cells: Dictionary, cell_type: String) -> int:
	var count := 0
	for cell: Vector2i in cells:
		if str(cells[cell]) == cell_type:
			count += 1
	return count


## DLX-5 合法断言更新：generate_mine 常量耦合退役，authored 矿井改为
## generate_authored + 外置布局（WorldConfig 装载 world_config.json）。
## 断言值（采样/计数/比例/矩形）保持迁移前逐字节不变——本文件即等价快照。
func _mine_chunk() -> Dictionary:
	return CHUNK_DATA_SCRIPT.generate_authored(
		MINE_CHUNK_ID, WorldConfig.layout_for_chunk(MINE_CHUNK_ID))


# --------------------------------------------------------------- 任务 1：手工布局


func test_generate_authored_is_deterministic_and_structure_compatible() -> void:
	var first: Dictionary = _mine_chunk()
	var second: Dictionary = _mine_chunk()
	assert_eq(str(first.get("chunk_id", "")), MINE_CHUNK_ID)
	assert_eq(first, second, "authored 生成是手工固定布局，两次生成必须全等。")
	assert_true(first.has("cells"), "返回结构必须与 generate 一致（cells 字典）。")
	assert_gt((first["cells"] as Dictionary).size(), 0)


func test_generate_authored_cells_stay_in_bounds_and_use_known_types() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	var known_types: Array[String] = ["rock_wall", "ore_dust", "ore_shard", "ore_core"]
	for cell: Vector2i in cells:
		assert_true(cell.x >= 0 and cell.x < 32, "矿井格 x 越界: %s" % cell)
		assert_true(cell.y >= 0 and cell.y < 32, "矿井格 y 越界: %s" % cell)
		assert_has(known_types, str(cells[cell]), "未知格型: %s" % str(cells[cell]))


func test_generate_authored_ore_total_and_ratio_match_contract() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	var dust := _count_type(cells, "ore_dust")
	var shard := _count_type(cells, "ore_shard")
	var core := _count_type(cells, "ore_core")
	var total := dust + shard + core
	assert_between(total, 60, 90, "矿井矿石总量必须在 60..90（实测 %d）。" % total)
	assert_eq(dust * 4, shard * 3, "dust:shard 必须 3:4。")
	assert_eq(core, dust, "dust:core 必须 3:3（同比例）。")
	assert_eq(dust, 24)
	assert_eq(shard, 32)
	assert_eq(core, 24)


func test_generate_authored_keeps_entry_and_corridor_open() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	for local_cell: Vector2i in ENTRY_LOCAL_CELLS:
		assert_false(
			cells.has(local_cell),
			"入口格 %s 必须保持开阔（无墙无矿，衔接 chunk_2_1 土壤）。" % local_cell
		)
	for local_cell: Vector2i in CORRIDOR_PATH_SAMPLES:
		assert_false(
			cells.has(local_cell),
			"矿井通路格 %s 必须可通行（soil）。" % local_cell
		)


func test_generate_authored_boss_room_is_open_with_no_ore() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	for y: int in range(BOSS_ROOM_RECT.position.y, BOSS_ROOM_RECT.end.y):
		for x: int in range(BOSS_ROOM_RECT.position.x, BOSS_ROOM_RECT.end.x):
			assert_false(
				cells.has(Vector2i(x, y)),
				"Boss 房格 (%d, %d) 必须开阔且无矿。" % [x, y]
			)


func test_generate_authored_walls_flank_corridor_and_enclose_rooms() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	for local_cell: Vector2i in WALL_SAMPLES:
		assert_eq(
			str(cells.get(local_cell, "")), "rock_wall",
			"采样格 %s 必须是岩壁。" % local_cell
		)


func test_generate_authored_ore_samples_match_authored_distribution() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	for local_cell: Vector2i in ORE_SAMPLES:
		assert_eq(
			str(cells.get(local_cell, "")), str(ORE_SAMPLES[local_cell]),
			"采样格 %s 必须是 %s。" % [local_cell, str(ORE_SAMPLES[local_cell])]
		)


# --------------------------------------------------------------- 任务 1：rock_wall 格型


func test_cell_def_returns_frozen_rock_wall_definition() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	var definition: Dictionary = CHUNK_DATA_SCRIPT.cell_def(cells, Vector2i(0, 7))
	assert_eq(definition, CELL_DEF_ROCK_WALL, "rock_wall 必须返回冻结 def（hardness 0 / min_tier 9）。")
	definition["min_tier"] = 0
	assert_eq(
		(CHUNK_DATA_SCRIPT.cell_def(cells, Vector2i(0, 7)) as Dictionary)["min_tier"],
		9,
		"cell_def 必须返回独立副本，不得泄漏可变模板。"
	)


func test_mine_ore_cells_stay_minable() -> void:
	var cells: Dictionary = _mine_chunk()["cells"]
	assert_eq(
		CHUNK_DATA_SCRIPT.cell_def(cells, Vector2i(5, 8)), CELL_DEF_ORE_DUST,
		"走廊矿格必须保持 ore_dust 可采 def。"
	)


func test_rock_wall_min_tier_guard_rejects_every_current_tool() -> void:
	# hardness 0 时 Gathering 直接判 not_mineable；min_tier 9 是第二道保险：
	# 即使未来调整 hardness，现有工具（tool_tier<=2）也永不满足。
	var hard_wall: Dictionary = {
		"type": "rock_wall", "hardness": 1, "min_tier": 9,
		"yield_item_id": "", "yield_amount": 0,
	}
	var strike: Dictionary = GATHERING_SCRIPT.mining_result(hard_wall, 2)
	assert_eq(str(strike.get("reason", "")), "tool_too_weak", "min_tier 9 必须拒绝现有全部工具。")
	var soft_wall: Dictionary = {
		"type": "rock_wall", "hardness": 0, "min_tier": 9,
		"yield_item_id": "", "yield_amount": 0,
	}
	assert_eq(
		str((GATHERING_SCRIPT.mining_result(soft_wall, 9) as Dictionary).get("reason", "")),
		"not_mineable",
		"hardness 0 的岩壁必须直接判不可采。"
	)


# --------------------------------------------------------------- 任务 1：渲染器


func test_renderer_builds_dedicated_rock_wall_source() -> void:
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	assert_eq(WorldRenderer.SOURCE_ROCK_WALL, 4, "rock_wall 使用新 source id 4。")
	assert_eq(
		int(renderer.call("_source_for", "rock_wall")), WorldRenderer.SOURCE_ROCK_WALL,
		"TYPE_SOURCES 必须把 rock_wall 映射到专用 source。"
	)
	var tile_set: TileSet = renderer.build_tile_set()
	assert_eq(
		tile_set.get_source_count(), 5,
		"soil + 3 ore + rock_wall 需要五个单色 source。"
	)
	var source: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ROCK_WALL) as TileSetAtlasSource
	assert_not_null(source, "TileSet 必须包含 rock_wall source。")
	if source != null:
		assert_eq(source.texture_region_size, Vector2i(32, 32))


func test_renderer_paints_rock_wall_on_ground_layer_not_ore_overlay() -> void:
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	var ground: TileMapLayer = TileMapLayer.new()
	ground.name = "Ground"
	var ore: TileMapLayer = TileMapLayer.new()
	ore.name = "OreOverlay"
	add_child_autofree(ground)
	add_child_autofree(ore)
	renderer.ground_layer = ground
	renderer.ore_layer = ore
	add_child_autofree(renderer)
	var cells: Dictionary = {
		Vector2i(2, 3): "rock_wall",
		Vector2i(5, 6): "ore_dust",
	}
	renderer.render({"chunk_id": MINE_CHUNK_ID, "cells": cells})

	assert_eq(
		ground.get_cell_source_id(Vector2i(2, 3)), WorldRenderer.SOURCE_ROCK_WALL,
		"岩壁必须绘制在 Ground 层（覆盖层切换只隐藏矿，不隐藏墙）。"
	)
	assert_eq(
		ore.get_cell_source_id(Vector2i(2, 3)), -1,
		"岩壁不得占用矿覆盖层。"
	)
	assert_eq(ore.get_cell_source_id(Vector2i(5, 6)), WorldRenderer.SOURCE_ORE_DUST)


# --------------------------------------------------------------- 任务 1：world 装配


func test_world_overrides_chunk_3_1_with_authored_mine() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var wall_world_cell := MINE_ORIGIN + Vector2i(0, 7)
	var wall_def: Dictionary = world.call("cell_def_at", MINE_CHUNK_ID, wall_world_cell)
	assert_eq(
		str(wall_def.get("type", "")), "rock_wall",
		"chunk_3_1 必须按外置 region 声明用 generate_authored 覆盖程序生成结果（世界格墙可解析）。"
	)
	assert_eq(int(wall_def.get("min_tier", 0)), 9, "cell_def_at 对 rock_wall 必须返回 min_tier 9。")
	assert_eq(int(wall_def.get("hardness", -1)), 0, "cell_def_at 对 rock_wall 必须返回 hardness 0。")

	var ore_world_cell := MINE_ORIGIN + Vector2i(5, 8)
	assert_eq(
		str((world.call("cell_def_at", MINE_CHUNK_ID, ore_world_cell) as Dictionary).get("type", "")),
		"ore_dust",
		"矿井走廊矿格在世界坐标下必须可解析为 ore_dust。"
	)
	var boss_world_cell := MINE_ORIGIN + Vector2i(12, 27)
	assert_eq(
		str((world.call("cell_def_at", MINE_CHUNK_ID, boss_world_cell) as Dictionary).get("type", "")),
		"soil",
		"Boss 房格在世界坐标下必须是土壤（无矿无墙）。"
	)


func test_world_keeps_other_chunks_procedural() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var generated: Dictionary = CHUNK_DATA_SCRIPT.generate("chunk_0_0", DEFAULT_WORLD_SEED)
	var cells: Dictionary = generated["cells"]
	var has_ore := false
	for cell: Vector2i in cells:
		if str(cells[cell]) == "ore_core":
			has_ore = true
			assert_eq(
				world.call("cell_def_at", "chunk_0_0", cell),
				CHUNK_DATA_SCRIPT.cell_def(cells, cell),
				"其余 7 chunk 必须保持程序生成结果。"
			)
			break
	assert_true(has_ore, "前置：chunk_0_0 必须存在 ore_core 采样格。")


func test_world_renders_mine_rock_wall_on_ground_layer() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ore_overlay: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	var wall_world_cell := MINE_ORIGIN + Vector2i(0, 7)
	assert_eq(
		ground.get_cell_source_id(wall_world_cell), WorldRenderer.SOURCE_ROCK_WALL,
		"矿井岩壁必须以专用 source 绘制在 Ground 层。"
	)
	assert_eq(
		ore_overlay.get_cell_source_id(wall_world_cell), -1,
		"矿井岩壁不得绘制在矿覆盖层。"
	)
	var ore_world_cell := MINE_ORIGIN + Vector2i(5, 8)
	assert_eq(
		ore_overlay.get_cell_source_id(ore_world_cell), WorldRenderer.SOURCE_ORE_DUST,
		"矿井矿格仍按矿种绘制在覆盖层。"
	)
	assert_eq(
		ground.get_used_cells().size(), 8192,
		"手工矿井不改变全图 Ground 覆盖规模（8 chunk x 1024）。"
	)
