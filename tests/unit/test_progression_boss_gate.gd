extends GutTest

## S2：Boss 门控链数据化测试（TDD：先 RED 后 GREEN）。
##
## 旧 _react_leviathan_gate 的"encounter_first_drift_won +
## encounter_husk_ambush_won 双胜 + 任一 policy_* flag → set_flag
## encounter_leviathan_due"硬编码外置到 data/progression/boss_gate.json
##（schema schemas/boss-gate.schema.json，与 event_chain/ending_gate 同一
## bootstrap 模式）：新增/调整 Boss 门 = 改 JSON，不改 progression.gd。
## 结构支持 N 条门（数组），每条各带 requires_all / requires_any_prefix /
## set_flag——现文件 1 条（迁移现值）。
## 行为等价约束（迁移快照冻结自旧实现的探针输出，存档于
## ops/evidence/S2-BOSS-GATE.md）：
## - 双胜 + 任一 policy_* → 置 encounter_leviathan_due（提交一个 patch）；
## - 缺任一胜利或缺 policy → 成功跳过（conditions_unmet）零写入；
## - due 已置 → 成功跳过（already_set）零写入（幂等）；
## - 非 stable id 的 encounter_id/policy_id → 失败（invalid_*_id）零写入；
## - 既有 test_progression.gd 的 encounter_won/policy_chosen 快照零修改为
##   第二证。
## 失败安全：门表缺失/坏文件 push_error 并回退空表 → react 恒成功跳过零写入
##（空表 = 永不触发，不是硬编码回退）。
## 防漂移同步：门表 requires_all ⊆ encounters.json 的 on_victory_flag 集合；
## 每条 set_flag ∈ encounters.json 的 trigger_flag 集合（门的产出必须真能
## 触发一场已声明遭遇）。

const PROGRESSION_SCRIPT_PATH: String = "res://src/progression/progression.gd"
const DEFAULT_BOSS_GATE_PATH: String = "res://data/progression/boss_gate.json"
const ENCOUNTERS_JSON_PATH: String = "res://data/encounters/encounters.json"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")

## 迁移快照：生产门表逐字节等价于旧硬编码值。
const MIGRATED_GATE: Dictionary = {
	"requires_all": ["encounter_first_drift_won", "encounter_husk_ambush_won"],
	"requires_any_prefix": "policy_",
	"set_flag": "encounter_leviathan_due",
}

var _progression: Script = null
var _temp_paths: Array[String] = []


func before_each() -> void:
	_progression = load(PROGRESSION_SCRIPT_PATH)


func after_each() -> void:
	# 恢复生产门表并清理临时文件，防止临时门状态泄漏到其他测试文件。
	if _progression != null and _progression.has_method("load_boss_gate_from"):
		_progression.load_boss_gate_from(DEFAULT_BOSS_GATE_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


func _require_boss_gate_api() -> bool:
	if _progression == null:
		fail_test("Missing required S2 implementation: %s" % PROGRESSION_SCRIPT_PATH)
		return false
	if not _progression.has_method("load_boss_gate_from"):
		fail_test("Missing required S2 implementation: Progression.load_boss_gate_from")
		return false
	if not _progression.has_method("_boss_gate_entries"):
		fail_test("Missing required S2 implementation: Progression._boss_gate_entries")
		return false
	return true


func _state_with(flags: Dictionary) -> Dictionary:
	return {"revision": 5, "flags": flags.duplicate(true)}


func _write_temp_gate(case_name: String, text: String) -> String:
	var path: String = "user://s2_boss_gate_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时门表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


# ---------------------------------------------------------------- 门表加载


func test_default_boss_gate_loads_migrated_values() -> void:
	if not _require_boss_gate_api():
		return
	var loaded: AppResult = _progression.load_boss_gate_from(DEFAULT_BOSS_GATE_PATH)
	assert_true(loaded.is_ok, "生产 boss_gate.json 必须可装载：%s" % loaded.message)
	var entries: Array[Dictionary] = _progression._boss_gate_entries()
	assert_eq(entries.size(), 1, "生产门表现含 1 条迁移条目。")
	var entry: Dictionary = entries[0]
	var requires_all: Array = entry.get("requires_all", [])
	assert_eq(requires_all.size(), MIGRATED_GATE["requires_all"].size(), "requires_all 长度必须与迁移值一致。")
	for index: int in mini(requires_all.size(), (MIGRATED_GATE["requires_all"] as Array).size()):
		assert_eq(
			String(requires_all[index]), String((MIGRATED_GATE["requires_all"] as Array)[index]),
			"requires_all[%d] 必须逐字节迁移旧硬编码。" % index
		)
	assert_eq(
		String(entry.get("requires_any_prefix", "")), String(MIGRATED_GATE["requires_any_prefix"]),
		"requires_any_prefix 必须逐字节迁移旧 policy_ 前缀。"
	)
	assert_eq(
		String(entry.get("set_flag", "")), String(MIGRATED_GATE["set_flag"]),
		"set_flag 必须逐字节迁移旧 encounter_leviathan_due。"
	)


func test_bootstrap_loads_default_boss_gate_idempotently() -> void:
	if not _require_boss_gate_api():
		return
	var first: AppResult = _progression.bootstrap()
	assert_true(first.is_ok, "默认 bootstrap 必须同时装载链/结局门/Boss 门：%s" % first.message)
	assert_eq(_progression._boss_gate_entries().size(), 1, "bootstrap 后门表必须就绪。")
	var second: AppResult = _progression.bootstrap()
	assert_true(second.is_ok, "重复 bootstrap 必须幂等成功。")
	assert_eq(_progression._boss_gate_entries().size(), 1, "重复 bootstrap 不得重复扩展门表。")


# ---------------------------------------------------------------- 行为等价快照
# 冻结自迁移前探针（旧 _react_leviathan_gate 真实输出，命令与输出见
# ops/evidence/S2-BOSS-GATE.md）。[label, state_flags, signal, payload,
# expect_ok, expect_code, expect_commits, expect_ops]


func _frozen_matrix() -> Array:
	var due_ops: Array[Dictionary] = [
		{"type": "set_flag", "flag_id": "encounter_leviathan_due", "enabled": true},
	]
	return [
		["E_empty", {}, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_drift_only", {"encounter_first_drift_won": true}, "encounter_won", {"encounter_id": "encounter_first_drift"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_husk_only", {"encounter_husk_ambush_won": true}, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_two_wins_no_policy", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true}, "encounter_won", {"encounter_id": "encounter_first_drift"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_policy_only", {"policy_extraction_quota": true}, "encounter_won", {"encounter_id": "encounter_first_drift"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_all_met", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_extraction_quota": true}, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, true, "committed", 1, due_ops],
		["E_due_already", {"encounter_leviathan_due": true}, "encounter_won", {"encounter_id": "encounter_leviathan"}, true, "already_set", 0, [] as Array[Dictionary]],
		["E_due_plus_all", {"encounter_leviathan_due": true, "encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_sanctuary": true}, "encounter_won", {"encounter_id": "encounter_leviathan"}, true, "already_set", 0, [] as Array[Dictionary]],
		["E_false_victory", {"encounter_first_drift_won": false, "encounter_husk_ambush_won": true, "policy_sanctuary": true}, "encounter_won", {"encounter_id": "encounter_first_drift"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_false_policy", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_sanctuary": false}, "encounter_won", {"encounter_id": "encounter_first_drift"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["E_due_false_all_met", {"encounter_leviathan_due": false, "encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_sanctuary": true}, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, true, "committed", 1, due_ops],
		["E_missing_id", {}, "encounter_won", {}, false, "invalid_encounter_id", 0, [] as Array[Dictionary]],
		["E_bad_id", {}, "encounter_won", {"encounter_id": "Bad Encounter"}, false, "invalid_encounter_id", 0, [] as Array[Dictionary]],
		["P_empty", {}, "policy_chosen", {"policy_id": "policy_sanctuary"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["P_two_wins_no_policy", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true}, "policy_chosen", {"policy_id": "policy_sanctuary"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["P_all_met", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_sanctuary": true}, "policy_chosen", {"policy_id": "policy_sanctuary"}, true, "committed", 1, due_ops],
		["P_due_already", {"encounter_leviathan_due": true}, "policy_chosen", {"policy_id": "policy_sanctuary"}, true, "already_set", 0, [] as Array[Dictionary]],
		["P_false_policy", {"encounter_first_drift_won": true, "encounter_husk_ambush_won": true, "policy_sanctuary": false}, "policy_chosen", {"policy_id": "policy_sanctuary"}, true, "conditions_unmet", 0, [] as Array[Dictionary]],
		["P_missing_id", {}, "policy_chosen", {}, false, "invalid_policy_id", 0, [] as Array[Dictionary]],
		["P_bad_id", {}, "policy_chosen", {"policy_id": "Policy X"}, false, "invalid_policy_id", 0, [] as Array[Dictionary]],
	]


func test_react_boss_gate_matches_pre_migration_frozen_matrix() -> void:
	if not _require_boss_gate_api():
		return
	# 生产门表在场（恢复默认）的前提下，react 的 encounter_won/policy_chosen
	# 必须逐行复现旧 _react_leviathan_gate 的冻结矩阵。
	assert_true(_progression.load_boss_gate_from(DEFAULT_BOSS_GATE_PATH).is_ok)
	for row: Array in _frozen_matrix():
		var duck := S2DuckStore.new()
		_kept_stores.append(duck)
		var result: AppResult = _progression.react(
			_state_with(row[1] as Dictionary), String(row[2]), row[3] as Dictionary, duck)
		assert_eq(result.is_ok, bool(row[4]), "矩阵 %s 的成败必须与迁移前一致。" % String(row[0]))
		assert_eq(String(result.code), String(row[5]), "矩阵 %s 的 skip 码必须与迁移前一致。" % String(row[0]))
		assert_eq(duck.commit_calls, int(row[6]), "矩阵 %s 的提交次数必须与迁移前一致。" % String(row[0]))
		assert_eq(duck.operations, row[7] as Array[Dictionary], "矩阵 %s 的 ops 必须与迁移前一致。" % String(row[0]))


func test_react_encounter_won_all_met_commits_via_real_game_state() -> void:
	if not _require_boss_gate_api():
		return
	# 真实 GameState 端到端：双胜 + policy → due 置位、revision +1、重放幂等。
	assert_true(_progression.load_boss_gate_from(DEFAULT_BOSS_GATE_PATH).is_ok)
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	var seed_patch: StatePatch = store.begin_patch("s2_seed_boss_conditions", 0)
	seed_patch.set_flag("encounter_first_drift_won", true)
	seed_patch.set_flag("encounter_husk_ambush_won", true)
	seed_patch.set_flag("policy_extraction_quota", true)
	assert_true(store.commit(seed_patch).is_ok)

	var state: Dictionary = store.snapshot()
	var result: AppResult = _progression.react(
		state, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, store)
	assert_true(result.is_ok, result.message)
	var committed: Dictionary = store.snapshot()
	assert_true(
		bool((committed.get("flags", {}) as Dictionary).get("encounter_leviathan_due", false)),
		"双胜 + policy 必须经真实 GameState 置 encounter_leviathan_due。"
	)
	assert_eq(int(committed["revision"]), int(state["revision"]) + 1)

	var second: AppResult = _progression.react(
		store.snapshot(), "encounter_won", {"encounter_id": "encounter_husk_ambush"}, store)
	assert_true(second.is_ok, second.message)
	assert_eq(int(store.snapshot()["revision"]), int(committed["revision"]), "重复信号必须幂等跳过。")


# ---------------------------------------------------------------- 纯数据扩门


func test_pure_data_second_boss_gate_needs_no_code_change() -> void:
	if not _require_boss_gate_api():
		return
	# 纯数据扩门证明：临时门表加第二条 DLC 门（只写 JSON，不改 progression.gd）
	# 即进入 react 判定。第二条门用自己的 requires_all/set_flag，与旧门互不干扰。
	var extended: Array = [
		MIGRATED_GATE,
		{
			"requires_all": ["s2_dlc_encounter_won"],
			"requires_any_prefix": null,
			"set_flag": "s2_dlc_boss_due",
		},
	]
	var path := _write_temp_gate("extended", JSON.stringify(extended, "  "))
	assert_true(_progression.load_boss_gate_from(path).is_ok)

	# 只有第二条门的前置满足：旧门不置 due，新门置自己的 flag（DLC 门独立生效）。
	var dlc_only_duck := S2DuckStore.new()
	_kept_stores.append(dlc_only_duck)
	var dlc_only: AppResult = _progression.react(
		_state_with({"s2_dlc_encounter_won": true}), "encounter_won",
		{"encounter_id": "s2_dlc_encounter"}, dlc_only_duck)
	assert_true(dlc_only.is_ok, dlc_only.message)
	assert_eq(dlc_only_duck.operations, [
		{"type": "set_flag", "flag_id": "s2_dlc_boss_due", "enabled": true},
	] as Array[Dictionary], "新增门必须按 JSON 声明独立触发。")

	# 两条门同时到期：一次 patch 内按条目顺序逐条置位。
	var both_duck := S2DuckStore.new()
	_kept_stores.append(both_duck)
	var both: AppResult = _progression.react(
		_state_with({
			"encounter_first_drift_won": true,
			"encounter_husk_ambush_won": true,
			"policy_sanctuary": true,
			"s2_dlc_encounter_won": true,
		}), "policy_chosen", {"policy_id": "policy_sanctuary"}, both_duck)
	assert_true(both.is_ok, both.message)
	assert_eq(both_duck.commit_calls, 1, "多门同时到期必须合并为一次提交。")
	assert_eq(both_duck.operations, [
		{"type": "set_flag", "flag_id": "encounter_leviathan_due", "enabled": true},
		{"type": "set_flag", "flag_id": "s2_dlc_boss_due", "enabled": true},
	] as Array[Dictionary], "多门 ops 必须按条目顺序全部置位。")

	# 新门自身的幂等：set_flag 已置时该条跳过，其余门照常评估。
	var second_round_duck := S2DuckStore.new()
	_kept_stores.append(second_round_duck)
	var second_round: AppResult = _progression.react(
		_state_with({
			"encounter_leviathan_due": true,
			"s2_dlc_boss_due": true,
			"encounter_first_drift_won": true,
			"encounter_husk_ambush_won": true,
			"policy_sanctuary": true,
			"s2_dlc_encounter_won": true,
		}), "encounter_won", {"encounter_id": "encounter_husk_ambush"}, second_round_duck)
	assert_true(second_round.is_ok, second_round.message)
	assert_eq(second_round.code, "already_set", "全部条目 set_flag 已置时沿用 already_set 语义。")
	assert_eq(second_round_duck.commit_calls, 0, "全部条目已置时不得提交 patch。")


# ---------------------------------------------------------------- 失败安全


func test_missing_boss_gate_file_fails_safe_and_pushes_error() -> void:
	if not _require_boss_gate_api():
		return
	var result: AppResult = _progression.load_boss_gate_from(
		"res://data/progression/definitely_missing_boss_gate.json")
	assert_false(result.is_ok, "缺失门表文件必须加载失败。")
	assert_eq(result.code, "missing_boss_gate_file")
	# 规范要求文件缺失 push_error；预期错误断言同时消费该错误。
	assert_push_error("Progression: boss gate rejected")
	# 失败安全：空表 = 永不触发（不是硬编码回退）——旧条件全齐也不置 due。
	var all_set: Dictionary = {
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"policy_extraction_quota": true,
	}
	var duck := S2DuckStore.new()
	_kept_stores.append(duck)
	var skipped: AppResult = _progression.react(
		_state_with(all_set), "encounter_won", {"encounter_id": "encounter_husk_ambush"}, duck)
	assert_true(skipped.is_ok, "坏门表下 react 必须成功跳过。")
	assert_eq(String(skipped.code), "conditions_unmet", "空表兜底必须恒 conditions_unmet。")
	assert_eq(duck.commit_calls, 0, "空表兜底必须零写入。")


func test_malformed_boss_gate_files_are_rejected() -> void:
	if not _require_boss_gate_api():
		return
	var bad_cases: Array = [
		["syntax_error", "{\"requires_all\": not json"],
		["not_an_array", str(MIGRATED_GATE)],
		["empty_array", "[]"],
		["entry_not_object", "[\"encounter_leviathan_due\"]"],
		["missing_requires_all", "[{\"requires_any_prefix\": \"policy_\", \"set_flag\": \"encounter_leviathan_due\"}]"],
		["requires_all_not_array", "[{\"requires_all\": \"encounter_first_drift_won\", \"requires_any_prefix\": null, \"set_flag\": \"encounter_leviathan_due\"}]"],
		["requires_all_non_string_member", "[{\"requires_all\": [7], \"requires_any_prefix\": null, \"set_flag\": \"encounter_leviathan_due\"}]"],
		["requires_all_not_stable_id", "[{\"requires_all\": [\"First Won\"], \"requires_any_prefix\": null, \"set_flag\": \"encounter_leviathan_due\"}]"],
		["prefix_wrong_type", "[{\"requires_all\": [], \"requires_any_prefix\": 3, \"set_flag\": \"encounter_leviathan_due\"}]"],
		["prefix_empty_string", "[{\"requires_all\": [], \"requires_any_prefix\": \"\", \"set_flag\": \"encounter_leviathan_due\"}]"],
		["missing_set_flag", "[{\"requires_all\": [\"encounter_first_drift_won\"], \"requires_any_prefix\": null}]"],
		["set_flag_not_string", "[{\"requires_all\": [], \"requires_any_prefix\": null, \"set_flag\": 7}]"],
		["set_flag_not_stable_id", "[{\"requires_all\": [], \"requires_any_prefix\": null, \"set_flag\": \"Leviathan Due\"}]"],
		["duplicate_set_flag", "[{\"requires_all\": [], \"requires_any_prefix\": null, \"set_flag\": \"encounter_leviathan_due\"}, {\"requires_all\": [], \"requires_any_prefix\": null, \"set_flag\": \"encounter_leviathan_due\"}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_gate(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = _progression.load_boss_gate_from(path)
		assert_false(result.is_ok, "坏门表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_eq(result.code, "invalid_boss_gate_file", "坏门表 %s 必须报告 invalid。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Progression: boss gate rejected")
		# 失败安全：坏表兜底空表后，旧条件全齐也不得触发任何写入。
		var duck := S2DuckStore.new()
		_kept_stores.append(duck)
		var skipped: AppResult = _progression.react(
			_state_with({
				"encounter_first_drift_won": true,
				"encounter_husk_ambush_won": true,
				"policy_extraction_quota": true,
			}), "encounter_won", {"encounter_id": "encounter_husk_ambush"}, duck)
		assert_true(skipped.is_ok, "坏门表 %s 兜底后 react 必须成功跳过。" % String(case_entry[0]))
		assert_eq(duck.commit_calls, 0, "坏门表 %s 兜底后必须零写入。" % String(case_entry[0]))


# ---------------------------------------------------------------- 防漂移同步


func test_boss_gate_flags_stay_in_sync_with_encounter_data() -> void:
	if not _require_boss_gate_api():
		return
	# 门表旗标必须逐个出现在 data/encounters/encounters.json 的对应集合中：
	# requires_all ⊆ on_victory_flag 集合（门输入来自真实胜利旗标）；
	# set_flag ∈ trigger_flag 集合（门产出真能触发已声明遭遇）。
	assert_true(_progression.load_boss_gate_from(DEFAULT_BOSS_GATE_PATH).is_ok)
	var text: String = FileAccess.get_file_as_string(ENCOUNTERS_JSON_PATH)
	assert_false(text.is_empty(), "encounters.json 必须可读。")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(typeof(parsed) == TYPE_ARRAY, "encounters.json 必须是数组。")
	if typeof(parsed) != TYPE_ARRAY:
		return
	var victory_flags: Dictionary = {}
	var trigger_flags: Dictionary = {}
	for entry_value: Variant in parsed:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var encounter: Dictionary = entry_value
		var victory_id := String(encounter.get("on_victory_flag", ""))
		if not victory_id.is_empty():
			victory_flags[victory_id] = true
		var trigger_id := String(encounter.get("trigger_flag", ""))
		if not trigger_id.is_empty():
			trigger_flags[trigger_id] = true
	assert_false(victory_flags.is_empty(), "前置：遭遇数据必须提供 on_victory_flag。")
	assert_false(trigger_flags.is_empty(), "前置：遭遇数据必须提供 trigger_flag。")
	for gate: Dictionary in _progression._boss_gate_entries():
		for flag_variant: Variant in (gate.get("requires_all", []) as Array):
			assert_true(
				victory_flags.has(String(flag_variant)),
				"Boss 门输入旗标 %s 必须是某场遭遇的 on_victory_flag（防漂移）。" % String(flag_variant)
			)
		assert_true(
			trigger_flags.has(String(gate.get("set_flag", ""))),
			"Boss 门产出旗标 %s 必须是某场遭遇的 trigger_flag（防漂移）。" % String(gate.get("set_flag", ""))
		)


# ---------------------------------------------------------------- 测试替身宿主


## DuckStore 保活容器（Callable 只持 ObjectID，替身必须由宿主实例字段保活）。
var _kept_stores: Array[RefCounted] = []


class S2DuckStore extends RefCounted:
	var operations: Array[Dictionary] = []
	var commit_calls: int = 0

	func snapshot() -> Dictionary:
		return {"revision": 9}

	func begin_patch(_source_id: String, _expected_revision: int) -> S2DuckStore:
		return self

	func set_flag(flag_id: String, enabled: bool) -> void:
		operations.append({"type": "set_flag", "flag_id": flag_id, "enabled": enabled})

	func commit(_patch: Object) -> AppResult:
		commit_calls += 1
		return AppResult.success({"operations": operations.duplicate(true)}, "committed")
