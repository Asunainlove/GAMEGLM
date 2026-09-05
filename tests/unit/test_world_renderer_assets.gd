extends GutTest

## G6P-1 任务 2：世界渲染器 TileSet 资产探测契约测试（TDD：先于实现编写）。
##
## 契约：
## - 生产基态（res://assets/art 不存在）→ TileSet 与灰盒基线逐字节等价
##   （5 源单色、32×32、tile (0,0)、source_id 冻结映射不变、零告警）；
## - 注入资产目录 → 命中源用上纹理，未命中源逐源独立回退单色（互不牵连）；
## - 探测序：A6 合同落位 assets/art/world/tiles/ 优先，任务书平铺
##   world/tilesets/ 兜底；
## - 混合态（部分加载部分缺失）→ last_asset_report 记账 + 一次性汇总告警
##   （告警文案经纯函数 partial_asset_warning 断言；全缺失静默）。
## 测试经 build_tile_set 的 base_dir 参数注入 user:// 临时纹理目录。

const WORLD_RENDERER_SCRIPT: Script = preload("res://src/world/world_renderer.gd")
const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")
const WORLD_CONFIG_SCRIPT: Script = preload("res://src/world/world_config.gd")
const ADAPTER_SCRIPT: Script = preload("res://src/assets/asset_adapter.gd")
const RENDER_SEED: int = 7
const RENDER_CHUNK_ID: String = "chunk_0_0"

var _temp_dir: String = ""


func before_each() -> void:
	_temp_dir = "user://g6p1_world_assets_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir_recursive(_temp_dir)
	_temp_dir = ""


# ---------------------------------------------------------------- 工具


func _write_png(rel_dir: String, file_name: String, size: Vector2i, color: Color) -> void:
	var dir := _temp_dir.path_join(rel_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	assert_eq(image.save_png(dir.path_join(file_name)), OK, "PNG 写入必须成功。")


func _write_atlas_strip(rel_dir: String, file_name: String, tile_count: int, colors: Array) -> void:
	# 横排图集：每格 32×32，格序颜色取 colors（循环取色）。
	var dir := _temp_dir.path_join(rel_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(32 * tile_count, 32, false, Image.FORMAT_RGBA8)
	for index: int in tile_count:
		image.fill_rect(
			Rect2i(index * 32, 0, 32, 32), colors[index % colors.size()] as Color)
	assert_eq(image.save_png(dir.path_join(file_name)), OK, "图集 PNG 写入必须成功。")


func _pixel_of(texture: Texture2D) -> Color:
	var image := texture.get_image()
	return image.get_pixel(0, 0)


## 8-bit PNG 量化容差比较（RGB8 逐通道 0.5/255 ≈ 0.002；取 0.01 裕度）。
func _assert_pixel_close(texture: Texture2D, expected: Color, label: String) -> void:
	var actual := _pixel_of(texture)
	assert_true(
		absf(actual.r - expected.r) < 0.01 			and absf(actual.g - expected.g) < 0.01 			and absf(actual.b - expected.b) < 0.01,
		"%s（实际 %s，期望 %s）" % [label, actual, expected])


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		if dir.current_is_dir():
			_remove_dir_recursive(path.path_join(entry))
		else:
			DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- 基态等价


func test_build_tile_set_without_assets_matches_greybox_baseline() -> void:
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)

	assert_not_null(tile_set, "无资产也必须照常构建 TileSet。")
	assert_eq(tile_set.tile_size, Vector2i(32, 32))
	assert_eq(tile_set.get_source_count(), 5, "五个 source 映射冻结不变。")
	var expected_colors: Dictionary = {
		WorldRenderer.SOURCE_SOIL: WorldRenderer.SOIL_COLOR,
		WorldRenderer.SOURCE_ORE_DUST: WorldRenderer.ORE_DUST_COLOR,
		WorldRenderer.SOURCE_ORE_SHARD: WorldRenderer.ORE_SHARD_COLOR,
		WorldRenderer.SOURCE_ORE_CORE: WorldRenderer.ORE_CORE_COLOR,
		WorldRenderer.SOURCE_ROCK_WALL: WORLD_CONFIG_SCRIPT.rock_wall_color(),
	}
	for source_id: int in expected_colors:
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		assert_not_null(source, "source %d 必须存在。" % source_id)
		if source == null:
			continue
		assert_eq(source.texture_region_size, Vector2i(32, 32))
		assert_eq(source.texture.get_size(), Vector2(32, 32))
		assert_true(source.has_tile(Vector2i.ZERO))
		_assert_pixel_close(
			source.texture, expected_colors[source_id] as Color,
			"source %d 缺资产必须回退冻结单色。" % source_id)
	var report: Dictionary = renderer.get("last_asset_report")
	if report == null:
		report = {}
	assert_eq(int(report.get("loaded", -1)), 0, "基态记账：零资产加载。")
	var missing: Array = report.get("missing", [])
	assert_eq(missing.size(), 5, "基态记账：五个 source 全部记为缺失。")
	assert_eq(
		WorldRenderer.partial_asset_warning(0, PackedStringArray(["soil"]), ), "",
		"全缺失基态必须静默（汇总文案为空）。")


func test_build_tile_set_default_base_dir_matches_adapter_root() -> void:
	assert_eq(
		str(WORLD_RENDERER_SCRIPT.DEFAULT_ASSET_BASE_DIR),
		str(ADAPTER_SCRIPT.DEFAULT_BASE_DIR),
		"渲染器默认探测根必须与适配层单一取值一致。")


# ---------------------------------------------------------------- 逐源独立回退


func test_build_tile_set_uses_injected_soil_and_keeps_others_monochrome() -> void:
	_write_png("world/tiles", "env_world_soil_base.png", Vector2i(32, 32), Color(1, 0, 0))
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)

	var soil: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_SOIL) as TileSetAtlasSource
	assert_not_null(soil)
	if soil != null:
		_assert_pixel_close(soil.texture, Color(1, 0, 0), "命中的 soil 源必须用上注入纹理。")
	var dust: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ORE_DUST) as TileSetAtlasSource
	assert_not_null(dust)
	if dust != null:
		_assert_pixel_close(
			dust.texture, WorldRenderer.ORE_DUST_COLOR,
			"未命中源必须逐源独立回退单色（互不牵连）。")
	var report: Dictionary = renderer.get("last_asset_report")
	if report == null:
		report = {}
	assert_eq(int(report.get("loaded", -1)), 1)
	var missing: Array = report.get("missing", [])
	assert_eq(missing, ["ore_dust", "ore_shard", "ore_core", "rock_wall"] as Array)
	var warning: String = WORLD_RENDERER_SCRIPT.partial_asset_warning(
		int(report.get("loaded", 0)), PackedStringArray(missing))
	assert_true(warning.contains("ore_dust"), "混合态汇总文案必须点名缺失源。")
	assert_true(warning.contains("rock_wall"))


func test_build_tile_set_prefers_contract_path_over_tilesets_dir() -> void:
	_write_png("world/tiles", "env_world_soil_base.png", Vector2i(32, 32), Color(1, 0, 0))
	_write_png("world/tilesets", "soil.png", Vector2i(32, 32), Color(0, 1, 0))
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)
	var soil: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_SOIL) as TileSetAtlasSource
	assert_not_null(soil)
	if soil != null:
		_assert_pixel_close(soil.texture, Color(1, 0, 0), "A6 合同落位必须优先于平铺目录。")


func test_build_tile_set_falls_back_to_tilesets_dir() -> void:
	_write_png("world/tilesets", "ore_dust.png", Vector2i(32, 32), Color(0, 1, 0))
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)
	var dust: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ORE_DUST) as TileSetAtlasSource
	assert_not_null(dust)
	if dust != null:
		_assert_pixel_close(dust.texture, Color(0, 1, 0), "任务书平铺 world/tilesets/ 兜底必须生效。")


func test_build_tile_set_accepts_ore_atlas_strip() -> void:
	# A6 ENV-04 合同形态：160×32 五格横排（_s0.._s2 + glint 两帧）。
	_write_atlas_strip(
		"world/tiles", "env_ore_dust_set.png", 5,
		[Color(0, 1, 1), Color(1, 1, 0), Color(1, 0, 1), Color(0, 0, 0), Color(1, 1, 1)])
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)
	var dust: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ORE_DUST) as TileSetAtlasSource
	assert_not_null(dust)
	if dust != null:
		assert_eq(dust.texture.get_size(), Vector2(160, 32), "合同图集整图必须原样加载。")
		assert_eq(dust.texture_region_size, Vector2i(32, 32))
		assert_eq(dust.get_tiles_count(), 1, "本包只挂 _s0（格 0,0）；态切换属后续接线包。")
		_assert_pixel_close(dust.texture, Color(0, 1, 1), "tile (0,0) 必须取图集首格（_s0）。")
		# Atlas 坐标 (0,0) 读数与灰盒渲染路径一致（render() 恒写 ZERO 坐标）。
		assert_true(dust.has_tile(Vector2i.ZERO))


func test_build_tile_set_accepts_rock_wall_atlas_strip() -> void:
	_write_atlas_strip(
		"world/tiles", "env_mine_wall_atlas.png", 12,
		[Color(1, 0, 0), Color(0, 1, 0)])
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)
	var wall: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ROCK_WALL) as TileSetAtlasSource
	assert_not_null(wall)
	if wall != null:
		assert_eq(wall.texture.get_size(), Vector2(384, 32))
		_assert_pixel_close(wall.texture, Color(1, 0, 0), "岩壁 tile (0,0) 必须取图集首格。")


func test_build_tile_set_full_injection_loads_all_five_sources() -> void:
	_write_png("world/tiles", "env_world_soil_base.png", Vector2i(32, 32), Color(1, 0, 0))
	_write_png("world/tiles", "env_ore_dust_set.png", Vector2i(32, 32), Color(0, 1, 0))
	_write_png("world/tiles", "env_ore_shard_set.png", Vector2i(32, 32), Color(0, 0, 1))
	_write_png("world/tiles", "env_ore_core_set.png", Vector2i(32, 32), Color(1, 0, 1))
	_write_png("world/tiles", "env_mine_wall_atlas.png", Vector2i(32, 32), Color(0, 0, 0))
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)

	var expected: Dictionary = {
		WorldRenderer.SOURCE_SOIL: Color(1, 0, 0),
		WorldRenderer.SOURCE_ORE_DUST: Color(0, 1, 0),
		WorldRenderer.SOURCE_ORE_SHARD: Color(0, 0, 1),
		WorldRenderer.SOURCE_ORE_CORE: Color(1, 0, 1),
		WorldRenderer.SOURCE_ROCK_WALL: Color(0, 0, 0),
	}
	for source_id: int in expected:
		var source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
		assert_not_null(source, "source %d 必须存在。" % source_id)
		if source != null:
			_assert_pixel_close(source.texture, expected[source_id] as Color, "source %d 注入纹理命中。" % source_id)
	var report: Dictionary = renderer.get("last_asset_report")
	if report == null:
		report = {}
	assert_eq(int(report.get("loaded", -1)), 5)
	assert_eq((report.get("missing", []) as Array).size(), 0)
	assert_eq(
		WORLD_RENDERER_SCRIPT.partial_asset_warning(5, PackedStringArray()), "",
		"全量命中必须静默（无汇总告警）。")


# ---------------------------------------------------------------- 渲染路径不受影响


func test_render_with_injected_assets_keeps_grid_semantics() -> void:
	_write_png("world/tiles", "env_world_soil_base.png", Vector2i(32, 32), Color(1, 0, 0))
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

	var cells: Dictionary = CHUNK_DATA_SCRIPT.generate(RENDER_CHUNK_ID, RENDER_SEED)["cells"]
	renderer.render({"chunk_id": RENDER_CHUNK_ID, "cells": cells})

	assert_eq(ground.get_used_cells().size(), 1024, "注入资产不改变铺格语义。")
	assert_eq(ore.get_used_cells().size(), cells.size())
	var tile_set: TileSet = ground.tile_set
	assert_eq(tile_set.get_source_count(), 5)


func test_build_tile_set_prefers_rock_wall_over_mine_wall_atlas() -> void:
	# PR #29 contract: env_world_rock_wall.png wins; mine wall atlas is fallback only.
	_write_png("world/tiles", "env_world_rock_wall.png", Vector2i(32, 32), Color(0, 1, 0))
	_write_atlas_strip("world/tiles", "env_mine_wall_atlas.png", 12, [Color(1, 0, 0)])
	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(_temp_dir)
	var wall: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ROCK_WALL) as TileSetAtlasSource
	assert_not_null(wall)
	if wall != null:
		assert_eq(wall.texture.get_size(), Vector2(32, 32), "Prefer single rock_wall tile over atlas strip.")
		_assert_pixel_close(wall.texture, Color(0, 1, 0), "env_world_rock_wall must win probe order.")

