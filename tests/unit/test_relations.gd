extends GutTest

## WP09 关系与立场单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 契约：docs/plans/contracts/module-contracts.md §0（store 注入模式）、§5（Relations）、§7（角色/门控数值）。
## 脚本运行时加载（绝不 preload），缺失实现以失败断言暴露而非静默跳过。

const RELATIONS_SCRIPT_PATH: String = "res://src/relations/relations.gd"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")

## DuckPatch/DuckStore 宿主实例字段：注入调用只传 ObjectID，替身必须由
## 测试实例字段保活，否则临时 RefCounted 会被立即释放、记录静默丢失。
var _duck_store: DuckStore = null

var _relations: Script = null


func before_all() -> void:
	_relations = load(RELATIONS_SCRIPT_PATH)


func _require_relations() -> bool:
	if _relations == null:
		fail_test("Missing required WP09 implementation: %s" % RELATIONS_SCRIPT_PATH)
		return false
	return true


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _fresh_game_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _relationships_state(relationships: Dictionary) -> Dictionary:
	return {"revision": 3, "relationships": relationships}


# --- get_dim：读取关系维度，任何缺失返回 0 ----------------------------------


func test_get_dim_reads_existing_values() -> void:
	if not _require_relations():
		return
	var state: Dictionary = _relationships_state({
		"luoxian": {"affection": 42, "trust": 17, "ideology": 5},
		"misa": {"affection": 8, "trust": 66, "ideology": -3},
	})
	assert_eq(_relations.get_dim(state, "luoxian", "trust"), 17)
	assert_eq(_relations.get_dim(state, "luoxian", "affection"), 42)
	assert_eq(_relations.get_dim(state, "misa", "ideology"), -3)


func test_get_dim_missing_character_returns_zero() -> void:
	if not _require_relations():
		return
	var state: Dictionary = _relationships_state({"luoxian": {"trust": 17}})
	assert_eq(_relations.get_dim(state, "misa", "trust"), 0)


func test_get_dim_missing_dimension_returns_zero() -> void:
	if not _require_relations():
		return
	var state: Dictionary = _relationships_state({"luoxian": {"trust": 17}})
	assert_eq(_relations.get_dim(state, "luoxian", "affection"), 0)


func test_get_dim_empty_state_returns_zero() -> void:
	if not _require_relations():
		return
	assert_eq(_relations.get_dim({}, "luoxian", "trust"), 0)


# --- change：真实 GameState 注入 store 的成功路径 ---------------------------


func test_change_success_writes_relationship_and_advances_revision() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var result: AppResult = _relations.change(
		state, "luoxian", "trust", 35, "test_help_luoxian", store)
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int(snapshot["relationships"]["luoxian"]["trust"]), 35)
	assert_eq(int(snapshot["revision"]), int(state["revision"]) + 1)


func test_change_accumulates_on_existing_value() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var seed_patch: StatePatch = store.begin_patch("test_seed_trust_partial", 0)
	seed_patch.set_relationship("misa", "trust", 30)
	assert_true(store.commit(seed_patch).is_ok)
	var result: AppResult = _relations.change(
		store.snapshot(), "misa", "trust", 12, "test_add_trust", store)
	assert_true(result.is_ok, result.message)
	assert_eq(int(store.snapshot()["relationships"]["misa"]["trust"]), 42)


func test_change_clamps_to_upper_bound() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var seed_patch: StatePatch = store.begin_patch("test_seed_trust_high", 0)
	seed_patch.set_relationship("misa", "affection", 95)
	assert_true(store.commit(seed_patch).is_ok)
	var result: AppResult = _relations.change(
		store.snapshot(), "misa", "affection", 10, "test_clamp_high", store)
	assert_true(result.is_ok, result.message)
	assert_eq(int(store.snapshot()["relationships"]["misa"]["affection"]), 100)


func test_change_clamps_to_lower_bound() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var seed_patch: StatePatch = store.begin_patch("test_seed_trust_low", 0)
	seed_patch.set_relationship("luoxian", "trust", 5)
	assert_true(store.commit(seed_patch).is_ok)
	var result: AppResult = _relations.change(
		store.snapshot(), "luoxian", "trust", -10, "test_clamp_low", store)
	assert_true(result.is_ok, result.message)
	assert_eq(int(store.snapshot()["relationships"]["luoxian"]["trust"]), 0)


# --- change：非法输入零修改 --------------------------------------------------


func test_change_invalid_character_fails_without_modification() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var baseline: String = _canonical(store.snapshot())
	var result: AppResult = _relations.change(
		store.snapshot(), "nadia", "trust", 5, "test_bad_char", store)
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_character")
	assert_eq(_canonical(store.snapshot()), baseline, "失败必须零修改。")
	assert_eq(int(store.snapshot()["revision"]), 0, "失败不得推进 revision。")


func test_change_invalid_dimension_fails_without_modification() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var baseline: String = _canonical(store.snapshot())
	var result: AppResult = _relations.change(
		store.snapshot(), "luoxian", "honor", 5, "test_bad_dim", store)
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_dim")
	assert_eq(_canonical(store.snapshot()), baseline, "失败必须零修改。")
	assert_eq(int(store.snapshot()["revision"]), 0, "失败不得推进 revision。")


func test_change_invalid_input_never_calls_begin_patch_on_store() -> void:
	if not _require_relations():
		return
	var baseline: String = _canonical(GameState.snapshot())
	_duck_store = DuckStore.new()
	var bad_char: AppResult = _relations.change(
		_relationships_state({}), "vex", "trust", 5, "test_duck_bad_char", _duck_store)
	assert_false(bad_char.is_ok)
	assert_eq(bad_char.code, "invalid_character")
	var bad_dim: AppResult = _relations.change(
		_relationships_state({}), "luoxian", "honor", 5, "test_duck_bad_dim", _duck_store)
	assert_false(bad_dim.is_ok)
	assert_eq(bad_dim.code, "invalid_dim")
	assert_eq(_duck_store.begin_calls, 0, "非法输入必须在构造 patch 之前失败。")
	assert_eq(_canonical(GameState.snapshot()), baseline, "注入 store 时不得触碰 GameState autoload。")


# --- change：DuckPatch 替身记录 op 参数 ---------------------------------------


func test_change_records_operation_on_duck_store() -> void:
	if not _require_relations():
		return
	var baseline: String = _canonical(GameState.snapshot())
	_duck_store = DuckStore.new()
	var state: Dictionary = _relationships_state({"luoxian": {"trust": 30}})
	var result: AppResult = _relations.change(
		state, "luoxian", "trust", 12, "test_duck_help", _duck_store)
	assert_true(result.is_ok, result.message)
	assert_eq(_duck_store.begin_calls, 1)
	assert_eq(_duck_store.last_source_id, "relations_test_duck_help_3")
	assert_eq(_duck_store.last_expected_revision, 3)
	assert_eq(_duck_store.committed_patches.size(), 1)
	var patch: DuckPatch = _duck_store.committed_patches[0] as DuckPatch
	assert_eq(patch.source_id, "relations_test_duck_help_3")
	var expected_operations: Array[Dictionary] = [
		{"type": "set_relationship", "char_id": "luoxian", "dim": "trust", "value": 42},
	]
	assert_eq(_canonical(patch.operations), _canonical(expected_operations))
	assert_eq(_canonical(GameState.snapshot()), baseline, "注入 store 时不得触碰 GameState autoload。")


# --- change：默认 store（null → GameState autoload）--------------------------


func test_change_default_store_writes_game_state_autoload() -> void:
	if not _require_relations():
		return
	var relationships_before: Dictionary = GameState.snapshot().get("relationships", {})
	var trust_before: int = int((relationships_before.get("misa", {}) as Dictionary).get("trust", 0))
	var revision_before: int = int(GameState.snapshot()["revision"])
	var result: AppResult = _relations.change(
		GameState.snapshot(), "misa", "trust", 4, "test_default_store", null)
	assert_true(result.is_ok, result.message)
	var relationships_after: Dictionary = GameState.snapshot().get("relationships", {})
	var trust_after: int = int((relationships_after.get("misa", {}) as Dictionary).get("trust", 0))
	assert_eq(trust_after, trust_before + 4)
	assert_eq(int(GameState.snapshot()["revision"]), revision_before + 1)


# --- change：幂等重放 ---------------------------------------------------------


func test_change_same_source_id_replay_is_idempotent() -> void:
	if not _require_relations():
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var first: AppResult = _relations.change(
		state, "luoxian", "affection", 10, "test_replay", store)
	assert_true(first.is_ok, first.message)
	var revision_after_first: int = int(store.snapshot()["revision"])

	# 同一 state（同一 revision）+ 同一 reason → 同一 source_id，重放必须幂等。
	var replay: AppResult = _relations.change(
		state, "luoxian", "affection", 10, "test_replay", store)
	assert_true(replay.is_ok, replay.message)
	assert_eq(replay.code, "already_applied")
	assert_eq(int(store.snapshot()["revision"]), revision_after_first, "重放不得推进 revision。")
	assert_eq(
		int(store.snapshot()["relationships"]["luoxian"]["affection"]),
		10,
		"重放不得重复叠加。"
	)


# --- trust：便捷读取 -----------------------------------------------------------
# DLX-1 合法断言更新：policy_unlocked 两项测试随死 API 一并删除（无生产调用方，
# policy_sanctuary 的 trust≥40 门控由 event_policy.json 的 requires_trust 对象
# 形态 + EventRunner.option_meets_trust 单一判定源承担，覆盖见
# test_narrative_event_runner.gd 与 test_integration.gd）。


func test_trust_convenience_reads_trust_dimension() -> void:
	if not _require_relations():
		return
	var state: Dictionary = _relationships_state({
		"misa": {"trust": 55, "affection": 90},
	})
	assert_eq(_relations.trust(state, "misa"), 55)
	assert_eq(_relations.trust(state, "luoxian"), 0, "缺失角色返回 0。")


# --- 测试替身：契约 §0 注入 store 的 DuckPatch/DuckStore -----------------------


class DuckPatch extends RefCounted:
	## 测试替身：记录操作序列，模拟 StatePatch 的可链式调用形状。
	var source_id: String = ""
	var expected_revision: int = -1
	var operations: Array[Dictionary] = []

	func set_relationship(char_id: String, dim: String, value: int) -> DuckPatch:
		operations.append({
			"type": "set_relationship",
			"char_id": char_id,
			"dim": dim,
			"value": value,
		})
		return self


class DuckStore extends RefCounted:
	## 测试替身：模拟契约 §0 的注入 store（begin_patch/commit 语义）。
	var begin_calls: int = 0
	var last_source_id: String = ""
	var last_expected_revision: int = -1
	var committed_patches: Array = []

	func begin_patch(p_source_id: String, p_expected_revision: int) -> DuckPatch:
		begin_calls += 1
		last_source_id = p_source_id
		last_expected_revision = p_expected_revision
		var patch: DuckPatch = DuckPatch.new()
		patch.source_id = p_source_id
		patch.expected_revision = p_expected_revision
		committed_patches.append(patch)
		return patch

	func commit(_patch: Variant) -> AppResult:
		return AppResult.success({}, "committed")
