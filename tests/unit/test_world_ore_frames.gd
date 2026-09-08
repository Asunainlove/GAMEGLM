extends GutTest

## P0-D：ore atlas damage frames from gathering hardness progress.

const WORLD_RENDERER_SCRIPT: Script = preload("res://src/world/world_renderer.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")

var _snapshot_store: SnapshotStore
var _progress_host: ProgressHost


class SnapshotStore:
	var data: Dictionary = {}

	func _init(initial_data: Dictionary) -> void:
		data = initial_data

	func snapshot() -> Dictionary:
		return data.duplicate(true)


class ProgressHost:
	var progress: Dictionary = {}

	func get_progress() -> Dictionary:
		return progress.duplicate()


func test_ore_atlas_coords_maps_hardness_without_new_numbers() -> void:
	assert_eq(WorldRenderer.ore_atlas_coords(2, 2), WorldRenderer.ORE_FRAME_S0)
	assert_eq(WorldRenderer.ore_atlas_coords(2, 1), WorldRenderer.ORE_FRAME_S2)
	assert_eq(WorldRenderer.ore_atlas_coords(3, 3), WorldRenderer.ORE_FRAME_S0)
	assert_eq(WorldRenderer.ore_atlas_coords(3, 2), WorldRenderer.ORE_FRAME_S1)
	assert_eq(WorldRenderer.ore_atlas_coords(3, 1), WorldRenderer.ORE_FRAME_S2)
	assert_eq(WorldRenderer.ore_atlas_coords(4, 3), WorldRenderer.ORE_FRAME_S1)
	assert_eq(WorldRenderer.ore_atlas_coords(4, 1), WorldRenderer.ORE_FRAME_S2)
	assert_eq(WorldRenderer.ore_atlas_coords(0, 0), WorldRenderer.ORE_FRAME_S0)


func test_build_tile_set_registers_ore_damage_frames_for_atlases() -> void:
	var temp := "user://p0d_ore_atlas_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(temp.path_join("world/tiles"))
	var image := Image.create_empty(160, 32, false, Image.FORMAT_RGBA8)
	for column: int in 5:
		image.fill_rect(Rect2i(column * 32, 0, 32, 32), Color(0.1 * column, 0.2, 0.3))
	assert_eq(image.save_png(temp.path_join("world/tiles/env_ore_dust_set.png")), OK)

	var renderer: WorldRenderer = WORLD_RENDERER_SCRIPT.new()
	add_child_autofree(renderer)
	var tile_set: TileSet = renderer.build_tile_set(temp)
	var dust: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_ORE_DUST) as TileSetAtlasSource
	assert_not_null(dust)
	assert_true(dust.has_tile(Vector2i(0, 0)))
	assert_true(dust.has_tile(Vector2i(1, 0)), "Ore atlas must expose s1 damage frame.")
	assert_true(dust.has_tile(Vector2i(2, 0)), "Ore atlas must expose s2 near-destroy frame.")
	var soil: TileSetAtlasSource = tile_set.get_source(WorldRenderer.SOURCE_SOIL) as TileSetAtlasSource
	assert_true(soil.has_tile(Vector2i.ZERO))
	assert_false(soil.has_tile(Vector2i(1, 0)))
	_remove_dir_recursive(temp)


func test_world_applies_mining_progress_to_ore_overlay_frame() -> void:
	var scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	var world: Node2D = scene.instantiate() as Node2D
	_snapshot_store = SnapshotStore.new({
		"revision": 0,
		"world_seed": 7,
		"chunk_deltas": {},
		"placed_buildings": [],
		"flags": {},
	})
	_progress_host = ProgressHost.new()
	world.set("player_scene_path", "")
	world.set("snapshot_provider", Callable(_snapshot_store, "snapshot"))
	world.set("mining_progress_provider", Callable(_progress_host, "get_progress"))
	add_child_autofree(world)

	var chunk: Dictionary = CHUNK_DATA_SCRIPT.generate("chunk_0_0", 7)
	var cells: Dictionary = chunk["cells"]
	var ore_cell := Vector2i(-1, -1)
	for cell: Vector2i in cells:
		if str(cells[cell]) == "ore_dust":
			ore_cell = cell
			break
	assert_ne(ore_cell, Vector2i(-1, -1), "Fixture seed must yield ore_dust.")
	var hardness := int(CHUNK_DATA_SCRIPT.cell_def(cells, ore_cell)["hardness"])
	assert_eq(hardness, 2)

	var ore_layer: TileMapLayer = world.get_node("OreOverlay") as TileMapLayer
	assert_eq(ore_layer.get_cell_atlas_coords(ore_cell), Vector2i.ZERO)

	_progress_host.progress["chunk_0_0|%d|%d" % [ore_cell.x, ore_cell.y]] = 1
	world.call("sync_ore_presentation")
	assert_eq(
		ore_layer.get_cell_atlas_coords(ore_cell),
		WorldRenderer.ORE_FRAME_S2,
		"hardness_left=1 on dust (hardness 2) maps to s2."
	)

	_progress_host.progress.clear()
	world.call("sync_ore_presentation")
	assert_eq(ore_layer.get_cell_atlas_coords(ore_cell), WorldRenderer.ORE_FRAME_S0)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
