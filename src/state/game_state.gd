extends Node

const MAX_CELL_COORDINATE: int = 1_000_000
const RELATIONSHIP_DIMENSIONS: Array[String] = ["affection", "trust", "ideology"]
const MAX_RELATIONSHIP_SCORE: int = 100
const IDEOLOGY_AXES: Array[String] = ["stewardship", "continuity", "agency"]
const MIN_IDEOLOGY_SCORE: int = -100
const MAX_IDEOLOGY_SCORE: int = 100
const BATTLE_RESULTS: Array[String] = ["victory", "defeat"]

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
		StatePatch.OP_SET_RELATIONSHIP:
			return _apply_set_relationship(working, operation)
		StatePatch.OP_ADJUST_IDEOLOGY:
			return _apply_adjust_ideology(working, operation)
		StatePatch.OP_COMPLETE_EVENT:
			return _apply_complete_event(working, operation)
		StatePatch.OP_RECORD_BATTLE_OUTCOME:
			return _apply_record_battle_outcome(working, operation)
		StatePatch.OP_SET_PLAYER_POSITION:
			return _apply_set_player_position(working, operation)
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


func _apply_set_relationship(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("char_id")) != TYPE_STRING or not _is_stable_id(operation["char_id"]):
		return AppResult.failure("invalid_char_id", "Character ID must be stable snake_case.")
	if typeof(operation.get("dim")) != TYPE_STRING or not RELATIONSHIP_DIMENSIONS.has(operation["dim"]):
		return AppResult.failure("invalid_dim", "Relationship dimension must be affection, trust, or ideology.")
	if typeof(operation.get("value")) != TYPE_INT:
		return AppResult.failure("invalid_relationship_value", "Relationship value must be an integer.")

	var char_id: String = operation["char_id"]
	var relationships: Dictionary = working["relationships"]
	if not relationships.has(char_id):
		relationships[char_id] = {"affection": 0, "trust": 0, "ideology": 0}
	var record: Dictionary = relationships[char_id]
	record[operation["dim"]] = clampi(int(operation["value"]), 0, MAX_RELATIONSHIP_SCORE)
	return AppResult.success()


func _apply_adjust_ideology(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("axis")) != TYPE_STRING or not IDEOLOGY_AXES.has(operation["axis"]):
		return AppResult.failure("invalid_ideology_axis", "Ideology axis must be stewardship, continuity, or agency.")
	if typeof(operation.get("delta")) != TYPE_INT:
		return AppResult.failure("invalid_ideology_delta", "Ideology delta must be an integer.")

	var ideology: Dictionary = working["ideology"]
	var adjusted: int = int(ideology[operation["axis"]]) + int(operation["delta"])
	ideology[operation["axis"]] = clampi(adjusted, MIN_IDEOLOGY_SCORE, MAX_IDEOLOGY_SCORE)
	return AppResult.success()


func _apply_complete_event(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("event_id")) != TYPE_STRING or not _is_stable_id(operation["event_id"]):
		return AppResult.failure("invalid_event_id", "Event ID must be stable snake_case.")

	var completed_events: Array = working["completed_events"]
	if completed_events.has(operation["event_id"]):
		return AppResult.success()
	completed_events.append(operation["event_id"])
	return AppResult.success()


func _apply_record_battle_outcome(working: Dictionary, operation: Dictionary) -> AppResult:
	if typeof(operation.get("battle_id")) != TYPE_STRING or not _is_stable_id(operation["battle_id"]):
		return AppResult.failure("invalid_battle_id", "Battle ID must be stable snake_case.")
	if typeof(operation.get("result")) != TYPE_STRING or not BATTLE_RESULTS.has(operation["result"]):
		return AppResult.failure("invalid_battle_result", "Battle result must be victory or defeat.")
	if typeof(operation.get("turns")) != TYPE_INT or int(operation["turns"]) < 0:
		return AppResult.failure("invalid_battle_result", "Battle turns must be a non-negative integer.")

	var battle_outcomes: Dictionary = working["battle_outcomes"]
	battle_outcomes[operation["battle_id"]] = {
		"result": operation["result"],
		"turns": int(operation["turns"]),
	}
	return AppResult.success()


func _apply_set_player_position(working: Dictionary, operation: Dictionary) -> AppResult:
	for coordinate_key: String in ["cell_x", "cell_y"]:
		if typeof(operation.get(coordinate_key)) != TYPE_INT:
			return AppResult.failure("invalid_cell_coordinate", "Cell coordinates must be integers.")
		if abs(int(operation[coordinate_key])) > MAX_CELL_COORDINATE:
			return AppResult.failure("invalid_cell_coordinate", "Cell coordinate exceeds the supported range.")

	var player: Dictionary = working["player"]
	player["position"] = {"x": int(operation["cell_x"]), "y": int(operation["cell_y"])}
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
