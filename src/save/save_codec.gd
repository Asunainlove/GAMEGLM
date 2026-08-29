class_name SaveCodec
extends RefCounted

const SAVE_VERSION: int = 1
## Version -> Array[Callable] of migration steps. Each step receives the payload
## Dictionary and returns an AppResult whose value is the migrated payload.
## Version 1 is the initial schema, so its migration list is empty (identity).
const MIGRATIONS: Dictionary = {1: []}
const REQUIRED_SNAPSHOT_FIELDS: Array[String] = [
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


func encode_snapshot(snapshot: Dictionary) -> AppResult:
	var validation: AppResult = validate_snapshot(snapshot)
	if not validation.is_ok:
		return validation
	var normalized: Dictionary = validation.value
	var body: Dictionary = {
		"save_version": SAVE_VERSION,
		"revision": normalized["revision"],
		"payload": normalized,
	}
	var envelope: Dictionary = body.duplicate(true)
	envelope["checksum"] = _sha256(canonical_json(body))
	return AppResult.success(canonical_json(envelope), "encoded")


func decode_text(text: String) -> AppResult:
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_json",
			"Save JSON is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
	if typeof(parser.data) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_envelope", "Save envelope must be a dictionary.")
	var envelope: Dictionary = parser.data
	for key: String in ["save_version", "revision", "payload", "checksum"]:
		if not envelope.has(key):
			return AppResult.failure("missing_envelope_field", "Save envelope is missing %s." % key)

	var envelope_version: Variant = _integral_number(envelope["save_version"])
	if envelope_version == null:
		return AppResult.failure("invalid_envelope", "Envelope save_version must be an integer number.")
	if int(envelope_version) > SAVE_VERSION:
		return AppResult.failure("future_save_version", "Save was created by a newer version.")
	if int(envelope_version) != SAVE_VERSION:
		return AppResult.failure("unsupported_save_version", "Save version is not supported.")
	var envelope_revision: Variant = _integral_number(envelope["revision"])
	if envelope_revision == null or int(envelope_revision) < 0:
		return AppResult.failure("invalid_envelope", "Envelope revision must be a non-negative integer number.")
	if typeof(envelope["payload"]) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_envelope", "Envelope payload must be a dictionary.")
	if typeof(envelope["checksum"]) != TYPE_STRING or not _is_checksum(envelope["checksum"]):
		return AppResult.failure("invalid_checksum", "Envelope checksum must be 64 lowercase hexadecimal characters.")

	var body: Dictionary = {
		"save_version": int(envelope_version),
		"revision": int(envelope_revision),
		"payload": envelope["payload"],
	}
	var expected_checksum: String = _sha256(canonical_json(body))
	if envelope["checksum"] != expected_checksum:
		return AppResult.failure("checksum_mismatch", "Save checksum does not match its payload.")

	# Migration runs after the checksum was verified against the writer's
	# original body, so older envelopes authenticate before their payload is
	# transformed. For save_version 1 the migration is identity, which keeps
	# current decode behavior unchanged.
	var migration_result: AppResult = migrate_to_latest(envelope)
	if not migration_result.is_ok:
		return migration_result

	var validation: AppResult = validate_snapshot(migration_result.value)
	if not validation.is_ok:
		return validation
	var normalized: Dictionary = validation.value
	if int(normalized["revision"]) != int(envelope_revision):
		return AppResult.failure("revision_mismatch", "Envelope and payload revisions differ.")
	return AppResult.success(normalized.duplicate(true), "decoded")


## Applies every pending migration from envelope.save_version up to SAVE_VERSION.
## The payload is migrated on a deep copy; the input envelope is never mutated.
static func migrate_to_latest(envelope: Dictionary) -> AppResult:
	var version_value: Variant = _integral_number(envelope.get("save_version"))
	if version_value == null:
		return AppResult.failure("invalid_envelope", "Envelope save_version must be an integer number.")
	var version: int = int(version_value)
	if version > SAVE_VERSION:
		return AppResult.failure("future_save_version", "Save was created by a newer version.")
	if not MIGRATIONS.has(version):
		return AppResult.failure("unsupported_save_version", "Save version %d has no migration path." % version)
	var payload_value: Variant = envelope.get("payload")
	if typeof(payload_value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_envelope", "Envelope payload must be a dictionary.")

	var payload: Dictionary = (payload_value as Dictionary).duplicate(true)
	var current_version: int = version
	while current_version < SAVE_VERSION:
		current_version += 1
		var steps: Array = MIGRATIONS[current_version]
		for migration: Callable in steps:
			var step_result: AppResult = migration.call(payload)
			if not step_result.is_ok:
				return step_result
			payload = step_result.value
	return AppResult.success(payload, "migrated")


func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value), "", true, true)


func validate_snapshot(snapshot: Dictionary) -> AppResult:
	for key: String in REQUIRED_SNAPSHOT_FIELDS:
		if not snapshot.has(key):
			return AppResult.failure("missing_snapshot_field", "Snapshot is missing %s." % key)
	var json_result: AppResult = _validate_json_value(snapshot)
	if not json_result.is_ok:
		return json_result

	var normalized: Dictionary = _canonicalize(snapshot)
	var save_version: Variant = _integral_number(normalized["save_version"])
	if save_version == null:
		return AppResult.failure("invalid_snapshot_field", "save_version must be an integer number.")
	if int(save_version) > SAVE_VERSION:
		return AppResult.failure("future_save_version", "Snapshot was created by a newer version.")
	if int(save_version) != SAVE_VERSION:
		return AppResult.failure("unsupported_save_version", "Snapshot version is not supported.")
	normalized["save_version"] = int(save_version)

	for integer_key: String in ["generator_version", "revision", "world_seed"]:
		var integer_value: Variant = _integral_number(normalized[integer_key])
		if integer_value == null:
			return AppResult.failure("invalid_snapshot_field", "%s must be an integer number." % integer_key)
		if integer_key != "world_seed" and int(integer_value) < 0:
			return AppResult.failure("invalid_snapshot_field", "%s cannot be negative." % integer_key)
		normalized[integer_key] = int(integer_value)
	if typeof(normalized["content_hash"]) != TYPE_STRING:
		return AppResult.failure("invalid_snapshot_field", "content_hash must be a string.")

	var player_result: AppResult = _validate_player(normalized["player"])
	if not player_result.is_ok:
		return player_result
	var inventory_result: AppResult = _validate_inventory(normalized["inventory"])
	if not inventory_result.is_ok:
		return inventory_result
	var flags_result: AppResult = _validate_boolean_dictionary(normalized["flags"], "flags")
	if not flags_result.is_ok:
		return flags_result
	var enums_result: AppResult = _validate_string_dictionary(normalized["world_enums"], "world_enums")
	if not enums_result.is_ok:
		return enums_result
	var deltas_result: AppResult = _validate_chunk_deltas(normalized["chunk_deltas"])
	if not deltas_result.is_ok:
		return deltas_result
	var buildings_result: AppResult = _validate_buildings(normalized["placed_buildings"])
	if not buildings_result.is_ok:
		return buildings_result
	var relationships_result: AppResult = _validate_relationships(normalized["relationships"])
	if not relationships_result.is_ok:
		return relationships_result
	var ideology_result: AppResult = _validate_ideology(normalized["ideology"])
	if not ideology_result.is_ok:
		return ideology_result
	var events_result: AppResult = _validate_string_array(normalized["completed_events"], "completed_events")
	if not events_result.is_ok:
		return events_result
	if typeof(normalized["battle_outcomes"]) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "battle_outcomes must be a dictionary.")
	var sources_result: AppResult = _validate_string_array(normalized["applied_patch_sources"], "applied_patch_sources", true)
	if not sources_result.is_ok:
		return sources_result
	return AppResult.success(normalized)


func _validate_player(value: Variant) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "player must be a dictionary.")
	var player: Dictionary = value
	if not player.has("position") or typeof(player["position"]) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "player.position must be a dictionary.")
	var position: Dictionary = player["position"]
	for axis: String in ["x", "y"]:
		if not position.has(axis) or not _is_finite_number(position[axis]):
			return AppResult.failure("invalid_snapshot_field", "player.position.%s must be finite numeric data." % axis)
	return AppResult.success()


func _validate_inventory(value: Variant) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "inventory must be a dictionary.")
	var inventory: Dictionary = value
	for raw_item_id: Variant in inventory.keys():
		if typeof(raw_item_id) != TYPE_STRING or not _is_stable_id(raw_item_id):
			return AppResult.failure("invalid_snapshot_field", "Inventory keys must be stable IDs.")
		var amount: Variant = _integral_number(inventory[raw_item_id])
		if amount == null or int(amount) < 0:
			return AppResult.failure("invalid_snapshot_field", "Inventory amounts must be non-negative integers.")
		inventory[raw_item_id] = int(amount)
	return AppResult.success()


func _validate_boolean_dictionary(value: Variant, field_name: String) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "%s must be a dictionary." % field_name)
	var dictionary: Dictionary = value
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not _is_stable_id(raw_key) or typeof(dictionary[raw_key]) != TYPE_BOOL:
			return AppResult.failure("invalid_snapshot_field", "%s must map stable IDs to booleans." % field_name)
	return AppResult.success()


func _validate_string_dictionary(value: Variant, field_name: String) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "%s must be a dictionary." % field_name)
	var dictionary: Dictionary = value
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not _is_stable_id(raw_key) or typeof(dictionary[raw_key]) != TYPE_STRING:
			return AppResult.failure("invalid_snapshot_field", "%s must map stable IDs to strings." % field_name)
	return AppResult.success()


func _validate_chunk_deltas(value: Variant) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "chunk_deltas must be a dictionary.")
	var chunks: Dictionary = value
	for raw_chunk_id: Variant in chunks.keys():
		if typeof(raw_chunk_id) != TYPE_STRING or not _is_stable_id(raw_chunk_id):
			return AppResult.failure("invalid_snapshot_field", "Chunk delta keys must be stable IDs.")
		if typeof(chunks[raw_chunk_id]) != TYPE_ARRAY:
			return AppResult.failure("invalid_snapshot_field", "Each chunk delta must be an array.")
		var seen_cells: Dictionary = {}
		for raw_delta: Variant in chunks[raw_chunk_id]:
			if typeof(raw_delta) != TYPE_DICTIONARY:
				return AppResult.failure("invalid_snapshot_field", "Chunk cell deltas must be dictionaries.")
			var delta: Dictionary = raw_delta
			for coordinate_key: String in ["cell_x", "cell_y"]:
				if not delta.has(coordinate_key):
					return AppResult.failure("invalid_snapshot_field", "Chunk cell delta is missing %s." % coordinate_key)
				var coordinate: Variant = _integral_number(delta[coordinate_key])
				if coordinate == null:
					return AppResult.failure("invalid_snapshot_field", "Chunk cell coordinates must be integers.")
				delta[coordinate_key] = int(coordinate)
			if not delta.has("destroyed") or typeof(delta["destroyed"]) != TYPE_BOOL:
				return AppResult.failure("invalid_snapshot_field", "Chunk destroyed state must be boolean.")
			var cell_key: String = "%d,%d" % [delta["cell_x"], delta["cell_y"]]
			if seen_cells.has(cell_key):
				return AppResult.failure("invalid_snapshot_field", "Chunk delta contains a duplicate cell.")
			seen_cells[cell_key] = true
	return AppResult.success()


func _validate_buildings(value: Variant) -> AppResult:
	if typeof(value) != TYPE_ARRAY:
		return AppResult.failure("invalid_snapshot_field", "placed_buildings must be an array.")
	var seen_cells: Dictionary = {}
	for raw_building: Variant in value:
		if typeof(raw_building) != TYPE_DICTIONARY:
			return AppResult.failure("invalid_snapshot_field", "Placed buildings must be dictionaries.")
		var building: Dictionary = raw_building
		for id_key: String in ["building_id", "chunk_id"]:
			if not building.has(id_key) or typeof(building[id_key]) != TYPE_STRING or not _is_stable_id(building[id_key]):
				return AppResult.failure("invalid_snapshot_field", "Placed building IDs must be stable.")
		for coordinate_key: String in ["cell_x", "cell_y"]:
			if not building.has(coordinate_key):
				return AppResult.failure("invalid_snapshot_field", "Placed building is missing %s." % coordinate_key)
			var coordinate: Variant = _integral_number(building[coordinate_key])
			if coordinate == null:
				return AppResult.failure("invalid_snapshot_field", "Placed building coordinates must be integers.")
			building[coordinate_key] = int(coordinate)
		var cell_key: String = "%s:%d,%d" % [building["chunk_id"], building["cell_x"], building["cell_y"]]
		if seen_cells.has(cell_key):
			return AppResult.failure("invalid_snapshot_field", "Placed buildings contain an occupied duplicate cell.")
		seen_cells[cell_key] = true
	return AppResult.success()


func _validate_relationships(value: Variant) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "relationships must be a dictionary.")
	var relationships: Dictionary = value
	for raw_character_id: Variant in relationships.keys():
		if typeof(raw_character_id) != TYPE_STRING or not _is_stable_id(raw_character_id):
			return AppResult.failure("invalid_snapshot_field", "Relationship keys must be stable IDs.")
		if typeof(relationships[raw_character_id]) != TYPE_DICTIONARY:
			return AppResult.failure("invalid_snapshot_field", "Relationship records must be dictionaries.")
		var record: Dictionary = relationships[raw_character_id]
		for axis: String in ["affection", "trust"]:
			if not record.has(axis):
				return AppResult.failure("invalid_snapshot_field", "Relationship record is missing %s." % axis)
			var score: Variant = _integral_number(record[axis])
			if score == null:
				return AppResult.failure("invalid_snapshot_field", "Relationship scores must be integers.")
			record[axis] = int(score)
	return AppResult.success()


func _validate_ideology(value: Variant) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_snapshot_field", "ideology must be a dictionary.")
	var ideology: Dictionary = value
	for axis: String in ["stewardship", "continuity", "agency"]:
		if not ideology.has(axis):
			return AppResult.failure("invalid_snapshot_field", "Ideology is missing %s." % axis)
		var score: Variant = _integral_number(ideology[axis])
		if score == null:
			return AppResult.failure("invalid_snapshot_field", "Ideology scores must be integers.")
		ideology[axis] = int(score)
	return AppResult.success()


func _validate_string_array(value: Variant, field_name: String, require_unique: bool = false) -> AppResult:
	if typeof(value) != TYPE_ARRAY:
		return AppResult.failure("invalid_snapshot_field", "%s must be an array." % field_name)
	var seen: Dictionary = {}
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or not _is_stable_id(entry):
			return AppResult.failure("invalid_snapshot_field", "%s entries must be stable IDs." % field_name)
		if require_unique and seen.has(entry):
			return AppResult.failure("invalid_snapshot_field", "%s entries must be unique." % field_name)
		seen[entry] = true
	return AppResult.success()


func _validate_json_value(value: Variant) -> AppResult:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return AppResult.success()
		TYPE_FLOAT:
			if _is_finite_number(value):
				return AppResult.success()
			return AppResult.failure("non_json_value", "Save contains a non-finite number.")
		TYPE_ARRAY:
			for entry: Variant in value:
				var entry_result: AppResult = _validate_json_value(entry)
				if not entry_result.is_ok:
					return entry_result
			return AppResult.success()
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			for raw_key: Variant in dictionary.keys():
				if typeof(raw_key) != TYPE_STRING:
					return AppResult.failure("non_json_value", "Save dictionary keys must be strings.")
				var child_result: AppResult = _validate_json_value(dictionary[raw_key])
				if not child_result.is_ok:
					return child_result
			return AppResult.success()
		_:
			return AppResult.failure("non_json_value", "Save contains an unsupported Variant type.")


func _canonicalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array[String] = []
			for raw_key: Variant in source.keys():
				keys.append(str(raw_key))
			keys.sort()
			var dictionary: Dictionary = {}
			for key: String in keys:
				dictionary[key] = _canonicalize(source[key])
			return dictionary
		TYPE_ARRAY:
			var array: Array = []
			for entry: Variant in value:
				array.append(_canonicalize(entry))
			return array
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and number == floor(number):
				return int(number)
			return number
		_:
			return value


static func _integral_number(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		if is_finite(number) and number == floor(number):
			return int(number)
	return null


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value))


func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


func _is_checksum(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _sha256(text: String) -> String:
	return text.sha256_text()
