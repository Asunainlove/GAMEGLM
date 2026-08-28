class_name PowerGrid
extends RefCounted

## WP07 房间与电力：纯逻辑模块（RefCounted，无场景树 / GameState 依赖）。
##
## 房间 = 同 chunk 内建筑 footprint（每建筑 1 格）的最大 4 连通组，且至少含 2 座
## 建筑：单座孤立建筑（孤岛）不构成房间，因此 `requires_room` 建筑必须与至少一座
## 同 chunk 建筑相邻才被视为有效（契约 §5 的“位于任一房间内”）。
##
## 供给按 `buildings` 输入序分配：`available` 从 0 起，迭代中遇 `power_supply > 0`
## 先累加，遇 `power_draw > 0` 按序尝试占用。输入/输出全部为 Dictionary/Array。

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


## 返回按发现序（输入序）排列的房间列表，元素形如
## `{"building_ids": Array[String], "cells": Array[Vector2i]}`，成员保持输入序。
static func find_rooms(buildings: Array) -> Array[Dictionary]:
	return _room_dictionaries(buildings, _find_room_indices(buildings))


## 按输入序分配供给并评估满足度。`defs`：building_id ->
## `{"power_draw": int, "power_supply": int, "requires_room": bool}`（缺省 0 / 0 / false）。
## 返回 `{"supply": int, "demand": int, "satisfied": bool,
## "powered_ids": Array[String], "rooms": Array[Dictionary]}`；
## satisfied = 所有 power_draw > 0 的建筑均获电。
static func evaluate(buildings: Array, defs: Dictionary) -> Dictionary:
	var room_groups: Array[Array] = _find_room_indices(buildings)
	var room_of_entry: Dictionary = {}
	for room_index: int in room_groups.size():
		for member_index: int in room_groups[room_index]:
			room_of_entry[member_index] = room_index

	var supply_total := 0
	var demand_total := 0
	var demand_entry_count := 0
	var available := 0
	var powered_ids: Array[String] = []

	for entry_index: int in buildings.size():
		var entry: Dictionary = buildings[entry_index]
		var building_id: String = str(entry.get("building_id", ""))
		var building_def: Dictionary = _definition_for(defs, building_id)
		var power_supply := int(building_def.get("power_supply", 0))
		var power_draw := int(building_def.get("power_draw", 0))
		var requires_room := bool(building_def.get("requires_room", false))

		supply_total += power_supply
		if power_supply > 0:
			available += power_supply
		if power_draw <= 0:
			continue

		demand_total += power_draw
		demand_entry_count += 1
		var in_room: bool = room_of_entry.has(entry_index)
		if available >= power_draw and (not requires_room or in_room):
			available -= power_draw
			powered_ids.append(building_id)

	return {
		"supply": supply_total,
		"demand": demand_total,
		"satisfied": powered_ids.size() == demand_entry_count,
		"powered_ids": powered_ids,
		"rooms": _room_dictionaries(buildings, room_groups),
	}


## 内部：按输入序 BFS，返回每个房间成员的建筑下标数组（升序 = 输入序），
## 房间按发现序（首个成员的输入序）排列；仅保留大小 >= 2 的连通组。
## 相邻 = 同 chunk 且 |dx| + |dy| == 1；同格重复条目互不相邻，保持孤岛。
static func _find_room_indices(buildings: Array) -> Array[Array]:
	var entry_count := buildings.size()
	var chunk_ids: Array[String] = []
	chunk_ids.resize(entry_count)
	var cells: Array[Vector2i] = []
	cells.resize(entry_count)
	var occupants: Dictionary = {}
	for entry_index: int in entry_count:
		var entry: Dictionary = buildings[entry_index]
		var chunk_id: String = str(entry.get("chunk_id", ""))
		var cell := Vector2i(int(entry.get("cell_x", 0)), int(entry.get("cell_y", 0)))
		chunk_ids[entry_index] = chunk_id
		cells[entry_index] = cell
		if not occupants.has(chunk_id):
			occupants[chunk_id] = {}
		var chunk_map: Dictionary = occupants[chunk_id]
		if not chunk_map.has(cell):
			chunk_map[cell] = entry_index

	var assigned: Array[bool] = []
	assigned.resize(entry_count)
	var room_groups: Array[Array] = []
	for seed_index: int in entry_count:
		if assigned[seed_index]:
			continue
		var members: Array[int] = [seed_index]
		assigned[seed_index] = true
		var head := 0
		while head < members.size():
			var current: int = members[head]
			head += 1
			var chunk_map: Dictionary = occupants.get(chunk_ids[current], {})
			for offset: Vector2i in _NEIGHBOR_OFFSETS:
				var neighbor_cell: Vector2i = cells[current] + offset
				if not chunk_map.has(neighbor_cell):
					continue
				var neighbor: int = chunk_map[neighbor_cell]
				if assigned[neighbor]:
					continue
				assigned[neighbor] = true
				members.append(neighbor)
		if members.size() < 2:
			continue
		members.sort()
		room_groups.append(members)
	return room_groups


static func _room_dictionaries(buildings: Array, room_groups: Array[Array]) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	for members: Array in room_groups:
		var building_ids: Array[String] = []
		var room_cells: Array[Vector2i] = []
		for member_index: int in members:
			var entry: Dictionary = buildings[member_index]
			building_ids.append(str(entry.get("building_id", "")))
			room_cells.append(Vector2i(int(entry.get("cell_x", 0)), int(entry.get("cell_y", 0))))
		rooms.append({"building_ids": building_ids, "cells": room_cells})
	return rooms


static func _definition_for(defs: Dictionary, building_id: String) -> Dictionary:
	var def_value: Variant = defs.get(building_id, {})
	if typeof(def_value) != TYPE_DICTIONARY:
		return {}
	return def_value
