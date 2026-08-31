extends GutTest

## WP08 EventRunner contract tests (see docs/plans/contracts/module-contracts.md §5).
## Fixtures are built in code or written to user:// temporary directories;
## narrative event content under data/events belongs to WP12, not WP08.
## Scripts are loaded at runtime (never preloaded) so that a missing
## implementation surfaces as a failing assertion instead of a silent skip.

const EVENT_RUNNER_PATH: String = "res://src/narrative/event_runner.gd"
const TEMP_ROOT: String = "user://wp08_event_fixtures"

## DuckPatch store double per contract §0: records operation dictionaries and
## simulates commit semantics without touching real persistent state. The
## instance is held in an instance field (not a temporary) because only the
## ObjectID travels through injected calls; temporary RefCounted doubles would
## be released immediately and the recording would silently stop.
var _duck: DuckStore = null


class DuckStore extends RefCounted:
	var last_source_id: String = ""
	var last_expected_revision: int = -1
	var operations: Array[Dictionary] = []
	var commit_calls: int = 0
	## 快照替身：默认只带 revision；effect 步 relation_delta 的 clamp 计算会
	## 读取其中的 relationships，测试按需覆写。
	var snapshot_state: Dictionary = {"revision": 7}

	func snapshot() -> Dictionary:
		return snapshot_state

	func begin_patch(source_id: String, expected_revision: int) -> DuckStore:
		last_source_id = source_id
		last_expected_revision = expected_revision
		return self

	func set_flag(flag_id: String, enabled: bool) -> void:
		operations.append({"type": "set_flag", "flag_id": flag_id, "enabled": enabled})

	func add_item(item_id: String, amount: int) -> void:
		operations.append({"type": "add_item", "item_id": item_id, "amount": amount})

	func remove_item(item_id: String, amount: int) -> void:
		operations.append({"type": "remove_item", "item_id": item_id, "amount": amount})

	func commit(_patch: Object) -> AppResult:
		commit_calls += 1
		return AppResult.success({"operations": operations.duplicate(true)}, "committed")


func _duck_store() -> DuckStore:
	_duck = DuckStore.new()
	return _duck


func _new_runner() -> RefCounted:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return null
	var runner: RefCounted = script.new()
	assert_not_null(runner, "EventRunner must be instantiable as pure logic.")
	return runner


func _event_touchdown() -> Dictionary:
	return {
		"id": "event_test_touchdown",
		"kind": "dialogue",
		"steps": [
			{"type": "line", "speaker": "洛弦", "text_zh": "降落舱的铰链发出轻响，星壤的风裹着尘粒扑面而来。"},
			{"type": "line", "speaker": "弥砂", "text_zh": "信号源在矿脉深处，我们得赶在余辉熄灭前抵达。"},
		],
	}


func _event_relay_choice() -> Dictionary:
	return {
		"id": "event_test_relay_choice",
		"kind": "choice",
		"requires_flag": "event_test_touchdown_done",
		"steps": [
			{
				"type": "choice",
				"choice_id": "test_relay_core",
				"prompt_zh": "中继器的能量核心开始过载，如何处置？",
				"options": [
					{"id": "test_seal_core", "text_zh": "封存核心，保全矿脉余辉。", "set_flag": "test_core_sealed"},
					{
						"id": "test_tap_core",
						"text_zh": "抽取能量维持营地运转。",
						"set_flag": "test_core_tapped",
						"requires_trust": 40,
					},
				],
			},
		],
	}


func _base_state() -> Dictionary:
	return {
		"revision": 4,
		"flags": {},
		"relationships": {},
		"completed_events": [],
	}


func _write_fixture(dir_name: String, file_name: String, content: String) -> void:
	var dir_path: String = TEMP_ROOT + "/" + dir_name
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file: FileAccess = FileAccess.open(dir_path + "/" + file_name, FileAccess.WRITE)
	assert_not_null(file, "Fixture file %s must be writable." % file_name)
	if file != null:
		file.store_string(content)
		file.close()


func _write_event_fixture(dir_name: String, file_name: String, event_def: Dictionary) -> void:
	_write_fixture(dir_name, file_name, JSON.stringify(event_def, "  "))


func after_all() -> void:
	_remove_dir_recursive(TEMP_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child_path: String = path + "/" + entry
		if dir.current_is_dir():
			_remove_dir_recursive(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- load_events_from


func test_load_events_from_missing_directory_succeeds_with_empty_events() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var result: AppResult = runner.call("load_events_from", TEMP_ROOT + "/never_created")
	assert_true(result.is_ok, "A missing event directory must succeed with no events.")
	assert_eq(result.value, [] as Array[Dictionary], "Missing directory yields an empty event list.")


func test_load_events_from_parses_valid_events_and_ignores_non_json_files() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	_write_event_fixture("valid", "a_touchdown.json", _event_touchdown())
	_write_event_fixture("valid", "b_relay_choice.json", _event_relay_choice())
	_write_fixture("valid", "notes.txt", "非 JSON 文件必须被忽略")

	var result: AppResult = runner.call("load_events_from", TEMP_ROOT + "/valid")
	assert_true(result.is_ok, result.message)
	var events: Array = result.value
	assert_eq(events.size(), 2, "Exactly the two JSON event files are loaded.")
	for event_def: Dictionary in events:
		assert_true(event_def is Dictionary, "Loaded events must be dictionaries.")
	assert_eq(String(events[0]["id"]), "event_test_touchdown", "Files load in sorted name order.")
	assert_eq(String(events[1]["id"]), "event_test_relay_choice")
	assert_eq(String(events[0]["steps"][0]["speaker"]), "洛弦")


func test_load_events_from_fails_on_malformed_json_and_names_the_file() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	_write_fixture("broken_json", "broken.json", '{"id": "event_test_broken",')
	var result: AppResult = runner.call("load_events_from", TEMP_ROOT + "/broken_json")
	assert_false(result.is_ok, "Malformed JSON must fail.")
	assert_eq(result.code, "invalid_event_file")
	assert_true(result.message.contains("broken.json"), "Failure must name the offending file.")


func test_load_events_from_fails_on_missing_required_fields() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	_write_fixture(
		"missing_kind",
		"missing.json",
		JSON.stringify({"id": "event_test_missing_kind", "steps": [{"type": "line", "speaker": "洛弦", "text_zh": "……"}]}, "  ")
	)
	var result: AppResult = runner.call("load_events_from", TEMP_ROOT + "/missing_kind")
	assert_false(result.is_ok, "An event without kind must fail minimal validation.")
	assert_eq(result.code, "invalid_event_file")


func test_load_events_from_fails_on_unknown_step_type() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	_write_event_fixture("bad_step", "bad_step.json", {
		"id": "event_test_bad_step",
		"kind": "dialogue",
		"steps": [{"type": "song", "speaker": "洛弦", "text_zh": "……"}],
	})
	var result: AppResult = runner.call("load_events_from", TEMP_ROOT + "/bad_step")
	assert_false(result.is_ok, "step.type outside line/choice/effect must fail.")
	assert_eq(result.code, "invalid_event_file")
	assert_true(result.message.contains("bad_step.json"))


# ---------------------------------------------------------------- available_events


func test_available_events_filters_by_requires_flag_gate() -> void:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	if not assert_not_null(script):
		return
	var events: Array = [_event_touchdown(), _event_relay_choice()]

	var closed_state: Dictionary = _base_state()
	closed_state["flags"] = {"event_test_touchdown_done": false}
	var closed: Array = script.call("available_events", events, closed_state)
	assert_does_not_have(closed, "event_test_relay_choice", "Flag-gated event stays hidden while flag is false.")
	assert_has(closed, "event_test_touchdown", "Events without requires_flag stay available.")

	var open_state: Dictionary = _base_state()
	open_state["flags"] = {"event_test_touchdown_done": true}
	var open: Array = script.call("available_events", events, open_state)
	assert_has(open, "event_test_relay_choice", "Flag-gated event unlocks once the flag is true.")


func test_available_events_excludes_finished_once_events() -> void:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	if not assert_not_null(script):
		return
	var events: Array = [_event_touchdown()]
	var once_false: Dictionary = _event_touchdown()
	once_false["once"] = false
	events.append(once_false)

	var completed_state: Dictionary = _base_state()
	completed_state["completed_events"] = ["event_test_touchdown"]
	var completed_result: Array = script.call("available_events", events, completed_state)
	assert_does_not_have(completed_result, "event_test_touchdown", "Once events hide after completed_events entry.")
	assert_has(completed_result, "event_test_touchdown", "once=false events ignore completion records.")

	var flagged_state: Dictionary = _base_state()
	flagged_state["flags"] = {"event_test_touchdown_done": true}
	var flagged_result: Array = script.call("available_events", events, flagged_state)
	assert_does_not_have(flagged_result, "event_test_touchdown", "Once events hide after their done flag.")
	assert_has(flagged_result, "event_test_touchdown", "once=false events ignore the done flag.")


# ---------------------------------------------------------------- next_step


func test_next_step_returns_requested_step_or_empty_for_invalid_index() -> void:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	if not assert_not_null(script):
		return
	var event_def: Dictionary = _event_touchdown()

	var first: Dictionary = script.call("next_step", event_def, 0)
	assert_eq(String(first.get("speaker")), "洛弦")
	var second: Dictionary = script.call("next_step", event_def, 1)
	assert_eq(String(second.get("speaker")), "弥砂")
	assert_eq(script.call("next_step", event_def, 2), {}, "Out-of-range index yields {}.")
	assert_eq(script.call("next_step", event_def, -1), {}, "Negative index yields {}.")


# ---------------------------------------------------------------- choose_option


func _choice_step() -> Dictionary:
	return _event_relay_choice()["steps"][0]


func test_choose_option_sets_flag_through_injected_store() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var state: Dictionary = _base_state()
	var step: Dictionary = _choice_step()
	var option: Dictionary = {"id": "test_seal_core", "text_zh": "封存核心。", "set_flag": "test_core_sealed"}

	var result: AppResult = runner.call("choose_option", state, _event_relay_choice(), step, option, duck)
	assert_true(result.is_ok, result.message)
	# Contract §5 literal format: source_id = "event_" + event_id + "_choice";
	# event ids already carry the "event_" prefix, so the derived ids repeat it.
	assert_eq(duck.last_source_id, "event_event_test_relay_choice_choice")
	assert_eq(duck.last_expected_revision, 4, "expected_revision must come from state.revision.")
	assert_eq(duck.commit_calls, 1, "One patch per choice.")
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "test_core_sealed", "enabled": true},
	] as Array[Dictionary])
	var value: Dictionary = result.value
	assert_eq(value.get("deferred_ops", []), [] as Array[Dictionary], "No relation delta means no deferred ops.")


func test_choose_option_fails_when_trust_insufficient_with_zero_writes() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var state: Dictionary = _base_state()
	state["relationships"] = {"luoxian": {"trust": 10}}
	var step: Dictionary = _choice_step()
	var option: Dictionary = {"id": "test_tap_core", "text_zh": "抽取能量。", "requires_trust": 40}

	var result: AppResult = runner.call("choose_option", state, _event_relay_choice(), step, option, duck)
	assert_false(result.is_ok, "Insufficient trust must block the option.")
	assert_eq(result.code, "trust_insufficient")
	assert_eq(duck.last_source_id, "", "No patch may be started on failure.")
	assert_eq(duck.operations, [] as Array[Dictionary], "Failure must leave zero writes.")


func test_choose_option_allows_option_when_trust_meets_requirement() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var state: Dictionary = _base_state()
	state["relationships"] = {"luoxian": {"trust": 40}}
	var step: Dictionary = _choice_step()
	var option: Dictionary = {"id": "test_tap_core", "text_zh": "抽取能量。", "set_flag": "test_core_tapped", "requires_trust": 40}

	var result: AppResult = runner.call("choose_option", state, _event_relay_choice(), step, option, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "test_core_tapped", "enabled": true},
	] as Array[Dictionary])


func test_choose_option_defers_relation_delta_with_clamping() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var state: Dictionary = _base_state()
	state["relationships"] = {"misa": {"trust": 80}}
	# The option definition inside step.options is authoritative; the passed
	# option only selects it by id.
	var delta_step: Dictionary = {
		"type": "choice",
		"choice_id": "test_delta_core",
		"prompt_zh": "面对弥砂的迟疑，如何回应？",
		"options": [
			{
				"id": "test_high_delta",
				"text_zh": "热忱回应她的迟疑。",
				"relation_delta": {"char_id": "misa", "dim": "trust", "delta": 150},
			},
			{
				"id": "test_low_delta",
				"text_zh": "沉默地保持距离。",
				"relation_delta": {"char_id": "misa", "dim": "trust", "delta": -150},
			},
		],
	}

	var result: AppResult = runner.call(
		"choose_option", state, _event_relay_choice(), delta_step, {"id": "test_high_delta"}, duck
	)
	assert_true(result.is_ok, result.message)
	var value: Dictionary = result.value
	var deferred_ops: Array = value.get("deferred_ops", [])
	assert_eq(deferred_ops.size(), 1, "relation_delta becomes exactly one deferred op.")
	if deferred_ops.size() == 1:
		assert_eq(deferred_ops[0], {
			"op": "set_relationship",
			"char_id": "misa",
			"dim": "trust",
			"value": 100,
		}, "80 + 150 clamps to 100 in the deferred op.")
	assert_eq(duck.operations, [] as Array[Dictionary], "relation_delta is never applied directly by WP08.")
	assert_eq(duck.commit_calls, 0, "No direct patch is committed for a delta-only option.")

	var low_result: AppResult = runner.call(
		"choose_option", state, _event_relay_choice(), delta_step, {"id": "test_low_delta"}, duck
	)
	assert_true(low_result.is_ok, low_result.message)
	var low_value: Dictionary = low_result.value
	var low_ops: Array = low_value.get("deferred_ops", [])
	assert_eq(low_ops.size(), 1)
	if low_ops.size() == 1:
		assert_eq(low_ops[0]["value"], 0, "80 - 150 clamps to 0 in the deferred op.")


func test_choose_option_rejects_option_outside_step_with_zero_writes() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var step: Dictionary = _choice_step()
	var foreign_option: Dictionary = {"id": "test_unknown_option", "text_zh": "不属于本步骤。", "set_flag": "test_must_not_apply"}

	var result: AppResult = runner.call("choose_option", _base_state(), _event_relay_choice(), step, foreign_option, duck)
	assert_false(result.is_ok, "An option outside step.options must be rejected.")
	assert_eq(duck.operations, [] as Array[Dictionary], "Rejection must leave zero writes.")


func test_choose_option_rejects_non_choice_step() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var line_step: Dictionary = {"type": "line", "speaker": "洛弦", "text_zh": "……"}
	var option: Dictionary = {"id": "test_seal_core", "text_zh": "封存核心。"}

	var result: AppResult = runner.call("choose_option", _base_state(), _event_touchdown(), line_step, option, duck)
	assert_false(result.is_ok, "choose_option requires a choice step.")
	assert_eq(result.code, "invalid_step")
	assert_eq(duck.operations, [] as Array[Dictionary])


func test_choose_option_defaults_to_game_state_autoload_store() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	# The caller-provided state revision must match the fallback store's actual
	# revision, exactly as in production integration.
	var autoload_snapshot: Dictionary = GameState.snapshot()
	var state: Dictionary = _base_state()
	state["revision"] = int(autoload_snapshot["revision"])
	# The step definition (not the passed option) carries the flag to set.
	var step: Dictionary = {
		"type": "choice",
		"choice_id": "test_probe",
		"prompt_zh": "灰盒探测步骤。",
		"options": [
			{"id": "test_probe_seal", "text_zh": "写入探测标记。", "set_flag": "wp08_null_store_probe_flag"},
		],
	}

	var result: AppResult = runner.call(
		"choose_option", state, _event_relay_choice(), step, {"id": "test_probe_seal"}
	)
	assert_true(result.is_ok, result.message)
	var committed: Dictionary = GameState.snapshot()
	assert_true(
		bool((committed["flags"] as Dictionary).get("wp08_null_store_probe_flag", false)),
		"Null store must fall back to the GameState autoload."
	)
	var cleanup: StatePatch = GameState.begin_patch("wp08_null_store_probe_cleanup", int(committed["revision"]))
	cleanup.set_flag("wp08_null_store_probe_flag", false)
	assert_true(GameState.commit(cleanup).is_ok)


# ---------------------------------------------------------------- apply_effect_step


func test_apply_effect_step_applies_all_branches_in_one_patch() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var step: Dictionary = {
		"type": "effect",
		"flag_id": "test_effect_flag",
		"grant_items": [{"item_id": "starsoil_dust", "amount": 3}],
		"due_encounter": "encounter_test_ambush_due",
	}

	var result: AppResult = runner.call("apply_effect_step", "event_test_touchdown", step, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 1, "Effect steps commit exactly one patch.")
	assert_eq(duck.last_source_id, "event_event_test_touchdown_effect")
	assert_eq(duck.last_expected_revision, 7, "Store-provided revision must be used when state is not passed.")
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "test_effect_flag", "enabled": true},
		{"type": "add_item", "item_id": "starsoil_dust", "amount": 3},
		{"type": "set_flag", "flag_id": "encounter_test_ambush_due", "enabled": true},
	] as Array[Dictionary])


func test_apply_effect_step_honors_flag_value_default_and_false() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var default_duck := _duck_store()
	var default_result: AppResult = runner.call(
		"apply_effect_step",
		"event_test_touchdown",
		{"type": "effect", "flag_id": "test_default_flag"},
		default_duck
	)
	assert_true(default_result.is_ok, default_result.message)
	assert_eq(default_duck.operations, [
		{"type": "set_flag", "flag_id": "test_default_flag", "enabled": true},
	] as Array[Dictionary], "flag_value defaults to true.")

	var false_duck := DuckStore.new()
	_duck = false_duck
	var false_result: AppResult = runner.call(
		"apply_effect_step",
		"event_test_touchdown",
		{"type": "effect", "flag_id": "test_false_flag", "flag_value": false},
		false_duck
	)
	assert_true(false_result.is_ok, false_result.message)
	assert_eq(false_duck.operations, [
		{"type": "set_flag", "flag_id": "test_false_flag", "enabled": false},
	] as Array[Dictionary], "Explicit flag_value=false must be preserved.")


func test_apply_effect_step_rejects_non_effect_step() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var result: AppResult = runner.call(
		"apply_effect_step",
		"event_test_touchdown",
		{"type": "choice", "choice_id": "test_relay_core", "options": []},
		duck
	)
	assert_false(result.is_ok, "apply_effect_step requires an effect step.")
	assert_eq(result.code, "invalid_step")
	assert_eq(duck.operations, [] as Array[Dictionary])


# ---------------------------------------------------------------- apply_effect_step: relation_delta


func test_apply_effect_step_returns_relation_delta_as_deferred_op_with_clamping() -> void:
	# W002-GAP1：effect 步骤支持 relation_delta，沿 choose_option 的
	# deferred_ops 通道返回；目标值基于快照关系值计算并钳制 0..100。
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	duck.snapshot_state = {"revision": 7, "relationships": {"luoxian": {"trust": 90}}}
	var step: Dictionary = {
		"type": "effect",
		"relation_delta": {"char_id": "luoxian", "dim": "trust", "delta": 150},
	}

	var result: AppResult = runner.call("apply_effect_step", "event_test_touchdown", step, duck)
	assert_true(result.is_ok, result.message)
	var value: Dictionary = result.value
	var deferred_ops: Array = value.get("deferred_ops", [])
	assert_eq(deferred_ops.size(), 1, "relation_delta becomes exactly one deferred op.")
	if deferred_ops.size() == 1:
		assert_eq(deferred_ops[0], {
			"op": "set_relationship",
			"char_id": "luoxian",
			"dim": "trust",
			"value": 100,
		}, "90 + 150 clamps to 100 in the deferred op.")
	assert_eq(duck.operations, [] as Array[Dictionary], "relation_delta is never applied directly by WP08.")
	assert_eq(duck.commit_calls, 0, "A delta-only effect step commits no patch.")


func test_apply_effect_step_commits_direct_ops_alongside_relation_delta() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	duck.snapshot_state = {"revision": 7, "relationships": {"misa": {"affection": 3}}}
	var step: Dictionary = {
		"type": "effect",
		"flag_id": "test_bond_flag",
		"relation_delta": {"char_id": "misa", "dim": "affection", "delta": 5},
	}

	var result: AppResult = runner.call("apply_effect_step", "event_test_touchdown", step, duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 1, "Direct ops still commit exactly one patch.")
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "test_bond_flag", "enabled": true},
	] as Array[Dictionary])
	var deferred_ops: Array = (result.value as Dictionary).get("deferred_ops", [])
	assert_eq(deferred_ops, [
		{"op": "set_relationship", "char_id": "misa", "dim": "affection", "value": 8},
	] as Array[Dictionary], "3 + 5 surfaces as a deferred op alongside the direct patch.")


func test_apply_effect_step_derives_relationships_from_store_snapshot() -> void:
	# 未显式提供关系值时，从 store 快照派生（缺省 0），与 revision 派生同源。
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var step: Dictionary = {
		"type": "effect",
		"relation_delta": {"char_id": "luoxian", "dim": "trust", "delta": 12},
	}

	var result: AppResult = runner.call("apply_effect_step", "event_test_touchdown", step, duck)
	assert_true(result.is_ok, result.message)
	var deferred_ops: Array = (result.value as Dictionary).get("deferred_ops", [])
	assert_eq(deferred_ops, [
		{"op": "set_relationship", "char_id": "luoxian", "dim": "trust", "value": 12},
	] as Array[Dictionary], "Missing relationships default to 0 before clamping.")


func test_apply_effect_step_skips_malformed_relation_delta_defensively() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var step: Dictionary = {
		"type": "effect",
		"flag_id": "test_defensive_flag",
		"relation_delta": {"dim": "trust", "delta": 10},
	}

	var result: AppResult = runner.call("apply_effect_step", "event_test_touchdown", step, duck)
	assert_true(result.is_ok, result.message)
	var deferred_ops: Array = (result.value as Dictionary).get("deferred_ops", [])
	assert_eq(
		deferred_ops, [] as Array[Dictionary],
		"A relation_delta without char_id is skipped defensively."
	)
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "test_defensive_flag", "enabled": true},
	] as Array[Dictionary], "Direct ops must survive a malformed relation_delta.")


# ---------------------------------------------------------------- 条件行可见性（W003-A2）


func _conditional_line_event() -> Dictionary:
	return {
		"id": "event_test_conditional",
		"kind": "mixed",
		"steps": [
			{"type": "line", "speaker": "洛弦", "text_zh": "无条件开场白。"},
			{
				"type": "line", "speaker": "弥砂", "text_zh": "只给开采立场听的话。",
				"requires_flag": "world_response_exploited",
			},
			{
				"type": "line", "speaker": "洛弦", "text_zh": "没开采过才听得到的鼓励。",
				"requires_flag_absent": "world_response_exploited",
			},
		],
	}


func test_line_is_visible_without_conditions_is_always_true() -> void:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return
	var line: Dictionary = {"type": "line", "speaker": "洛弦", "text_zh": "无条件台词。"}
	assert_true(script.call("line_is_visible", line, {}), "无条件行在空状态下必须可见。")
	assert_true(
		script.call("line_is_visible", line, {"flags": {"any_flag": true}}),
		"无条件行在带旗标状态下必须可见。"
	)


func test_line_is_visible_hides_line_until_required_flag_is_set() -> void:
	# W003-A2 游标路径一（flag 置/未置）：requires_flag 行仅在 flags[flag]==true 时可见。
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return
	var line: Dictionary = _conditional_line_event()["steps"][1]
	assert_false(
		script.call("line_is_visible", line, {"flags": {}}),
		"required flag 未置时条件行必须不可见。"
	)
	assert_false(
		script.call("line_is_visible", line, {"flags": {"world_response_exploited": false}}),
		"required flag 为 false 时条件行必须不可见。"
	)
	assert_true(
		script.call("line_is_visible", line, {"flags": {"world_response_exploited": true}}),
		"required flag 置位后条件行必须可见。"
	)


func test_line_is_visible_hides_line_once_forbidden_flag_is_set() -> void:
	# W003-A2 游标路径二：requires_flag_absent 行仅在该 flag 未置时可见。
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return
	var line: Dictionary = _conditional_line_event()["steps"][2]
	assert_true(
		script.call("line_is_visible", line, {"flags": {}}),
		"absent flag 未置时条件行必须可见。"
	)
	assert_true(
		script.call("line_is_visible", line, {"flags": {"world_response_exploited": false}}),
		"absent flag 为 false 时条件行必须可见。"
	)
	assert_false(
		script.call("line_is_visible", line, {"flags": {"world_response_exploited": true}}),
		"absent flag 置位后条件行必须隐藏。"
	)


func test_line_is_visible_combines_both_conditions_with_and_semantics() -> void:
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return
	var line: Dictionary = {
		"type": "line",
		"speaker": "弥砂",
		"text_zh": "双条件台词。",
		"requires_flag": "station_mode_exploit",
		"requires_flag_absent": "diplomatic_stance",
	}
	assert_false(script.call("line_is_visible", line, {"flags": {}}), "required 未置必须不可见。")
	assert_false(
		script.call("line_is_visible", line, {"flags": {"station_mode_exploit": true, "diplomatic_stance": true}}),
		"absent 已置时双条件行必须不可见。"
	)
	assert_true(
		script.call("line_is_visible", line, {"flags": {"station_mode_exploit": true, "diplomatic_stance": false}}),
		"required 置位且 absent 未置时双条件行必须可见。"
	)


func test_next_step_returns_conditional_line_steps_verbatim() -> void:
	# W003-A2 分工：next_step 保持既有游标语义（按索引原样返回步骤，条件字段
	# 原文随行携带），条件跳过由展示层（DialogueBox.show_lines）负责。
	var script: Script = load(EVENT_RUNNER_PATH) as Script
	assert_not_null(script, "EventRunner script must exist at %s." % EVENT_RUNNER_PATH)
	if script == null:
		return
	var event_def: Dictionary = _conditional_line_event()
	var first: Dictionary = script.call("next_step", event_def, 0)
	assert_eq(String(first.get("text_zh")), "无条件开场白。")
	var gated: Dictionary = script.call("next_step", event_def, 1)
	assert_eq(String(gated.get("requires_flag")), "world_response_exploited", "条件字段必须原样随行返回。")
	var absent_gated: Dictionary = script.call("next_step", event_def, 2)
	assert_eq(String(absent_gated.get("requires_flag_absent")), "world_response_exploited")


# ---------------------------------------------------------------- complete_event


func test_complete_event_writes_done_flag() -> void:
	var runner := _new_runner()
	if runner == null:
		return
	var duck := _duck_store()
	var result: AppResult = runner.call("complete_event", "event_test_touchdown", duck)
	assert_true(result.is_ok, result.message)
	assert_eq(duck.commit_calls, 1)
	assert_eq(duck.last_source_id, "event_event_test_touchdown_complete")
	assert_eq(duck.operations, [
		{"type": "set_flag", "flag_id": "event_event_test_touchdown_done", "enabled": true},
	] as Array[Dictionary])
