class_name Gathering
extends RefCounted

## WP05 采集纯逻辑（契约 docs/plans/contracts/module-contracts.md §0/§5）。
## mining_result：确定性单次敲击结算，无内部进度（相同输入必得相同结果）。
## apply_mining：一次调用执行一次敲击；仅当本次敲击使 hardness 归零（耗尽）时
## 提交单个持久 patch（set_destructible_cell + add_item）。中间敲击进度为暂态，
## 不构造、不提交任何 patch（决策记录见 ops/evidence/WP05.md）。

const SOURCE_ID_PREFIX: String = "gathering"


static func mining_result(cell_def: Dictionary, tool_tier: int) -> Dictionary:
	var hardness: int = int(cell_def.get("hardness", 0))
	var min_tier: int = int(cell_def.get("min_tier", 0))
	if hardness <= 0:
		return _strike_result(0, false, "not_mineable")
	if tool_tier < min_tier:
		return _strike_result(hardness, false, "tool_too_weak")
	var hardness_left: int = hardness - 1
	if hardness_left <= 0:
		return {
			"item_id": String(cell_def.get("yield_item_id", "")),
			"amount": int(cell_def.get("yield_amount", 0)),
			"hardness_left": 0,
			"depleted": true,
			"reason": "",
		}
	return _strike_result(hardness_left, false, "")


static func apply_mining(
		state: Dictionary,
		chunk_id: String,
		cell: Vector2i,
		cell_def: Dictionary,
		tool_tier: int,
		store: Object = null
) -> AppResult:
	if cell.x < 0 or cell.y < 0:
		return AppResult.failure(
			"invalid_cell_coordinate",
			"Mining cell coordinates must be non-negative, got (%d, %d)." % [cell.x, cell.y]
		)
	if _is_cell_destroyed(state, chunk_id, cell):
		return AppResult.failure(
			"cell_already_destroyed",
			"Cell (%d, %d) in %s is already destroyed." % [cell.x, cell.y, chunk_id]
		)

	var strike: Dictionary = mining_result(cell_def, tool_tier)
	var reason: String = String(strike["reason"])
	if not reason.is_empty():
		return AppResult.failure(reason, "Mining strike rejected: %s." % reason)
	if not bool(strike["depleted"]):
		return AppResult.success(strike)

	# 坐标已通过非负校验，"%d" 不会引入 "-"，source_id 保持稳定 snake_case。
	var source_id: String = "%s_%s_%d_%d" % [SOURCE_ID_PREFIX, chunk_id, cell.x, cell.y]
	var expected_revision: int = int(state.get("revision", 0))
	var patch: Variant = _begin_patch(store, source_id, expected_revision)
	patch.set_destructible_cell(chunk_id, cell.x, cell.y, true)
	patch.add_item(String(strike["item_id"]), int(strike["amount"]))
	return _commit(store, patch)


## 契约 §0 注入模式：patch 经未类型化变量（Variant）走鸭子调用，
## 以便 DuckPatch 测试替身与真实 StatePatch 共用同一提交路径。
static func _begin_patch(store: Object, source_id: String, expected_revision: int) -> Variant:
	if store == null:
		return GameState.begin_patch(source_id, expected_revision)
	return store.begin_patch(source_id, expected_revision)


static func _commit(store: Object, patch: Variant) -> AppResult:
	if store == null:
		return GameState.commit(patch)
	return store.commit(patch)


static func _is_cell_destroyed(state: Dictionary, chunk_id: String, cell: Vector2i) -> bool:
	var chunk_deltas: Dictionary = state.get("chunk_deltas", {})
	if not chunk_deltas.has(chunk_id):
		return false
	var deltas: Array = chunk_deltas[chunk_id]
	for delta: Dictionary in deltas:
		if int(delta["cell_x"]) == cell.x and int(delta["cell_y"]) == cell.y and bool(delta["destroyed"]):
			return true
	return false


static func _strike_result(hardness_left: int, depleted: bool, reason: String) -> Dictionary:
	return {
		"item_id": "",
		"amount": 0,
		"hardness_left": hardness_left,
		"depleted": depleted,
		"reason": reason,
	}
