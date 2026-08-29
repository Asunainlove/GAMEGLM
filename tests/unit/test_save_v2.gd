extends GutTest

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const GOLDEN_RESOURCE_PATH: String = "res://tests/golden/save_v1_golden.json"


func _new_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _state_with_all_new_operations() -> Dictionary:
	var state: Node = _new_state()
	var seed_patch: StatePatch = state.begin_patch("wp04_v2_seed", 0)
	seed_patch.add_item("starsoil_dust", 12)
	seed_patch.set_destructible_cell("surface_0_0", 3, 5, true)
	seed_patch.place_building("anchor_block", "surface_0_0", 8, 9)
	seed_patch.set_flag("first_anchor_placed", true)
	seed_patch.complete_event("event_prologue_landing")
	seed_patch.set_relationship("luoxian", "affection", 35)
	seed_patch.set_relationship("luoxian", "trust", 20)
	seed_patch.adjust_ideology("stewardship", 20)
	seed_patch.set_player_position(4, -2)
	assert_true(state.commit(seed_patch).is_ok)

	var outcome_patch: StatePatch = state.begin_patch("wp04_v2_outcome", 1)
	outcome_patch.add_item("resonant_glass", 2)
	outcome_patch.set_relationship("misa", "affection", 30)
	outcome_patch.set_relationship("misa", "trust", 25)
	outcome_patch.adjust_ideology("agency", 40)
	outcome_patch.complete_event("event_first_mining")
	outcome_patch.record_battle_outcome("encounter_first_drift", "victory", 4)
	assert_true(state.commit(outcome_patch).is_ok)
	return state.snapshot()


func _envelope_from(snapshot: Dictionary) -> Dictionary:
	var encoded: AppResult = SaveCodec.new().encode_snapshot(snapshot)
	assert_true(encoded.is_ok, encoded.message)
	return JSON.parse_string(encoded.value as String) as Dictionary


func _golden_text() -> String:
	return FileAccess.get_file_as_string(GOLDEN_RESOURCE_PATH)


func test_migration_table_declares_v1_identity() -> void:
	assert_eq(SaveCodec.SAVE_VERSION, 1)
	assert_true(SaveCodec.MIGRATIONS.has(1))
	assert_true((SaveCodec.MIGRATIONS[1] as Array).is_empty())


func test_migrate_to_latest_is_identity_for_v1_envelope() -> void:
	var envelope: Dictionary = _envelope_from(_state_with_all_new_operations())
	var migrated: AppResult = SaveCodec.migrate_to_latest(envelope)
	assert_true(migrated.is_ok, migrated.message)
	assert_eq(_canonical(migrated.value), _canonical(envelope["payload"]))


func test_migrate_to_latest_rejects_unknown_and_future_versions() -> void:
	var envelope: Dictionary = _envelope_from(_state_with_all_new_operations())

	var unknown: Dictionary = envelope.duplicate(true)
	unknown["save_version"] = 0
	var unknown_result: AppResult = SaveCodec.migrate_to_latest(unknown)
	assert_false(unknown_result.is_ok)
	assert_eq(unknown_result.code, "unsupported_save_version")

	var future: Dictionary = envelope.duplicate(true)
	future["save_version"] = 2
	var future_result: AppResult = SaveCodec.migrate_to_latest(future)
	assert_false(future_result.is_ok)
	assert_eq(future_result.code, "future_save_version")


func test_golden_fixture_decodes_with_expected_v1_payload() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var golden_text: String = _golden_text()
	assert_true(golden_text.length() > 0, "Golden fixture must exist and be non-empty.")

	var decoded: AppResult = codec.decode_text(golden_text)
	assert_true(decoded.is_ok, decoded.message)
	var payload: Dictionary = decoded.value
	assert_eq(payload["save_version"], 1)
	assert_eq(payload["revision"], 2)
	assert_eq(payload["world_seed"], 1337)
	assert_eq(payload["content_hash"].length(), 64)
	assert_eq(
		payload["inventory"],
		{"starsoil_dust": 12, "salvage_metal": 5, "resonant_glass": 2}
	)
	assert_eq(
		payload["relationships"]["luoxian"],
		{"affection": 35, "trust": 20, "ideology": 10}
	)
	assert_eq(payload["relationships"]["misa"]["affection"], 30)
	assert_eq(payload["relationships"]["misa"]["trust"], 25)
	assert_eq(payload["ideology"], {"stewardship": 20, "continuity": -15, "agency": 40})
	assert_has(payload["completed_events"], "event_prologue_landing")
	assert_has(payload["completed_events"], "event_first_mining")
	assert_eq(
		payload["battle_outcomes"]["encounter_first_drift"],
		{"result": "victory", "turns": 4}
	)
	assert_true(payload["flags"]["first_anchor_placed"])
	assert_true(payload["flags"]["encounter_first_drift_won"])
	assert_eq(payload["player"]["position"], {"x": 4, "y": -2})
	assert_eq((payload["chunk_deltas"]["surface_0_0"] as Array).size(), 1)
	assert_eq((payload["placed_buildings"] as Array).size(), 1)


func test_golden_fixture_migration_is_identity() -> void:
	var envelope: Dictionary = JSON.parse_string(_golden_text()) as Dictionary
	var migrated: AppResult = SaveCodec.migrate_to_latest(envelope)
	assert_true(migrated.is_ok, migrated.message)
	assert_eq(_canonical(migrated.value), _canonical(envelope["payload"]))


func test_golden_fixture_reencodes_to_identical_envelope() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var golden_text: String = _golden_text()
	var decoded: AppResult = codec.decode_text(golden_text)
	assert_true(decoded.is_ok, decoded.message)

	var reencoded: AppResult = codec.encode_snapshot(decoded.value)
	assert_true(reencoded.is_ok, reencoded.message)
	assert_eq(reencoded.value, golden_text)


func test_golden_fixture_rejects_tampered_payload_via_checksum() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var envelope: Dictionary = JSON.parse_string(_golden_text()) as Dictionary
	envelope["payload"]["inventory"]["starsoil_dust"] = 999

	var result: AppResult = codec.decode_text(JSON.stringify(envelope, "", true, true))
	assert_false(result.is_ok)
	assert_eq(result.code, "checksum_mismatch")


func test_golden_envelope_with_future_save_version_is_rejected() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var envelope: Dictionary = JSON.parse_string(_golden_text()) as Dictionary
	envelope["save_version"] = 2
	envelope["payload"]["save_version"] = 2

	var result: AppResult = codec.decode_text(JSON.stringify(envelope, "", true, true))
	assert_false(result.is_ok)
	assert_eq(result.code, "future_save_version")


func test_content_hash_round_trips_through_encode_and_decode() -> void:
	var snapshot: Dictionary = _state_with_all_new_operations()
	snapshot["content_hash"] = "b7f2a1c9e5d34f608a9b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3d4e5f607"
	var codec: SaveCodec = SaveCodec.new()

	var encoded: AppResult = codec.encode_snapshot(snapshot)
	assert_true(encoded.is_ok, encoded.message)
	var decoded: AppResult = codec.decode_text(encoded.value as String)
	assert_true(decoded.is_ok, decoded.message)
	assert_eq(decoded.value["content_hash"], snapshot["content_hash"])
