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

var ground_layer: TileMapLayer
var ore_layer: TileMapLayer

var _tile_set: TileSet


## Builds a fresh TileSet with one single-color atlas source per cell type.
func build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE)
	_add_monochrome_source(tile_set, SOURCE_SOIL, SOIL_COLOR)
	_add_monochrome_source(tile_set, SOURCE_ORE_DUST, ORE_DUST_COLOR)
	_add_monochrome_source(tile_set, SOURCE_ORE_SHARD, ORE_SHARD_COLOR)
	_add_monochrome_source(tile_set, SOURCE_ORE_CORE, ORE_CORE_COLOR)
	_add_monochrome_source(tile_set, SOURCE_ROCK_WALL, WorldConfig.rock_wall_color())
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


func _add_monochrome_source(tile_set: TileSet, source_id: int, color: Color) -> void:
	var image := Image.create_empty(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE, false, Image.FORMAT_RGB8)
	image.fill(color)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(ChunkData.CELL_SIZE, ChunkData.CELL_SIZE)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, source_id)


func _source_for(ore_type: String) -> int:
	return int(TYPE_SOURCES.get(ore_type, SOURCE_SOIL))
