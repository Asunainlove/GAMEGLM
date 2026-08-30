extends GutTest

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const SAVE_SERVICE_SCRIPT: Script = preload("res://src/save/save_service.gd")

var _root_path: String = ""
var _service: Node
var _created_slots: Array[String] = []


func before_each() -> void:
	_root_path = "user://w000_p02_%s" % str(Time.get_ticks_usec())
	_service = SAVE_SERVICE_SCRIPT.new()
	add_child_autofree(_service)
	var configured: AppResult = _service.configure_root_for_tests(_root_path)
	assert_true(configured.is_ok, configured.message)


func after_each() -> void:
	var absolute_root: String = ProjectSettings.globalize_path(_root_path)
	for slot: String in _created_slots:
		for suffix: String in [".json", ".json.tmp", ".json.bak"]:
			var candidate: String = absolute_root.path_join(slot + suffix)
			if FileAccess.file_exists(candidate):
				var remove_error: Error = DirAccess.remove_absolute(candidate)
				assert_eq(remove_error, OK, "Test cleanup must remove only its exact candidate.")
	if DirAccess.dir_exists_absolute(absolute_root):
		var remove_dir_error: Error = DirAccess.remove_absolute(absolute_root)
		assert_eq(remove_dir_error, OK, "Test cleanup only removes its now-empty directory.")
	_created_slots.clear()


func _remember_slot(slot: String) -> String:
	if not _created_slots.has(slot):
		_created_slots.append(slot)
	return slot


func _new_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


func _snapshot_at_revision(target_revision: int) -> Dictionary:
	var state: Node = _new_state()
	for index: int in range(target_revision):
		var patch: StatePatch = state.begin_patch("save_fixture_%d" % index, index)
		patch.add_item("starsoil_dust", index + 1)
		if index == 0:
			patch.set_destructible_cell("surface_0_0", 1, 2, true)
			patch.place_building("anchor_block", "surface_0_0", 4, 6)
		assert_true(state.commit(patch).is_ok)
	return state.snapshot()


func _encode(snapshot: Dictionary) -> String:
	var codec: SaveCodec = SaveCodec.new()
	var result: AppResult = codec.encode_snapshot(snapshot)
	assert_true(result.is_ok, result.message)
	return result.value as String


func _write_candidate(slot: String, suffix: String, text: String) -> void:
	var absolute_root: String = ProjectSettings.globalize_path(_root_path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute_root)
	assert_eq(make_error, OK)
	var file_path: String = absolute_root.path_join(slot + suffix)
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file = null


func test_save_round_trip_preserves_persistent_delta_state() -> void:
	var slot: String = _remember_slot("round_trip")
	var snapshot: Dictionary = _snapshot_at_revision(2)
	var saved: AppResult = _service.save_slot(slot, snapshot)
	var loaded: AppResult = _service.load_slot(slot)

	assert_true(saved.is_ok, saved.message)
	assert_true(loaded.is_ok, loaded.message)
	assert_eq(loaded.details["source"], "primary")
	assert_eq(loaded.value["revision"], snapshot["revision"])
	assert_eq(loaded.value["inventory"], snapshot["inventory"])
	assert_eq(loaded.value["chunk_deltas"], snapshot["chunk_deltas"])
	assert_eq(loaded.value["placed_buildings"], snapshot["placed_buildings"])


func test_third_save_replaces_existing_backup_with_previous_primary() -> void:
	var slot: String = _remember_slot("three_generations")
	assert_true(_service.save_slot(slot, _snapshot_at_revision(1)).is_ok)
	assert_true(_service.save_slot(slot, _snapshot_at_revision(2)).is_ok)
	assert_true(_service.save_slot(slot, _snapshot_at_revision(3)).is_ok)

	var backup_path: String = ProjectSettings.globalize_path(_root_path).path_join(slot + ".json.bak")
	var backup_text: String = FileAccess.get_file_as_string(backup_path)
	var decoded_backup: AppResult = SaveCodec.new().decode_text(backup_text)
	assert_true(decoded_backup.is_ok, decoded_backup.message)
	assert_eq(decoded_backup.value["revision"], 2)
	assert_false(FileAccess.file_exists(backup_path.trim_suffix(".bak") + ".tmp"))


func test_codec_rejects_bad_checksum_invalid_json_and_future_version() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var valid_text: String = _encode(_snapshot_at_revision(1))
	var envelope: Dictionary = JSON.parse_string(valid_text) as Dictionary
	envelope["checksum"] = "0".repeat(64)
	var checksum_result: AppResult = codec.decode_text(JSON.stringify(envelope, "", true, true))
	assert_false(checksum_result.is_ok)
	assert_eq(checksum_result.code, "checksum_mismatch")

	var json_result: AppResult = codec.decode_text("{not valid json")
	assert_false(json_result.is_ok)
	assert_eq(json_result.code, "invalid_json")

	var future_envelope: Dictionary = JSON.parse_string(valid_text) as Dictionary
	future_envelope["save_version"] = 2
	future_envelope["payload"]["save_version"] = 2
	var future_result: AppResult = codec.decode_text(JSON.stringify(future_envelope, "", true, true))
	assert_false(future_result.is_ok)
	assert_eq(future_result.code, "future_save_version")


func test_codec_rejects_envelope_payload_revision_mismatch() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var envelope: Dictionary = JSON.parse_string(_encode(_snapshot_at_revision(1))) as Dictionary
	envelope["revision"] = 2
	var body: Dictionary = {
		"save_version": envelope["save_version"],
		"revision": envelope["revision"],
		"payload": envelope["payload"],
	}
	envelope["checksum"] = codec.canonical_json(body).sha256_text()

	var result: AppResult = codec.decode_text(JSON.stringify(envelope, "", true, true))
	assert_false(result.is_ok)
	assert_eq(result.code, "revision_mismatch")


func test_load_chooses_highest_valid_revision_across_all_candidates() -> void:
	var slot: String = _remember_slot("highest_revision")
	_write_candidate(slot, ".json", _encode(_snapshot_at_revision(1)))
	_write_candidate(slot, ".json.tmp", _encode(_snapshot_at_revision(3)))
	_write_candidate(slot, ".json.bak", _encode(_snapshot_at_revision(2)))

	var loaded: AppResult = _service.load_slot(slot)
	assert_true(loaded.is_ok, loaded.message)
	assert_eq(loaded.value["revision"], 3)
	assert_eq(loaded.details["source"], "tmp")


func test_equal_revision_uses_primary_then_tmp_then_backup_priority() -> void:
	var slot: String = _remember_slot("tie_priority")
	var primary: Dictionary = _snapshot_at_revision(1)
	var temporary: Dictionary = primary.duplicate(true)
	var backup: Dictionary = primary.duplicate(true)
	primary["content_hash"] = "primary"
	temporary["content_hash"] = "temporary"
	backup["content_hash"] = "backup"
	_write_candidate(slot, ".json", _encode(primary))
	_write_candidate(slot, ".json.tmp", _encode(temporary))
	_write_candidate(slot, ".json.bak", _encode(backup))

	var loaded: AppResult = _service.load_slot(slot)
	assert_true(loaded.is_ok, loaded.message)
	assert_eq(loaded.details["source"], "primary")
	assert_eq(loaded.value["content_hash"], "primary")


func test_corrupt_primary_recovers_from_valid_backup() -> void:
	var slot: String = _remember_slot("backup_recovery")
	var backup: Dictionary = _snapshot_at_revision(2)
	_write_candidate(slot, ".json", "truncated{")
	_write_candidate(slot, ".json.bak", _encode(backup))

	var loaded: AppResult = _service.load_slot(slot)
	assert_true(loaded.is_ok, loaded.message)
	assert_eq(loaded.details["source"], "backup")
	assert_eq(loaded.value["revision"], 2)


func test_delete_slot_removes_all_three_generations_and_reports_count() -> void:
	var slot: String = _remember_slot("delete_all_generations")
	assert_true(_service.save_slot(slot, _snapshot_at_revision(1)).is_ok)
	assert_true(_service.save_slot(slot, _snapshot_at_revision(2)).is_ok)
	_write_candidate(slot, ".json.tmp", _encode(_snapshot_at_revision(3)))
	var absolute_root: String = ProjectSettings.globalize_path(_root_path)

	var deleted: AppResult = _service.delete_slot(slot)

	assert_true(deleted.is_ok, "delete_slot 必须成功。")
	assert_eq(deleted.code, "deleted")
	assert_eq(int(deleted.details["removed"]), 3)
	assert_false(FileAccess.file_exists(absolute_root.path_join(slot + ".json")))
	assert_false(FileAccess.file_exists(absolute_root.path_join(slot + ".json.tmp")))
	assert_false(FileAccess.file_exists(absolute_root.path_join(slot + ".json.bak")))
	assert_false(_service.load_slot(slot).is_ok, "删除后 load 必须返回无档。")


func test_delete_slot_reports_absent_when_slot_has_no_files() -> void:
	var slot: String = _remember_slot("delete_absent_slot")

	var deleted: AppResult = _service.delete_slot(slot)

	assert_true(deleted.is_ok, "槽无文件时 delete_slot 必须以 absent 成功。")
	assert_eq(deleted.code, "absent")
	assert_eq(int(deleted.details["removed"]), 0)


func test_delete_slot_rejects_unsafe_slot_name() -> void:
	var deleted: AppResult = _service.delete_slot("../escape")

	assert_false(deleted.is_ok, "路径穿越槽名必须被拒绝。")
	assert_eq(deleted.code, "invalid_slot")
	assert_false(
		FileAccess.file_exists(
			ProjectSettings.globalize_path(_root_path).path_join("escape.json")
		),
		"被拒绝的删除不得产生任何文件系统副作用。"
	)


func test_slot_path_traversal_is_rejected_for_save_and_load() -> void:
	var snapshot: Dictionary = _snapshot_at_revision(1)
	var save_result: AppResult = _service.save_slot("../escape", snapshot)
	var load_result: AppResult = _service.load_slot("..\\escape")
	assert_false(save_result.is_ok)
	assert_eq(save_result.code, "invalid_slot")
	assert_false(load_result.is_ok)
	assert_eq(load_result.code, "invalid_slot")


func test_codec_canonicalizes_nested_dictionary_key_order() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var first: Dictionary = {"outer": {"z": 1, "a": [{"right": 2, "left": 1}]}, "alpha": true}
	var second: Dictionary = {"alpha": true, "outer": {"a": [{"left": 1, "right": 2}], "z": 1}}
	assert_eq(codec.canonical_json(first), codec.canonical_json(second))


func test_codec_accepts_integral_json_numbers_and_normalizes_them_to_int() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var snapshot: Dictionary = _snapshot_at_revision(1)
	snapshot["save_version"] = 1.0
	snapshot["generator_version"] = 1.0
	snapshot["revision"] = 1.0
	snapshot["world_seed"] = 42.0
	snapshot["inventory"]["starsoil_dust"] = 1.0
	snapshot["chunk_deltas"]["surface_0_0"][0]["cell_x"] = 1.0
	snapshot["placed_buildings"][0]["cell_y"] = 6.0

	var result: AppResult = codec.validate_snapshot(snapshot)
	assert_true(result.is_ok, result.message)
	assert_eq(typeof(result.value["revision"]), TYPE_INT)
	assert_eq(typeof(result.value["world_seed"]), TYPE_INT)
	assert_eq(typeof(result.value["inventory"]["starsoil_dust"]), TYPE_INT)
	assert_eq(typeof(result.value["chunk_deltas"]["surface_0_0"][0]["cell_x"]), TYPE_INT)
	assert_eq(typeof(result.value["placed_buildings"][0]["cell_y"]), TYPE_INT)
