extends GutTest

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")


func _new_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func test_new_operations_commit_together_in_one_patch() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_all_new_ops", 0)
	patch.set_relationship("luoxian", "affection", 35)
	patch.adjust_ideology("agency", 40)
	patch.complete_event("event_prologue_landing")
	patch.record_battle_outcome("encounter_first_drift", "victory", 4)
	patch.set_player_position(4, -2)

	var result: AppResult = state.commit(patch)
	var snapshot: Dictionary = state.snapshot()
	assert_true(result.is_ok, result.message)
	assert_eq(snapshot["revision"], 1)
	assert_eq(snapshot["relationships"]["luoxian"]["affection"], 35)
	assert_eq(snapshot["ideology"]["agency"], 40)
	assert_eq(snapshot["completed_events"], ["event_prologue_landing"])
	assert_eq(snapshot["battle_outcomes"]["encounter_first_drift"], {"result": "victory", "turns": 4})
	assert_eq(snapshot["player"]["position"], {"x": 4, "y": -2})


func test_set_relationship_writes_clamped_values_into_relationships() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_relationship_write", 0)
	patch.set_relationship("luoxian", "affection", 150)
	patch.set_relationship("luoxian", "trust", 42)
	patch.set_relationship("misa", "ideology", -5)

	var result: AppResult = state.commit(patch)
	var snapshot: Dictionary = state.snapshot()
	assert_true(result.is_ok, result.message)
	assert_eq(snapshot["revision"], 1)
	assert_eq(snapshot["relationships"]["luoxian"]["affection"], 100)
	assert_eq(snapshot["relationships"]["luoxian"]["trust"], 42)
	assert_eq(snapshot["relationships"]["misa"]["ideology"], 0)


func test_set_relationship_rejects_invalid_char_id_and_dim() -> void:
	var state: Node = _new_state()
	var bad_char: StatePatch = state.begin_patch("wp04_bad_char", 0)
	bad_char.set_relationship("Luoxian", "affection", 10)
	var char_result: AppResult = state.commit(bad_char)
	assert_false(char_result.is_ok)
	assert_eq(char_result.code, "invalid_char_id")
	assert_eq(state.snapshot()["revision"], 0)

	var bad_dim: StatePatch = state.begin_patch("wp04_bad_dim", 0)
	bad_dim.set_relationship("luoxian", "honor", 10)
	var dim_result: AppResult = state.commit(bad_dim)
	assert_false(dim_result.is_ok)
	assert_eq(dim_result.code, "invalid_dim")
	assert_true((state.snapshot()["relationships"] as Dictionary).is_empty())


func test_adjust_ideology_accumulates_and_clamps_to_signed_range() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_ideology_clamp", 0)
	patch.adjust_ideology("stewardship", 20)
	patch.adjust_ideology("stewardship", -150)
	patch.adjust_ideology("agency", 200)

	var result: AppResult = state.commit(patch)
	var snapshot: Dictionary = state.snapshot()
	assert_true(result.is_ok, result.message)
	assert_eq(snapshot["ideology"]["stewardship"], -100)
	assert_eq(snapshot["ideology"]["agency"], 100)
	assert_eq(snapshot["ideology"]["continuity"], 0)


func test_adjust_ideology_rejects_unknown_axis() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_bad_axis", 0)
	patch.adjust_ideology("harmony", 10)
	var result: AppResult = state.commit(patch)
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_ideology_axis")
	assert_eq(state.snapshot()["ideology"], {"stewardship": 0, "continuity": 0, "agency": 0})


func test_complete_event_appends_once_and_is_idempotent() -> void:
	var state: Node = _new_state()
	var first: StatePatch = state.begin_patch("wp04_event_first", 0)
	first.complete_event("event_prologue_landing")
	assert_true(state.commit(first).is_ok)

	var replay: StatePatch = state.begin_patch("wp04_event_replay", 1)
	replay.complete_event("event_prologue_landing")
	replay.complete_event("event_first_mining")
	var replay_result: AppResult = state.commit(replay)
	var snapshot: Dictionary = state.snapshot()
	assert_true(replay_result.is_ok, replay_result.message)
	assert_eq((snapshot["completed_events"] as Array).size(), 2)
	assert_has(snapshot["completed_events"], "event_prologue_landing")
	assert_has(snapshot["completed_events"], "event_first_mining")


func test_complete_event_rejects_invalid_event_id() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_bad_event", 0)
	patch.complete_event("")
	var result: AppResult = state.commit(patch)
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_event_id")
	assert_true((state.snapshot()["completed_events"] as Array).is_empty())


func test_record_battle_outcome_writes_and_overwrites_outcome() -> void:
	var state: Node = _new_state()
	var first: StatePatch = state.begin_patch("wp04_battle_first", 0)
	first.record_battle_outcome("encounter_first_drift", "victory", 4)
	assert_true(state.commit(first).is_ok)
	assert_eq(
		state.snapshot()["battle_outcomes"]["encounter_first_drift"],
		{"result": "victory", "turns": 4}
	)

	var second: StatePatch = state.begin_patch("wp04_battle_second", 1)
	second.record_battle_outcome("encounter_first_drift", "defeat", 7)
	var second_result: AppResult = state.commit(second)
	assert_true(second_result.is_ok, second_result.message)
	assert_eq(
		state.snapshot()["battle_outcomes"]["encounter_first_drift"],
		{"result": "defeat", "turns": 7}
	)


func test_record_battle_outcome_rejects_invalid_result_and_negative_turns() -> void:
	var state: Node = _new_state()
	var bad_result: StatePatch = state.begin_patch("wp04_bad_result", 0)
	bad_result.record_battle_outcome("encounter_first_drift", "draw", 2)
	var result_failure: AppResult = state.commit(bad_result)
	assert_false(result_failure.is_ok)
	assert_eq(result_failure.code, "invalid_battle_result")
	assert_true((state.snapshot()["battle_outcomes"] as Dictionary).is_empty())

	var bad_turns: StatePatch = state.begin_patch("wp04_bad_turns", 0)
	bad_turns.record_battle_outcome("encounter_first_drift", "victory", -1)
	var turns_failure: AppResult = state.commit(bad_turns)
	assert_false(turns_failure.is_ok)
	assert_eq(turns_failure.code, "invalid_battle_result")
	assert_true((state.snapshot()["battle_outcomes"] as Dictionary).is_empty())


func test_set_player_position_writes_position_and_enforces_range() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_position_write", 0)
	patch.set_player_position(42, -17)
	var result: AppResult = state.commit(patch)
	assert_true(result.is_ok, result.message)
	assert_eq(state.snapshot()["player"]["position"], {"x": 42, "y": -17})

	var boundary: StatePatch = state.begin_patch("wp04_position_boundary", 1)
	boundary.set_player_position(
		GAME_STATE_SCRIPT.MAX_CELL_COORDINATE,
		-GAME_STATE_SCRIPT.MAX_CELL_COORDINATE
	)
	var boundary_result: AppResult = state.commit(boundary)
	assert_true(boundary_result.is_ok, boundary_result.message)
	assert_eq(
		state.snapshot()["player"]["position"],
		{"x": GAME_STATE_SCRIPT.MAX_CELL_COORDINATE, "y": -GAME_STATE_SCRIPT.MAX_CELL_COORDINATE}
	)

	var out_of_range: StatePatch = state.begin_patch("wp04_position_out_of_range", 2)
	out_of_range.set_player_position(GAME_STATE_SCRIPT.MAX_CELL_COORDINATE + 1, 0)
	var range_result: AppResult = state.commit(out_of_range)
	assert_false(range_result.is_ok)
	assert_eq(range_result.code, "invalid_cell_coordinate")
	assert_eq(
		state.snapshot()["player"]["position"],
		{"x": GAME_STATE_SCRIPT.MAX_CELL_COORDINATE, "y": -GAME_STATE_SCRIPT.MAX_CELL_COORDINATE}
	)


func test_new_operations_fail_atomically_after_prior_success() -> void:
	var state: Node = _new_state()
	var baseline: String = _canonical(state.snapshot())
	var patch: StatePatch = state.begin_patch("wp04_atomic_new_ops", 0)
	patch.add_item("starsoil_dust", 3)
	patch.set_relationship("luoxian", "affection", 50)
	patch.record_battle_outcome("encounter_first_drift", "draw", 2)

	var result: AppResult = state.commit(patch)
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_battle_result")
	assert_eq(_canonical(state.snapshot()), baseline)

	var second: StatePatch = state.begin_patch("wp04_atomic_new_ops_second", 0)
	second.set_relationship("luoxian", "trust", 20)
	second.set_player_position(GAME_STATE_SCRIPT.MAX_CELL_COORDINATE + 1, 0)
	var second_result: AppResult = state.commit(second)
	assert_false(second_result.is_ok)
	assert_eq(second_result.code, "invalid_cell_coordinate")
	assert_eq(_canonical(state.snapshot()), baseline)
	assert_eq(state.snapshot()["revision"], 0)


func test_reset_to_initial_returns_to_brand_new_fresh_state() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("p06_reset_seed", 0)
	patch.add_item("starsoil_dust", 3)
	patch.set_flag("first_mining_done", true)
	patch.complete_event("event_prologue_landing")
	patch.set_player_position(9, -4)
	assert_true(state.commit(patch).is_ok)
	assert_eq(int(state.snapshot()["revision"]), 1)

	state.reset_to_initial()

	var fresh: Node = _new_state()
	assert_eq(_canonical(state.snapshot()), _canonical(fresh.snapshot()))
	assert_eq(int(state.snapshot()["revision"]), 0)
	assert_true((state.snapshot()["inventory"] as Dictionary).is_empty())
	assert_true((state.snapshot()["flags"] as Dictionary).is_empty())
	assert_true((state.snapshot()["applied_patch_sources"] as Array).is_empty())


func test_restore_snapshot_is_unblocked_by_reset_to_initial() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("p06_reset_freshness", 0)
	patch.add_item("starsoil_dust", 5)
	assert_true(state.commit(patch).is_ok)
	var progressed: Dictionary = state.snapshot()

	var blocked: AppResult = state.restore_snapshot(progressed)
	assert_false(blocked.is_ok, "进度态（revision>0）必须拒绝 restore。")
	assert_eq(blocked.code, "restore_requires_fresh_state")

	state.reset_to_initial()
	var restored: AppResult = state.restore_snapshot(progressed)
	assert_true(restored.is_ok, restored.message)
	assert_eq(int(state.snapshot()["revision"]), 1)
	assert_eq(int((state.snapshot()["inventory"] as Dictionary).get("starsoil_dust", 0)), 5)


func test_new_operations_round_trip_through_save_v1_codec() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("wp04_codec_round_trip", 0)
	patch.set_relationship("luoxian", "affection", 60)
	patch.set_relationship("luoxian", "trust", 45)
	patch.adjust_ideology("continuity", -25)
	patch.complete_event("event_prologue_landing")
	patch.record_battle_outcome("encounter_first_drift", "victory", 3)
	patch.set_player_position(12, -30)
	assert_true(state.commit(patch).is_ok)
	var snapshot: Dictionary = state.snapshot()

	var encoded: AppResult = SaveCodec.new().encode_snapshot(snapshot)
	assert_true(encoded.is_ok, encoded.message)
	var decoded: AppResult = SaveCodec.new().decode_text(encoded.value as String)
	assert_true(decoded.is_ok, decoded.message)
	assert_eq(_canonical(decoded.value), _canonical(snapshot))
