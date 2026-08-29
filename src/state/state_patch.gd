class_name StatePatch
extends RefCounted

const OP_ADD_ITEM: String = "add_item"
const OP_REMOVE_ITEM: String = "remove_item"
const OP_SET_DESTRUCTIBLE_CELL: String = "set_destructible_cell"
const OP_PLACE_BUILDING: String = "place_building"
const OP_SET_FLAG: String = "set_flag"
const OP_SET_RELATIONSHIP: String = "set_relationship"
const OP_ADJUST_IDEOLOGY: String = "adjust_ideology"
const OP_COMPLETE_EVENT: String = "complete_event"
const OP_RECORD_BATTLE_OUTCOME: String = "record_battle_outcome"
const OP_SET_PLAYER_POSITION: String = "set_player_position"

var source_id: String
var expected_revision: int
var _operations: Array[Dictionary] = []


func _init(p_source_id: String, p_expected_revision: int) -> void:
	source_id = p_source_id
	expected_revision = p_expected_revision


func add_item(item_id: String, amount: int) -> StatePatch:
	_operations.append({"type": OP_ADD_ITEM, "item_id": item_id, "amount": amount})
	return self


func remove_item(item_id: String, amount: int) -> StatePatch:
	_operations.append({"type": OP_REMOVE_ITEM, "item_id": item_id, "amount": amount})
	return self


func set_destructible_cell(
		chunk_id: String,
		cell_x: int,
		cell_y: int,
		destroyed: bool
) -> StatePatch:
	_operations.append({
		"type": OP_SET_DESTRUCTIBLE_CELL,
		"chunk_id": chunk_id,
		"cell_x": cell_x,
		"cell_y": cell_y,
		"destroyed": destroyed,
	})
	return self


func place_building(
		building_id: String,
		chunk_id: String,
		cell_x: int,
		cell_y: int
) -> StatePatch:
	_operations.append({
		"type": OP_PLACE_BUILDING,
		"building_id": building_id,
		"chunk_id": chunk_id,
		"cell_x": cell_x,
		"cell_y": cell_y,
	})
	return self


func set_flag(flag_id: String, enabled: bool) -> StatePatch:
	_operations.append({"type": OP_SET_FLAG, "flag_id": flag_id, "enabled": enabled})
	return self


func set_relationship(char_id: String, dim: String, value: int) -> StatePatch:
	_operations.append({
		"type": OP_SET_RELATIONSHIP,
		"char_id": char_id,
		"dim": dim,
		"value": value,
	})
	return self


func adjust_ideology(axis: String, delta: int) -> StatePatch:
	_operations.append({"type": OP_ADJUST_IDEOLOGY, "axis": axis, "delta": delta})
	return self


func complete_event(event_id: String) -> StatePatch:
	_operations.append({"type": OP_COMPLETE_EVENT, "event_id": event_id})
	return self


func record_battle_outcome(battle_id: String, result: String, turns: int) -> StatePatch:
	_operations.append({
		"type": OP_RECORD_BATTLE_OUTCOME,
		"battle_id": battle_id,
		"result": result,
		"turns": turns,
	})
	return self


func set_player_position(cell_x: int, cell_y: int) -> StatePatch:
	_operations.append({"type": OP_SET_PLAYER_POSITION, "cell_x": cell_x, "cell_y": cell_y})
	return self


func _operations_for_commit() -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for operation: Dictionary in _operations:
		copied.append(operation.duplicate(true))
	return copied
