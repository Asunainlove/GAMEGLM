extends GutTest

## WP03 RED/GREEN contract tests for deterministic chunk generation and cell defs.

const CHUNK_DATA_SCRIPT: Script = preload("res://src/world/chunk_data.gd")

const ORE_TYPES: Array[String] = ["ore_dust", "ore_shard", "ore_core"]
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


func _chunk_data() -> GDScript:
	return CHUNK_DATA_SCRIPT


func test_constants_match_frozen_world_contract() -> void:
	var chunk_data: GDScript = _chunk_data()
	assert_eq(chunk_data.CHUNK_SIZE, 32)
	assert_eq(chunk_data.CELL_SIZE, 32)


func test_generate_is_deterministic_for_same_seed_and_chunk_id() -> void:
	var first: Dictionary = _chunk_data().generate("chunk_0_0", 42)
	var second: Dictionary = _chunk_data().generate("chunk_0_0", 42)
	assert_eq(first["chunk_id"], "chunk_0_0")
	assert_eq(second["chunk_id"], "chunk_0_0")
	assert_eq(first["cells"], second["cells"], "Same seed + chunk_id must reproduce identical cells.")


func test_generate_differs_across_seeds_and_chunk_ids() -> void:
	var base: Dictionary = _chunk_data().generate("chunk_0_0", 1)["cells"]
	var other_seed: Dictionary = _chunk_data().generate("chunk_0_0", 2)["cells"]
	var other_chunk: Dictionary = _chunk_data().generate("chunk_1_0", 1)["cells"]
	assert_ne(other_seed, base, "Different world_seed must produce different cells.")
	assert_ne(other_chunk, base, "Different chunk_id must produce different cells.")


func test_ore_cell_count_stays_within_contract_bounds() -> void:
	for world_seed: int in [0, 1, 42, 20260829, -7]:
		for chunk_id: String in ["chunk_0_0", "chunk_2_1", "chunk_3_1"]:
			var chunk: Dictionary = _chunk_data().generate(chunk_id, world_seed)
			var cell_count: int = (chunk["cells"] as Dictionary).size()
			assert_between(
				cell_count,
				60,
				120,
				"chunk %s seed %d produced %d ore cells; expected 60..120." % [
					chunk_id,
					world_seed,
					cell_count,
				]
			)


func test_cells_only_hold_ore_types_inside_chunk_bounds() -> void:
	var cells: Dictionary = _chunk_data().generate("chunk_0_0", 42)["cells"]
	assert_gt(cells.size(), 0)
	var seen_types: Dictionary = {}
	for cell: Vector2i in cells:
		assert_true(cell.x >= 0 and cell.x < 32, "Cell x out of chunk bounds: %s" % cell)
		assert_true(cell.y >= 0 and cell.y < 32, "Cell y out of chunk bounds: %s" % cell)
		var ore_type: String = cells[cell]
		assert_has(ORE_TYPES, ore_type, "Unexpected cell type: %s" % ore_type)
		seen_types[ore_type] = true
	assert_false(cells.values().has("soil"), "generate must only persist non-soil cells.")
	assert_true(seen_types.has("ore_dust"), "Deterministic seed set must expose ore_dust veins.")
	assert_true(seen_types.has("ore_shard"), "Deterministic seed set must expose ore_shard veins.")
	assert_true(seen_types.has("ore_core"), "Deterministic seed set must expose ore_core veins.")


func test_cell_def_returns_soil_for_missing_cells() -> void:
	var cells: Dictionary = _chunk_data().generate("chunk_0_0", 42)["cells"]
	var outside_cell := Vector2i(-1, 0)
	for cell: Vector2i in cells:
		if cells[cell] == "ore_dust":
			outside_cell = Vector2i(cell.x + 1, cell.y)
			if not cells.has(outside_cell):
				break
	assert_eq(_chunk_data().cell_def(cells, outside_cell), CELL_DEF_SOIL)
	assert_eq(_chunk_data().cell_def({}, Vector2i(3, 4)), CELL_DEF_SOIL)


func test_cell_def_maps_each_ore_type_to_frozen_gathering_values() -> void:
	var cells: Dictionary = {
		Vector2i(1, 1): "ore_dust",
		Vector2i(2, 2): "ore_shard",
		Vector2i(3, 3): "ore_core",
	}
	assert_eq(_chunk_data().cell_def(cells, Vector2i(1, 1)), CELL_DEF_ORE_DUST)
	assert_eq(_chunk_data().cell_def(cells, Vector2i(2, 2)), CELL_DEF_ORE_SHARD)
	assert_eq(_chunk_data().cell_def(cells, Vector2i(3, 3)), CELL_DEF_ORE_CORE)


func test_cell_def_returns_an_independent_copy() -> void:
	var cells: Dictionary = {Vector2i(0, 0): "ore_core"}
	var cell_def: Dictionary = _chunk_data().cell_def(cells, Vector2i(0, 0))
	cell_def["hardness"] = 99
	assert_eq(
		_chunk_data().cell_def(cells, Vector2i(0, 0))["hardness"],
		4,
		"cell_def must never hand out its mutable template."
	)


# ---------------------------------------------------------------- DLX-4：世界回应富集（enriched 参数）


func test_generate_enriched_is_deterministic_for_same_seed_and_chunk_id() -> void:
	var first: Dictionary = _chunk_data().generate("chunk_0_0", 42, true)
	var second: Dictionary = _chunk_data().generate("chunk_0_0", 42, true)
	assert_eq(first["cells"], second["cells"], "Same seed + chunk_id + enriched must reproduce identical cells.")


func test_generate_default_call_matches_enriched_false() -> void:
	var implicit: Dictionary = _chunk_data().generate("chunk_0_0", 42)
	var explicit: Dictionary = _chunk_data().generate("chunk_0_0", 42, false)
	assert_eq(implicit["cells"], explicit["cells"], "Default generate must stay equivalent to enriched=false.")


func test_generate_enriched_yields_strictly_more_ore_than_normal() -> void:
	# 富集实现为"同 rng 流追加矿脉"：enriched 结果必须是普通结果的超集且严格
	# 更多矿格——破坏性变更不可能，世界只增不减。
	for world_seed: int in [0, 1, 42, 20260829, -7]:
		var normal: Dictionary = _chunk_data().generate("chunk_0_0", world_seed)["cells"]
		var enriched: Dictionary = _chunk_data().generate("chunk_0_0", world_seed, true)["cells"]
		assert_gt(
			enriched.size(), normal.size(),
			"seed %d enriched chunk must contain more ore cells than normal." % world_seed
		)
		for cell: Vector2i in normal:
			assert_eq(
				enriched.get(cell, ""), normal[cell],
				"enriched must keep every normal ore cell (superset, seed %d)." % world_seed
			)


func test_generate_enriched_cells_stay_inside_chunk_bounds_and_ore_types() -> void:
	var cells: Dictionary = _chunk_data().generate("chunk_2_1", 7, true)["cells"]
	for cell: Vector2i in cells:
		assert_true(cell.x >= 0 and cell.x < 32, "Enriched cell x out of chunk bounds: %s" % cell)
		assert_true(cell.y >= 0 and cell.y < 32, "Enriched cell y out of chunk bounds: %s" % cell)
		assert_has(ORE_TYPES, cells[cell], "Unexpected enriched cell type: %s" % cells[cell])
