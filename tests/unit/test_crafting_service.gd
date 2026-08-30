extends GutTest

## W002-GAP4 精炼闭环单元测试（TDD：先 RED 后 GREEN）。
## CraftingService 为纯逻辑模块（RefCounted，无场景树依赖）：
## - available_recipes：仅已放置且供电的建筑的配方可用（powered_ids 由调用方算好传入）。
## - can_craft：输入材料足够与否的纯判定。
## - craft：材料检查 + 提交原子化，单 patch（remove_item 输入 + add_item 输出），
##   source_id = crafting_<building_id>_<revision>（同 revision 重放幂等）。
## 提交路径经注入的独立 GameState 实例（真实 patch 管线），不污染全局 autoload。

const CRAFTING_SCRIPT_PATH: String = "res://src/crafting/crafting_service.gd"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")

const LOOM_MIST_RECIPE: Dictionary = {
	"input_item_id": "lumen_shard", "input_count": 2,
	"output_item_id": "sedative_mist", "output_count": 1,
}
const LOOM_TRAP_RECIPE: Dictionary = {
	"input_item_id": "lumen_shard", "input_count": 2,
	"extra_input_item_id": "resonant_core", "extra_input_count": 1,
	"output_item_id": "shock_trap", "output_count": 1,
}
const REFINER_RECIPE: Dictionary = {
	"input_item_id": "starsoil_dust", "input_count": 3,
	"output_item_id": "resonant_core", "output_count": 1,
}

var _service: Script = null
var _store: Node = null


func before_all() -> void:
	_service = load(CRAFTING_SCRIPT_PATH)


func before_each() -> void:
	_store = GAME_STATE_SCRIPT.new()
	add_child_autofree(_store)


func after_each() -> void:
	_store = null


func _require_service() -> bool:
	if _service == null:
		fail_test("Missing required W002-GAP4 implementation: %s" % CRAFTING_SCRIPT_PATH)
		return false
	return true


func _defs() -> Dictionary:
	return {
		"anchor_block": {"id": "anchor_block"},
		"resonance_loom": {"id": "resonance_loom", "recipes": [LOOM_MIST_RECIPE, LOOM_TRAP_RECIPE]},
		"dust_refiner": {"id": "dust_refiner", "recipe": REFINER_RECIPE},
	}


func _state(building_ids: Array, inventory: Dictionary = {}) -> Dictionary:
	var placed: Array = []
	for building_id: String in building_ids:
		placed.append({
			"building_id": building_id,
			"chunk_id": "chunk_0_0",
			"cell_x": 20,
			"cell_y": placed.size() + 20,
		})
	return {
		"revision": 0,
		"inventory": inventory,
		"placed_buildings": placed,
	}


func _give(item_id: String, amount: int) -> void:
	var revision := int(_store.snapshot()["revision"])
	var patch: StatePatch = _store.begin_patch("test_gap4_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = _store.commit(patch)
	assert_true(committed.is_ok, committed.message)


# --- available_recipes -----------------------------------------------------------


func test_available_recipes_empty_without_placed_buildings() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state([]), _defs(), _string_ids(["resonance_loom"]))
	assert_eq(entries.size(), 0, "No placed buildings means no available recipes.")


func test_available_recipes_skip_unpowered_buildings() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["resonance_loom"]), _defs(), _string_ids([]))
	assert_eq(entries.size(), 0, "Placed but unpowered buildings provide no recipes.")


func test_available_recipes_list_powered_building_recipes_in_placement_order() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["resonance_loom", "dust_refiner"]), _defs(),
		_string_ids(["resonance_loom", "dust_refiner"]))
	assert_eq(entries.size(), 3, "Loom contributes 2 recipes, refiner 1.")
	if entries.size() == 3:
		assert_eq(str(entries[0]["building_id"]), "resonance_loom")
		assert_eq(str(entries[0]["recipe"]["output_item_id"]), "sedative_mist")
		assert_eq(str(entries[1]["building_id"]), "resonance_loom")
		assert_eq(str(entries[1]["recipe"]["output_item_id"]), "shock_trap")
		assert_eq(str(entries[2]["building_id"]), "dust_refiner")
		assert_eq(str(entries[2]["recipe"]["output_item_id"]), "resonant_core")


func test_available_recipes_support_single_recipe_field() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["dust_refiner"]), _defs(), _string_ids(["dust_refiner"]))
	assert_eq(entries.size(), 1)
	if entries.size() == 1:
		assert_eq(str(entries[0]["recipe"]), str(REFINER_RECIPE))


func test_available_recipes_dedupe_same_building_instances() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["resonance_loom", "resonance_loom"]), _defs(),
		_string_ids(["resonance_loom", "resonance_loom"]))
	assert_eq(entries.size(), 2, "Two loom instances still expose exactly 2 distinct recipes.")


func test_available_recipes_ignore_unknown_building_ids() -> void:
	if not _require_service():
		return
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["ghost_machine"]), _defs(), _string_ids(["ghost_machine"]))
	assert_eq(entries.size(), 0, "Placed ids without defs contribute no recipes.")


func test_available_recipes_only_powered_instances_among_duplicates() -> void:
	if not _require_service():
		return
	# 两台织机，供电判定只覆盖一台：配方仍可用（任一实例供电即可），但不得重复。
	var entries: Array[Dictionary] = _service.available_recipes(
		_state(["resonance_loom", "resonance_loom"]), _defs(), _string_ids(["resonance_loom"]))
	assert_eq(entries.size(), 2)


# --- recipe_inputs / can_craft ----------------------------------------------------


func test_recipe_inputs_normalize_single_and_dual_input() -> void:
	if not _require_service():
		return
	var single: Array[Dictionary] = _service.recipe_inputs(REFINER_RECIPE)
	assert_eq(single.size(), 1)
	if single.size() == 1:
		assert_eq(str(single[0]["item_id"]), "starsoil_dust")
		assert_eq(int(single[0]["count"]), 3)
	var dual: Array[Dictionary] = _service.recipe_inputs(LOOM_TRAP_RECIPE)
	assert_eq(dual.size(), 2, "extra_input fields extend the recipe to a second input.")
	if dual.size() == 2:
		assert_eq(str(dual[0]["item_id"]), "lumen_shard")
		assert_eq(str(dual[1]["item_id"]), "resonant_core")
		assert_eq(int(dual[1]["count"]), 1)


func test_recipe_inputs_empty_for_invalid_recipe() -> void:
	if not _require_service():
		return
	assert_eq(_service.recipe_inputs({}).size(), 0)


func test_can_craft_true_only_with_sufficient_inputs() -> void:
	if not _require_service():
		return
	assert_true(_service.can_craft(_state([], {"lumen_shard": 2}), LOOM_MIST_RECIPE))
	assert_false(_service.can_craft(_state([], {"lumen_shard": 1}), LOOM_MIST_RECIPE))
	assert_false(
		_service.can_craft(_state([], {"lumen_shard": 2}), LOOM_TRAP_RECIPE),
		"Dual-input recipe requires the extra input too."
	)
	assert_true(
		_service.can_craft(_state([], {"lumen_shard": 2, "resonant_core": 1}), LOOM_TRAP_RECIPE)
	)
	assert_false(_service.can_craft(_state([], {}), {}), "Invalid recipes are never craftable.")


# --- craft ------------------------------------------------------------------------


func test_craft_commits_single_patch_deducting_input_and_adding_output() -> void:
	if not _require_service():
		return
	_give("lumen_shard", 2)  # revision 0 -> 1
	var state: Dictionary = _store.snapshot()
	var result: AppResult = _service.craft(state, "resonance_loom", LOOM_MIST_RECIPE, _store)
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = _store.snapshot()
	var inventory: Dictionary = snapshot["inventory"]
	assert_false(inventory.has("lumen_shard"), "Exactly 2 shards were consumed and erased.")
	assert_eq(int(inventory.get("sedative_mist", 0)), 1, "Crafting yields 1 sedative_mist.")
	assert_eq(
		int(snapshot["revision"]), 2,
		"Craft commits exactly one patch on top of the give patch."
	)
	assert_true(
		(snapshot["applied_patch_sources"] as Array).has("crafting_resonance_loom_1"),
		"source_id must be crafting_<building_id>_<revision>."
	)


func test_craft_dual_input_recipe_deducts_both_inputs() -> void:
	if not _require_service():
		return
	_give("lumen_shard", 2)
	_give("resonant_core", 1)
	var state: Dictionary = _store.snapshot()
	var result: AppResult = _service.craft(state, "resonance_loom", LOOM_TRAP_RECIPE, _store)
	assert_true(result.is_ok, result.message)
	var inventory: Dictionary = _store.snapshot()["inventory"]
	assert_eq(int(inventory.get("shock_trap", 0)), 1)
	assert_false(inventory.has("lumen_shard"))
	assert_false(inventory.has("resonant_core"))


func test_craft_fails_insufficient_item_without_state_change() -> void:
	if not _require_service():
		return
	_give("lumen_shard", 1)  # revision 0 -> 1
	var state: Dictionary = _store.snapshot()
	var result: AppResult = _service.craft(state, "resonance_loom", LOOM_MIST_RECIPE, _store)
	assert_false(result.is_ok, "Missing input must fail the craft.")
	assert_eq(result.code, "insufficient_item")
	var snapshot: Dictionary = _store.snapshot()
	assert_eq(int(snapshot["revision"]), 1, "Failed craft must not advance revision.")
	assert_eq(int((snapshot["inventory"] as Dictionary).get("lumen_shard", 0)), 1)


func test_craft_fails_recipe_unavailable_for_invalid_recipe() -> void:
	if not _require_service():
		return
	var result: AppResult = _service.craft(_store.snapshot(), "resonance_loom", {}, _store)
	assert_false(result.is_ok)
	assert_eq(result.code, "recipe_unavailable")


func test_craft_replay_with_stale_state_is_idempotent() -> void:
	if not _require_service():
		return
	_give("lumen_shard", 4)
	var stale_state: Dictionary = _store.snapshot()
	var first: AppResult = _service.craft(stale_state, "resonance_loom", LOOM_MIST_RECIPE, _store)
	assert_true(first.is_ok, first.message)
	# 同一 stale 快照重放：source_id 已在 applied_patch_sources 中，不得重复扣料。
	var replay: AppResult = _service.craft(stale_state, "resonance_loom", LOOM_MIST_RECIPE, _store)
	assert_true(replay.is_ok, "Replay must be absorbed idempotently (already_applied).")
	assert_eq(replay.code, "already_applied")
	var inventory: Dictionary = _store.snapshot()["inventory"]
	assert_eq(int(inventory.get("lumen_shard", 0)), 2, "Replay must not deduct input again.")
	assert_eq(int(inventory.get("sedative_mist", 0)), 1, "Replay must not add output again.")


func _string_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	return result
