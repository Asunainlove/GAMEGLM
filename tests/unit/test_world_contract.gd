extends GutTest

## WP03 RED gate. This script intentionally avoids preload/class_name references to
## the not-yet-implemented world files so it stays executable while they are missing
## (GUT silently skips scripts that fail to parse).

const WORLD_FILES: Array[String] = [
	"res://src/world/chunk_data.gd",
	"res://src/world/world_renderer.gd",
	"res://src/world/world.gd",
	"res://scenes/world.tscn",
]


func test_wp03_production_files_exist() -> void:
	for path: String in WORLD_FILES:
		assert_true(FileAccess.file_exists(path), "Missing required WP03 implementation: %s" % path)


func test_chunk_data_script_loads_with_frozen_constants() -> void:
	var chunk_data: Variant = load("res://src/world/chunk_data.gd")
	assert_not_null(chunk_data, "chunk_data.gd must load.")
	if chunk_data == null:
		return
	assert_eq(chunk_data.CHUNK_SIZE, 32)
	assert_eq(chunk_data.CELL_SIZE, 32)
	var chunk: Dictionary = chunk_data.generate("chunk_0_0", 7)
	assert_eq(chunk["chunk_id"], "chunk_0_0")
	var cells: Dictionary = chunk["cells"]
	assert_between(cells.size(), 60, 120, "chunk_0_0/seed 7 ore cells must stay within 60..120.")
	var replayed: Dictionary = chunk_data.generate("chunk_0_0", 7)
	assert_eq(replayed["cells"], cells, "generate must be deterministic per seed + chunk_id.")
