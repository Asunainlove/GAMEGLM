class_name BuildingRules
extends RefCounted
## WP06 建造与放置 — pure-logic placement rules and material-costed builds.
##
## Frozen contract API (docs/plans/contracts/module-contracts.md §5) is static:
##   - validate_placement(state, building_def, chunk_id, cell) -> AppResult
##   - try_build(state, building_def, chunk_id, cell, store = null) -> AppResult
## The static entry points judge cell destruction from the snapshot's
## chunk_deltas only (no terrain query), and try_build delegates to the
## GameState Autoload when store is null (contract §0 injection pattern).
##
## Terrain-aware callers (e.g. WP03 world) instantiate BuildingRules, inject
## cell_lookup, and use the instance methods check_placement()/attempt_build().
## cell_lookup signature: Callable(chunk_id: String, cell: Vector2i) -> Dictionary
## returning the cell definition; a definition with destroyed == true rejects
## the cell. The injected lookup never overrides a recorded destroyed delta —
## the two sources are combined (either one destroys the cell).
##
## Validation order: invalid_building -> building_cell_occupied -> cell_destroyed
## -> no_nearby_structure. try_build runs the full placement validation before
## the material check, then commits exactly one atomic patch per build.

const NEIGHBOR_EXEMPT_BUILDING_ID: String = "anchor_block"
const NEIGHBOR_MAX_CHEBYSHEV_DISTANCE: int = 3

## Optional injectable terrain query: Callable(chunk_id: String, cell: Vector2i) -> Dictionary.
var cell_lookup: Callable = Callable()


## Instance path: honors the injected cell_lookup for the destruction check.
func check_placement(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i
) -> AppResult:
	return _validate_placement(state, building_def, chunk_id, cell, cell_lookup)


## Instance path: honors the injected cell_lookup; store injection per contract §0
## (null delegates to the GameState Autoload).
func attempt_build(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		store: Object = null
) -> AppResult:
	return _try_build(state, building_def, chunk_id, cell, store, cell_lookup)


## Frozen contract API (module-contracts §5).
static func validate_placement(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i
) -> AppResult:
	return _validate_placement(state, building_def, chunk_id, cell, Callable())


## Frozen contract API (module-contracts §5). store == null delegates to the
## GameState Autoload; otherwise store must expose snapshot/begin_patch/commit.
static func try_build(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		store: Object = null
) -> AppResult:
	return _try_build(state, building_def, chunk_id, cell, store, Callable())


static func _validate_placement(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		cell_lookup: Callable
) -> AppResult:
	var id_result: AppResult = _require_building_id(building_def)
	if not id_result.is_ok:
		return id_result

	var occupied_result: AppResult = _check_cell_occupied(state, chunk_id, cell)
	if not occupied_result.is_ok:
		return occupied_result

	var destroyed_result: AppResult = _check_cell_destroyed(state, chunk_id, cell, cell_lookup)
	if not destroyed_result.is_ok:
		return destroyed_result

	if str(building_def["id"]) != NEIGHBOR_EXEMPT_BUILDING_ID:
		var adjacency_result: AppResult = _check_adjacent_structure(state, chunk_id, cell)
		if not adjacency_result.is_ok:
			return adjacency_result

	return AppResult.success()


static func _try_build(
		state: Dictionary,
		building_def: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		store: Object,
		cell_lookup: Callable
) -> AppResult:
	var placement: AppResult = _validate_placement(state, building_def, chunk_id, cell, cell_lookup)
	if not placement.is_ok:
		return placement

	var building_id: String = building_def["id"]
	var inputs: Array = building_def.get("inputs", [])
	var inventory: Dictionary = state.get("inventory", {})
	var missing: Array[String] = []
	var amounts: Dictionary = {}
	for input_entry: Dictionary in inputs:
		var item_id_variant: Variant = input_entry.get("item_id")
		var count_variant: Variant = input_entry.get("count")
		if typeof(item_id_variant) != TYPE_STRING or not (typeof(count_variant) in [TYPE_INT, TYPE_FLOAT]):
			return AppResult.failure(
				"invalid_building",
				"Each building input requires a string item_id and a numeric count."
			)
		var item_id: String = item_id_variant
		var required: int = int(count_variant)
		amounts[item_id] = amounts.get(item_id, 0) + required
		if int(inventory.get(item_id, 0)) < int(amounts[item_id]):
			missing.append(item_id)
	if not missing.is_empty():
		return AppResult.failure(
			"insufficient_item",
			"Building %s is missing required items: %s." % [building_id, ", ".join(missing)]
		)

	var source_id: String = "building_%s_%d_%d" % [building_id, cell.x, cell.y]
	var effective_store: Object = store
	if effective_store == null:
		effective_store = GameState

	var patch: Variant = effective_store.begin_patch(source_id, int(state.get("revision", 0)))
	for input_entry: Dictionary in inputs:
		patch.remove_item(str(input_entry["item_id"]), int(input_entry["count"]))
	patch.place_building(building_id, chunk_id, cell.x, cell.y)
	return effective_store.commit(patch)


static func _require_building_id(building_def: Dictionary) -> AppResult:
	if building_def.is_empty() or not building_def.has("id"):
		return AppResult.failure("invalid_building", "A building definition with an id is required.")
	if typeof(building_def["id"]) != TYPE_STRING or (building_def["id"] as String).is_empty():
		return AppResult.failure("invalid_building", "The building id must be a non-empty string.")
	return AppResult.success()


static func _check_cell_occupied(state: Dictionary, chunk_id: String, cell: Vector2i) -> AppResult:
	var buildings: Array = state.get("placed_buildings", [])
	for existing: Dictionary in buildings:
		if (
			str(existing.get("chunk_id", "")) == chunk_id
			and int(existing.get("cell_x", 0)) == cell.x
			and int(existing.get("cell_y", 0)) == cell.y
		):
			return AppResult.failure(
				"building_cell_occupied", "A building already occupies this cell."
			)
	return AppResult.success()


static func _check_cell_destroyed(
		state: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		cell_lookup: Callable
) -> AppResult:
	var chunk_deltas: Dictionary = state.get("chunk_deltas", {})
	var deltas: Array = chunk_deltas.get(chunk_id, [])
	for delta: Dictionary in deltas:
		if (
			int(delta.get("cell_x", 0)) == cell.x
			and int(delta.get("cell_y", 0)) == cell.y
			and bool(delta.get("destroyed", false))
		):
			return AppResult.failure(
				"cell_destroyed", "This cell was destroyed and cannot host a building."
			)

	if cell_lookup.is_valid():
		var cell_def: Variant = cell_lookup.call(chunk_id, cell)
		if typeof(cell_def) == TYPE_DICTIONARY and bool((cell_def as Dictionary).get("destroyed", false)):
			return AppResult.failure(
				"cell_destroyed", "The terrain reports this cell as destroyed."
			)
	return AppResult.success()


static func _check_adjacent_structure(state: Dictionary, chunk_id: String, cell: Vector2i) -> AppResult:
	var buildings: Array = state.get("placed_buildings", [])
	for existing: Dictionary in buildings:
		if str(existing.get("chunk_id", "")) != chunk_id:
			continue
		var distance: int = maxi(
			absi(int(existing.get("cell_x", 0)) - cell.x),
			absi(int(existing.get("cell_y", 0)) - cell.y)
		)
		if distance <= NEIGHBOR_MAX_CHEBYSHEV_DISTANCE:
			return AppResult.success()
	return AppResult.failure(
		"no_nearby_structure",
		"A structure within Chebyshev distance %d in the same chunk is required."
			% NEIGHBOR_MAX_CHEBYSHEV_DISTANCE
	)
