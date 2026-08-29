extends GutTest

## WP05 采集逻辑单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 采集中间进度不持久化、负坐标边界等决策记录见 ops/evidence/WP05.md。

const GATHERING_SCRIPT_PATH: String = "res://src/gathering/gathering.gd"
const CHUNK_ID: String = "chunk_0_0"
const SOURCE_CELL_A: Vector2i = Vector2i(2, 3)
const SOURCE_CELL_B: Vector2i = Vector2i(4, 5)
const SOURCE_CELL_C: Vector2i = Vector2i(6, 8)
const SOURCE_CELL_D: Vector2i = Vector2i(9, 11)

const SOIL_CELL_DEF: Dictionary = {
	"type": "soil",
	"hardness": 0,
	"min_tier": 0,
	"yield_item_id": "",
	"yield_amount": 0,
}
const ORE_DUST_CELL_DEF: Dictionary = {
	"type": "ore_dust",
	"hardness": 2,
	"min_tier": 0,
	"yield_item_id": "starsoil_dust",
	"yield_amount": 2,
}
const ORE_SHARD_CELL_DEF: Dictionary = {
	"type": "ore_shard",
	"hardness": 3,
	"min_tier": 1,
	"yield_item_id": "lumen_shard",
	"yield_amount": 1,
}
const ORE_CORE_CELL_DEF: Dictionary = {
	"type": "ore_core",
	"hardness": 4,
	"min_tier": 2,
	"yield_item_id": "resonant_core",
	"yield_amount": 1,
}

var _gathering: Script = null


func before_all() -> void:
	_gathering = load(GATHERING_SCRIPT_PATH)


func _require_gathering() -> bool:
	if _gathering == null:
		fail_test("Missing required WP05 implementation: %s" % GATHERING_SCRIPT_PATH)
		return false
	return true


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _mining_state(revision: int, chunk_deltas: Dictionary = {}) -> Dictionary:
	return {"revision": revision, "chunk_deltas": chunk_deltas}


func _cell_def_at_hardness(base_def: Dictionary, hardness: int) -> Dictionary:
	## 瞬态进度协议：mining_result 确定性且无内部进度，
	## 调用方暂存 hardness_left 并把它写回 cell_def 副本，模拟下一击。
	var damaged: Dictionary = base_def.duplicate(true)
	damaged["hardness"] = hardness
	return damaged


# --- Gathering.mining_result：确定性单次敲击结算 ----------------------------


func test_soil_is_not_mineable() -> void:
	if not _require_gathering():
		return
	var expected: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 0,
		"depleted": false,
		"reason": "not_mineable",
	}
	assert_eq(_gathering.mining_result(SOIL_CELL_DEF, 3), expected)


func test_negative_hardness_is_not_mineable() -> void:
	if not _require_gathering():
		return
	var frozen_cell_def: Dictionary = {
		"type": "soil",
		"hardness": -1,
		"min_tier": 0,
		"yield_item_id": "",
		"yield_amount": 0,
	}
	var expected: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 0,
		"depleted": false,
		"reason": "not_mineable",
	}
	assert_eq(_gathering.mining_result(frozen_cell_def, 3), expected)


func test_tool_below_min_tier_is_rejected() -> void:
	if not _require_gathering():
		return
	var weak_expected: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 3,
		"depleted": false,
		"reason": "tool_too_weak",
	}
	assert_eq(_gathering.mining_result(ORE_SHARD_CELL_DEF, 0), weak_expected)

	var core_expected: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 4,
		"depleted": false,
		"reason": "tool_too_weak",
	}
	assert_eq(_gathering.mining_result(ORE_CORE_CELL_DEF, 1), core_expected)


func test_two_hit_ore_advances_then_yields_on_breaking_hit() -> void:
	if not _require_gathering():
		return
	var progress_expected: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 1,
		"depleted": false,
		"reason": "",
	}
	var first_hit: Dictionary = _gathering.mining_result(ORE_DUST_CELL_DEF, 0)
	assert_eq(first_hit, progress_expected, "硬度 2 的矿第一击只推进进度，无产出。")

	var breaking_expected: Dictionary = {
		"item_id": "starsoil_dust",
		"amount": 2,
		"hardness_left": 0,
		"depleted": true,
		"reason": "",
	}
	var second_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_DUST_CELL_DEF, int(first_hit["hardness_left"])), 0)
	assert_eq(second_hit, breaking_expected, "调用方暂存进度后的第二击敲到 0，结算产出并标记耗尽。")


func test_tier_gated_ore_mineable_at_exact_min_tier() -> void:
	if not _require_gathering():
		return
	var tool_tier: int = int(ORE_SHARD_CELL_DEF["min_tier"])
	var first_hit: Dictionary = _gathering.mining_result(ORE_SHARD_CELL_DEF, tool_tier)
	assert_eq(int(first_hit["hardness_left"]), 2, "工具等级恰好等于 min_tier 时允许开采。")
	assert_eq(String(first_hit["reason"]), "")
	assert_false(bool(first_hit["depleted"]))

	var second_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_SHARD_CELL_DEF, int(first_hit["hardness_left"])), tool_tier)
	assert_eq(int(second_hit["hardness_left"]), 1)
	assert_false(bool(second_hit["depleted"]))

	var third_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_SHARD_CELL_DEF, int(second_hit["hardness_left"])), tool_tier)
	var breaking_expected: Dictionary = {
		"item_id": "lumen_shard",
		"amount": 1,
		"hardness_left": 0,
		"depleted": true,
		"reason": "",
	}
	assert_eq(third_hit, breaking_expected)


func test_ore_core_yields_resonant_core_at_tier_two() -> void:
	if not _require_gathering():
		return
	var tool_tier: int = int(ORE_CORE_CELL_DEF["min_tier"])
	var first_hit: Dictionary = _gathering.mining_result(ORE_CORE_CELL_DEF, tool_tier)
	assert_eq(int(first_hit["hardness_left"]), 3)

	var second_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_CORE_CELL_DEF, int(first_hit["hardness_left"])), tool_tier)
	assert_eq(int(second_hit["hardness_left"]), 2)
	assert_false(bool(second_hit["depleted"]))

	var third_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_CORE_CELL_DEF, int(second_hit["hardness_left"])), tool_tier)
	assert_eq(int(third_hit["hardness_left"]), 1)
	assert_false(bool(third_hit["depleted"]))

	var fourth_hit: Dictionary = _gathering.mining_result(
		_cell_def_at_hardness(ORE_CORE_CELL_DEF, int(third_hit["hardness_left"])), tool_tier)
	var breaking_expected: Dictionary = {
		"item_id": "resonant_core",
		"amount": 1,
		"hardness_left": 0,
		"depleted": true,
		"reason": "",
	}
	assert_eq(fourth_hit, breaking_expected)


func test_hardness_one_boundary_depletes_on_first_hit() -> void:
	if not _require_gathering():
		return
	var fragile_cell_def: Dictionary = {
		"type": "ore_dust",
		"hardness": 1,
		"min_tier": 0,
		"yield_item_id": "starsoil_dust",
		"yield_amount": 2,
	}
	var expected: Dictionary = {
		"item_id": "starsoil_dust",
		"amount": 2,
		"hardness_left": 0,
		"depleted": true,
		"reason": "",
	}
	assert_eq(_gathering.mining_result(fragile_cell_def, 0), expected, "hardness 1 边界：单击即耗尽并产出。")


func test_mining_result_is_deterministic_per_hit() -> void:
	if not _require_gathering():
		return
	var first_call: Dictionary = _gathering.mining_result(ORE_DUST_CELL_DEF, 0)
	var second_call: Dictionary = _gathering.mining_result(ORE_DUST_CELL_DEF, 0)
	assert_eq(_canonical(first_call), _canonical(second_call), "相同输入必须得到完全相同的单次敲击结果。")
	assert_eq(int(second_call["hardness_left"]), 1, "函数不携带内部进度：每次调用都是独立的一击。")


# --- Gathering.apply_mining：持久化提交 -------------------------------------


func test_exhausted_mining_commits_yield_and_destroyed_delta() -> void:
	if not _require_gathering():
		return
	var snapshot_before: Dictionary = GameState.snapshot()
	var revision_before: int = int(snapshot_before["revision"])
	var inventory_before: int = int((snapshot_before["inventory"] as Dictionary).get("starsoil_dust", 0))

	# 第一击：硬度 2 的矿只推进进度，属暂态成功，不得产生持久 patch。
	var progress: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_A, ORE_DUST_CELL_DEF, 0)
	assert_true(progress.is_ok, progress.message)
	assert_eq(progress.code, "ok")
	assert_false(bool(progress.value["depleted"]))
	assert_eq(int(GameState.snapshot()["revision"]), revision_before, "进度敲击不得推进 revision。")

	# 第二击：调用方暂存进度后传入受损 cell_def（hardness=1），本次敲击耗尽并提交单个持久 patch。
	var damaged_def: Dictionary = _cell_def_at_hardness(
		ORE_DUST_CELL_DEF, int(progress.value["hardness_left"]))
	var result: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_A, damaged_def, 0)
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "committed")

	var snapshot_after: Dictionary = GameState.snapshot()
	assert_eq(int(snapshot_after["revision"]), revision_before + 1)
	assert_eq(
		int((snapshot_after["inventory"] as Dictionary).get("starsoil_dust", 0)),
		inventory_before + 2,
		"耗尽提交后背包必须增加产出。")

	var deltas: Array = (snapshot_after["chunk_deltas"] as Dictionary)[CHUNK_ID] as Array
	var found_destroyed_delta: bool = false
	for delta: Dictionary in deltas:
		if (
			int(delta["cell_x"]) == SOURCE_CELL_A.x
			and int(delta["cell_y"]) == SOURCE_CELL_A.y
			and bool(delta["destroyed"])
		):
			found_destroyed_delta = true
	assert_true(found_destroyed_delta, "chunk_deltas 必须出现 destroyed=true 的格delta。")
	assert_has(snapshot_after["applied_patch_sources"], "gathering_chunk_0_0_2_3", "source_id 必须是稳定 snake_case 构造。")


func test_repeated_mining_of_destroyed_cell_fails() -> void:
	if not _require_gathering():
		return
	var revision_before: int = int(GameState.snapshot()["revision"])
	var progress: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_B, ORE_DUST_CELL_DEF, 0)
	assert_true(progress.is_ok, progress.message)
	assert_eq(progress.code, "ok", "第一击只推进暂态进度，不破坏格。")

	var damaged_def: Dictionary = _cell_def_at_hardness(
		ORE_DUST_CELL_DEF, int(progress.value["hardness_left"]))
	var first: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_B, damaged_def, 0)
	assert_true(first.is_ok, first.message)
	assert_eq(first.code, "committed", "第二击耗尽并提交破坏格。")

	var fresh: Dictionary = GameState.snapshot()
	var replay_state: Dictionary = _mining_state(int(fresh["revision"]), fresh["chunk_deltas"])
	var second: AppResult = _gathering.apply_mining(
		replay_state, CHUNK_ID, SOURCE_CELL_B, ORE_DUST_CELL_DEF, 0)
	assert_false(second.is_ok)
	assert_eq(second.code, "cell_already_destroyed")
	assert_eq(int(GameState.snapshot()["revision"]), revision_before + 1, "重复采集失败不得再推进 revision。")


func test_unmineable_cell_fails_without_persistent_change() -> void:
	if not _require_gathering():
		return
	var baseline: String = _canonical(GameState.snapshot())
	var state: Dictionary = _mining_state(int(GameState.snapshot()["revision"]))
	var result: AppResult = _gathering.apply_mining(
		state, CHUNK_ID, SOURCE_CELL_C, SOIL_CELL_DEF, 3)
	assert_false(result.is_ok)
	assert_eq(result.code, "not_mineable")
	assert_eq(_canonical(GameState.snapshot()), baseline)


func test_weak_tool_fails_without_persistent_change() -> void:
	if not _require_gathering():
		return
	var baseline: String = _canonical(GameState.snapshot())
	var state: Dictionary = _mining_state(int(GameState.snapshot()["revision"]))
	var result: AppResult = _gathering.apply_mining(
		state, CHUNK_ID, SOURCE_CELL_C, ORE_CORE_CELL_DEF, 1)
	assert_false(result.is_ok)
	assert_eq(result.code, "tool_too_weak")
	assert_eq(_canonical(GameState.snapshot()), baseline)


func test_progress_hit_does_not_persist_any_change() -> void:
	if not _require_gathering():
		return
	var baseline: String = _canonical(GameState.snapshot())
	var state: Dictionary = _mining_state(int(GameState.snapshot()["revision"]))
	var result: AppResult = _gathering.apply_mining(
		state, CHUNK_ID, SOURCE_CELL_C, ORE_DUST_CELL_DEF, 0)
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "ok")
	var expected_value: Dictionary = {
		"item_id": "",
		"amount": 0,
		"hardness_left": 1,
		"depleted": false,
		"reason": "",
	}
	assert_eq(result.value, expected_value, "未耗尽的成功敲击返回进度信息。")
	assert_eq(
		_canonical(GameState.snapshot()),
		baseline,
		"中间敲击进度为暂态：不得产生持久 patch，revision 不变。")


func test_injected_store_receives_single_patch_with_both_operations() -> void:
	if not _require_gathering():
		return
	var baseline: String = _canonical(GameState.snapshot())
	var store: DuckStore = DuckStore.new()
	store.result_to_return = AppResult.success({"via": "duck"}, "committed")

	var progress: AppResult = _gathering.apply_mining(
		_mining_state(7), "chunk_1_0", Vector2i(5, 6), ORE_DUST_CELL_DEF, 0, store)
	assert_true(progress.is_ok, progress.message)
	assert_eq(progress.code, "ok", "未耗尽敲击即使注入 store 也不得产生 patch。")
	assert_eq(store.begin_calls, 0, "进度敲击不得调用 begin_patch。")

	var damaged_def: Dictionary = _cell_def_at_hardness(
		ORE_DUST_CELL_DEF, int(progress.value["hardness_left"]))
	var result: AppResult = _gathering.apply_mining(
		_mining_state(7), "chunk_1_0", Vector2i(5, 6), damaged_def, 0, store)
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "committed")
	assert_eq(result.value, {"via": "duck"}, "commit 结果必须透传给调用方。")

	assert_eq(store.begin_calls, 1)
	assert_eq(store.committed_patches.size(), 1, "耗尽提交必须是单个 patch。")
	var patch: DuckPatch = store.committed_patches[0] as DuckPatch
	assert_eq(patch.source_id, "gathering_chunk_1_0_5_6")
	assert_eq(patch.expected_revision, 7)
	var expected_operations: Array[Dictionary] = [
		{
			"type": "set_destructible_cell",
			"chunk_id": "chunk_1_0",
			"cell_x": 5,
			"cell_y": 6,
			"destroyed": true,
		},
		{"type": "add_item", "item_id": "starsoil_dust", "amount": 2},
	]
	assert_eq(
		_canonical(patch.operations),
		_canonical(expected_operations),
		"单次提交必须依序包含 set_destructible_cell 与 add_item。")
	assert_eq(_canonical(GameState.snapshot()), baseline, "注入 store 时不得触碰 GameState autoload。")


func test_negative_coordinates_fail_without_building_patch() -> void:
	if not _require_gathering():
		return
	var baseline: String = _canonical(GameState.snapshot())
	var store: DuckStore = DuckStore.new()
	var result: AppResult = _gathering.apply_mining(
		_mining_state(7), CHUNK_ID, Vector2i(-1, 4), ORE_DUST_CELL_DEF, 0, store)
	assert_false(result.is_ok, "负坐标不能崩溃，必须干净失败。")
	assert_eq(result.code, "invalid_cell_coordinate")
	assert_eq(store.begin_calls, 0, "负坐标必须在构造 patch 之前失败。")
	assert_eq(_canonical(GameState.snapshot()), baseline)


func test_mining_source_id_is_idempotent_on_replay() -> void:
	if not _require_gathering():
		return
	var revision_before: int = int(GameState.snapshot()["revision"])
	var progress: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_D, ORE_DUST_CELL_DEF, 0)
	assert_true(progress.is_ok, progress.message)
	assert_eq(progress.code, "ok", "第一击为暂态进度，不提交 source_id。")

	var damaged_def: Dictionary = _cell_def_at_hardness(
		ORE_DUST_CELL_DEF, int(progress.value["hardness_left"]))
	var result: AppResult = _gathering.apply_mining(
		_mining_state(revision_before), CHUNK_ID, SOURCE_CELL_D, damaged_def, 0)
	assert_true(result.is_ok, result.message)

	var replay: StatePatch = GameState.begin_patch(
		"gathering_chunk_0_0_9_11", int(GameState.snapshot()["revision"]))
	replay.add_item("starsoil_dust", 1)
	var replay_result: AppResult = GameState.commit(replay)
	assert_true(replay_result.is_ok, replay_result.message)
	assert_eq(replay_result.code, "already_applied", "同 source_id 重放必须幂等。")
	assert_eq(int(GameState.snapshot()["revision"]), revision_before + 1, "重放不得推进 revision。")


class DuckPatch extends RefCounted:
	## 测试替身：记录操作序列，模拟 StatePatch 的可链式调用形状。
	var source_id: String = ""
	var expected_revision: int = -1
	var operations: Array[Dictionary] = []

	func set_destructible_cell(chunk_id: String, cell_x: int, cell_y: int, destroyed: bool) -> DuckPatch:
		operations.append({
			"type": "set_destructible_cell",
			"chunk_id": chunk_id,
			"cell_x": cell_x,
			"cell_y": cell_y,
			"destroyed": destroyed,
		})
		return self

	func add_item(item_id: String, amount: int) -> DuckPatch:
		operations.append({"type": "add_item", "item_id": item_id, "amount": amount})
		return self


class DuckStore extends RefCounted:
	## 测试替身：模拟契约 §0 的注入 store（begin_patch/commit 语义）。
	var begin_calls: int = 0
	var committed_patches: Array = []
	var result_to_return: AppResult = null

	func begin_patch(p_source_id: String, p_expected_revision: int) -> DuckPatch:
		begin_calls += 1
		var patch: DuckPatch = DuckPatch.new()
		patch.source_id = p_source_id
		patch.expected_revision = p_expected_revision
		return patch

	func commit(patch: Variant) -> AppResult:
		committed_patches.append(patch)
		return result_to_return
