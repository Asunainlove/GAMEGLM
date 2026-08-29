extends GutTest

## WP03 RED/GREEN contract tests for the runtime-built grey-box world renderer.

const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")
const WORLD_RENDERER_SCRIPT: Script = preload("res://src/world/world_renderer.gd")
const RENDER_SEED: int = 7
const RENDER_CHUNK_ID: String = "chunk_0_0"


func _make_renderer() -> WorldRenderer:
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	renderer.name = "WorldRenderer"
	var ground: TileMapLayer = TileMapLayer.new()
	ground.name = "Ground"
	var ore: TileMapLayer = TileMapLayer.new()
	ore.name = "OreOverlay"
	add_child_autofree(ground)
	add_child_autofree(ore)
	renderer.ground_layer = ground
	renderer.ore_layer = ore
	add_child_autofree(renderer)
	return renderer


func _ore_cell(cells: Dictionary, ore_type: String = "") -> Vector2i:
	for cell: Vector2i in cells:
		if ore_type == "" or cells[cell] == ore_type:
			return cell
	fail_test("No cell of type '%s' available in fixture chunk." % ore_type)
	return Vector2i(-1, -1)


func _soil_cell(cells: Dictionary) -> Vector2i:
	for y in range(-1, 33):
		var candidate := Vector2i(0, y)
		if not cells.has(candidate):
			return candidate
	fail_test("Fixture chunk unexpectedly covers the whole column x=0.")
	return Vector2i(-1, -1)


func test_build_tile_set_creates_four_32px_monochrome_sources() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var tile_set: TileSet = renderer.build_tile_set()
	assert_not_null(tile_set, "WorldRenderer must build a TileSet at runtime.")
	assert_eq(tile_set.tile_size, Vector2i(32, 32))
	assert_eq(tile_set.get_source_count(), 4, "soil + three ore types need four sources.")
	for source_id: int in [
		WorldRenderer.SOURCE_SOIL,
		WorldRenderer.SOURCE_ORE_DUST,
		WorldRenderer.SOURCE_ORE_SHARD,
		WorldRenderer.SOURCE_ORE_CORE,
	]:
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		assert_not_null(source, "TileSet must contain atlas source %d." % source_id)
		if source != null:
			assert_eq(source.texture_region_size, Vector2i(32, 32))
			assert_eq(source.texture.get_size(), Vector2(32, 32))
			assert_true(source.has_tile(Vector2i.ZERO), "Source %d must expose tile (0,0)." % source_id)


func test_render_fills_ground_layer_and_ore_overlay() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})

	assert_not_null(renderer.ground_layer.tile_set, "render must attach the runtime TileSet.")
	assert_not_null(renderer.ore_layer.tile_set, "render must attach the runtime TileSet.")
	assert_eq(
		renderer.ground_layer.get_used_cells().size(),
		1024,
		"Ground layer must be fully filled with soil."
	)
	assert_eq(
		renderer.ore_layer.get_used_cells().size(),
		cells.size(),
		"Ore overlay must contain exactly the generated ore cells."
	)


func test_render_paints_ore_cells_as_double_layer() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})

	var ore_cell: Vector2i = _ore_cell(cells, "ore_dust")
	assert_eq(
		renderer.ground_layer.get_cell_source_id(ore_cell),
		WorldRenderer.SOURCE_SOIL,
		"Ore cells keep a soil base on the ground layer."
	)
	assert_eq(
		renderer.ore_layer.get_cell_source_id(ore_cell),
		WorldRenderer.SOURCE_ORE_DUST,
		"Ore overlay must paint the type-specific source."
	)
	var shard_cell: Vector2i = _ore_cell(cells, "ore_shard")
	assert_eq(renderer.ore_layer.get_cell_source_id(shard_cell), WorldRenderer.SOURCE_ORE_SHARD)
	var core_cell: Vector2i = _ore_cell(cells, "ore_core")
	assert_eq(renderer.ore_layer.get_cell_source_id(core_cell), WorldRenderer.SOURCE_ORE_CORE)

	var soil_cell: Vector2i = _soil_cell(cells)
	assert_eq(renderer.ore_layer.get_cell_source_id(soil_cell), -1)


func test_apply_deltas_erases_destroyed_cells_on_both_layers() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})

	var destroyed_ore: Vector2i = _ore_cell(cells, "ore_shard")
	var surviving_ore: Vector2i = _ore_cell(cells, "ore_core")
	var destroyed: Array[Vector2i] = [destroyed_ore]
	renderer.apply_deltas(destroyed)

	assert_eq(
		renderer.ground_layer.get_cell_source_id(destroyed_ore),
		-1,
		"Destroyed cells must be erased from the ground layer."
	)
	assert_eq(
		renderer.ore_layer.get_cell_source_id(destroyed_ore),
		-1,
		"Destroyed cells must be erased from the ore overlay."
	)
	assert_eq(
		renderer.ore_layer.get_cell_source_id(surviving_ore),
		WorldRenderer.SOURCE_ORE_CORE,
		"apply_deltas must not touch surviving cells."
	)
	assert_gt(renderer.ground_layer.get_used_cells().size(), 0)


func test_apply_deltas_with_empty_array_changes_nothing() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})
	var before_ground: int = renderer.ground_layer.get_used_cells().size()
	var before_ore: int = renderer.ore_layer.get_used_cells().size()

	renderer.apply_deltas([])

	assert_eq(renderer.ground_layer.get_used_cells().size(), before_ground)
	assert_eq(renderer.ore_layer.get_used_cells().size(), before_ore)
