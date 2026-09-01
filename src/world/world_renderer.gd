class_name WorldRenderer
extends Node2D

## Grey-box renderer for the generated chunks of the 4x2 slice world. Builds a
## 32x32 monochrome TileSet at runtime (no binary art assets) and writes cells
## into two injected TileMapLayer nodes owned by the world scene. This node
## never touches persistent state: destroyed cells arrive as plain coordinates.
## Chunk payloads are chunk-local; `render()` translates them by the chunk
## origin so all 8 world chunks accumulate on the shared layers.

const SOURCE_SOIL: int = 0
const SOURCE_ORE_DUST: int = 1
const SOURCE_ORE_SHARD: int = 2
const SOURCE_ORE_CORE: int = 3
## W002-GAP2 手工矿井岩壁专用单色 source（深褐）。
const SOURCE_ROCK_WALL: int = 4

const SOIL_COLOR := Color(0.16, 0.17, 0.19)
const ORE_DUST_COLOR := Color(0.33, 0.44, 0.58)
const ORE_SHARD_COLOR := Color(0.29, 0.57, 0.6)
const ORE_CORE_COLOR := Color(0.47, 0.36, 0.58)
## DLX-5：岩壁色外置于 world_config.json（mine_rock_wall_color），经 WorldConfig
## 读取（文件缺失/坏文件回退同值兜底色，WorldConfig.FALLBACK_ROCK_WALL_COLOR）。

const TYPE_SOURCES: Dictionary = {
	"soil": SOURCE_SOIL,
	"ore_dust": SOURCE_ORE_DUST,
	"ore_shard": SOURCE_ORE_SHARD,
	"ore_core": SOURCE_ORE_CORE,
	"rock_wall": SOURCE_ROCK_WALL,
}

## G6P-1 任务 2：世界格资产探测点（docs/art/environment-assets.md 合同落位
## assets/art/world/tiles/ 优先，任务书平铺 assets/art/world/tilesets/<格型>.png
## 兜底）。逐源独立探测：命中即用该纹理替换单色图；任一缺失该源回退单色灰盒
## （逐源独立回退，互不牵连——有 rock_wall 纹理但缺 soil 也只替换 rock_wall 源）。
## 图集形态（ore 三态 160×32 / 岩壁 384×32）按 32×32 region 挂 tile (0,0)=首格
##（矿= _s0 完好帧；岩壁= _tile0 平铺变体）；态切换属后续接线包。
const CELL_ASSET_PROBES: Dictionary = {
	SOURCE_SOIL: ["world/tiles/env_world_soil_base.png", "world/tilesets/soil.png"],
	SOURCE_ORE_DUST: ["world/tiles/env_ore_dust_set.png", "world/tilesets/ore_dust.png"],
	SOURCE_ORE_SHARD: ["world/tiles/env_ore_shard_set.png", "world/tilesets/ore_shard.png"],
	SOURCE_ORE_CORE: ["world/tiles/env_ore_core_set.png", "world/tilesets/ore_core.png"],
	SOURCE_ROCK_WALL: ["world/tiles/env_mine_wall_atlas.png", "world/tilesets/rock_wall.png"],
}

## 默认探测根（与 AssetAdapter.DEFAULT_BASE_DIR 同值；跨类常量默认参受限就地
## 镜像，测试断言两值一致）。
const DEFAULT_ASSET_BASE_DIR: String = "res://assets/art"

## 最近一次 build_tile_set 的资产装配报告（测试观察缝；瞬态，不入持久状态）：
## {loaded: int, missing: PackedStringArray}。
var last_asset_report: Dictionary = {}

var ground_layer: TileMapLayer
var ore_layer: TileMapLayer

var _tile_set: TileSet


## Builds a fresh TileSet with one atlas source per cell type. Each source first
## probes the G6P-1 asset list (CELL_ASSET_PROBES); a hit replaces the monochrome
## image, a miss falls back to that source's frozen single color independently.
## 全缺失（生产基态）保持静默且行为与灰盒基线逐字节一致；混合态（部分加载
## 部分缺失）一次性 push_warning 汇总缺失清单。
func build_tile_set(base_dir: String = DEFAULT_ASSET_BASE_DIR) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE)
	var report := {"loaded": 0, "missing": []}
	_add_cell_source(tile_set, SOURCE_SOIL, SOIL_COLOR, base_dir, report)
	_add_cell_source(tile_set, SOURCE_ORE_DUST, ORE_DUST_COLOR, base_dir, report)
	_add_cell_source(tile_set, SOURCE_ORE_SHARD, ORE_SHARD_COLOR, base_dir, report)
	_add_cell_source(tile_set, SOURCE_ORE_CORE, ORE_CORE_COLOR, base_dir, report)
	_add_cell_source(tile_set, SOURCE_ROCK_WALL, WorldConfig.rock_wall_color(), base_dir, report)
	last_asset_report = report
	var warning := partial_asset_warning(
		int(report["loaded"]), PackedStringArray(report["missing"] as Array))
	if warning != "":
		push_warning(warning)
	return tile_set


## Fills both layers from a ChunkData.generate() result, translating chunk-local
## cells by `chunk_origin` (the chunk's cell offset inside the world grid).
## Multiple chunks accumulate on the shared layers: call clear_layers() first
## for a full-world repaint. Ore cells are painted as a double layer: soil base
## on the ground layer plus the ore color overlay.
func render(chunk: Dictionary, chunk_origin: Vector2i = Vector2i.ZERO) -> void:
	if ground_layer == null or ore_layer == null:
		push_warning("WorldRenderer.render() skipped: ground/ore layers are not injected.")
		return
	var tile_set := ensure_tile_set()
	ground_layer.tile_set = tile_set
	ore_layer.tile_set = tile_set

	for grid_y: int in ChunkData.CHUNK_SIZE:
		for grid_x: int in ChunkData.CHUNK_SIZE:
			ground_layer.set_cell(Vector2i(grid_x, grid_y) + chunk_origin, SOURCE_SOIL, Vector2i.ZERO)

	var cells: Dictionary = chunk.get("cells", {})
	for cell_value: Variant in cells:
		if typeof(cell_value) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = cell_value
		var source_id := _source_for(str(cells[cell_value]))
		if source_id == SOURCE_ROCK_WALL:
			# W002-GAP2：岩壁是地形而非矿——绘制在 Ground 层（替换土壤底色），
			# 覆盖层切换（toggle_overlay）只隐藏矿，不隐藏墙。
			ground_layer.set_cell(cell + chunk_origin, SOURCE_ROCK_WALL, Vector2i.ZERO)
		else:
			ore_layer.set_cell(cell + chunk_origin, source_id, Vector2i.ZERO)


## Empties both layers; full-world repaint entry point before re-rendering all
## chunks (world.gd calls this once, then render()s every chunk by origin).
func clear_layers() -> void:
	if ground_layer == null or ore_layer == null:
		push_warning("WorldRenderer.clear_layers() skipped: ground/ore layers are not injected.")
		return
	ground_layer.clear()
	ore_layer.clear()


## Erases destroyed cells from both layers at once (set_cell with source -1).
## Cells are world-absolute; kept as the chunk_0_0-compatible legacy seam.
func apply_deltas(destroyed_cells: Array[Vector2i]) -> void:
	if ground_layer == null or ore_layer == null:
		push_warning("WorldRenderer.apply_deltas() skipped: ground/ore layers are not injected.")
		return
	for cell: Vector2i in destroyed_cells:
		ground_layer.set_cell(cell, -1)
		ore_layer.set_cell(cell, -1)


## Chunk-aware destruction seam: erases one destroyed cell of `chunk_id` from
## both layers. `cell` is chunk-local; the chunk origin is resolved internally
## via ChunkData.chunk_origin. destroyed=false is a documented no-op —
## production deltas only ever record destruction, and repainting a restored
## cell would need the ore type, which this seam does not carry.
func apply_delta(chunk_id: String, cell: Vector2i, destroyed: bool) -> void:
	if ground_layer == null or ore_layer == null:
		push_warning("WorldRenderer.apply_delta() skipped: ground/ore layers are not injected.")
		return
	if not destroyed:
		return
	var world_cell := cell + ChunkData.chunk_origin(chunk_id)
	ground_layer.set_cell(world_cell, -1)
	ore_layer.set_cell(world_cell, -1)


func ensure_tile_set() -> TileSet:
	if _tile_set == null:
		_tile_set = build_tile_set()
	return _tile_set


## G6P-1：逐源资产探测 + 单色回退装配（report 为引用累积器：字典按引用传递）。
func _add_cell_source(
		tile_set: TileSet, source_id: int, color: Color, base_dir: String, report: Dictionary) -> void:
	var source := TileSetAtlasSource.new()
	source.texture_region_size = Vector2i(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE)
	var texture := _probe_cell_texture(source_id, base_dir)
	if texture == null:
		var image := Image.create_empty(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE, false, Image.FORMAT_RGB8)
		image.fill(color)
		texture = ImageTexture.create_from_image(image)
		(report["missing"] as Array).append(_source_name(source_id))
	else:
		report["loaded"] = int(report["loaded"]) + 1
	source.texture = texture
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, source_id)


func _probe_cell_texture(source_id: int, base_dir: String) -> Texture2D:
	var probes: Array = CELL_ASSET_PROBES.get(source_id, [])
	for probe_path: Variant in probes:
		var texture := AssetAdapter.texture_at("%s/%s" % [base_dir, str(probe_path)])
		if texture != null:
			return texture
	return null


## source_id → 格型名（回退记账与告警文案用；未映射 id 给中性名兜底）。
func _source_name(source_id: int) -> String:
	for type_name: String in TYPE_SOURCES:
		if int(TYPE_SOURCES[type_name]) == source_id:
			return type_name
	return "source_%d" % source_id


## 混合态一次性汇总告警文案（纯函数，测试断言用）：loaded==0（全缺失生产基态）
## 或 missing 为空（全量命中）时返回 ""（静默）；只有"部分加载部分缺失"才汇总。
static func partial_asset_warning(loaded: int, missing: PackedStringArray) -> String:
	if loaded <= 0 or missing.is_empty():
		return ""
	return "WorldRenderer: 世界格资产部分缺失，%d 个 source 回退单色灰盒：%s（合同 docs/art/environment-assets.md）" % [
		missing.size(), ", ".join(missing),
	]


func _source_for(ore_type: String) -> int:
	return int(TYPE_SOURCES.get(ore_type, SOURCE_SOIL))
