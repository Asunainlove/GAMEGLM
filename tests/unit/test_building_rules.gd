extends GutTest
## WP06 建造与放置 — BuildingRules contract tests.
##
## All fixtures use the frozen contract §7 content IDs. Tests depend only on the
## frozen module contract and local test doubles (DuckPatch/DuckStore, §0 store
## injection pattern); no other work package's files are referenced.
##
## The implementation is loaded dynamically so the file stays parseable while
## res://src/building/building_rules.gd is still missing (RED phase): every test
## then fails through _skip_without_implementation() instead of being silently
## skipped by a preload parse warning.

const RULES_SCRIPT_PATH: String = "res://src/building/building_rules.gd"
const CHUNK_ID: String = "chunk_0_0"
const OTHER_CHUNK_ID: String = "chunk_0_1"

const ANCHOR_BLOCK_DEF: Dictionary = {
	"id": "anchor_block",
	"inputs": [{"item_id": "starsoil_dust", "count": 2}],
}
const ANCHOR_WORKSHOP_DEF: Dictionary = {
	"id": "anchor_workshop",
	"inputs": [{"item_id": "starsoil_dust", "count": 4}],
}
const DUST_REFINER_DEF: Dictionary = {
	"id": "dust_refiner",
	"inputs": [{"item_id": "lumen_shard", "count": 2}],
}

var _rules_script: Script = null


func before_all() -> void:
	_rules_script = load(RULES_SCRIPT_PATH) as Script


func _skip_without_implementation() -> bool:
	if _rules_script == null:
		assert_true(false, "Missing required WP06 implementation: %s" % RULES_SCRIPT_PATH)
		return true
	return false


func _new_rules() -> RefCounted:
	return _rules_script.new() as RefCounted


## Static contract API (module-contracts §5), invoked through a dynamically
## loaded script instance (verified: static dispatch via instance works).
func _validate(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i
) -> AppResult:
	var rules: RefCounted = _new_rules()
	return rules.call("validate_placement", state, building_def, chunk_id, cell) as AppResult


func _build(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		store: Object
) -> AppResult:
	var rules: RefCounted = _new_rules()
	return rules.call("try_build", state, building_def, chunk_id, cell, store) as AppResult


func _state_with(
		inventory: Dictionary,
		buildings: Array[Dictionary],
		chunk_deltas: Dictionary,
		revision: int
) -> Dictionary:
	return {
		"revision": revision,
		"inventory": inventory,
		"chunk_deltas": chunk_deltas,
		"placed_buildings": buildings,
	}


func _building_at(building_id: String, chunk_id: String, cell: Vector2i) -> Dictionary:
	return {
		"building_id": building_id,
		"chunk_id": chunk_id,
		"cell_x": cell.x,
		"cell_y": cell.y,
	}


func _delta_at(cell: Vector2i, destroyed: bool) -> Dictionary:
	return {"cell_x": cell.x, "cell_y": cell.y, "destroyed": destroyed}


func _find_building(snapshot: Dictionary, chunk_id: String, cell: Vector2i) -> Dictionary:
	for existing: Dictionary in snapshot["placed_buildings"]:
		if (
			existing["chunk_id"] == chunk_id
			and int(existing["cell_x"]) == cell.x
			and int(existing["cell_y"]) == cell.y
		):
			return existing
	return {}


# --- Test doubles (contract §0 store-injection pattern) ---


class DuckPatch:
	var source_id: String
	var expected_revision: int
	var operations: Array[Dictionary] = []

	func _init(patch_source_id: String, patch_expected_revision: int) -> void:
		source_id = patch_source_id
		expected_revision = patch_expected_revision

	func remove_item(item_id: String, amount: int) -> DuckPatch:
		operations.append({"type": "remove_item", "item_id": item_id, "amount": amount})
		return self

	func place_building(building_id: String, chunk_id: String, cell_x: int, cell_y: int) -> DuckPatch:
		operations.append({
			"type": "place_building",
			"building_id": building_id,
			"chunk_id": chunk_id,
			"cell_x": cell_x,
			"cell_y": cell_y,
		})
		return self


class DuckStore:
	## Simulates GameState.commit semantics atomically over an in-memory state.
	var revision: int = 0
	var inventory: Dictionary = {}
	var placed_buildings: Array[Dictionary] = []
	var begin_patch_calls: int = 0
	var patches: Array[DuckPatch] = []
	var committed_source_ids: Array[String] = []

	func _init(store_inventory: Dictionary) -> void:
		inventory = store_inventory.duplicate(true)

	func snapshot() -> Dictionary:
		return {
			"revision": revision,
			"inventory": inventory.duplicate(true),
			"chunk_deltas": {},
			"placed_buildings": placed_buildings.duplicate(true),
		}

	func begin_patch(source_id: String, expected_revision: int) -> DuckPatch:
		begin_patch_calls += 1
		var patch: DuckPatch = DuckPatch.new(source_id, expected_revision)
		patches.append(patch)
		return patch

	func commit(patch: DuckPatch) -> AppResult:
		## Mirrors GameState.commit gate order: idempotency, revision, empty patch.
		if committed_source_ids.has(patch.source_id):
			return AppResult.success(snapshot(), "already_applied")
		if patch.expected_revision != revision:
			return AppResult.failure(
				"revision_conflict",
				"DuckStore revision is %d but the patch expected %d." % [
					revision,
					patch.expected_revision,
				]
			)
		if patch.operations.is_empty():
			return AppResult.failure("empty_patch", "A patch must contain at least one operation.")
		var working_inventory: Dictionary = inventory.duplicate(true)
		var working_buildings: Array[Dictionary] = placed_buildings.duplicate(true)
		for operation: Dictionary in patch.operations:
			match str(operation["type"]):
				"remove_item":
					var item_id: String = operation["item_id"]
					var have: int = int(working_inventory.get(item_id, 0))
					var amount: int = int(operation["amount"])
					if have < amount:
						return AppResult.failure(
							"insufficient_item", "DuckStore lacks %s." % item_id
						)
					working_inventory[item_id] = have - amount
				"place_building":
					for existing: Dictionary in working_buildings:
						if (
							existing["chunk_id"] == operation["chunk_id"]
							and int(existing["cell_x"]) == int(operation["cell_x"])
							and int(existing["cell_y"]) == int(operation["cell_y"])
						):
							return AppResult.failure(
								"building_cell_occupied", "DuckStore cell occupied."
							)
					working_buildings.append({
						"building_id": operation["building_id"],
						"chunk_id": operation["chunk_id"],
						"cell_x": int(operation["cell_x"]),
						"cell_y": int(operation["cell_y"]),
					})
				_:
					return AppResult.failure(
						"unsupported_operation",
						"DuckStore cannot apply %s." % str(operation.get("type"))
					)
		inventory = working_inventory
		placed_buildings = working_buildings
		revision += 1
		committed_source_ids.append(patch.source_id)
		return AppResult.success(snapshot(), "committed")


class RecordingCellLookup:
	## Cell-definition double for the injectable cell_lookup Callable:
	## signature Callable(chunk_id: String, cell: Vector2i) -> Dictionary.
	var calls: Array[Dictionary] = []
	var cell_defs: Dictionary = {}

	func on_cell_lookup(chunk_id: String, cell: Vector2i) -> Dictionary:
		calls.append({"chunk_id": chunk_id, "cell_x": cell.x, "cell_y": cell.y})
		var definition: Variant = cell_defs.get(cell, {})
		if typeof(definition) == TYPE_DICTIONARY:
			return definition
		return {}


# --- validate_placement ---


func test_validate_rejects_empty_definition_and_definition_without_id() -> void:
	if _skip_without_implementation():
		return
	var state: Dictionary = _state_with({}, [], {}, 0)

	var empty: AppResult = _validate(state, {}, CHUNK_ID, Vector2i(4, 6))
	assert_false(empty.is_ok)
	assert_eq(empty.code, "invalid_building")

	var no_id: AppResult = _validate(state, {"name_zh": "锚块"}, CHUNK_ID, Vector2i(4, 6))
	assert_false(no_id.is_ok)
	assert_eq(no_id.code, "invalid_building")


func test_validate_rejects_occupied_cell() -> void:
	if _skip_without_implementation():
		return
	var occupied: Vector2i = Vector2i(4, 6)
	var state: Dictionary = _state_with(
		{},
		[_building_at("anchor_block", CHUNK_ID, occupied)],
		{},
		0
	)

	var same_id: AppResult = _validate(state, ANCHOR_BLOCK_DEF, CHUNK_ID, occupied)
	assert_false(same_id.is_ok)
	assert_eq(same_id.code, "building_cell_occupied")

	var other_id: AppResult = _validate(state, DUST_REFINER_DEF, CHUNK_ID, occupied)
	assert_false(other_id.is_ok)
	assert_eq(other_id.code, "building_cell_occupied")


func test_validate_rejects_destroyed_cell_from_chunk_deltas() -> void:
	if _skip_without_implementation():
		return
	var destroyed: Vector2i = Vector2i(4, 6)
	var state: Dictionary = _state_with(
		{}, [], {CHUNK_ID: [_delta_at(destroyed, true)]}, 0
	)

	var result: AppResult = _validate(state, ANCHOR_BLOCK_DEF, CHUNK_ID, destroyed)
	assert_false(result.is_ok)
	assert_eq(result.code, "cell_destroyed")


func test_validate_allows_cell_with_intact_delta_and_cell_without_delta() -> void:
	if _skip_without_implementation():
		return
	var repaired: Vector2i = Vector2i(4, 6)
	var repaired_state: Dictionary = _state_with(
		{}, [], {CHUNK_ID: [_delta_at(repaired, false)]}, 0
	)
	var intact: AppResult = _validate(repaired_state, ANCHOR_BLOCK_DEF, CHUNK_ID, repaired)
	assert_true(intact.is_ok, intact.message)

	var undeltaed: AppResult = _validate(
		_state_with({}, [], {}, 0), ANCHOR_BLOCK_DEF, CHUNK_ID, repaired
	)
	assert_true(undeltaed.is_ok, undeltaed.message)


func test_validate_allows_anchor_block_without_neighbors() -> void:
	if _skip_without_implementation():
		return
	var result: AppResult = _validate(
		_state_with({}, [], {}, 0), ANCHOR_BLOCK_DEF, CHUNK_ID, Vector2i(4, 6)
	)
	assert_true(result.is_ok, result.message)


func test_validate_rejects_non_anchor_without_neighbors() -> void:
	if _skip_without_implementation():
		return
	var state: Dictionary = _state_with({}, [], {}, 0)

	var workshop: AppResult = _validate(state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(4, 6))
	assert_false(workshop.is_ok)
	assert_eq(workshop.code, "no_nearby_structure")

	var refiner: AppResult = _validate(state, DUST_REFINER_DEF, CHUNK_ID, Vector2i(4, 6))
	assert_false(refiner.is_ok)
	assert_eq(refiner.code, "no_nearby_structure")


func test_validate_allows_neighbor_within_chebyshev_three() -> void:
	if _skip_without_implementation():
		return
	var neighbor: Vector2i = Vector2i(10, 10)
	var state: Dictionary = _state_with(
		{},
		[_building_at("anchor_block", CHUNK_ID, neighbor)],
		{},
		0
	)

	var diagonal_three: AppResult = _validate(
		state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(13, 13)
	)
	assert_true(diagonal_three.is_ok, diagonal_three.message)

	var straight_three: AppResult = _validate(
		state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(7, 10)
	)
	assert_true(straight_three.is_ok, straight_three.message)


func test_validate_rejects_neighbor_beyond_chebyshev_three() -> void:
	if _skip_without_implementation():
		return
	var neighbor: Vector2i = Vector2i(10, 10)
	var state: Dictionary = _state_with(
		{},
		[_building_at("anchor_block", CHUNK_ID, neighbor)],
		{},
		0
	)

	var straight_four: AppResult = _validate(
		state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(14, 10)
	)
	assert_false(straight_four.is_ok)
	assert_eq(straight_four.code, "no_nearby_structure")

	var diagonal_four: AppResult = _validate(
		state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(14, 13)
	)
	assert_false(diagonal_four.is_ok)
	assert_eq(diagonal_four.code, "no_nearby_structure")


func test_validate_ignores_neighbors_in_other_chunks() -> void:
	if _skip_without_implementation():
		return
	var neighbor: Vector2i = Vector2i(11, 10)
	var state: Dictionary = _state_with(
		{},
		[_building_at("anchor_block", OTHER_CHUNK_ID, neighbor)],
		{},
		0
	)

	var workshop: AppResult = _validate(
		state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, Vector2i(13, 10)
	)
	assert_false(workshop.is_ok)
	assert_eq(workshop.code, "no_nearby_structure")

	var anchor: AppResult = _validate(state, ANCHOR_BLOCK_DEF, CHUNK_ID, Vector2i(13, 10))
	assert_true(anchor.is_ok, anchor.message)


func test_validate_injected_cell_lookup_reports_destroyed_cell() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var lookup: RecordingCellLookup = RecordingCellLookup.new()
	lookup.cell_defs = {target: {"destroyed": true}}
	var rules: RefCounted = _new_rules()
	rules.set("cell_lookup", Callable(lookup, "on_cell_lookup"))

	var state: Dictionary = _state_with({}, [], {}, 0)
	var result: AppResult = rules.call(
		"check_placement", state, ANCHOR_BLOCK_DEF, CHUNK_ID, target
	) as AppResult

	assert_false(result.is_ok)
	assert_eq(result.code, "cell_destroyed")
	assert_eq(lookup.calls.size(), 1, "Injected cell_lookup must be consulted.")
	assert_eq(
		lookup.calls[0],
		{"chunk_id": CHUNK_ID, "cell_x": target.x, "cell_y": target.y}
	)


func test_validate_injected_cell_lookup_does_not_override_recorded_delta() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var lookup: RecordingCellLookup = RecordingCellLookup.new()
	var rules: RefCounted = _new_rules()
	rules.set("cell_lookup", Callable(lookup, "on_cell_lookup"))

	var destroyed_state: Dictionary = _state_with(
		{}, [], {CHUNK_ID: [_delta_at(target, true)]}, 0
	)
	var result: AppResult = rules.call(
		"check_placement", destroyed_state, ANCHOR_BLOCK_DEF, CHUNK_ID, target
	) as AppResult
	assert_false(result.is_ok)
	assert_eq(result.code, "cell_destroyed")


func test_validate_injected_cell_lookup_reports_intact_cell() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var lookup: RecordingCellLookup = RecordingCellLookup.new()
	lookup.cell_defs = {target: {"destroyed": false}}
	var rules: RefCounted = _new_rules()
	rules.set("cell_lookup", Callable(lookup, "on_cell_lookup"))

	var result: AppResult = rules.call(
		"check_placement", _state_with({}, [], {}, 0), ANCHOR_BLOCK_DEF, CHUNK_ID, target
	) as AppResult
	assert_true(result.is_ok, result.message)
	assert_eq(lookup.calls.size(), 1, "Injected cell_lookup must be consulted.")


# --- try_build ---


func test_try_build_success_deducts_materials_and_places_building() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var store: DuckStore = DuckStore.new({"starsoil_dust": 5})
	var state: Dictionary = store.snapshot()

	var result: AppResult = _build(state, ANCHOR_BLOCK_DEF, CHUNK_ID, target, store)
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "committed")

	assert_eq(store.inventory.get("starsoil_dust", 0), 3)
	assert_eq(store.revision, 1)
	assert_eq(
		store.placed_buildings,
		[_building_at("anchor_block", CHUNK_ID, target)] as Array[Dictionary]
	)
	assert_eq(store.committed_source_ids, ["building_anchor_block_4_6"] as Array[String])

	var committed: Dictionary = result.value as Dictionary
	assert_eq(
		_find_building(committed, CHUNK_ID, target)["building_id"],
		"anchor_block"
	)
	assert_eq(int(committed["inventory"].get("starsoil_dust", 0)), 3)


func test_try_build_records_exactly_remove_then_place_operations() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var store: DuckStore = DuckStore.new({"starsoil_dust": 5})

	var result: AppResult = _build(
		store.snapshot(), ANCHOR_BLOCK_DEF, CHUNK_ID, target, store
	)
	assert_true(result.is_ok, result.message)

	assert_eq(store.patches.size(), 1, "Exactly one patch must be committed.")
	var patch: DuckPatch = store.patches[0]
	assert_eq(patch.source_id, "building_anchor_block_4_6")
	assert_eq(patch.expected_revision, 0)
	var expected: Array[Dictionary] = [
		{"type": "remove_item", "item_id": "starsoil_dust", "amount": 2},
		{
			"type": "place_building",
			"building_id": "anchor_block",
			"chunk_id": CHUNK_ID,
			"cell_x": target.x,
			"cell_y": target.y,
		},
	]
	assert_eq(patch.operations, expected, "Operations must be exactly remove_item xN + place_building.")


func test_try_build_insufficient_materials_leaves_store_untouched() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var neighbor: Dictionary = _building_at("anchor_block", CHUNK_ID, Vector2i(4, 5))
	var store: DuckStore = DuckStore.new({"starsoil_dust": 1})
	var baseline: Dictionary = store.snapshot()
	var state: Dictionary = _state_with(
		{"starsoil_dust": 1}, [neighbor], {}, int(baseline["revision"])
	)

	var result: AppResult = _build(state, ANCHOR_WORKSHOP_DEF, CHUNK_ID, target, store)
	assert_false(result.is_ok)
	assert_eq(result.code, "insufficient_item")
	assert_true(result.message.contains("starsoil_dust"), "Message must name the missing item.")

	assert_eq(store.revision, 0, "Failed build must not bump the revision.")
	assert_eq(store.begin_patch_calls, 0, "Failed build must not open a patch.")
	assert_eq(store.inventory, baseline["inventory"])
	assert_eq(store.placed_buildings.size(), 0)


func test_try_build_failure_message_names_missing_item() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var neighbor: Dictionary = _building_at("anchor_block", CHUNK_ID, Vector2i(4, 5))
	var store: DuckStore = DuckStore.new({"lumen_shard": 1})
	var state: Dictionary = _state_with(
		{"lumen_shard": 1}, [neighbor], {}, int(store.snapshot()["revision"])
	)

	var result: AppResult = _build(state, DUST_REFINER_DEF, CHUNK_ID, target, store)
	assert_false(result.is_ok)
	assert_eq(result.code, "insufficient_item")
	assert_true(result.message.contains("lumen_shard"), "Message must name the missing item.")
	assert_eq(store.begin_patch_calls, 0)


func test_try_build_validates_placement_before_materials() -> void:
	if _skip_without_implementation():
		return
	var far: Vector2i = Vector2i(20, 20)
	var store: DuckStore = DuckStore.new({})

	var result: AppResult = _build(store.snapshot(), DUST_REFINER_DEF, CHUNK_ID, far, store)
	assert_false(result.is_ok)
	assert_eq(result.code, "no_nearby_structure", "Placement validation must run before materials.")
	assert_eq(store.begin_patch_calls, 0)


func test_try_build_rejects_second_building_on_same_cell() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var store: DuckStore = DuckStore.new({"starsoil_dust": 8})
	store.placed_buildings.append(_building_at("anchor_block", CHUNK_ID, target))
	var baseline: Dictionary = store.snapshot()

	var result: AppResult = _build(baseline, ANCHOR_WORKSHOP_DEF, CHUNK_ID, target, store)
	assert_false(result.is_ok)
	assert_eq(result.code, "building_cell_occupied")
	assert_eq(store.begin_patch_calls, 0)
	assert_eq(store.inventory, baseline["inventory"])
	assert_eq(store.placed_buildings, baseline["placed_buildings"] as Array[Dictionary])


func test_try_build_honors_injected_cell_lookup() -> void:
	if _skip_without_implementation():
		return
	var target: Vector2i = Vector2i(4, 6)
	var lookup: RecordingCellLookup = RecordingCellLookup.new()
	lookup.cell_defs = {target: {"destroyed": true}}
	var rules: RefCounted = _new_rules()
	rules.set("cell_lookup", Callable(lookup, "on_cell_lookup"))
	var store: DuckStore = DuckStore.new({"starsoil_dust": 5})

	var result: AppResult = rules.call(
		"attempt_build", store.snapshot(), ANCHOR_BLOCK_DEF, CHUNK_ID, target, store
	) as AppResult
	assert_false(result.is_ok)
	assert_eq(result.code, "cell_destroyed")
	assert_eq(lookup.calls.size(), 1, "Injected cell_lookup must be consulted.")
	assert_eq(store.begin_patch_calls, 0, "Destroyed terrain must prevent any patch.")


func test_try_build_passes_through_store_commit_failure() -> void:
	if _skip_without_implementation():
		return
	var stale_state: Dictionary = _state_with({"starsoil_dust": 5}, [], {}, 3)
	var store: DuckStore = DuckStore.new({"starsoil_dust": 5})

	var result: AppResult = _build(
		stale_state, ANCHOR_BLOCK_DEF, CHUNK_ID, Vector2i(4, 6), store
	)
	assert_false(result.is_ok)
	assert_eq(result.code, "revision_conflict")
	assert_eq(store.committed_source_ids.size(), 0)
	assert_eq(store.inventory.get("starsoil_dust", 0), 5)
	assert_eq(store.revision, 0)


func test_try_build_without_store_commits_through_game_state_autoload() -> void:
	if _skip_without_implementation():
		return
	var fund_revision: int = int(GameState.snapshot()["revision"])
	var fund_patch: StatePatch = GameState.begin_patch("wp06_test_fund_autoload_build", fund_revision)
	fund_patch.add_item("starsoil_dust", 5)
	var funded: AppResult = GameState.commit(fund_patch)
	assert_true(funded.is_ok, funded.message)

	var target: Vector2i = Vector2i(40001, 40002)
	var rules: RefCounted = _new_rules()
	var result: AppResult = rules.call(
		"try_build", GameState.snapshot(), ANCHOR_BLOCK_DEF, CHUNK_ID, target
	) as AppResult
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "committed")

	var after: Dictionary = GameState.snapshot()
	assert_eq(int(after["inventory"].get("starsoil_dust", 0)), 3)
	assert_eq(
		_find_building(after, CHUNK_ID, target)["building_id"],
		"anchor_block"
	)

	var second: AppResult = rules.call(
		"try_build", GameState.snapshot(), ANCHOR_BLOCK_DEF, CHUNK_ID, target
	) as AppResult
	assert_false(second.is_ok)
	assert_eq(second.code, "building_cell_occupied")
	assert_eq(int(GameState.snapshot()["revision"]), int(after["revision"]))
