extends GutTest

## DLX-3 建造反应通用化测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
##
## 任务书（DL2）：删除 _react_built 的逐 id match，改为通用规则——输入
## building_def：place_flag 存在→set_flag（place_flag_powered=true 时需供电）；
## effect_flag 存在且 powered→set_flag；powered=false 且 effect_flag 存在→不置。
## 建造反应行为逐字节等价：本文件的冻结矩阵来自旧 id-match 实现的真实输出
##（anchor_block/anchor_workshop 无条件置位、stabilizer_pylon/echo_chamber
## 供电门控、其余建筑 no_op），既有 test_progression.gd 快照零修改为第二证。
## 纯数据扩展测试证明"新增建造反应 = 建筑定义加字段"，不改 progression.gd。

const PROGRESSION_SCRIPT_PATH: String = "res://src/progression/progression.gd"
const BUILDINGS_JSON_PATH: String = "res://data/content/buildings.json"
const DEFAULT_REACTIONS_PATH: String = "res://data/content/buildings.json"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")

var _progression: Script = null
var _temp_paths: Array[String] = []


func before_each() -> void:
	_progression = load(PROGRESSION_SCRIPT_PATH)


func after_each() -> void:
	# 恢复默认反应表并清理临时文件，防止临时状态泄漏到其他测试文件。
	if _progression != null and _progression.has_method("load_building_reactions_from"):
		_progression.load_building_reactions_from(DEFAULT_REACTIONS_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


## DuckStore/DuckPatch 宿主实例字段：保活注入替身（Callable 只持 ObjectID）。
var _duck_store: DuckStore = null


class DuckStore extends RefCounted:
	var last_source_id: String = ""
	var operations: Array[Dictionary] = []
	var commit_calls: int = 0

	func snapshot() -> Dictionary:
		return {"revision": 9}

	func begin_patch(source_id: String, _expected_revision: int) -> DuckStore:
		last_source_id = source_id
		return self

	func set_flag(flag_id: String, enabled: bool) -> void:
		operations.append({"type": "set_flag", "flag_id": flag_id, "enabled": enabled})

	func commit(_patch: Object) -> AppResult:
		commit_calls += 1
		return AppResult.success({"operations": operations.duplicate(true)}, "committed")


func _duck() -> DuckStore:
	_duck_store = DuckStore.new()
	return _duck_store


func _require_progression() -> bool:
	if _progression == null:
		fail_test("Missing required DLX-3 implementation: %s" % PROGRESSION_SCRIPT_PATH)
		return false
	return true


func _fresh_game_state() -> Node:
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	return store


## 直接从数据文件读取生产建筑定义（不依赖 ContentDB autoload 的引导时序），
## 作为"payload 携带 building_def"路径的数据源。
func _production_building_defs() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(BUILDINGS_JSON_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		fail_test("buildings.json must parse: %s" % json.get_error_message())
		return {}
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		fail_test("buildings.json must be an array.")
		return {}
	var defs: Dictionary = {}
	for entry_value: Variant in parsed:
		var entry: Dictionary = entry_value
		defs[String(entry["id"])] = entry
	return defs


# ---------------------------------------------------------------- 反应表加载


func test_production_reactions_table_loads_from_buildings_json() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_building_reactions_from(DEFAULT_REACTIONS_PATH)
	assert_true(loaded.is_ok, "生产 buildings.json 必须可作为反应表加载：%s" % loaded.message)
	var reactions: Dictionary = _progression._reactions_table()
	assert_eq(reactions.size(), 6, "反应表必须覆盖全部 6 个建筑定义。")
	assert_eq(
		String((reactions.get("anchor_block", {}) as Dictionary).get("place_flag", "")),
		"first_anchor_placed",
		"anchor_block 必须声明 place_flag。"
	)
	assert_eq(
		String((reactions.get("anchor_workshop", {}) as Dictionary).get("place_flag", "")),
		"anchor_workshop_placed",
		"anchor_workshop 必须声明 place_flag。"
	)
	assert_eq(
		String((reactions.get("stabilizer_pylon", {}) as Dictionary).get("effect_flag", "")),
		"pylon_stabilized",
		"stabilizer_pylon 的 effect_flag 语义保持不变（供电门控）。"
	)
	assert_eq(
		String((reactions.get("echo_chamber", {}) as Dictionary).get("effect_flag", "")),
		"echo_chamber_active",
		"echo_chamber 的 effect_flag 语义保持不变（供电门控）。"
	)
	assert_true(
		String((reactions.get("dust_refiner", {}) as Dictionary).get("place_flag", "")).is_empty(),
		"无里程碑语义的建筑不得声明 place_flag。"
	)


# ---------------------------------------------------------------- 等价快照矩阵


## 冻结自旧 id-match 实现的真实行为（迁移前快照）：[building_id, powered, 期望 ops]。
## anchor_block/anchor_workshop 与 powered 无关（放置即置位）；两座 effect 建筑
## 供电才置位；无反应建筑恒 no_op。
func _frozen_built_matrix() -> Array:
	var anchor_ops: Array[Dictionary] = [
		{"type": "set_flag", "flag_id": "first_anchor_placed", "enabled": true},
	]
	var workshop_ops: Array[Dictionary] = [
		{"type": "set_flag", "flag_id": "anchor_workshop_placed", "enabled": true},
	]
	var pylon_ops: Array[Dictionary] = [
		{"type": "set_flag", "flag_id": "pylon_stabilized", "enabled": true},
	]
	var chamber_ops: Array[Dictionary] = [
		{"type": "set_flag", "flag_id": "echo_chamber_active", "enabled": true},
	]
	return [
		["anchor_block", true, anchor_ops],
		["anchor_block", false, anchor_ops],
		["anchor_workshop", true, workshop_ops],
		["anchor_workshop", false, workshop_ops],
		["stabilizer_pylon", true, pylon_ops],
		["stabilizer_pylon", false, [] as Array[Dictionary]],
		["echo_chamber", true, chamber_ops],
		["echo_chamber", false, [] as Array[Dictionary]],
		["dust_refiner", true, [] as Array[Dictionary]],
	]


func test_built_reactions_match_frozen_matrix_without_def() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_building_reactions_from(DEFAULT_REACTIONS_PATH)
	assert_true(loaded.is_ok, loaded.message)
	# 无 building_def 的旧调用形态（直接 react 的既有测试快照路径）必须逐字节等价。
	for row: Array in _frozen_built_matrix():
		var duck := _duck()
		var result: AppResult = _progression.react(
			{"revision": 5, "flags": {}}, "built",
			{"building_id": String(row[0]), "powered": bool(row[1])}, duck)
		assert_true(
			result.is_ok, "built(%s, powered=%s) 必须成功。" % [row[0], row[1]]
		)
		assert_eq(
			duck.operations, row[2] as Array[Dictionary],
			"built(%s, powered=%s) 的 ops 必须与迁移前一致。" % [row[0], row[1]]
		)
		if (row[2] as Array).is_empty():
			assert_eq(duck.commit_calls, 0, "无反应建筑不得提交 patch。")
			assert_eq(String(result.code), "no_op")
		else:
			assert_eq(duck.commit_calls, 1)


func test_built_reactions_match_frozen_matrix_with_payload_def() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_building_reactions_from(DEFAULT_REACTIONS_PATH)
	assert_true(loaded.is_ok, loaded.message)
	var defs: Dictionary = _production_building_defs()
	assert_false(defs.is_empty(), "前置：生产建筑定义必须可读。")
	# 集成调用形态（payload 携带 building_def）必须与无 def 的回退路径逐字节一致。
	for row: Array in _frozen_built_matrix():
		var duck := _duck()
		var result: AppResult = _progression.react(
			{"revision": 5, "flags": {}}, "built",
			{
				"building_id": String(row[0]),
				"powered": bool(row[1]),
				"building_def": defs[String(row[0])],
			}, duck)
		assert_true(result.is_ok, result.message)
		assert_eq(
			duck.operations, row[2] as Array[Dictionary],
			"payload def 路径的 ops 必须与冻结矩阵一致。"
		)


# ---------------------------------------------------------------- 通用规则（纯数据扩展）


func test_pure_data_place_flag_extension_needs_no_code_change() -> void:
	if not _require_progression():
		return
	# 测试内临时 building_def 带 place_flag：放置后 flag 置位——证明新增建造反应
	# 只需建筑定义加字段，零代码扩展。
	var store: Node = _fresh_game_state()
	var custom_def: Dictionary = {
		"id": "dlx3_shrine",
		"place_flag": "dlx3_shrine_raised",
	}
	var result: AppResult = _progression.react(
		store.snapshot(), "built",
		{"building_id": "dlx3_shrine", "powered": false, "building_def": custom_def}, store)
	assert_true(result.is_ok, result.message)
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("dlx3_shrine_raised", false)),
		"place_flag 定义必须在放置成功后置位（不受 powered 影响）。"
	)


func test_place_flag_powered_gates_on_power() -> void:
	if not _require_progression():
		return
	# place_flag_powered=true 复刻 effect_flag 语义：需供电才置位。
	var powered_def: Dictionary = {
		"id": "dlx3_beacon",
		"place_flag": "dlx3_beacon_lit",
		"place_flag_powered": true,
	}
	var unpowered_duck := _duck()
	var unpowered: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built",
		{"building_id": "dlx3_beacon", "powered": false, "building_def": powered_def}, unpowered_duck)
	assert_true(unpowered.is_ok, "未供电仍须成功返回（零写入）。")
	assert_eq(unpowered_duck.commit_calls, 0, "未供电的 powered-place_flag 不得提交 patch。")
	assert_eq(unpowered_duck.operations, [] as Array[Dictionary])

	var lit_duck := _duck()
	var lit: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built",
		{"building_id": "dlx3_beacon", "powered": true, "building_def": powered_def}, lit_duck)
	assert_true(lit.is_ok, lit.message)
	assert_eq(lit_duck.operations, [
		{"type": "set_flag", "flag_id": "dlx3_beacon_lit", "enabled": true},
	] as Array[Dictionary])


func test_effect_flag_general_rule_reads_def_not_id() -> void:
	if not _require_progression():
		return
	# effect_flag"供电后置位"是通用规则而非 id 特判：任意定义携带即生效。
	var duck := _duck()
	var result: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built",
		{
			"building_id": "dlx3_resonator",
			"powered": true,
			"building_def": {"id": "dlx3_resonator", "effect_flag": "dlx3_resonance_active"},
		}, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "dlx3_resonance_active", "enabled": true},
	] as Array[Dictionary])

	var silent_duck := _duck()
	var silent: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built",
		{
			"building_id": "dlx3_resonator",
			"powered": false,
			"building_def": {"id": "dlx3_resonator", "effect_flag": "dlx3_resonance_active"},
		}, silent_duck)
	assert_true(silent.is_ok, "未供电仍须成功返回。")
	assert_eq(silent_duck.commit_calls, 0, "未供电的 effect_flag 不得提交 patch。")


func test_built_def_without_flags_is_no_op_even_for_known_id() -> void:
	if not _require_progression():
		return
	# payload def 是权威输入：无反应字段的 def（即使 id 是 anchor_block）不产生 ops。
	var duck := _duck()
	var result: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built",
		{"building_id": "anchor_block", "powered": true, "building_def": {"id": "anchor_block"}}, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 0, "无反应字段的 def 不得提交 patch。")
	assert_eq(duck.operations, [] as Array[Dictionary])
	assert_eq(String(result.code), "no_op")


# ---------------------------------------------------------------- 失败安全


func test_missing_reactions_file_fails_safe_and_pushes_error() -> void:
	if not _require_progression():
		return
	var result: AppResult = _progression.load_building_reactions_from(
		"res://data/progression/definitely_missing_reactions.json")
	assert_false(result.is_ok, "缺失反应表文件必须加载失败。")
	assert_eq(result.code, "missing_reactions_file")
	# 规范要求文件缺失 push_error；预期错误断言同时消费该错误。
	assert_push_error("building reactions rejected")
	# 失败安全：回退表为空时，无 def 的 built 反应恒 no_op。
	var duck := _duck()
	var react_result: AppResult = _progression.react(
		{"revision": 5, "flags": {}}, "built", {"building_id": "anchor_block"}, duck)
	assert_true(react_result.is_ok, "坏表下 built 必须失败安全（成功 + 零写入）。")
	assert_eq(duck.commit_calls, 0)
	assert_eq(duck.operations, [] as Array[Dictionary])


func test_malformed_reactions_files_are_rejected() -> void:
	if not _require_progression():
		return
	var bad_cases: Array = [
		["syntax_error", "{\"id\": not json"],
		["not_an_array", "{\"id\": \"anchor_block\"}"],
		["entry_not_object", "[\"anchor_block\"]"],
		["missing_id", "[{\"place_flag\": \"x\"}]"],
		["duplicate_id", "[{\"id\": \"b1\"}, {\"id\": \"b1\"}]"],
		["place_flag_wrong_type", "[{\"id\": \"b1\", \"place_flag\": 7}]"],
		["place_flag_not_stable_id", "[{\"id\": \"b1\", \"place_flag\": \"First Flag\"}]"],
		["powered_wrong_type", "[{\"id\": \"b1\", \"place_flag_powered\": \"yes\"}]"],
		["effect_flag_wrong_type", "[{\"id\": \"b1\", \"effect_flag\": []}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_reactions(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = _progression.load_building_reactions_from(path)
		assert_false(result.is_ok, "坏反应表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Progression: building reactions rejected")


func _write_temp_reactions(case_name: String, text: String) -> String:
	var path: String = "user://dlx3_reactions_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时反应表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path
