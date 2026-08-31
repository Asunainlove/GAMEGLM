class_name ChunkData
extends RefCounted

## Deterministic chunk generation for the WP03 slice world.
##
## Chunks are pure data: a chunk id plus the set of non-soil (ore) cells. Ore veins
## are grown with a seeded RandomNumberGenerator so the same (world_seed, chunk_id)
## pair always reproduces the same cells across runs, saves, and platforms.

const CHUNK_SIZE: int = 32
const CELL_SIZE: int = 32

const VEIN_COUNT: int = 10
const VEIN_WALK_MIN: int = 3
const VEIN_WALK_MAX: int = 8
## Each vein claims at least this many unique cells so the per-chunk ore total
## stays inside the frozen 60..120 contract bound (10 veins x 6..9 cells).
const VEIN_MIN_CELLS: int = 6
const VEIN_GROWTH_ATTEMPT_CAP: int = 4096

const CELL_DEF_SOIL: Dictionary = {
	"type": "soil",
	"hardness": 0,
	"min_tier": 0,
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
const CELL_DEF_ORE_SHARD: Dictionary = {
	"type": "ore_shard",
	"hardness": 3,
	"min_tier": 1,
	"yield_item_id": "lumen_shard",
	"yield_amount": 1,
}
const CELL_DEF_ORE_CORE: Dictionary = {
	"type": "ore_core",
	"hardness": 4,
	"min_tier": 2,
	"yield_item_id": "resonant_core",
	"yield_amount": 1,
}
## W002-GAP2 手工矿井岩壁：hardness 0 直接判不可采；min_tier 9 是第二道保险
## （现有工具最高 tier 2，永不满足），天然不可采也不可破坏。
const CELL_DEF_ROCK_WALL: Dictionary = {
	"type": "rock_wall",
	"hardness": 0,
	"min_tier": 9,
	"yield_item_id": "",
	"yield_amount": 0,
}

## W002-GAP2 手工矿井所在 chunk（4x2 网格最东南 chunk，世界格 x∈[96,128)、
## y∈[32,64)）。生成时以 generate_mine 覆盖程序生成结果。
const MINE_CHUNK_ID: String = "chunk_3_1"

## 手工矿井岩壁矩形（chunk 本地坐标，Rect2i(position, size)，end=position+size
## 为开区间下界）。布局：北岩体 + 入口走廊（y=8..9，西端 x=0 开口衔接 chunk_2_1 土壤）+
## 竖井（x=12..13）+ 中央矿脉富集腔（x=6..25, y=13..21）+ 南端 Boss 房
## （x=10..19, y=22..31，10x10 开阔）。
const MINE_WALL_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 32, 8),
	Rect2i(14, 8, 18, 2),
	Rect2i(0, 10, 12, 3),
	Rect2i(14, 10, 18, 3),
	Rect2i(0, 13, 6, 9),
	Rect2i(26, 13, 6, 9),
	Rect2i(0, 22, 10, 10),
	Rect2i(20, 22, 12, 10),
]

## 手工矿井矿脉矩形（含矿种）：dust 12+12、shard 16+16、core 9+9+6，
## 总计 80 格，比例 3:4:3。走廊（D1）与腔内（D2..C3）散布，Boss 房无矿。
const MINE_ORE_VEINS: Dictionary = {
	"ore_dust": [Rect2i(3, 8, 6, 2), Rect2i(17, 13, 6, 2)],
	"ore_shard": [Rect2i(7, 15, 4, 4), Rect2i(14, 15, 4, 4)],
	"ore_core": [Rect2i(8, 19, 3, 3), Rect2i(20, 19, 3, 3), Rect2i(24, 16, 2, 3)],
}

## Boss 房矩形（chunk 本地坐标）：世界格 y >= 32+22 即腔体南端，供触发链使用。
const MINE_BOSS_ROOM_RECT: Rect2i = Rect2i(10, 22, 10, 10)


## Parses a "chunk_<x>_<y>" id into its grid coordinates inside the world grid.
## Returns Vector2i(-1, -1) when the id does not follow the pattern.
static func grid_coords(chunk_id: String) -> Vector2i:
	var parts := chunk_id.split("_", false)
	if parts.size() != 3 or parts[0] != "chunk":
		return Vector2i(-1, -1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]), int(parts[2]))


## World-grid cell origin of a chunk id (grid coordinates x CHUNK_SIZE), i.e.
## the chunk-local (0, 0) cell expressed in world cell coordinates. Unparseable
## ids degrade to the chunk_0_0 origin so callers stay safe by default.
static func chunk_origin(chunk_id: String) -> Vector2i:
	var grid := grid_coords(chunk_id)
	if grid.x < 0 or grid.y < 0:
		return Vector2i.ZERO
	return grid * CHUNK_SIZE


## Generates one chunk deterministically. Returns
## `{"chunk_id": String, "cells": Dictionary}` where `cells` maps Vector2i grid
## coordinates to ore type ids and only contains non-soil cells.
static func generate(chunk_id: String, world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [world_seed, chunk_id])
	var cells: Dictionary = {}
	for _vein: int in VEIN_COUNT:
		_grow_vein(cells, rng)
	return {"chunk_id": chunk_id, "cells": cells}


## W002-GAP2 手工 authored 矿井（无 RNG）：按 MINE_WALL_RECTS / MINE_ORE_VEINS
## 固定布局填充 chunk_3_1。cells 只存非 soil 格（rock_wall 墙 + 矿），返回结构
## 与 generate() 完全一致；同参数重复调用结果全等（确定性由常量表保证，不依赖
## world_seed）。布局（chunk 本地坐标，北在上南在下）：
##   - 入口走廊 y=8..9（西端 x=0 开口，衔接 chunk_2_1 全 soil 边缘，天然可通行）；
##   - 竖井 x=12..13 连接走廊与矿脉腔；
##   - 中央矿脉富集腔 x=6..25, y=13..21（高密度矿）；
##   - Boss 房 x=10..19, y=22..31（腔体南端 10x10 开阔区，无矿）。
static func generate_mine(chunk_id: String) -> Dictionary:
	var cells: Dictionary = {}
	for rect: Rect2i in MINE_WALL_RECTS:
		_fill_rect(cells, rect, "rock_wall")
	for ore_type: String in MINE_ORE_VEINS:
		for rect: Rect2i in MINE_ORE_VEINS[ore_type]:
			_fill_rect(cells, rect, ore_type)
	return {"chunk_id": chunk_id, "cells": cells}


## Returns the frozen gathering definition for a cell. Cells missing from the
## map (or outside it) are plain soil.
static func cell_def(cells: Dictionary, cell: Vector2i) -> Dictionary:
	match str(cells.get(cell, "soil")):
		"ore_dust":
			return CELL_DEF_ORE_DUST.duplicate()
		"ore_shard":
			return CELL_DEF_ORE_SHARD.duplicate()
		"ore_core":
			return CELL_DEF_ORE_CORE.duplicate()
		"rock_wall":
			return CELL_DEF_ROCK_WALL.duplicate()
		_:
			return CELL_DEF_SOIL.duplicate()


## Fills an inclusive Rect2i (position..position+size-1) with one cell type.
static func _fill_rect(cells: Dictionary, rect: Rect2i, cell_type: String) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, y)] = cell_type


static func _grow_vein(cells: Dictionary, rng: RandomNumberGenerator) -> void:
	var vein_type := _roll_vein_type(rng)
	var cluster: Array[Vector2i] = []
	var cursor := Vector2i(rng.randi_range(0, CHUNK_SIZE - 1), rng.randi_range(0, CHUNK_SIZE - 1))
	_claim_cell(cells, cluster, cursor, vein_type)
	for _step: int in rng.randi_range(VEIN_WALK_MIN, VEIN_WALK_MAX):
		cursor = _clamped_neighbor(cursor, rng)
		_claim_cell(cells, cluster, cursor, vein_type)
	var attempts := 0
	while cluster.size() < VEIN_MIN_CELLS and attempts < VEIN_GROWTH_ATTEMPT_CAP:
		attempts += 1
		var anchor: Vector2i = cluster[rng.randi_range(0, cluster.size() - 1)]
		_claim_cell(cells, cluster, _clamped_neighbor(anchor, rng), vein_type)


## First writer wins: a cell claimed by another vein is never re-typed and does
## not count toward this vein's cluster, so totals stay within bounds.
static func _claim_cell(
	cells: Dictionary,
	cluster: Array[Vector2i],
	cell: Vector2i,
	vein_type: String
) -> void:
	if cluster.has(cell) or cells.has(cell):
		return
	cells[cell] = vein_type
	cluster.append(cell)


static func _clamped_neighbor(cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var neighbor := cell
	match rng.randi_range(0, 3):
		0:
			neighbor.x += 1
		1:
			neighbor.x -= 1
		2:
			neighbor.y += 1
		3:
			neighbor.y -= 1
	neighbor.x = clampi(neighbor.x, 0, CHUNK_SIZE - 1)
	neighbor.y = clampi(neighbor.y, 0, CHUNK_SIZE - 1)
	return neighbor


## Seed type distribution: 40% ore_dust, 40% ore_shard, 20% ore_core.
static func _roll_vein_type(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.4:
		return "ore_dust"
	if roll < 0.8:
		return "ore_shard"
	return "ore_core"
