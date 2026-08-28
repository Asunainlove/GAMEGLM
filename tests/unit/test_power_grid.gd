extends GutTest

## WP07 房间与电力单元测试。
## 建筑参数取自冻结契约 §7 的本地夹具（不依赖 ContentDB 与 GameState）：
## anchor_workshop supply=10；dust_refiner draw=4；stabilizer_pylon draw=6；
## resonance_loom draw=5；echo_chamber draw=8 且 requires_room=true。

const CHUNK_A: String = "chunk_0_0"
const CHUNK_B: String = "chunk_1_0"

const BUILDING_DEFS: Dictionary = {
	"anchor_block": {"power_draw": 0, "power_supply": 0, "requires_room": false},
	"anchor_workshop": {"power_draw": 0, "power_supply": 10, "requires_room": false},
	"dust_refiner": {"power_draw": 4, "power_supply": 0, "requires_room": false},
	"stabilizer_pylon": {"power_draw": 6, "power_supply": 0, "requires_room": false},
	"resonance_loom": {"power_draw": 5, "power_supply": 0, "requires_room": false},
	"echo_chamber": {"power_draw": 8, "power_supply": 0, "requires_room": true},
}


func _building(building_id: String, chunk_id: String, cell_x: int, cell_y: int) -> Dictionary:
	return {
		"building_id": building_id,
		"chunk_id": chunk_id,
		"cell_x": cell_x,
		"cell_y": cell_y,
	}


func _assert_room(
		rooms: Array,
		room_index: int,
		expected_ids: Array,
		expected_cells: Array
) -> void:
	assert_true(
		room_index < rooms.size(),
		"Expected at least %d room(s), found %d." % [room_index + 1, rooms.size()]
	)
	if room_index >= rooms.size():
		return
	var room: Dictionary = rooms[room_index]
	var room_ids: Array = room["building_ids"]
	assert_eq(room_ids.size(), expected_ids.size(), "Room %d building count" % room_index)
	for position: int in expected_ids.size():
		assert_eq(room_ids[position], expected_ids[position], "Room %d member %d" % [room_index, position])
	var room_cells: Array = room["cells"]
	assert_eq(room_cells.size(), expected_cells.size(), "Room %d cell count" % room_index)
	for position: int in expected_cells.size():
		assert_eq(room_cells[position], expected_cells[position], "Room %d cell %d" % [room_index, position])


func _assert_powered(result: Dictionary, expected_ids: Array) -> void:
	var powered: Array = result["powered_ids"]
	assert_eq(powered.size(), expected_ids.size(), "powered_ids size")
	for position: int in expected_ids.size():
		assert_eq(powered[position], expected_ids[position], "powered_ids member %d" % position)


func test_find_rooms_groups_two_adjacent_buildings_into_one_room() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_A, 1, 0),
	]
	var rooms: Array[Dictionary] = PowerGrid.find_rooms(buildings)
	assert_eq(rooms.size(), 1)
	_assert_room(rooms, 0, ["anchor_workshop", "echo_chamber"], [Vector2i(0, 0), Vector2i(1, 0)])


func test_find_rooms_keeps_gap_separated_buildings_out_of_any_room() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_A, 2, 0),
	]
	var rooms: Array[Dictionary] = PowerGrid.find_rooms(buildings)
	assert_eq(rooms.size(), 0, "A 1-cell gap must prevent any room from forming.")


func test_find_rooms_never_joins_buildings_across_chunks() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_B, 1, 0),
	]
	var rooms: Array[Dictionary] = PowerGrid.find_rooms(buildings)
	assert_eq(rooms.size(), 0, "Adjacency must never cross chunk boundaries.")


func test_find_rooms_preserves_input_order_in_members_and_discovery() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("resonance_loom", CHUNK_A, 5, 0),
		_building("dust_refiner", CHUNK_A, 1, 0),
	]
	var rooms: Array[Dictionary] = PowerGrid.find_rooms(buildings)
	assert_eq(rooms.size(), 1)
	_assert_room(rooms, 0, ["anchor_workshop", "dust_refiner"], [Vector2i(0, 0), Vector2i(1, 0)])

	var reversed: Array = [
		_building("echo_chamber", CHUNK_A, 1, 0),
		_building("anchor_workshop", CHUNK_A, 0, 0),
	]
	var reversed_rooms: Array[Dictionary] = PowerGrid.find_rooms(reversed)
	assert_eq(reversed_rooms.size(), 1)
	_assert_room(reversed_rooms, 0, ["echo_chamber", "anchor_workshop"], [Vector2i(1, 0), Vector2i(0, 0)])

	var multi: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("resonance_loom", CHUNK_A, 10, 0),
		_building("dust_refiner", CHUNK_A, 1, 0),
		_building("stabilizer_pylon", CHUNK_A, 11, 0),
	]
	var multi_rooms: Array[Dictionary] = PowerGrid.find_rooms(multi)
	assert_eq(multi_rooms.size(), 2, "Rooms are discovered in input order of their first member.")
	_assert_room(multi_rooms, 0, ["anchor_workshop", "dust_refiner"], [Vector2i(0, 0), Vector2i(1, 0)])
	_assert_room(multi_rooms, 1, ["resonance_loom", "stabilizer_pylon"], [Vector2i(10, 0), Vector2i(11, 0)])


func test_find_rooms_traces_l_shaped_triplet_as_one_room() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("dust_refiner", CHUNK_A, 1, 0),
		_building("stabilizer_pylon", CHUNK_A, 1, 1),
	]
	var rooms: Array[Dictionary] = PowerGrid.find_rooms(buildings)
	assert_eq(rooms.size(), 1)
	_assert_room(
		rooms,
		0,
		["anchor_workshop", "dust_refiner", "stabilizer_pylon"],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	)


func test_evaluate_powers_every_demand_when_supply_is_sufficient() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("dust_refiner", CHUNK_A, 10, 10),
		_building("stabilizer_pylon", CHUNK_A, 20, 20),
	]
	var result: Dictionary = PowerGrid.evaluate(buildings, BUILDING_DEFS)
	assert_eq(result["supply"], 10)
	assert_eq(result["demand"], 10)
	assert_true(result["satisfied"])
	_assert_powered(result, ["dust_refiner", "stabilizer_pylon"])
	assert_true((result["rooms"] as Array).is_empty(), "Isolated buildings form no room.")


func test_evaluate_rations_supply_in_input_order_and_cuts_later_demand() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("dust_refiner", CHUNK_A, 10, 0),
		_building("stabilizer_pylon", CHUNK_A, 20, 0),
		_building("resonance_loom", CHUNK_A, 30, 0),
	]
	var result: Dictionary = PowerGrid.evaluate(buildings, BUILDING_DEFS)
	assert_eq(result["supply"], 10)
	assert_eq(result["demand"], 15)
	assert_false(result["satisfied"])
	_assert_powered(result, ["dust_refiner", "stabilizer_pylon"])


func test_evaluate_withholds_power_from_demand_placed_before_any_supply() -> void:
	var buildings: Array = [
		_building("dust_refiner", CHUNK_A, 5, 5),
		_building("anchor_workshop", CHUNK_A, 0, 0),
	]
	var result: Dictionary = PowerGrid.evaluate(buildings, BUILDING_DEFS)
	assert_eq(result["supply"], 10)
	assert_eq(result["demand"], 4)
	assert_false(result["satisfied"])
	_assert_powered(result, [])


func test_evaluate_powers_requires_room_building_only_inside_a_room() -> void:
	var paired: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_A, 1, 0),
	]
	var paired_result: Dictionary = PowerGrid.evaluate(paired, BUILDING_DEFS)
	assert_eq(paired_result["supply"], 10)
	assert_eq(paired_result["demand"], 8)
	assert_true(paired_result["satisfied"])
	_assert_powered(paired_result, ["echo_chamber"])

	var island: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_A, 7, 7),
	]
	var island_result: Dictionary = PowerGrid.evaluate(island, BUILDING_DEFS)
	assert_eq(island_result["supply"], 10)
	assert_eq(island_result["demand"], 8)
	assert_false(island_result["satisfied"], "An island echo_chamber stays unpowered.")
	_assert_powered(island_result, [])


func test_evaluate_handles_empty_settlement_without_supply_or_demand() -> void:
	var result: Dictionary = PowerGrid.evaluate([], BUILDING_DEFS)
	assert_eq(result["supply"], 0)
	assert_eq(result["demand"], 0)
	assert_true(result["satisfied"])
	_assert_powered(result, [])
	assert_true((result["rooms"] as Array).is_empty())
	assert_true(PowerGrid.find_rooms([]).is_empty())


func test_evaluate_defaults_missing_defs_to_passive_zero_draw() -> void:
	var buildings: Array = [
		_building("mystery_machinery", CHUNK_A, 0, 0),
		_building("dust_refiner", CHUNK_A, 10, 0),
	]
	var partial_defs: Dictionary = {"dust_refiner": {"power_draw": 4}}
	var result: Dictionary = PowerGrid.evaluate(buildings, partial_defs)
	assert_eq(result["supply"], 0, "Missing defs contribute neither supply nor draw.")
	assert_eq(result["demand"], 4)
	assert_false(result["satisfied"])
	_assert_powered(result, [])


func test_evaluate_satisfies_adjacent_echo_chamber_with_workshop_supply() -> void:
	var buildings: Array = [
		_building("anchor_workshop", CHUNK_A, 0, 0),
		_building("echo_chamber", CHUNK_A, 1, 0),
	]
	var result: Dictionary = PowerGrid.evaluate(buildings, BUILDING_DEFS)
	assert_eq(result["supply"], 10)
	assert_eq(result["demand"], 8)
	assert_true(result["satisfied"], "Supply 10 must cover echo_chamber draw 8 inside a room.")
	_assert_powered(result, ["echo_chamber"])
	var rooms: Array = result["rooms"]
	assert_eq(rooms.size(), 1)
	_assert_room(rooms, 0, ["anchor_workshop", "echo_chamber"], [Vector2i(0, 0), Vector2i(1, 0)])
