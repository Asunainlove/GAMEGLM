extends GutTest

## WP05 背包纯逻辑单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 契约：module-contracts.md §5 —— stack_counts/can_carry/total_slots。
## 槽位模型决策（槽位数 = 物品种类数；stack_limit 参数为预留）见 ops/evidence/WP05.md。

const INVENTORY_SCRIPT_PATH: String = "res://src/gathering/inventory_model.gd"

var _inventory_model: Script = null


func before_all() -> void:
	_inventory_model = load(INVENTORY_SCRIPT_PATH)


func _require_inventory_model() -> bool:
	if _inventory_model == null:
		fail_test("Missing required WP05 implementation: %s" % INVENTORY_SCRIPT_PATH)
		return false
	return true


func test_stack_counts_sorted_by_item_id() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {
		"starsoil_dust": 4,
		"resonant_core": 1,
		"lumen_shard": 2,
	}
	var expected: Array[Dictionary] = [
		{"item_id": "lumen_shard", "count": 2},
		{"item_id": "resonant_core", "count": 1},
		{"item_id": "starsoil_dust", "count": 4},
	]
	assert_eq(_inventory_model.stack_counts(inventory), expected, "必须按 item_id 字典序升序排列。")


func test_stack_counts_empty_inventory_is_empty_list() -> void:
	if not _require_inventory_model():
		return
	assert_eq(_inventory_model.stack_counts({}).size(), 0)


func test_can_carry_new_item_within_capacity() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {"starsoil_dust": 4}
	assert_true(
		_inventory_model.can_carry(inventory, "lumen_shard", 1, 99, 2),
		"1 现有种类 + 1 新槽 = 2 ≤ 容量 2。")


func test_can_carry_new_item_beyond_capacity() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {"starsoil_dust": 4, "lumen_shard": 2}
	assert_false(
		_inventory_model.can_carry(inventory, "resonant_core", 1, 99, 2),
		"2 现有种类 + 1 新槽 = 3 > 容量 2。")


func test_can_carry_new_item_at_empty_capacity_boundary() -> void:
	if not _require_inventory_model():
		return
	assert_true(
		_inventory_model.can_carry({}, "starsoil_dust", 1, 99, 1),
		"空背包容量 1：新物品恰好占用 1 槽。")
	assert_false(
		_inventory_model.can_carry({}, "starsoil_dust", 1, 99, 0),
		"容量 0 无法容纳任何新物品。")


func test_can_carry_existing_item_needs_no_new_slot() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {"starsoil_dust": 4}
	assert_true(
		_inventory_model.can_carry(inventory, "starsoil_dust", 10, 99, 1),
		"已有种类继续叠加不新增槽位，1 ≤ 容量 1。")


func test_can_carry_non_positive_amount_is_rejected() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {"starsoil_dust": 4}
	assert_false(
		_inventory_model.can_carry(inventory, "starsoil_dust", 0, 99, 8),
		"amount 0 不是可携带的增量。")
	assert_false(
		_inventory_model.can_carry(inventory, "starsoil_dust", -2, 99, 8),
		"amount 负数不是可携带的增量。")


func test_total_slots_counts_distinct_kinds() -> void:
	if not _require_inventory_model():
		return
	var inventory: Dictionary = {"starsoil_dust": 7, "lumen_shard": 2, "resonant_core": 1}
	assert_eq(
		_inventory_model.total_slots(inventory, {"starsoil_dust": 99, "lumen_shard": 99, "resonant_core": 99}),
		3,
		"槽位数 = 物品种类数。")


func test_total_slots_empty_inventory_is_zero() -> void:
	if not _require_inventory_model():
		return
	assert_eq(_inventory_model.total_slots({}, {}), 0)
