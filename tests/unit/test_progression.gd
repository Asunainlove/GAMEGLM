extends GutTest

## WP14 剧情推进与世界回应单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 契约：docs/plans/contracts/module-contracts.md §0（store 注入模式）、§5（Progression）、§7（事件链/Boss 条件/结局门控）。
## 以真实 GameState 注入为主、本地 DuckStore/DuckPatch 替身为辅；替身由测试实例字段保活，
## 否则临时 RefCounted 只传 ObjectID、记录会静默丢失。脚本运行时加载（绝不 preload），
## 缺失实现以失败断言暴露而非整包解析失败。

const PROGRESSION_SCRIPT_PATH: String = "res://src/progression/progression.gd"
const EVENT_RUNNER_SCRIPT_PATH: String = "res://src/narrative/event_runner.gd"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const BUILDINGS_JSON_PATH: String = "res://data/content/buildings.json"

## 与 EventRunner 一致的完成标记模板：完整事件 id 已带 event_ 前缀，
## 因此实际 flag 形如 event_event_prologue_landing_done（双前缀）。
const DONE_FORMAT: String = "event_%s_done"
const STATE_REVISION: int = 5

## DuckStore/DuckPatch 宿主实例字段：保活注入替身。
var _duck_store: DuckStore = null
var _duck_patch: DuckPatch = null
var _progression: Script = null


func before_all() -> void:
	_progression = load(PROGRESSION_SCRIPT_PATH)


func _require_progression() -> bool:
	if _progression == null:
		fail_test("Missing required WP14 implementation: %s" % PROGRESSION_SCRIPT_PATH)
		return false
	return true


func _fresh_game_state() -> Node:
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	return store


func _duck() -> DuckStore:
	_duck_store = DuckStore.new()
	return _duck_store


func _done_flag(event_id: String) -> String:
	return DONE_FORMAT % event_id


func _state_with(flags: Dictionary) -> Dictionary:
	return {"revision": STATE_REVISION, "flags": flags.duplicate(true)}


func _flags_of(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("flags", {}) as Dictionary


## G7P-2 M12：built 反应 payload 必须携带 building_def（唯一权威路径，生产
## GameSession 本就携带）。断言语义与迁移前一致：直接读生产 buildings.json。
func _production_building_def(building_id: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(BUILDINGS_JSON_PATH)
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.get_data()) != TYPE_ARRAY:
		fail_test("buildings.json must parse as an array.")
		return {}
	for entry_value: Variant in json.get_data():
		if typeof(entry_value) == TYPE_DICTIONARY and String((entry_value as Dictionary).get("id", "")) == building_id:
			return entry_value
	fail_test("buildings.json must define %s." % building_id)
	return {}


class DuckStore extends RefCounted:
	var last_source_id: String = ""
	var last_expected_revision: int = -1
	var operations: Array[Dictionary] = []
	var commit_calls: int = 0

	func snapshot() -> Dictionary:
		return {"revision": 9}

	func begin_patch(source_id: String, expected_revision: int) -> DuckStore:
		last_source_id = source_id
		last_expected_revision = expected_revision
		return self

	func set_flag(flag_id: String, enabled: bool) -> void:
		operations.append({"type": "set_flag", "flag_id": flag_id, "enabled": enabled})

	func commit(_patch: Object) -> AppResult:
		commit_calls += 1
		return AppResult.success({"operations": operations.duplicate(true)}, "committed")


class DuckPatch extends RefCounted:
	var calls: Array[Dictionary] = []

	func set_relationship(char_id: String, dim: String, value: int) -> void:
		calls.append({"char_id": char_id, "dim": dim, "value": value})


# ---------------------------------------------------------------- due_event


func test_due_event_empty_state_returns_prologue() -> void:
	if not _require_progression():
		return
	assert_eq(_progression.due_event({}), "event_prologue_landing")


func test_due_event_done_flag_matches_event_runner_template() -> void:
	if not _require_progression():
		return
	var runner_script: Script = load(EVENT_RUNNER_SCRIPT_PATH)
	# DLX-2 空转守卫修复：GUT 断言返回 void，`if not assert_xxx(...)` 恒真，
	# 此前的早退让后续断言从未执行；改为显式断言 + 空值早退。
	assert_not_null(runner_script)
	if runner_script == null:
		return
	var runner_constants: Dictionary = runner_script.get_script_constant_map()
	assert_eq(
		String(_progression.get_script_constant_map().get("EVENT_DONE_FLAG_FORMAT", "")),
		String(runner_constants.get("EVENT_DONE_FLAG_FORMAT", "")),
		"WP14 must reuse the EventRunner done-flag template verbatim."
	)
	# EventRunner.complete_event writes event_<完整id>_done（双前缀）；
	# 该字面 flag 置位后 prologue 必须视为已完成。
	var flagged: Dictionary = _state_with({_done_flag("event_prologue_landing"): true})
	assert_eq(_progression.due_event(flagged), "", "Literal double-prefix done flag must complete the prologue.")


func test_due_event_walks_full_chain_to_empty() -> void:
	if not _require_progression():
		return
	# W003-A1 后的 24 事件有序链：9 个内容量扩充事件按各自前置 flag 插入
	# （插入序与守卫 flag 见 ops/evidence/W003-A1.md）。链是"优先级序"而非
	# 严格序列：前置未满足者被跳过，同帧多个可跑事件取链上最前者。
	# 本走查按真实游玩时序补 flag；exploit 主线覆盖 wildfire 与 epilogue_exploited，
	# 末尾补 seal+echo 覆盖 epilogue_sealed。合法断言更新：旧 15 步走查中
	# "husk 胜利前等待"的空断言被 dust/quiet/pylon 的真实触发取代。
	var flags: Dictionary = {}

	# 1) prologue。
	assert_eq(_progression.due_event({"flags": flags}), "event_prologue_landing")
	flags[_done_flag("event_prologue_landing")] = true

	# 2) 采集 → event_first_mining；drift_aftermath 因首战未胜被跳过。
	flags["first_mining_done"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_first_mining")
	flags[_done_flag("event_first_mining")] = true

	# 3) 首战未胜 → 链等待；胜利 → event_drift_aftermath（trust +12）。
	assert_eq(_progression.due_event({"flags": flags}), "", "Without the first-drift victory the chain waits.")
	flags["encounter_first_drift_won"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_drift_aftermath")
	flags[_done_flag("event_drift_aftermath")] = true

	# 4) 首个锚块 → event_first_anchor。
	flags["first_anchor_placed"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_first_anchor")
	flags[_done_flag("event_first_anchor")] = true

	# 5) 锚居工坊 → event_workshop_guide，随后同前置的 event_misa_campfire（trust +8）。
	flags["anchor_workshop_placed"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_workshop_guide")
	flags[_done_flag("event_workshop_guide")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_misa_campfire")
	flags[_done_flag("event_misa_campfire")] = true

	# 6) W003-A1：工坊既立、campfire 完成标记（双前缀）在手 → 尘暴与静夜先行
	#    （链位在 boss 段之后，但此刻 7-16 号位均不可跑，故由它们接棒）。
	assert_eq(_progression.due_event({"flags": flags}), "event_dust_calamity")
	flags[_done_flag("event_dust_calamity")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_quiet_night")
	flags[_done_flag("event_quiet_night")] = true
	flags["pylon_stabilized"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_pylon_hum")
	flags[_done_flag("event_pylon_hum")] = true

	# 7) 碎壳伏击未胜 → 等待；胜利 → event_husk_aftermath（trust +12）。
	assert_eq(_progression.due_event({"flags": flags}), "", "Without the husk victory the chain waits.")
	flags["encounter_husk_ambush_won"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_husk_aftermath")
	flags[_done_flag("event_husk_aftermath")] = true

	# 8) 回响舱激活 → event_station_mode，随后 event_echo_resonance（trust +8）。
	flags["echo_chamber_active"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_station_mode")
	flags[_done_flag("event_station_mode")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_echo_resonance")
	flags[_done_flag("event_echo_resonance")] = true

	# 9) exploit 主线：任一 station_mode_* → event_approach；approach 选项 flag
	#    → event_policy；随后 world_response_exploited 放行 event_lumen_wildfire。
	flags["station_mode_exploit"] = true
	flags["world_response_exploited"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_approach")
	flags[_done_flag("event_approach")] = true
	flags["approach_direct"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_policy")
	flags[_done_flag("event_policy")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_lumen_wildfire")
	flags[_done_flag("event_lumen_wildfire")] = true

	# 10) W003-A1：diplomatic_stance + echo_chamber_active → event_diplomat_envoy。
	flags["diplomatic_stance"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_diplomat_envoy")
	flags[_done_flag("event_diplomat_envoy")] = true

	# 11) 进矿 + 遭遇 due flag → event_leviathan_pact_pre 先于 event_leviathan_pact。
	flags["mine_entered"] = true
	flags["encounter_leviathan_due"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_leviathan_pact_pre")
	flags[_done_flag("event_leviathan_pact_pre")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_leviathan_pact")
	flags[_done_flag("event_leviathan_pact")] = true

	# 12) Boss 未胜 → 等待；胜利 → event_leviathan_aftermath（trust +15）。
	assert_eq(_progression.due_event({"flags": flags}), "", "Without the leviathan victory the chain waits.")
	flags["encounter_leviathan_won"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_leviathan_aftermath")
	flags[_done_flag("event_leviathan_aftermath")] = true

	# 13) W003-A1：决战后 → event_final_ascent（三分支通用前奏）。
	assert_eq(_progression.due_event({"flags": flags}), "event_final_ascent")
	flags[_done_flag("event_final_ascent")] = true

	# 14) 结局就绪 → 两个结局事件。
	assert_eq(_progression.due_event({"flags": flags}), "event_ending_luoxian")
	flags[_done_flag("event_ending_luoxian")] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_ending_misa")
	flags[_done_flag("event_ending_misa")] = true

	# 15) W003-A1：终章感言按驻地基调分支——exploit + 对话路径世界回应 flag
	#     → event_epilogue_exploited；再补 seal+echo → event_epilogue_sealed。
	assert_eq(_progression.due_event({"flags": flags}), "event_epilogue_exploited")
	flags[_done_flag("event_epilogue_exploited")] = true
	flags["station_mode_seal"] = true
	assert_eq(_progression.due_event({"flags": flags}), "event_epilogue_sealed")
	flags[_done_flag("event_epilogue_sealed")] = true
	assert_eq(_progression.due_event({"flags": flags}), "", "A fully consumed chain yields an empty id.")


func test_due_event_gap5_events_stay_clear_of_frozen_integration_gate_paths() -> void:
	if not _require_progression():
		return
	# 冻结集成测试的两条 flag 集的回归语义（W003-A1 禁改
	# tests/unit/test_integration*.gd，新事件只能靠双守卫让路；DLX-2 起
	# event_envoy_trust 经外置链生效，见路径 b 的合法断言更新）：
	# a) 结局路径：全旧事件 done + exploit + 三胜，但不含对话路径 flag
	#    （world_response_exploited / echo_chamber_active / mine_entered /
	#    encounter_leviathan_due / pylon_stabilized / anchor_workshop_placed）。
	var legacy_done: Array[String] = [
		"event_prologue_landing", "event_first_mining", "event_drift_aftermath",
		"event_first_anchor", "event_workshop_guide", "event_misa_campfire",
		"event_husk_aftermath", "event_station_mode", "event_echo_resonance",
		"event_approach", "event_policy", "event_leviathan_pact",
		"event_leviathan_aftermath", "event_ending_luoxian", "event_ending_misa",
	]
	var ending_flags: Dictionary = {
		"station_mode_exploit": true,
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"encounter_leviathan_won": true,
	}
	for event_id: String in legacy_done:
		ending_flags[_done_flag(event_id)] = true
	assert_eq(
		_progression.due_event({"flags": ending_flags}), "",
		"结局门控路径不得被 W003-A1 新事件抢占。"
	)

	# b) 软锁死路径：低信任直达 policy，diplomatic_stance 与 station_mode_seal
	#    已置但 echo_chamber_active 缺席 → epilogue_sealed 等其余新事件必须让路。
	#    DLX-2 合法断言更新：event_envoy_trust（DLX-1 tick 过渡钩子事件）并入
	#    外置链后，due_event 在本 state 下返回它——旧系统全局行为一致（钩子
	#    先于 due_event 触发同一事件），仅断言从"链内不可见"改为"链首可见"。
	var softlock_flags: Dictionary = {
		"station_mode_seal": true,
		"approach_diplomatic": true,
		"diplomatic_stance": true,
		"policy_extraction_quota": true,
	}
	for event_id: String in [
		"event_prologue_landing", "event_first_mining", "event_drift_aftermath",
		"event_first_anchor", "event_workshop_guide", "event_misa_campfire",
		"event_husk_aftermath", "event_station_mode", "event_echo_resonance",
		"event_approach", "event_policy",
	]:
		softlock_flags[_done_flag(event_id)] = true
	assert_eq(
		_progression.due_event({"flags": softlock_flags}), "event_envoy_trust",
		"并入外置链的 envoy_trust 在本 state 到期（旧钩子同帧会先触发它）；其余新事件必须让路。"
	)


func test_event_chain_ids_all_exist_in_event_pack() -> void:
	if not _require_progression():
		return
	# 链-包一致性：due_event 链引用的每个事件 id 都必须有 data/events/*.json
	# 定义（EventRunner 装载失败或文件缺失都会让 GameSession 推进死等）。
	var runner: RefCounted = load(EVENT_RUNNER_SCRIPT_PATH).new()
	var loaded: AppResult = runner.load_events_from("res://data/events")
	# DLX-2 空转守卫修复：同上，`if not assert_true(...)` 恒真导致本测试此前
	# 只执行了一条断言；链-包一致性检查现在真正运行。
	assert_true(loaded.is_ok, loaded.message)
	if not loaded.is_ok:
		return
	var packed_ids: Dictionary = {}
	for event_def: Dictionary in (loaded.value as Array):
		packed_ids[String(event_def["id"])] = true
	for entry: Dictionary in _progression._event_chain():
		assert_true(
			packed_ids.has(String(entry["id"])),
			"due_event 链上的 %s 必须有 data/events 事件定义。" % String(entry["id"])
		)


func test_due_event_bond_events_gate_on_their_own_victory_flags() -> void:
	if not _require_progression():
		return
	# 羁绊事件未满足自己的前置 flag 时必须被跳过，既不阻塞链也不抢先触发：
	# 首战/伏击均未胜，但建造链前置齐全 → 链上第一个可跑者是 workshop_guide。
	var flags: Dictionary = {
		_done_flag("event_prologue_landing"): true,
		_done_flag("event_first_mining"): true,
		_done_flag("event_first_anchor"): true,
		"anchor_workshop_placed": true,
		"echo_chamber_active": true,
	}
	assert_eq(
		_progression.due_event({"flags": flags}), "event_workshop_guide",
		"Unmet bond-event flags must be skipped in chain order."
	)


func test_due_event_drift_aftermath_unblocks_exactly_on_victory_flag() -> void:
	if not _require_progression():
		return
	var flags: Dictionary = {
		_done_flag("event_prologue_landing"): true,
		_done_flag("event_first_mining"): true,
	}
	assert_eq(_progression.due_event({"flags": flags}), "", "The chain waits before the first-drift victory.")
	flags["encounter_first_drift_won"] = true
	assert_eq(
		_progression.due_event({"flags": flags}), "event_drift_aftermath",
		"The drift aftermath unblocks exactly when its victory flag is set."
	)


func test_due_event_skips_events_with_unsatisfied_prerequisites() -> void:
	if not _require_progression():
		return
	# 采矿/锚块/工坊前置不满足，但回响舱已激活 → 直接跳到 event_station_mode。
	var flags: Dictionary = {
		_done_flag("event_prologue_landing"): true,
		"echo_chamber_active": true,
	}
	assert_eq(_progression.due_event({"flags": flags}), "event_station_mode")


func test_due_event_ignores_done_flags_explicitly_false() -> void:
	if not _require_progression():
		return
	var flags: Dictionary = {_done_flag("event_prologue_landing"): false}
	assert_eq(_progression.due_event({"flags": flags}), "event_prologue_landing")


# ---------------------------------------------------------------- react: mined


func test_react_mined_sets_first_mining_done_once_with_real_game_state() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var result: AppResult = _progression.react(state, "mined", {}, store)
	assert_true(result.is_ok, result.message)
	var committed: Dictionary = store.snapshot()
	assert_true(
		bool(_flags_of(committed).get("first_mining_done", false)),
		"mined must set the one-time first_mining_done flag."
	)
	assert_eq(int(committed["revision"]), int(state["revision"]) + 1)

	# 刷新快照后的第二次 mined：成功跳过、不再有 patch。
	var second: AppResult = _progression.react(store.snapshot(), "mined", {}, store)
	assert_true(second.is_ok, second.message)
	assert_eq(int(store.snapshot()["revision"]), int(state["revision"]) + 1, "Repeat mined must not commit again.")


func test_react_mined_uses_progression_source_id_and_skips_when_flag_set() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var result: AppResult = _progression.react(_state_with({}), "mined", {}, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.last_source_id, "progression_mined_%d" % STATE_REVISION)
	assert_eq(duck.last_expected_revision, STATE_REVISION)
	assert_eq(duck.commit_calls, 1)
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "first_mining_done", "enabled": true},
	] as Array[Dictionary])

	var skip_duck := _duck()
	var skip_result: AppResult = _progression.react(
		_state_with({"first_mining_done": true}), "mined", {}, skip_duck)
	assert_true(skip_result.is_ok, skip_result.message)
	assert_eq(skip_duck.commit_calls, 0, "Already-set one-time flag must skip without any patch.")
	assert_eq(skip_duck.operations, [] as Array[Dictionary])
	assert_eq(skip_duck.last_source_id, "", "Skipped reaction must not begin a patch.")


# ---------------------------------------------------------------- react: built


func test_react_built_anchor_block_sets_first_anchor_flag() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var result: AppResult = _progression.react(
		store.snapshot(), "built",
		{"building_id": "anchor_block", "building_def": _production_building_def("anchor_block")},
		store)
	assert_true(result.is_ok, result.message)
	assert_true(bool(_flags_of(store.snapshot()).get("first_anchor_placed", false)))


func test_react_built_anchor_workshop_sets_workshop_flag() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var result: AppResult = _progression.react(
		store.snapshot(), "built",
		{"building_id": "anchor_workshop", "building_def": _production_building_def("anchor_workshop")},
		store)
	assert_true(result.is_ok, result.message)
	assert_true(bool(_flags_of(store.snapshot()).get("anchor_workshop_placed", false)))


func test_react_built_pylon_effect_flag_depends_on_powered() -> void:
	if not _require_progression():
		return
	# 供电成功 → effect_flag 置位。
	var store: Node = _fresh_game_state()
	var powered: AppResult = _progression.react(
		store.snapshot(), "built",
		{
			"building_id": "stabilizer_pylon",
			"powered": true,
			"building_def": _production_building_def("stabilizer_pylon"),
		},
		store)
	assert_true(powered.is_ok, powered.message)
	assert_true(bool(_flags_of(store.snapshot()).get("pylon_stabilized", false)))

	# 未供电 → 成功但不置 effect_flag、零写入。
	var unpowered_duck := _duck()
	var unpowered: AppResult = _progression.react(
		_state_with({}), "built",
		{
			"building_id": "stabilizer_pylon",
			"powered": false,
			"building_def": _production_building_def("stabilizer_pylon"),
		},
		unpowered_duck)
	assert_true(unpowered.is_ok, unpowered.message)
	assert_eq(unpowered_duck.commit_calls, 0, "Unpowered effect building must not commit a patch.")
	assert_eq(unpowered_duck.operations, [] as Array[Dictionary])

	# powered 缺省为 true。
	var default_duck := _duck()
	var defaulted: AppResult = _progression.react(
		_state_with({}), "built",
		{
			"building_id": "stabilizer_pylon",
			"building_def": _production_building_def("stabilizer_pylon"),
		},
		default_duck)
	assert_true(defaulted.is_ok, defaulted.message)
	assert_eq(default_duck.operations, [
		{"type": "set_flag", "flag_id": "pylon_stabilized", "enabled": true},
	] as Array[Dictionary])


func test_react_built_echo_chamber_effect_flag_depends_on_powered() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var powered: AppResult = _progression.react(
		store.snapshot(), "built",
		{
			"building_id": "echo_chamber",
			"powered": true,
			"building_def": _production_building_def("echo_chamber"),
		},
		store)
	assert_true(powered.is_ok, powered.message)
	assert_true(bool(_flags_of(store.snapshot()).get("echo_chamber_active", false)))

	var unpowered_duck := _duck()
	var unpowered: AppResult = _progression.react(
		_state_with({}), "built",
		{
			"building_id": "echo_chamber",
			"powered": false,
			"building_def": _production_building_def("echo_chamber"),
		},
		unpowered_duck)
	assert_true(unpowered.is_ok, unpowered.message)
	assert_eq(unpowered_duck.commit_calls, 0)
	assert_eq(unpowered_duck.operations, [] as Array[Dictionary])


func test_react_built_unrelated_building_is_no_op_success() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var result: AppResult = _progression.react(_state_with({}), "built", {"building_id": "dust_refiner"}, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 0, "Buildings without progression effects must not commit.")
	assert_eq(duck.operations, [] as Array[Dictionary])


func test_react_built_rejects_invalid_building_id() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var missing: AppResult = _progression.react(_state_with({}), "built", {}, duck)
	assert_false(missing.is_ok, "built without building_id must fail validation.")
	assert_eq(missing.code, "invalid_building_id")
	var malformed: AppResult = _progression.react(
		_state_with({}), "built", {"building_id": "Anchor Block"}, duck)
	assert_false(malformed.is_ok, "Non snake_case building_id must fail validation.")
	assert_eq(duck.commit_calls, 0, "Validation failure must leave zero writes.")


# ---------------------------------------------------------------- react: event_completed


func test_react_event_completed_validates_event_id_without_writes() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var valid: AppResult = _progression.react(
		_state_with({_done_flag("event_prologue_landing"): true}),
		"event_completed",
		{"event_id": "event_prologue_landing"},
		duck
	)
	assert_true(valid.is_ok, valid.message)
	assert_eq(duck.commit_calls, 0, "EventRunner already wrote the done flag; Progression writes nothing.")
	assert_eq(duck.operations, [] as Array[Dictionary])

	var missing: AppResult = _progression.react(_state_with({}), "event_completed", {}, duck)
	assert_false(missing.is_ok, "event_completed without event_id must fail validation.")
	assert_eq(missing.code, "invalid_event_id")

	var malformed: AppResult = _progression.react(
		_state_with({}), "event_completed", {"event_id": "event_bad id"}, duck)
	assert_false(malformed.is_ok, "Non stable event_id must fail validation.")
	assert_eq(duck.commit_calls, 0, "Validation failure must leave zero writes.")


# ---------------------------------------------------------------- react: encounter_won / policy_chosen


func test_react_encounter_won_requires_both_victories_and_policy() -> void:
	if not _require_progression():
		return
	# 缺一场胜利 → 不置。
	var one_win_duck := _duck()
	var one_win: AppResult = _progression.react(
		_state_with({"encounter_first_drift_won": true, "policy_extraction_quota": true}),
		"encounter_won",
		{"encounter_id": "encounter_husk_ambush"},
		one_win_duck
	)
	assert_true(one_win.is_ok, one_win.message)
	assert_eq(one_win_duck.commit_calls, 0, "Missing one of the first two victories must not set the due flag.")

	# 两场齐但缺 policy → 不置。
	var no_policy_duck := _duck()
	var no_policy: AppResult = _progression.react(
		_state_with({"encounter_first_drift_won": true, "encounter_husk_ambush_won": true}),
		"encounter_won",
		{"encounter_id": "encounter_first_drift"},
		no_policy_duck
	)
	assert_true(no_policy.is_ok, no_policy.message)
	assert_eq(no_policy_duck.commit_calls, 0, "Missing any policy_* flag must not set the due flag.")

	# due flag 已置 → 幂等跳过。
	var due_duck := _duck()
	var due: AppResult = _progression.react(
		_state_with({"encounter_leviathan_due": true}),
		"encounter_won",
		{"encounter_id": "encounter_leviathan"},
		due_duck
	)
	assert_true(due.is_ok, due.message)
	assert_eq(due_duck.commit_calls, 0, "Already-due leviathan must skip without any patch.")


func test_react_encounter_won_sets_leviathan_due_when_conditions_met() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var seed_patch: StatePatch = store.begin_patch("wp14_seed_encounter_conditions", 0)
	seed_patch.set_flag("encounter_first_drift_won", true)
	seed_patch.set_flag("encounter_husk_ambush_won", true)
	seed_patch.set_flag("policy_extraction_quota", true)
	assert_true(store.commit(seed_patch).is_ok)

	var state: Dictionary = store.snapshot()
	var result: AppResult = _progression.react(
		state, "encounter_won", {"encounter_id": "encounter_husk_ambush"}, store)
	assert_true(result.is_ok, result.message)
	assert_true(
		bool(_flags_of(store.snapshot()).get("encounter_leviathan_due", false)),
		"Both victories plus a policy choice must set encounter_leviathan_due."
	)
	assert_eq(int(store.snapshot()["revision"]), int(state["revision"]) + 1)

	# 刷新快照后的重复信号：幂等跳过。
	var second: AppResult = _progression.react(
		store.snapshot(), "encounter_won", {"encounter_id": "encounter_husk_ambush"}, store)
	assert_true(second.is_ok, second.message)
	assert_eq(int(store.snapshot()["revision"]), int(state["revision"]) + 1)


func test_react_policy_chosen_sets_leviathan_due_when_conditions_met() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var seed_patch: StatePatch = store.begin_patch("wp14_seed_policy_conditions", 0)
	seed_patch.set_flag("encounter_first_drift_won", true)
	seed_patch.set_flag("encounter_husk_ambush_won", true)
	assert_true(store.commit(seed_patch).is_ok)

	# 政策选择提交后的快照含 policy flag → 触发 due flag。
	var choice_patch: StatePatch = store.begin_patch("wp14_seed_policy_choice", 1)
	choice_patch.set_flag("policy_sanctuary", true)
	assert_true(store.commit(choice_patch).is_ok)

	var state: Dictionary = store.snapshot()
	var result: AppResult = _progression.react(
		state, "policy_chosen", {"policy_id": "policy_sanctuary"}, store)
	assert_true(result.is_ok, result.message)
	assert_true(
		bool(_flags_of(store.snapshot()).get("encounter_leviathan_due", false)),
		"policy_chosen with both victories must set encounter_leviathan_due."
	)


func test_react_policy_chosen_requires_both_victories() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var result: AppResult = _progression.react(
		_state_with({"policy_extraction_quota": true, "encounter_first_drift_won": true}),
		"policy_chosen",
		{"policy_id": "policy_extraction_quota"},
		duck
	)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 0, "Missing one of the first two victories must not set the due flag.")

	var malformed: AppResult = _progression.react(_state_with({}), "policy_chosen", {}, duck)
	assert_false(malformed.is_ok, "policy_chosen without policy_id must fail validation.")
	assert_eq(malformed.code, "invalid_policy_id")


# ---------------------------------------------------------------- react: 未知信号与默认 store


func test_react_unknown_signal_fails_without_writes() -> void:
	if not _require_progression():
		return
	var duck := _duck()
	var result: AppResult = _progression.react(_state_with({}), "something_else", {}, duck)
	assert_false(result.is_ok, "Unknown signals must fail.")
	assert_eq(result.code, "unknown_signal")
	assert_eq(duck.commit_calls, 0, "Unknown signals must leave zero writes.")
	assert_eq(duck.operations, [] as Array[Dictionary])


func test_react_defaults_to_game_state_autoload_when_store_null() -> void:
	if not _require_progression():
		return
	# 共享 autoload 上的探测 flag 先清理干净。
	var before: Dictionary = GameState.snapshot()
	if bool(_flags_of(before).get("first_mining_done", false)):
		var reset: StatePatch = GameState.begin_patch("wp14_null_store_probe_reset", int(before["revision"]))
		reset.set_flag("first_mining_done", false)
		assert_true(GameState.commit(reset).is_ok)

	var state: Dictionary = _state_with({})
	state["revision"] = int(GameState.snapshot()["revision"])
	var result: AppResult = _progression.react(state, "mined", {})
	assert_true(result.is_ok, result.message)
	var committed: Dictionary = GameState.snapshot()
	assert_true(
		bool(_flags_of(committed).get("first_mining_done", false)),
		"Null store must fall back to the GameState autoload."
	)
	var cleanup: StatePatch = GameState.begin_patch("wp14_null_store_probe_cleanup", int(committed["revision"]))
	cleanup.set_flag("first_mining_done", false)
	assert_true(GameState.commit(cleanup).is_ok)


# ---------------------------------------------------------------- world_response_ops


func test_world_response_ops_maps_known_triggers() -> void:
	if not _require_progression():
		return
	assert_eq(_progression.world_response_ops({}, "station_mode_exploit"), [
		{"op": "set_flag", "flag_id": "world_response_exploited", "enabled": true},
	] as Array[Dictionary])
	assert_eq(_progression.world_response_ops({}, "policy_extraction_quota"), [
		{"op": "set_flag", "flag_id": "boss_condition_escalated", "enabled": true},
	] as Array[Dictionary])
	assert_eq(_progression.world_response_ops({}, "approach_diplomatic"), [
		{"op": "set_flag", "flag_id": "diplomatic_stance", "enabled": true},
	] as Array[Dictionary])


func test_world_response_ops_unknown_trigger_returns_empty() -> void:
	if not _require_progression():
		return
	assert_eq(_progression.world_response_ops({}, "station_mode_seal"), [] as Array[Dictionary])
	assert_eq(_progression.world_response_ops({}, "approach_direct"), [] as Array[Dictionary])
	assert_eq(_progression.world_response_ops({}, ""), [] as Array[Dictionary])


# ---------------------------------------------------------------- boss_hp_multiplier


func test_boss_hp_multiplier_escalates_only_with_escalated_flag() -> void:
	if not _require_progression():
		return
	assert_eq(_progression.boss_hp_multiplier({}), 1.0)
	assert_eq(_progression.boss_hp_multiplier({"flags": {}}), 1.0)
	assert_eq(_progression.boss_hp_multiplier({"flags": {"boss_condition_escalated": false}}), 1.0)
	assert_eq(
		_progression.boss_hp_multiplier({"flags": {"boss_condition_escalated": true}}),
		1.2,
		"The escalated boss condition must raise HP to 1.2x."
	)


# ---------------------------------------------------------------- ending_ready


func test_ending_ready_requires_station_mode_and_all_three_victories() -> void:
	if not _require_progression():
		return
	var victories: Dictionary = {
		"encounter_first_drift_won": true,
		"encounter_husk_ambush_won": true,
		"encounter_leviathan_won": true,
	}
	assert_false(_progression.ending_ready({}), "Empty state is never ending-ready.")
	assert_false(_progression.ending_ready({"flags": {}}))
	assert_false(
		_progression.ending_ready({"flags": {"station_mode_symbiosis": true}}),
		"Station mode alone is not enough."
	)
	assert_false(
		_progression.ending_ready({"flags": victories.duplicate()}),
		"Three victories without any station mode are not enough."
	)

	var missing_husk: Dictionary = victories.duplicate()
	missing_husk["encounter_husk_ambush_won"] = false
	missing_husk["station_mode_exploit"] = true
	assert_false(
		_progression.ending_ready({"flags": missing_husk}),
		"Missing any single victory blocks the ending."
	)

	var full: Dictionary = victories.duplicate()
	full["station_mode_exploit"] = true
	assert_true(_progression.ending_ready({"flags": full}))
	var symbiosis: Dictionary = victories.duplicate()
	symbiosis["station_mode_symbiosis"] = true
	assert_true(_progression.ending_ready({"flags": symbiosis}))


# ---------------------------------------------------------------- deferred_to_patch


func test_deferred_to_patch_forwards_each_relationship_op_in_order() -> void:
	if not _require_progression():
		return
	_duck_patch = DuckPatch.new()
	var ops: Array = [
		{"op": "set_relationship", "char_id": "misa", "dim": "trust", "value": 55},
		{"op": "set_relationship", "char_id": "luoxian", "dim": "affection", "value": 20},
	]
	_progression.deferred_to_patch(ops, _duck_patch)
	assert_eq(_duck_patch.calls, [
		{"char_id": "misa", "dim": "trust", "value": 55},
		{"char_id": "luoxian", "dim": "affection", "value": 20},
	] as Array[Dictionary], "Each deferred op must map to one set_relationship call in order.")


func test_deferred_to_patch_empty_ops_makes_no_calls() -> void:
	if not _require_progression():
		return
	_duck_patch = DuckPatch.new()
	_progression.deferred_to_patch([], _duck_patch)
	assert_eq(_duck_patch.calls, [] as Array[Dictionary])


func test_deferred_to_patch_applies_relationships_via_real_state_patch() -> void:
	if not _require_progression():
		return
	var store: Node = _fresh_game_state()
	var ops: Array = [
		{"op": "set_relationship", "char_id": "misa", "dim": "trust", "value": 55},
		{"op": "set_relationship", "char_id": "luoxian", "dim": "affection", "value": 20},
		{"op": "set_relationship", "char_id": "luoxian", "dim": "ideology", "value": 120},
	]
	var patch: StatePatch = store.begin_patch("wp14_deferred_bridge_probe", 0)
	_progression.deferred_to_patch(ops, patch)
	var commit: AppResult = store.commit(patch)
	assert_true(commit.is_ok, commit.message)
	var relationships: Dictionary = store.snapshot()["relationships"] as Dictionary
	assert_eq(int((relationships["misa"] as Dictionary)["trust"]), 55)
	assert_eq(int((relationships["luoxian"] as Dictionary)["affection"]), 20)
	assert_eq(
		int((relationships["luoxian"] as Dictionary)["ideology"]), 100,
		"GameState clamps relationship values to 0..100."
	)


func test_deferred_to_patch_consumes_event_runner_deferred_ops_shape() -> void:
	if not _require_progression():
		return
	var runner_script: Script = load(EVENT_RUNNER_SCRIPT_PATH)
	# DLX-2 空转守卫修复：同上，`if not assert_not_null(...)` 恒真导致桥接断言
	# 从未执行；改为显式断言 + 空值早退。
	assert_not_null(runner_script)
	if runner_script == null:
		return
	var runner: RefCounted = runner_script.new()
	var step: Dictionary = {
		"type": "choice",
		"choice_id": "wp14_bridge_choice",
		"prompt_zh": "桥接测试：如何回应弥砂？",
		"options": [
			{
				"id": "wp14_bridge_option",
				"text_zh": "提高信任。",
				"relation_delta": {"char_id": "misa", "dim": "trust", "delta": 30},
			},
		],
	}
	var event_def: Dictionary = {"id": "event_wp14_bridge", "kind": "choice", "steps": [step]}
	var state: Dictionary = {
		"revision": 1,
		"flags": {},
		"relationships": {"misa": {"trust": 10}},
		"completed_events": [],
	}
	var duck := _duck()
	var chosen: AppResult = runner.call(
		"choose_option", state, event_def, step, {"id": "wp14_bridge_option"}, duck)
	assert_true(chosen.is_ok, chosen.message)
	var ops: Array = (chosen.value as Dictionary).get("deferred_ops", [])
	assert_eq(ops.size(), 1, "The relation_delta must surface as exactly one deferred op.")

	var store: Node = _fresh_game_state()
	var patch: StatePatch = store.begin_patch("wp14_bridge_event_runner_probe", 0)
	_progression.deferred_to_patch(ops, patch)
	var commit: AppResult = store.commit(patch)
	assert_true(commit.is_ok, commit.message)
	var relationships: Dictionary = store.snapshot()["relationships"] as Dictionary
	assert_eq(
		int((relationships["misa"] as Dictionary)["trust"]), 40,
		"The bridge must apply EventRunner's deferred op onto a real StatePatch."
	)
