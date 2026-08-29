class_name InventoryModel
extends RefCounted

## WP05 背包纯逻辑（契约 docs/plans/contracts/module-contracts.md §5）。
## 槽位模型：槽位数 = 背包中物品种类数（每种物品占一个槽位）。
## stack_limit 参数按契约签名保留，供未来分堆上限扩展使用。

const ITEM_ID_KEY: String = "item_id"
const COUNT_KEY: String = "count"


static func stack_counts(inventory: Dictionary) -> Array[Dictionary]:
	var item_ids: Array = inventory.keys()
	item_ids.sort()
	var stacks: Array[Dictionary] = []
	for item_id: String in item_ids:
		stacks.append({ITEM_ID_KEY: item_id, COUNT_KEY: int(inventory[item_id])})
	return stacks


static func can_carry(
		inventory: Dictionary,
		item_id: String,
		amount: int,
		stack_limit: int,
		capacity: int
) -> bool:
	if amount <= 0:
		return false
	var used_slots: int = inventory.size()
	if not inventory.has(item_id):
		used_slots += 1
	return used_slots <= capacity


static func total_slots(inventory: Dictionary, stack_limits: Dictionary) -> int:
	return inventory.size()
