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
## DLX-4 世界回应富集：exploit 路线（world_response_exploited）下每 chunk 矿脉
## 种子数 10 → 14。实现为"同 rng 流追加矿脉"——同 (seed, chunk_id) 仍确定性，
## 且富集结果是普通结果的严格超集（矿格只增不减，普通格全部保留）。
const ENRICHED_VEIN_COUNT: int = 14
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
## DLX-4：可选 enriched=true 时以 ENRICHED_VEIN_COUNT 追加矿脉种子——前
## VEIN_COUNT 条矿脉与普通生成逐格一致（同 rng 流前缀），保证富集是普通
## 结果的超集；同 (world_seed, chunk_id, enriched) 三元组恒确定性复现。
static func generate(chunk_id: String, world_seed: int, enriched: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [world_seed, chunk_id])
	var cells: Dictionary = {}
	var vein_count := ENRICHED_VEIN_COUNT if enriched else VEIN_COUNT
	for _vein: int in vein_count:
		_grow_vein(cells, rng)
	return {"chunk_id": chunk_id, "cells": cells}


## DLX-5 authored 地区生成（无 RNG）：按外置 layout（WorldConfig 解析
## world_config.json regions[].layout 的归一化结果）固定布局填充任意
## authored chunk。语义与迁移前的 generate_mine 完全一致：
##   - wall_rects（Array[Rect2i]）→ 逐格填充 rock_wall（世界/表现层经
##     CELL_DEF_ROCK_WALL 冻结 def 解析，不可采不可建）；
##   - ore_rects（Array[{rect: Rect2i, type: String}]）→ 逐格填充对应矿种，
##     文件顺序即填充顺序（后写覆盖前写）；
##   - boss_room_rect → 仅作地区标记（触发链消费），**不填格**——Boss 房
##     必须保持开阔无矿。
## cells 只存非 soil 格，返回结构与 generate() 完全一致；同 layout 重复调用
## 结果全等（确定性由数据表保证，不依赖 world_seed 与 RNG）。
static func generate_authored(chunk_id: String, layout: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for rect: Rect2i in layout.get("wall_rects", []) as Array:
		_fill_rect(cells, rect, "rock_wall")
	for ore_rect_value: Variant in layout.get("ore_rects", []) as Array:
		var ore_rect: Dictionary = ore_rect_value
		_fill_rect(cells, ore_rect["rect"], str(ore_rect["type"]))
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
	# 防御：矿脉完全被既有矿格围死时 cluster 可能为空（更高矿脉数下概率升高），
	# 空集群无法取 anchor，直接放弃补足（不影响非退化路径的 rng 消耗序列）。
	while cluster.size() > 0 and cluster.size() < VEIN_MIN_CELLS and attempts < VEIN_GROWTH_ATTEMPT_CAP:
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
