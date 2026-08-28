extends GutTest

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")


func _new_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func test_initial_snapshot_contains_complete_save_v1_delta_contract() -> void:
	var snapshot: Dictionary = _new_state().snapshot()
	var required_fields: Array[String] = [
		"save_version",
		"generator_version",
		"content_hash",
		"revision",
		"world_seed",
		"player",
		"inventory",
		"flags",
		"world_enums",
		"chunk_deltas",
		"placed_buildings",
		"relationships",
		"ideology",
		"completed_events",
		"battle_outcomes",
		"applied_patch_sources",
	]
	for field: String in required_fields:
		assert_true(snapshot.has(field), "Initial Save v1 state is missing %s." % field)
	assert_eq(snapshot["save_version"], 1)
	assert_eq(snapshot["generator_version"], 1)
	assert_eq(snapshot["revision"], 0)
	assert_true(snapshot["player"]["position"].has_all(["x", "y"]))
	assert_false(snapshot.has("tile_map"), "Snapshots persist deltas, never a complete TileMap.")


func test_snapshot_is_a_deeply_isolated_copy() -> void:
	var state: Node = _new_state()
	var baseline: Dictionary = state.snapshot()
	var external: Dictionary = state.snapshot()
	external["inventory"]["starsoil_dust"] = 99
	external["player"]["position"]["x"] = 12
	external["ideology"]["agency"] = 7

	assert_eq(_canonical(state.snapshot()), _canonical(baseline))
	assert_eq(state.snapshot()["inventory"], {})


func test_successful_patch_commits_all_operations_once() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("test_successful_patch", 0)
	patch.add_item("starsoil_dust", 4)
	patch.set_destructible_cell("surface_0_0", 3, 5, true)
	patch.place_building("anchor_block", "surface_0_0", 8, 9)
	patch.set_flag("first_anchor_placed", true)

	var result: AppResult = state.commit(patch)
	var snapshot: Dictionary = state.snapshot()
	assert_true(result.is_ok, result.message)
	assert_eq(snapshot["revision"], 1)
	assert_eq(snapshot["inventory"]["starsoil_dust"], 4)
	assert_eq(snapshot["chunk_deltas"]["surface_0_0"][0]["cell_x"], 3)
	assert_eq(snapshot["chunk_deltas"]["surface_0_0"][0]["cell_y"], 5)
	assert_eq(snapshot["placed_buildings"][0]["building_id"], "anchor_block")
	assert_true(snapshot["flags"]["first_anchor_placed"])
	assert_has(snapshot["applied_patch_sources"], "test_successful_patch")


func test_mid_patch_failure_leaves_state_and_revision_unchanged() -> void:
	var state: Node = _new_state()
	var baseline: String = _canonical(state.snapshot())
	var patch: StatePatch = state.begin_patch("test_atomic_failure", 0)
	patch.add_item("starsoil_dust", 2)
	patch.remove_item("starsoil_dust", 3)

	var result: AppResult = state.commit(patch)
	assert_false(result.is_ok)
	assert_eq(result.code, "insufficient_item")
	assert_eq(_canonical(state.snapshot()), baseline)
	assert_does_not_have(state.snapshot()["applied_patch_sources"], "test_atomic_failure")


func test_revision_conflict_does_not_modify_state() -> void:
	var state: Node = _new_state()
	var first: StatePatch = state.begin_patch("test_first_revision", 0)
	first.add_item("salvage_metal", 1)
	assert_true(state.commit(first).is_ok)
	var baseline: String = _canonical(state.snapshot())

	var stale: StatePatch = state.begin_patch("test_stale_revision", 0)
	stale.set_flag("must_not_apply", true)
	var result: AppResult = state.commit(stale)
	assert_false(result.is_ok)
	assert_eq(result.code, "revision_conflict")
	assert_eq(_canonical(state.snapshot()), baseline)


func test_successful_source_replay_is_idempotent_even_with_stale_revision() -> void:
	var state: Node = _new_state()
	var patch: StatePatch = state.begin_patch("test_idempotent_source", 0)
	patch.add_item("resonant_glass", 2)
	assert_true(state.commit(patch).is_ok)
	var committed: String = _canonical(state.snapshot())

	var replay: AppResult = state.commit(patch)
	assert_true(replay.is_ok)
	assert_eq(replay.code, "already_applied")
	assert_eq(_canonical(state.snapshot()), committed)
	assert_eq(state.snapshot()["revision"], 1)


func test_duplicate_building_cell_is_rejected_without_partial_change() -> void:
	var state: Node = _new_state()
	var first: StatePatch = state.begin_patch("test_first_building", 0)
	first.place_building("anchor_block", "surface_0_0", -2, 4)
	assert_true(state.commit(first).is_ok)
	var baseline: String = _canonical(state.snapshot())

	var duplicate: StatePatch = state.begin_patch("test_duplicate_building", 1)
	duplicate.add_item("starsoil_dust", 1)
	duplicate.place_building("workbench", "surface_0_0", -2, 4)
	var result: AppResult = state.commit(duplicate)
	assert_false(result.is_ok)
	assert_eq(result.code, "building_cell_occupied")
	assert_eq(_canonical(state.snapshot()), baseline)


func test_duplicate_destructible_cell_is_rejected_without_partial_change() -> void:
	var state: Node = _new_state()
	var first: StatePatch = state.begin_patch("test_first_cell_delta", 0)
	first.set_destructible_cell("surface_0_0", 5, -3, true)
	assert_true(state.commit(first).is_ok)
	var baseline: String = _canonical(state.snapshot())

	var duplicate: StatePatch = state.begin_patch("test_duplicate_cell_delta", 1)
	duplicate.add_item("starsoil_dust", 1)
	duplicate.set_destructible_cell("surface_0_0", 5, -3, true)
	var result: AppResult = state.commit(duplicate)
	assert_false(result.is_ok)
	assert_eq(result.code, "cell_delta_exists")
	assert_eq(_canonical(state.snapshot()), baseline)


func test_invalid_quantity_and_empty_source_are_rejected() -> void:
	var state: Node = _new_state()
	var invalid_amount: StatePatch = state.begin_patch("test_invalid_amount", 0)
	invalid_amount.add_item("starsoil_dust", 0)
	var amount_result: AppResult = state.commit(invalid_amount)
	assert_false(amount_result.is_ok)
	assert_eq(amount_result.code, "invalid_amount")
	assert_eq(state.snapshot()["revision"], 0)

	var empty_source: StatePatch = state.begin_patch("", 0)
	empty_source.set_flag("must_not_apply", true)
	var source_result: AppResult = state.commit(empty_source)
	assert_false(source_result.is_ok)
	assert_eq(source_result.code, "invalid_source_id")
	assert_eq(state.snapshot()["revision"], 0)


func test_restore_snapshot_fully_validates_and_only_replaces_fresh_state() -> void:
	var source: Node = _new_state()
	var patch: StatePatch = source.begin_patch("test_restore_source", 0)
	patch.add_item("starsoil_dust", 3)
	patch.place_building("anchor_block", "surface_0_0", 2, 7)
	assert_true(source.commit(patch).is_ok)
	var saved_snapshot: Dictionary = source.snapshot()

	var target: Node = _new_state()
	var restored: AppResult = target.restore_snapshot(saved_snapshot)
	assert_true(restored.is_ok, restored.message)
	assert_eq(restored.code, "restored_for_load")
	assert_eq(_canonical(target.snapshot()), _canonical(saved_snapshot))

	saved_snapshot["inventory"]["starsoil_dust"] = 99
	assert_eq(target.snapshot()["inventory"]["starsoil_dust"], 3)
	var committed_state: String = _canonical(target.snapshot())
	var second_restore: AppResult = target.restore_snapshot(source.snapshot())
	assert_false(second_restore.is_ok)
	assert_eq(second_restore.code, "restore_requires_fresh_state")
	assert_eq(_canonical(target.snapshot()), committed_state)


func test_restore_rejects_invalid_snapshot_without_modifying_fresh_state() -> void:
	var target: Node = _new_state()
	var baseline: String = _canonical(target.snapshot())
	var invalid: Dictionary = target.snapshot()
	invalid.erase("inventory")

	var result: AppResult = target.restore_snapshot(invalid)
	assert_false(result.is_ok)
	assert_eq(result.code, "missing_snapshot_field")
	assert_eq(_canonical(target.snapshot()), baseline)
