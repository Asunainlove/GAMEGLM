extends GutTest

## DLX-2 事件链外置测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 覆盖：链文件加载与迁移逐条快照、守卫字段四组合、坏文件拒绝、
## 纯数据扩链（加事件=改 JSON，不改 progression.gd）、迁移前后 due 序列等价矩阵。
## 等价矩阵期望值冻结自迁移前探针输出（旧硬编码 _event_chain() 的真实运行结果，
## 探针命令与输出存档于 ops/evidence/DLX-2.md）。矩阵 H 的期望序列为旧系统
## 全局行为：DLX-1 tick 过渡钩子先于 due_event 触发 event_envoy_trust，故
## event_envoy_trust 在外置链中占据链首（优先级序），使删除钩子后同一 state
## 的触发序列逐事件一致。

const PROGRESSION_SCRIPT_PATH: String = "res://src/progression/progression.gd"
const DEFAULT_CHAIN_PATH: String = "res://data/progression/event_chain.json"
const DONE_FORMAT: String = "event_%s_done"

var _progression: Script = null
var _temp_paths: Array[String] = []


func before_each() -> void:
	_progression = load(PROGRESSION_SCRIPT_PATH)


func after_each() -> void:
	# 恢复默认链并清理临时文件，防止临时链状态泄漏到其他测试文件。
	if _progression != null and _progression.has_method("load_chain_from"):
		_progression.load_chain_from(DEFAULT_CHAIN_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


# ---------------------------------------------------------------- 链文件加载


func test_bootstrap_loads_default_chain_and_is_idempotent() -> void:
	if not _require_progression():
		return
	var first: AppResult = _progression.bootstrap()
	assert_true(first.is_ok, "默认链文件必须可加载：%s" % first.message)
	assert_eq(_progression._event_chain().size(), 25, "外置链必须包含 24 个迁移条目 + 1 个并入的 envoy_trust。")
	var second: AppResult = _progression.bootstrap()
	assert_true(second.is_ok, "重复 bootstrap 必须幂等成功。")
	assert_eq(_progression._event_chain().size(), 25, "重复 bootstrap 不得重复扩展链。")


func test_chain_file_matches_pre_migration_entries_verbatim() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_chain_from(DEFAULT_CHAIN_PATH)
	assert_true(loaded.is_ok, loaded.message)
	# 迁移快照：与旧 _event_chain() 逐条逐字段等价（探针导出的字面量），
	# 另加 DLX-1 过渡钩子并入的 event_envoy_trust（链首 = 旧钩子先于链的优先级）。
	var expected: Array = [
		{"id": "event_envoy_trust", "requires_all": ["approach_diplomatic"], "prefix": null, "ending": false},
		{"id": "event_prologue_landing", "requires_all": [], "prefix": null, "ending": false},
		{"id": "event_first_mining", "requires_all": ["first_mining_done"], "prefix": null, "ending": false},
		{"id": "event_drift_aftermath", "requires_all": ["encounter_first_drift_won"], "prefix": null, "ending": false},
		{"id": "event_first_anchor", "requires_all": ["first_anchor_placed"], "prefix": null, "ending": false},
		{"id": "event_workshop_guide", "requires_all": ["anchor_workshop_placed"], "prefix": null, "ending": false},
		{"id": "event_misa_campfire", "requires_all": ["anchor_workshop_placed"], "prefix": null, "ending": false},
		{"id": "event_husk_aftermath", "requires_all": ["encounter_husk_ambush_won"], "prefix": null, "ending": false},
		{"id": "event_station_mode", "requires_all": ["echo_chamber_active"], "prefix": null, "ending": false},
		{"id": "event_echo_resonance", "requires_all": ["echo_chamber_active"], "prefix": null, "ending": false},
		{"id": "event_approach", "requires_all": [], "prefix": "station_mode_", "ending": false},
		{"id": "event_policy", "requires_all": [], "prefix": "approach_", "ending": false},
		{"id": "event_lumen_wildfire", "requires_all": ["world_response_exploited"], "prefix": null, "ending": false},
		{"id": "event_diplomat_envoy", "requires_all": ["diplomatic_stance", "echo_chamber_active"], "prefix": null, "ending": false},
		{"id": "event_leviathan_pact_pre", "requires_all": ["mine_entered", "encounter_leviathan_due"], "prefix": null, "ending": false},
		{"id": "event_leviathan_pact", "requires_all": ["encounter_leviathan_due"], "prefix": null, "ending": false},
		{"id": "event_leviathan_aftermath", "requires_all": ["encounter_leviathan_won"], "prefix": null, "ending": false},
		{"id": "event_dust_calamity", "requires_all": ["anchor_workshop_placed"], "prefix": null, "ending": false},
		{"id": "event_quiet_night", "requires_all": ["event_event_misa_campfire_done", "anchor_workshop_placed"], "prefix": null, "ending": false},
		{"id": "event_pylon_hum", "requires_all": ["pylon_stabilized"], "prefix": null, "ending": false},
		{"id": "event_final_ascent", "requires_all": ["encounter_leviathan_won", "encounter_leviathan_due"], "prefix": null, "ending": false},
		{"id": "event_ending_luoxian", "requires_all": [], "prefix": null, "ending": true},
		{"id": "event_ending_misa", "requires_all": [], "prefix": null, "ending": true},
		{"id": "event_epilogue_exploited", "requires_all": ["station_mode_exploit", "world_response_exploited", "encounter_leviathan_won"], "prefix": null, "ending": false},
		{"id": "event_epilogue_sealed", "requires_all": ["station_mode_seal", "echo_chamber_active", "encounter_leviathan_won"], "prefix": null, "ending": false},
	]
	var chain: Array[Dictionary] = _progression._event_chain()
	assert_eq(chain.size(), expected.size(), "链长度必须与迁移快照一致。")
	for index: int in mini(chain.size(), expected.size()):
		var actual: Dictionary = chain[index]
		var wanted: Dictionary = expected[index]
		assert_eq(
			String(actual.get("id", "")), String(wanted["id"]),
			"链位 %d 的 id 必须与迁移快照一致。" % index
		)
		var actual_all: Array = actual.get("requires_all", [])
		var wanted_all: Array = wanted["requires_all"]
		assert_eq(actual_all.size(), wanted_all.size(), "条目 %s requires_all 长度不一致。" % String(wanted["id"]))
		for flag_index: int in mini(actual_all.size(), wanted_all.size()):
			assert_eq(
				String(actual_all[flag_index]), String(wanted_all[flag_index]),
				"条目 %s requires_all[%d] 不一致。" % [String(wanted["id"]), flag_index]
			)
		var actual_prefix: Variant = actual.get("requires_any_prefix")
		if wanted["prefix"] == null:
			assert_true(
				actual_prefix == null or String(actual_prefix).is_empty(),
				"条目 %s requires_any_prefix 必须为空。" % String(wanted["id"])
			)
		else:
			assert_eq(
				String(actual_prefix), String(wanted["prefix"]),
				"条目 %s requires_any_prefix 不一致。" % String(wanted["id"])
			)
		assert_eq(
			bool(actual.get("requires_ending_ready", false)), bool(wanted["ending"]),
			"条目 %s requires_ending_ready 不一致。" % String(wanted["id"])
		)


# ---------------------------------------------------------------- 守卫字段四组合


func test_chain_guard_field_combinations_on_production_chain() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_chain_from(DEFAULT_CHAIN_PATH)
	assert_true(loaded.is_ok, loaded.message)

	# 1) 无守卫（空 requires_all / null prefix / false ending）：空 state 即到期
	#    链首无守卫条目（envoy 需要 approach_diplomatic，未置 → 让路）。
	assert_eq(_progression.due_event({"flags": {}}), "event_prologue_landing")

	# 2) requires_all：flag 未置 → 跳过；置位（含 done 模板形态的双前缀 flag）→ 到期。
	var all_missing: Dictionary = {"flags": {_done("event_prologue_landing"): true}}
	assert_eq(_progression.due_event(all_missing), "", "requires_all 未满足时必须让路。")
	var all_met: Dictionary = {"flags": {
		_done("event_prologue_landing"): true,
		"first_mining_done": true,
	}}
	assert_eq(_progression.due_event(all_met), "event_first_mining")

	# 3) requires_any_prefix：任一同前缀 flag 置位即通过，false 值不算命中。
	var prefix_absent: Dictionary = {"flags": {
		_done("event_prologue_landing"): true,
		"station_mode_exploit": false,
	}}
	assert_eq(_progression.due_event(prefix_absent), "", "requires_any_prefix 无命中时必须让路。")
	var prefix_met: Dictionary = {"flags": {
		_done("event_prologue_landing"): true,
		_done("event_first_mining"): true,
		_done("event_drift_aftermath"): true,
		_done("event_first_anchor"): true,
		_done("event_workshop_guide"): true,
		_done("event_misa_campfire"): true,
		_done("event_husk_aftermath"): true,
		_done("event_station_mode"): true,
		_done("event_echo_resonance"): true,
		"station_mode_symbiosis": true,
	}}
	assert_eq(
		_progression.due_event(prefix_met), "event_approach",
		"任一 station_mode_* flag 置位必须放行 event_approach。"
	)

	# 4) requires_ending_ready：Progression.ending_ready(state) 为假 → 结局条目让路；
	#    为真 → 到期。（approach 需一并 done：station_mode_exploit 同时命中其
	#    requires_any_prefix，会抢先成为链首 due。）
	var ending_blocked: Dictionary = {"flags": {
		_done("event_prologue_landing"): true,
		_done("event_drift_aftermath"): true,
		_done("event_husk_aftermath"): true,
		_done("event_leviathan_aftermath"): true,
		_done("event_approach"): true,
		"station_mode_exploit": true,
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
	}}
	assert_eq(
		_progression.due_event(ending_blocked), "",
		"ending_ready 为假时结局条目必须让路（该 state 下整链为空）。"
	)
	ending_blocked["flags"]["encounter_leviathan_won"] = true
	assert_eq(_progression.due_event(ending_blocked), "event_ending_luoxian")


# ---------------------------------------------------------------- 坏文件拒绝


func test_malformed_chain_files_are_rejected_and_due_event_fails_safe() -> void:
	if not _require_progression():
		return
	var bad_cases: Array = [
		["syntax_error", "{\"id\": not json"],
		["not_an_array", "{\"id\": \"event_x\"}"],
		["entry_not_object", "[\"event_x\"]"],
		["missing_id", "[{\"requires_all\": []}]"],
		["empty_id", "[{\"id\": \"\", \"requires_all\": []}]"],
		["non_snake_case_id", "[{\"id\": \"Event X\", \"requires_all\": []}]"],
		["duplicate_id", "[{\"id\": \"event_x\", \"requires_all\": []}, {\"id\": \"event_x\", \"requires_all\": []}]"],
		["requires_all_wrong_type", "[{\"id\": \"event_x\", \"requires_all\": \"first_mining_done\"}]"],
		["requires_all_non_string_member", "[{\"id\": \"event_x\", \"requires_all\": [7]}]"],
		["prefix_wrong_type", "[{\"id\": \"event_x\", \"requires_all\": [], \"requires_any_prefix\": 3}]"],
		["ending_ready_wrong_type", "[{\"id\": \"event_x\", \"requires_all\": [], \"requires_ending_ready\": \"yes\"}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_chain(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = _progression.load_chain_from(path)
		assert_false(result.is_ok, "坏链文件 %s 必须被拒绝。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		# 规范要求坏文件 push_error；GUT 的预期错误断言同时消费该错误
		#（标记 handled），使其成为被验证的行为而非"意外错误"。
		assert_push_error("Progression: event chain rejected")
		assert_eq(
			_progression.due_event({"flags": {}}), "",
			"坏链文件加载后 due_event 必须失败安全（返回空串）。"
		)


func test_missing_chain_file_pushes_error_and_due_event_returns_empty() -> void:
	if not _require_progression():
		return
	var result: AppResult = _progression.load_chain_from("res://data/progression/definitely_missing_chain.json")
	assert_false(result.is_ok, "缺失链文件必须加载失败。")
	assert_eq(result.code, "missing_chain_file")
	# 规范要求文件缺失 push_error（见上：预期错误断言同时消费该错误）。
	assert_push_error("Event chain file not found")
	assert_eq(_progression.due_event({"flags": {}}), "", "链文件缺失时 due_event 必须返回空串。")


# ---------------------------------------------------------------- 纯数据扩链


func test_pure_data_chain_extension_needs_no_code_change() -> void:
	if not _require_progression():
		return
	# 纯数据扩链证明：新增事件只写临时链 JSON（不改 progression.gd）即可进入
	# due_event 的判定与 done 消费流程。
	var extended: Array = [
		{"id": "event_dlx2_alpha", "requires_all": [], "requires_any_prefix": null, "requires_ending_ready": false},
		{"id": "event_dlx2_beta", "requires_all": ["dlx2_beta_unlocked"], "requires_any_prefix": null, "requires_ending_ready": false},
	]
	var path := _write_temp_chain("extended", JSON.stringify(extended, "  "))
	var loaded: AppResult = _progression.load_chain_from(path)
	assert_true(loaded.is_ok, loaded.message)

	var flags: Dictionary = {}
	assert_eq(_progression.due_event({"flags": flags}), "event_dlx2_alpha", "扩链事件必须按 JSON 声明到期。")
	flags[_done("event_dlx2_alpha")] = true
	assert_eq(_progression.due_event({"flags": flags}), "", "beta 的 requires_all 未满足时必须让路。")
	flags["dlx2_beta_unlocked"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_dlx2_beta", "新增事件的守卫必须生效。")
	flags[_done("event_dlx2_beta")] = true
	assert_eq(_progression.due_event({"flags": flags}), "", "扩链事件的 done 消费必须沿用同一模板。")


# ---------------------------------------------------------------- 行为等价快照


func test_due_sequences_match_pre_migration_snapshot_matrix() -> void:
	if not _require_progression():
		return
	var loaded: AppResult = _progression.load_chain_from(DEFAULT_CHAIN_PATH)
	assert_true(loaded.is_ok, loaded.message)
	# 冻结自迁移前探针（旧硬编码 _event_chain() 真实输出，见 ops/evidence/DLX-2.md）。
	# 矩阵 A-G 不含 approach_diplomatic → envoy 不到期 → 序列必须与旧链逐事件一致。
	var expected_sequences: Dictionary = {
		"A": "event_prologue_landing",
		"B": "event_prologue_landing,event_first_mining",
		"C": "event_prologue_landing,event_first_mining,event_drift_aftermath",
		"D": "event_prologue_landing,event_first_mining,event_drift_aftermath,event_first_anchor,event_workshop_guide,event_misa_campfire,event_dust_calamity,event_quiet_night",
		"E": "event_prologue_landing,event_first_mining,event_drift_aftermath,event_first_anchor,event_workshop_guide,event_misa_campfire,event_dust_calamity,event_quiet_night,event_pylon_hum",
		"F": "event_prologue_landing,event_first_mining,event_drift_aftermath,event_first_anchor,event_workshop_guide,event_misa_campfire,event_husk_aftermath,event_station_mode,event_echo_resonance,event_approach,event_policy,event_lumen_wildfire,event_leviathan_pact_pre,event_leviathan_pact,event_leviathan_aftermath,event_dust_calamity,event_quiet_night,event_pylon_hum,event_final_ascent,event_ending_luoxian,event_ending_misa,event_epilogue_exploited",
		"G": "event_prologue_landing,event_first_mining,event_drift_aftermath,event_first_anchor,event_workshop_guide,event_misa_campfire,event_husk_aftermath,event_station_mode,event_echo_resonance,event_approach,event_policy,event_lumen_wildfire,event_leviathan_pact_pre,event_leviathan_pact,event_leviathan_aftermath,event_dust_calamity,event_quiet_night,event_pylon_hum,event_final_ascent,event_ending_luoxian,event_ending_misa,event_epilogue_exploited,event_epilogue_sealed",
	}
	for key: String in ["A", "B", "C", "D", "E", "F", "G"]:
		assert_eq(
			",".join(_drain(_matrix_flags(key))),
			String(expected_sequences[key]),
			"矩阵 %s 的 due 序列必须与迁移前一致。" % key
		)
	# 矩阵 H（approach_diplomatic 已置）：旧系统 = DLX-1 tick 钩子先触发
	# event_envoy_trust，再走旧链（探针 H 序列）；外置后 = envoy 居链首，
	# 同一 state 的全系统触发序列必须逐事件一致。
	assert_eq(
		",".join(_drain(_matrix_flags("H"))),
		"event_envoy_trust,event_prologue_landing,event_station_mode,event_echo_resonance,event_policy,event_diplomat_envoy",
		"矩阵 H 必须复现旧钩子+旧链的全局触发序列。"
	)


# ---------------------------------------------------------------- 内部工具


func _require_progression() -> bool:
	if _progression == null:
		fail_test("Missing required implementation: %s" % PROGRESSION_SCRIPT_PATH)
		return false
	return true


func _done(event_id: String) -> String:
	return DONE_FORMAT % event_id


func _write_temp_chain(case_name: String, text: String) -> String:
	var path: String = "user://dlx2_chain_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时链文件必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


func _matrix_flags(key: String) -> Dictionary:
	var base: Dictionary = {
		"first_mining_done": true,
		"encounter_first_drift_won": true,
		"first_anchor_placed": true,
		"anchor_workshop_placed": true,
		"pylon_stabilized": true,
		"encounter_husk_ambush_won": true,
		"echo_chamber_active": true,
		"station_mode_exploit": true,
		"approach_direct": true,
		"world_response_exploited": true,
		"mine_entered": true,
		"encounter_leviathan_due": true,
		"encounter_leviathan_won": true,
	}
	var flags: Dictionary = {}
	match key:
		"A":
			pass
		"B":
			flags["first_mining_done"] = true
		"C":
			flags["first_mining_done"] = true
			flags["encounter_first_drift_won"] = true
		"D":
			flags.merge({"first_mining_done": true, "encounter_first_drift_won": true, "first_anchor_placed": true, "anchor_workshop_placed": true})
		"E":
			flags.merge({
				"first_mining_done": true, "encounter_first_drift_won": true,
				"first_anchor_placed": true, "anchor_workshop_placed": true,
				"pylon_stabilized": true,
			})
		"F", "G":
			flags.merge(base)
		"H":
			flags.merge({"approach_diplomatic": true, "diplomatic_stance": true, "echo_chamber_active": true})
	if key == "G":
		flags["station_mode_seal"] = true
	return flags


## 排干链：反复取 due 事件并标记 done，返回触发序列（上限 64 防死循环）。
func _drain(flags: Dictionary) -> Array[String]:
	var sequence: Array[String] = []
	var working: Dictionary = flags.duplicate(true)
	var guard := 0
	while guard < 64:
		guard += 1
		var event_id: String = _progression.due_event({"flags": working})
		if event_id.is_empty():
			break
		sequence.append(event_id)
		working[_done(event_id)] = true
	return sequence
