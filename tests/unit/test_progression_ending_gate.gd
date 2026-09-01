extends GutTest

## G7P-2 S1：ending_ready 门控数据化（TDD：先 RED 后 GREEN）。
##
## 结局门控的"全部遭遇胜利旗标"外置到 data/progression/ending_gate.json
## （schema schemas/ending-gate.schema.json）：新增/调整结局门条件 = 改 JSON，
## 不改 progression.gd。行为等价约束：
## - station_mode_* 前缀守卫保留在 Progression（链前缀词汇表的规范来源）；
## - 生产门旗标集 = 迁移前硬编码的三个遭遇胜利旗标（既有
##   test_progression.gd 的 ending_ready 快照零修改为等价证明）；
## - 文件缺失/坏文件 push_error 并回退空表 → ending_ready 失败安全恒 false
##   （空表 = 永不满足，不是空真）。
## 同步测试锁定 ending_gate.requires_all ⊆ encounters.json 的 on_victory_flag
## 集合（防门控旗标与遭遇数据漂移）。

const PROGRESSION_SCRIPT_PATH: String = "res://src/progression/progression.gd"
const DEFAULT_ENDING_GATE_PATH: String = "res://data/progression/ending_gate.json"
const ENCOUNTERS_JSON_PATH: String = "res://data/encounters/encounters.json"

var _progression: Script = null
var _temp_paths: Array[String] = []


func before_each() -> void:
	_progression = load(PROGRESSION_SCRIPT_PATH)


func after_each() -> void:
	# 恢复生产门表并清理临时文件，防止临时状态泄漏到其他测试文件。
	if _progression != null and _progression.has_method("load_ending_gate_from"):
		_progression.load_ending_gate_from(DEFAULT_ENDING_GATE_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


func _require_progression() -> bool:
	if _progression == null:
		fail_test("Missing required implementation: %s" % PROGRESSION_SCRIPT_PATH)
		return false
	return true


func _state_with(flags: Dictionary) -> Dictionary:
	return {"revision": 5, "flags": flags.duplicate(true)}


func _write_temp_gate(case_name: String, text: String) -> String:
	var path: String = "user://g7p2_ending_gate_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时门表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


# ---------------------------------------------------------------- 门表加载


func test_default_ending_gate_loads_from_production_data() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_ending_gate_from(DEFAULT_ENDING_GATE_PATH)
	assert_true(loaded.is_ok, "生产 ending_gate.json 必须可装载：%s" % loaded.message)
	assert_eq(
		_progression._ending_gate_requires_all(),
		[
			"encounter_first_drift_won",
			"encounter_husk_ambush_won",
			"encounter_leviathan_won",
		] as Array[String],
		"生产门表必须逐字节迁移旧硬编码的三个遭遇胜利旗标。"
	)


func test_bootstrap_loads_default_ending_gate() -> void:
	if not _require_progression():
		return
	var result: AppResult = _progression.bootstrap()
	assert_true(result.is_ok, "默认 bootstrap 必须同时装载事件链与结局门表：%s" % result.message)
	assert_eq(_progression._ending_gate_requires_all().size(), 3, "bootstrap 后门旗标集必须就绪。")


# ---------------------------------------------------------------- ending_ready 等价


func test_ending_ready_requires_station_mode_and_all_gate_flags() -> void:
	if not _require_progression():
		return
	# 与迁移前硬编码行为逐字节等价（test_progression.gd 快照的第二证）。
	var victories: Dictionary = {
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"encounter_leviathan_won": true,
	}
	assert_false(_progression.ending_ready({}), "空 state 永不就绪。")
	assert_false(_progression.ending_ready({"flags": {}}))
	assert_false(
		_progression.ending_ready(_state_with({"station_mode_symbiosis": true})),
		"仅驻地模式不够。"
	)
	assert_false(
		_progression.ending_ready(_state_with(victories.duplicate())),
		"三门旗标齐全但无驻地模式不够。"
	)

	var missing_husk: Dictionary = victories.duplicate()
	missing_husk["encounter_husk_ambush_won"] = false
	missing_husk["station_mode_exploit"] = true
	assert_false(
		_progression.ending_ready(_state_with(missing_husk)),
		"缺任一门旗标阻塞结局。"
	)

	var full: Dictionary = victories.duplicate()
	full["station_mode_exploit"] = true
	assert_true(_progression.ending_ready(_state_with(full)))
	var symbiosis: Dictionary = victories.duplicate()
	symbiosis["station_mode_symbiosis"] = true
	assert_true(_progression.ending_ready(_state_with(symbiosis)))


# ---------------------------------------------------------------- 纯数据扩展


func test_gate_flag_set_is_pure_data_extension() -> void:
	if not _require_progression():
		return
	# 门旗标集加一项 = 改 JSON：第四旗标未置位时不就绪，置位后恢复就绪。
	var gate_path := _write_temp_gate("extended", JSON.stringify({
		"requires_all": [
			"encounter_first_drift_won",
			"encounter_husk_ambush_won",
			"encounter_leviathan_won",
			"g7p2_extra_gate_flag",
		],
	}))
	assert_true(_progression.load_ending_gate_from(gate_path).is_ok)
	var base: Dictionary = {
		"station_mode_exploit": true,
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"encounter_leviathan_won": true,
	}
	assert_false(
		_progression.ending_ready(_state_with(base)),
		"数据新增的第四门旗标未置位时不得就绪。"
	)
	var extended: Dictionary = base.duplicate()
	extended["g7p2_extra_gate_flag"] = true
	assert_true(_progression.ending_ready(_state_with(extended)))


# ---------------------------------------------------------------- 失败安全


func test_missing_gate_file_fails_safe_and_pushes_error() -> void:
	if not _require_progression():
		return
	var result: AppResult = _progression.load_ending_gate_from(
		"res://data/progression/definitely_missing_ending_gate.json")
	assert_false(result.is_ok, "缺失门表文件必须加载失败。")
	assert_eq(result.code, "missing_ending_gate_file")
	# 规范要求文件缺失 push_error；预期错误断言同时消费该错误。
	assert_push_error("Progression: ending gate rejected")
	# 失败安全：空表 = 永不满足（不是空真）——驻地模式齐全也不就绪。
	var all_set: Dictionary = {
		"station_mode_exploit": true,
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"encounter_leviathan_won": true,
	}
	assert_false(
		_progression.ending_ready(_state_with(all_set)),
		"坏表兜底空表必须永不满足。"
	)


func test_malformed_gate_files_are_rejected() -> void:
	if not _require_progression():
		return
	var bad_cases: Array = [
		["syntax_error", "{\"requires_all\": not json"],
		["not_an_object", "[\"encounter_first_drift_won\"]"],
		["missing_requires_all", "{}"],
		["requires_all_not_array", "{\"requires_all\": \"flag\"}"],
		["requires_all_empty", "{\"requires_all\": []}"],
		["requires_all_entry_not_string", "{\"requires_all\": [7]}"],
		["requires_all_entry_empty", "{\"requires_all\": [\"\"]}"],
		["requires_all_entry_not_stable_id", "{\"requires_all\": [\"First Won\"]}"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_gate(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = _progression.load_ending_gate_from(path)
		assert_false(result.is_ok, "坏门表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_eq(result.code, "invalid_ending_gate_file", "坏门表 %s 必须报告 invalid。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Progression: ending gate rejected")


# ---------------------------------------------------------------- 防漂移同步测试


func test_ending_gate_flags_are_subset_of_encounter_on_victory_flags() -> void:
	if not _require_progression():
		return
	# 门表旗标必须逐个出现在 data/encounters/encounters.json 的 on_victory_flag
	# 集合中：遭遇数据删改胜利旗标而门表未同步时显式红灯。
	assert_true(_progression.load_ending_gate_from(DEFAULT_ENDING_GATE_PATH).is_ok)
	var text: String = FileAccess.get_file_as_string(ENCOUNTERS_JSON_PATH)
	assert_false(text.is_empty(), "encounters.json 必须可读。")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(typeof(parsed) == TYPE_ARRAY, "encounters.json 必须是数组。")
	if typeof(parsed) != TYPE_ARRAY:
		return
	var victory_flags: Dictionary = {}
	for entry_value: Variant in parsed:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var encounter: Dictionary = entry_value
		var flag_id := String(encounter.get("on_victory_flag", ""))
		if not flag_id.is_empty():
			victory_flags[flag_id] = true
	assert_false(victory_flags.is_empty(), "前置：遭遇数据必须提供 on_victory_flag。")
	for flag_id: String in _progression._ending_gate_requires_all():
		assert_true(
			victory_flags.has(flag_id),
			"结局门旗标 %s 必须是某场遭遇的 on_victory_flag（防漂移）。" % flag_id
		)
