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


func test_build_tile_set_creates_five_32px_monochrome_sources() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var tile_set: TileSet = renderer.build_tile_set()
	assert_not_null(tile_set, "WorldRenderer must build a TileSet at runtime.")
	assert_eq(tile_set.tile_size, Vector2i(32, 32))
	# W002-GAP2 合法断言更新：新增 rock_wall 专用 source（手工矿井岩壁），
	# soil + 三矿种 + rock_wall = 五个单色 source。
	assert_eq(tile_set.get_source_count(), 5, "soil + three ore types + rock_wall need five sources.")
	for source_id: int in [
		WorldRenderer.SOURCE_SOIL,
		WorldRenderer.SOURCE_ORE_DUST,
		WorldRenderer.SOURCE_ORE_SHARD,
		WorldRenderer.SOURCE_ORE_CORE,
		WorldRenderer.SOURCE_ROCK_WALL,
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


# ---------------------------------------------------------------- W002-GAP3


func test_render_with_chunk_origin_offsets_both_layers() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var chunk_id: String = "chunk_2_1"
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(chunk_id, RENDER_SEED)["cells"]
	var origin := Vector2i(64, 32)
	renderer.render({"chunk_id": chunk_id, "cells": cells}, origin)

	assert_eq(
		renderer.ground_layer.get_used_cells().size(), 1024,
		"One chunk render must paint exactly its own 1024 ground cells."
	)
	var min_cell := origin
	var max_cell := origin + Vector2i(31, 31)
	for cell: Vector2i in renderer.ground_layer.get_used_cells():
		assert_true(
			cell.x >= min_cell.x and cell.x <= max_cell.x and cell.y >= min_cell.y and cell.y <= max_cell.y,
			"Ground cells must stay inside the chunk rect [%s .. %s]." % [min_cell, max_cell]
		)
	var ore_cell: Vector2i = _ore_cell(cells, "ore_dust")
	assert_eq(
		renderer.ore_layer.get_cell_source_id(ore_cell + origin),
		WorldRenderer.SOURCE_ORE_DUST,
		"Ore overlay must translate local cells by the chunk origin."
	)
	var soil_cell: Vector2i = _soil_cell(cells)
	assert_eq(renderer.ore_layer.get_cell_source_id(soil_cell + origin), -1)


func test_clear_layers_empties_both_layers_for_full_world_repaint() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})
	assert_gt(renderer.ground_layer.get_used_cells().size(), 0)

	renderer.clear_layers()

	assert_eq(renderer.ground_layer.get_used_cells().size(), 0)
	assert_eq(renderer.ore_layer.get_used_cells().size(), 0)


func test_apply_delta_resolves_chunk_origin_and_erases_destroyed_cell() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var chunk_id: String = "chunk_2_1"
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(chunk_id, RENDER_SEED)["cells"]
	var origin := Vector2i(64, 32)
	renderer.render({"chunk_id": chunk_id, "cells": cells}, origin)
	var destroyed_local: Vector2i = _ore_cell(cells, "ore_shard")
	var surviving_local: Vector2i = _ore_cell(cells, "ore_core")

	renderer.apply_delta(chunk_id, destroyed_local, true)

	assert_eq(
		renderer.ground_layer.get_cell_source_id(destroyed_local + origin), -1,
		"apply_delta must erase at local cell + chunk origin on Ground."
	)
	assert_eq(
		renderer.ore_layer.get_cell_source_id(destroyed_local + origin), -1,
		"apply_delta must erase at local cell + chunk origin on OreOverlay."
	)
	assert_eq(
		renderer.ore_layer.get_cell_source_id(surviving_local + origin),
		WorldRenderer.SOURCE_ORE_CORE,
		"apply_delta must not touch surviving cells."
	)


func test_apply_delta_ignores_non_destroyed_delta() -> void:
	var renderer: WorldRenderer = _make_renderer()
	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})
	var intact_cell: Vector2i = _ore_cell(cells, "ore_dust")

	renderer.apply_delta(RENDER_CHUNK_ID, intact_cell, false)

	assert_eq(
		renderer.ore_layer.get_cell_source_id(intact_cell), WorldRenderer.SOURCE_ORE_DUST,
		"destroyed=false deltas must not erase anything."
	)
