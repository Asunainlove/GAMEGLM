extends Node

const DEFAULT_SAVE_ROOT: String = "user://saves"

var _save_root: String = DEFAULT_SAVE_ROOT
var _codec: SaveCodec = SaveCodec.new()


func configure_root_for_tests(root_path: String) -> AppResult:
	if not root_path.begins_with("user://") or root_path.contains("..") or root_path.contains("\\"):
		return AppResult.failure("invalid_save_root", "Test save root must be an isolated user:// path.")
	_save_root = root_path.trim_suffix("/")
	return AppResult.success(null, "save_root_configured")


func save_slot(slot: String, snapshot: Dictionary) -> AppResult:
	if not _is_safe_slot(slot):
		return AppResult.failure("invalid_slot", "Slot may only contain ASCII letters, digits, underscore, and hyphen.")
	var encoded: AppResult = _codec.encode_snapshot(snapshot)
	if not encoded.is_ok:
		return encoded

	var absolute_root: String = ProjectSettings.globalize_path(_save_root)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute_root)
	if make_error != OK:
		return AppResult.failure("save_directory_failed", "Could not create save directory (error %d)." % make_error)
	var paths: Dictionary = _slot_paths(slot)
	var write_result: AppResult = _write_text(paths["tmp"], encoded.value)
	if not write_result.is_ok:
		return write_result

	var verified: AppResult = _read_and_decode(paths["tmp"])
	if not verified.is_ok:
		return AppResult.failure("tmp_verification_failed", "Temporary save did not pass a full decode: %s" % verified.code)

	if FileAccess.file_exists(paths["primary"]):
		var rotate_error: Error = DirAccess.rename_absolute(paths["primary"], paths["backup"])
		if rotate_error != OK:
			return AppResult.failure(
				"primary_rotation_failed",
				"Could not rotate primary to backup (error %d); existing candidates were preserved." % rotate_error
			)

	var promote_error: Error = DirAccess.rename_absolute(paths["tmp"], paths["primary"])
	if promote_error != OK:
		return AppResult.failure(
			"tmp_promotion_failed",
			"Could not promote verified temporary save (error %d); recovery candidates were preserved." % promote_error
		)
	return AppResult.success(snapshot.duplicate(true), "saved", {"source": "primary"})


func load_slot(slot: String) -> AppResult:
	if not _is_safe_slot(slot):
		return AppResult.failure("invalid_slot", "Slot may only contain ASCII letters, digits, underscore, and hyphen.")
	var paths: Dictionary = _slot_paths(slot)
	var descriptors: Array[Dictionary] = [
		{"source": "primary", "path": paths["primary"], "priority": 3},
		{"source": "tmp", "path": paths["tmp"], "priority": 2},
		{"source": "backup", "path": paths["backup"], "priority": 1},
	]
	var best_snapshot: Dictionary = {}
	var best_source: String = ""
	var best_revision: int = -1
	var best_priority: int = -1
	for descriptor: Dictionary in descriptors:
		if not FileAccess.file_exists(descriptor["path"]):
			continue
		var decoded: AppResult = _read_and_decode(descriptor["path"])
		if not decoded.is_ok:
			continue
		var candidate: Dictionary = decoded.value
		var revision: int = int(candidate["revision"])
		var priority: int = int(descriptor["priority"])
		if revision > best_revision or (revision == best_revision and priority > best_priority):
			best_snapshot = candidate.duplicate(true)
			best_source = descriptor["source"]
			best_revision = revision
			best_priority = priority
	if best_source.is_empty():
		return AppResult.failure("no_valid_save", "No valid primary, temporary, or backup candidate exists.")
	return AppResult.success(best_snapshot, "loaded", {"source": best_source})


func _write_text(absolute_path: String, text: String) -> AppResult:
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return AppResult.failure("tmp_write_failed", "Could not open temporary save (error %d)." % FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	var file_error: Error = file.get_error()
	file = null
	if file_error != OK:
		return AppResult.failure("tmp_write_failed", "Could not fully write temporary save (error %d)." % file_error)
	return AppResult.success()


func _read_and_decode(absolute_path: String) -> AppResult:
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return AppResult.failure("save_read_failed", "Could not open save candidate (error %d)." % FileAccess.get_open_error())
	var text: String = file.get_as_text()
	var file_error: Error = file.get_error()
	file = null
	if file_error != OK:
		return AppResult.failure("save_read_failed", "Could not fully read save candidate (error %d)." % file_error)
	return _codec.decode_text(text)


func _slot_paths(slot: String) -> Dictionary:
	var absolute_root: String = ProjectSettings.globalize_path(_save_root)
	var primary: String = absolute_root.path_join(slot + ".json")
	return {
		"primary": primary,
		"tmp": primary + ".tmp",
		"backup": primary + ".bak",
	}


func _is_safe_slot(slot: String) -> bool:
	if slot.is_empty():
		return false
	var matcher: RegEx = RegEx.new()
	if matcher.compile("^[A-Za-z0-9_-]+$") != OK:
		return false
	return matcher.search(slot) != null
