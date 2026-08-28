extends Node

const MAX_CELL_COORDINATE: int = 1_000_000

var _state: Dictionary = {}


func _init() -> void:
	_state = _make_initial_state()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func begin_patch(source_id: String, expected_revision: int) -> StatePatch:
	return StatePatch.new(source_id, expected_revision)


func commit(patch: StatePatch) -> AppResult:
	if patch == null:
		return AppResult.failure("invalid_patch", "StatePatch is required.")
	if not _is_stable_id(patch.source_id):
		return AppResult.failure("invalid_source_id", "Patch source_id must be a stable snake_case ID.")

	var applied_sources: Array = _state["applied_patch_sources"]
	if applied_sources.has(patch.source_id):
		return AppResult.success(snapshot(), "already_applied")
	if patch.expected_revision != _state["revision"]:
		return AppResult.failure(
			"revision_conflict",
			"Expected revision %d but current revision is %d." % [
				patch.expected_revision,
				_state["revision"],
			]
		)

	var operations: Array[Dictionary] = patch._operations_for_commit()
	if operations.is_empty():
		return AppResult.failure("empty_patch", "A patch must contain at least one operation.")

	var working: Dictionary = _state.duplicate(true)
	for operation: Dictionary in operations:
		var operation_result: AppResult = _apply_operation(working, operation)
		if not operation_result.is_ok:
			return operation_result

	working["revision"] = int(working["revision"]) + 1
	var working_sources: Array = working["applied_patch_sources"]
	working_sources.append(patch.source_id)
	_state = working
	return AppResult.success(snapshot(), "committed")


## Loading-lifecycle only. A fresh runtime may atomically adopt one fully validated
## snapshot. Gameplay code must use begin_patch()/commit().
func restore_snapshot(loaded_snapshot: Dictionary) -> AppResult:
	var validation: AppResult = SaveCodec.new().validate_snapshot(loaded_snapshot)
	if not validation.is_ok:
		return validation
	if int(_state["revision"]) != 0 or not (_state["applied_patch_sources"] as Array).is_empty():
		return AppResult.failure(
			"restore_requires_fresh_state",
			"A snapshot may only be restored into a fresh GameState runtime."
		)
	_state = (validation.value as Dictionary).duplicate(true)
	return AppResult.success(snapshot(), "restored_for_load")


func _apply_operation(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("type")) != TYPE_STRING:
		return AppResult.failure("invalid_operation", "Operation type must be a string.")
	var operation_type: String = operation["type"]
	match operation_type:
		StatePatch.OP_ADD_ITEM:
			return _apply_item_delta(working, operation, 1)
		StatePatch.OP_REMOVE_ITEM:
			return _apply_item_delta(working, operation, -1)
		StatePatch.OP_SET_DESTRUCTIBLE_CELL:
			return _apply_cell_delta(working, operation)
		StatePatch.OP_PLACE_BUILDING:
			return _apply_place_building(working, operation)
		StatePatch.OP_SET_FLAG:
			return _apply_set_flag(working, operation)
		_:
			return AppResult.failure("unsupported_operation", "Unsupported patch operation: %s" % operation_type)


func _apply_item_delta(working: Dictionary, operation: Dictionary, direction: int) -> AppResult:
	if typeof(operation.get("item_id")) != TYPE_STRING or not _is_stable_id(operation["item_id"]):
		return AppResult.failure("invalid_item_id", "Item ID must be stable snake_case.")
	if typeof(operation.get("amount")) != TYPE_INT or int(operation["amount"]) <= 0:
		return AppResult.failure("invalid_amount", "Item amount must be a positive integer.")

	var item_id: String = operation["item_id"]
	var amount: int = operation["amount"]
	var inventory: Dictionary = working["inventory"]
	var current: int = int(inventory.get(item_id, 0))
	if direction < 0 and current < amount:
		return AppResult.failure("insufficient_item", "Inventory does not contain enough %s." % item_id)
	var updated: int = current + amount * direction
	if updated < 0:
		return AppResult.failure("negative_inventory", "Inventory cannot become negative.")
	if updated == 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = updated
	return AppResult.success()


func _apply_cell_delta(working: Dictionary, operation: Dictionary) -> AppResult:
	var coordinate_result: AppResult = _validate_cell_operation(operation)
	if not coordinate_result.is_ok:
		return coordinate_result
	if typeof(operation.get("destroyed")) != TYPE_BOOL:
		return AppResult.failure("invalid_cell_delta", "Destroyed state must be boolean.")

	var chunk_id: String = operation["chunk_id"]
	var chunk_deltas: Dictionary = working["chunk_deltas"]
	if not chunk_deltas.has(chunk_id):
		chunk_deltas[chunk_id] = []
	var deltas: Array = chunk_deltas[chunk_id]
	for existing: Dictionary in deltas:
		if existing["cell_x"] == operation["cell_x"] and existing["cell_y"] == operation["cell_y"]:
			return AppResult.failure("cell_delta_exists", "A delta already exists for this cell.")
	deltas.append({
		"cell_x": operation["cell_x"],
		"cell_y": operation["cell_y"],
		"destroyed": operation["destroyed"],
	})
	return AppResult.success()


func _apply_place_building(working: Dictionary, operation: Dictionary) -> AppResult:
	var coordinate_result: AppResult = _validate_cell_operation(operation)
	if not coordinate_result.is_ok:
		return coordinate_result
	if typeof(operation.get("building_id")) != TYPE_STRING or not _is_stable_id(operation["building_id"]):
		return AppResult.failure("invalid_building_id", "Building ID must be stable snake_case.")

	var buildings: Array = working["placed_buildings"]
	for existing: Dictionary in buildings:
		if (
			existing["chunk_id"] == operation["chunk_id"]
			and existing["cell_x"] == operation["cell_x"]
			and existing["cell_y"] == operation["cell_y"]
		):
			return AppResult.failure("building_cell_occupied", "A building already occupies this cell.")
	buildings.append({
		"building_id": operation["building_id"],
		"chunk_id": operation["chunk_id"],
		"cell_x": operation["cell_x"],
		"cell_y": operation["cell_y"],
	})
	return AppResult.success()


func _apply_set_flag(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("flag_id")) != TYPE_STRING or not _is_stable_id(operation["flag_id"]):
		return AppResult.failure("invalid_flag_id", "Flag ID must be stable snake_case.")
	if typeof(operation.get("enabled")) != TYPE_BOOL:
		return AppResult.failure("invalid_flag_value", "Flag value must be boolean.")
	var flags: Dictionary = working["flags"]
	flags[operation["flag_id"]] = operation["enabled"]
	return AppResult.success()


func _validate_cell_operation(operation: Dictionary) -> AppResult:
	if typeof(operation.get("chunk_id")) != TYPE_STRING or not _is_stable_id(operation["chunk_id"]):
		return AppResult.failure("invalid_chunk_id", "Chunk ID must be stable snake_case.")
	for coordinate_key: String in ["cell_x", "cell_y"]:
		if typeof(operation.get(coordinate_key)) != TYPE_INT:
			return AppResult.failure("invalid_cell_coordinate", "Cell coordinates must be integers.")
		if abs(int(operation[coordinate_key])) > MAX_CELL_COORDINATE:
			return AppResult.failure("invalid_cell_coordinate", "Cell coordinate exceeds the supported range.")
	return AppResult.success()


func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


func _make_initial_state() -> Dictionary:
	return {
		"save_version": 1,
		"generator_version": 1,
		"content_hash": "",
		"revision": 0,
		"world_seed": 0,
		"player": {"position": {"x": 0, "y": 0}},
		"inventory": {},
		"flags": {},
		"world_enums": {},
		"chunk_deltas": {},
		"placed_buildings": [],
		"relationships": {},
		"ideology": {"stewardship": 0, "continuity": 0, "agency": 0},
		"completed_events": [],
		"battle_outcomes": {},
		"applied_patch_sources": [],
	}
