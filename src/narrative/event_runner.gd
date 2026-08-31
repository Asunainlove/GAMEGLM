class_name EventRunner
extends RefCounted

## WP08 narrative event runner (module-contracts.md §5).
## Pure logic, no scene-tree dependency. Persistent writes go through an
## injectable store (contract §0): `store: Object = null` falls back to the
## GameState autoload, and tests inject a local duck-typed double. Only main
## existing patch operations are applied directly (set_flag / add_item /
## remove_item); WP04-only operations such as set_relationship are returned as
## deferred operation dictionaries inside AppResult.value["deferred_ops"] so
## the post-merge integration layer can apply them through GameState.

const STEP_TYPES: Array[String] = ["line", "choice", "effect"]
const TRUST_CHAR_ID: String = "luoxian"
const EVENT_DONE_FLAG_FORMAT: String = "event_%s_done"
const RELATIONSHIP_MIN: int = 0
const RELATIONSHIP_MAX: int = 100
## Sentinel for _commit_operations: derive expected_revision from the store
## snapshot instead of a caller-provided value.
const USE_STORE_REVISION: int = -1


## Loads every `*.json` file directly inside `dir` (non-recursive, matching the
## `data/events/*.json` layout). Missing directory is a success with an empty
## list; malformed or minimally invalid files fail with `invalid_event_file`
## and name the offending file. value = Array[Dictionary] in file-name order.
func load_events_from(dir: String) -> AppResult:
	if not DirAccess.dir_exists_absolute(dir):
		var no_events: Array[Dictionary] = []
		return AppResult.success(no_events)
	var directory := DirAccess.open(dir)
	if directory == null:
		return AppResult.failure("invalid_event_file", "Cannot open event directory: %s" % dir)

	var file_names: Array[String] = []
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while entry != "":
		if not directory.current_is_dir() and entry.ends_with(".json"):
			file_names.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	file_names.sort()

	var events: Array[Dictionary] = []
	for file_name: String in file_names:
		var file_result: AppResult = _load_event_file(dir.path_join(file_name))
		if not file_result.is_ok:
			return file_result
		events.append(file_result.value)
	return AppResult.success(events)


func _load_event_file(path: String) -> AppResult:
	var file_name: String = path.get_file()
	if not FileAccess.file_exists(path):
		return AppResult.failure("invalid_event_file", "Cannot read event file: %s" % file_name)
	var text: String = FileAccess.get_file_as_string(path)
	# JSON.new().parse() reports failures via the returned Error code instead of
	# printing an engine error, so intentionally malformed fixture files stay
	# silent in test runs.
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_event_file",
			"Event file is not valid JSON at line %d: %s" % [json.get_error_line(), file_name]
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_event_file", "Event file must contain a JSON object: %s" % file_name)
	var event_def: Dictionary = parsed

	if typeof(event_def.get("id")) != TYPE_STRING or (event_def["id"] as String).is_empty():
		return AppResult.failure("invalid_event_file", "Event file is missing a string id: %s" % file_name)
	var event_id: String = event_def["id"]
	if typeof(event_def.get("kind")) != TYPE_STRING or (event_def["kind"] as String).is_empty():
		return AppResult.failure(
			"invalid_event_file",
			"Event %s is missing a string kind: %s" % [event_id, file_name]
		)
	if typeof(event_def.get("steps")) != TYPE_ARRAY or (event_def["steps"] as Array).is_empty():
		return AppResult.failure(
			"invalid_event_file",
			"Event %s must define a non-empty steps array: %s" % [event_id, file_name]
		)

	var steps: Array = event_def["steps"]
	for step_variant: Variant in steps:
		if typeof(step_variant) != TYPE_DICTIONARY:
			return AppResult.failure(
				"invalid_event_file",
				"Event %s has a step that is not an object: %s" % [event_id, file_name]
			)
		var step: Dictionary = step_variant
		if not STEP_TYPES.has(String(step.get("type", ""))):
			return AppResult.failure(
				"invalid_event_file",
				"Event %s has a step whose type is not one of line/choice/effect: %s" % [event_id, file_name]
			)
	return AppResult.success(event_def)


## Returns the ids of events that may run for `state`:
## - requires_flag must be null/absent or `state.flags[requires_flag] == true`;
## - once (default true) hides events whose id is recorded in
##   state.completed_events (when present) or whose `event_<id>_done` flag is
##   already true.
static func available_events(events: Array, state: Dictionary) -> Array[String]:
	var available: Array[String] = []
	var flags: Dictionary = state.get("flags", {})
	var completed_events: Array = state.get("completed_events", [])
	for event_def: Dictionary in events:
		var event_id: String = String(event_def.get("id", ""))
		if event_id.is_empty():
			continue
		var requires_flag: Variant = event_def.get("requires_flag")
		if requires_flag != null and not bool(flags.get(String(requires_flag), false)):
			continue
		var once: bool = true
		if event_def.has("once"):
			once = bool(event_def["once"])
		if once:
			if completed_events.has(event_id):
				continue
			if bool(flags.get(EVENT_DONE_FLAG_FORMAT % event_id, false)):
				continue
		available.append(event_id)
	return available


## Returns the step at `step_index`, or {} for negative/out-of-range indexes.
## W003-A2：条件 line（requires_flag / requires_flag_absent）原样随行返回——
## 本方法保持既有游标语义，不做过滤；条件跳过由展示层（DialogueBox.show_lines）
## 调用 line_is_visible 完成。
static func next_step(event_def: Dictionary, step_index: int) -> Dictionary:
	var steps: Array = event_def.get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return {}
	var step: Variant = steps[step_index]
	if typeof(step) != TYPE_DICTIONARY:
		return {}
	return (step as Dictionary).duplicate(true)


## W003-A2 条件行可见性（纯函数）：line 步骤可选 requires_flag /
## requires_flag_absent。requires_flag 仅当 state.flags[flag] == true 时可见；
## requires_flag_absent 仅当该 flag 未置（false 或缺失）时可见；两者同时存在
## 时取交集。无条件字段（或 state 缺 flags）的行始终可见。缺失键按空值处理，
## 与 available_events 的旗标口径一致。
static func line_is_visible(step: Dictionary, state: Dictionary) -> bool:
	var flags: Dictionary = state.get("flags", {})
	var required: String = String(step.get("requires_flag", ""))
	if not required.is_empty() and not bool(flags.get(required, false)):
		return false
	var forbidden: String = String(step.get("requires_flag_absent", ""))
	if not forbidden.is_empty() and bool(flags.get(forbidden, false)):
		return false
	return true


## Applies the direct effects of a chosen option (main-existing set_flag only)
## and returns relation_delta effects as deferred ops for the WP04-merged
## integration layer. Requires a choice step and an option that belongs to
## step.options; trust gates fail with zero writes.
func choose_option(
		state: Dictionary,
		event_def: Dictionary,
		step: Dictionary,
		option: Dictionary,
		store: Object = null
) -> AppResult:
	if String(step.get("type", "")) != "choice":
		return AppResult.failure("invalid_step", "choose_option requires a choice step.")
	var event_id: String = String(event_def.get("id", ""))
	var option_id: String = String(option.get("id", ""))
	var matched: Dictionary = _find_option(step, option_id)
	if matched.is_empty():
		return AppResult.failure(
			"unknown_option",
			"Option %s does not belong to the options of event %s." % [option_id, event_id]
		)

	var trust_result: AppResult = _check_trust_requirement(state, matched)
	if not trust_result.is_ok:
		return trust_result

	var deferred_ops: Array[Dictionary] = _deferred_relation_ops(state, matched)

	var flag_id: String = String(matched.get("set_flag", ""))
	if not flag_id.is_empty():
		var operations: Array[Dictionary] = [
			{"type": StatePatch.OP_SET_FLAG, "flag_id": flag_id, "enabled": true},
		]
		var commit_result: AppResult = _commit_operations(
			store,
			"event_%s_choice" % event_id,
			operations,
			int(state.get("revision", 0))
		)
		if not commit_result.is_ok:
			return commit_result
	return AppResult.success({"deferred_ops": deferred_ops})


## Applies an effect step in one patch: flag_id -> set_flag (flag_value default
## true), grant_items -> add_item, due_encounter -> set_flag(due_encounter, true).
## A relation_delta (W002-GAP1, same shape as choice options) is NOT committed
## directly: like choose_option it is computed against the store snapshot's
## relationships (missing values default to 0), clamped to 0..100 and returned
## as a deferred op in AppResult.value["deferred_ops"] for the post-merge
## integration layer. A delta-only step commits no patch.
func apply_effect_step(event_id: String, step: Dictionary, store: Object = null) -> AppResult:
	if String(step.get("type", "")) != "effect":
		return AppResult.failure("invalid_step", "apply_effect_step requires an effect step.")

	var operations: Array[Dictionary] = []
	if step.has("flag_id"):
		operations.append({
			"type": StatePatch.OP_SET_FLAG,
			"flag_id": String(step["flag_id"]),
			"enabled": bool(step.get("flag_value", true)),
		})
	var grant_items: Array = step.get("grant_items", [])
	for item_variant: Variant in grant_items:
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item_entry: Dictionary = item_variant
		operations.append({
			"type": StatePatch.OP_ADD_ITEM,
			"item_id": String(item_entry.get("item_id", "")),
			"amount": int(item_entry.get("amount", 0)),
		})
	var due_encounter: String = String(step.get("due_encounter", ""))
	if not due_encounter.is_empty():
		operations.append({
			"type": StatePatch.OP_SET_FLAG,
			"flag_id": due_encounter,
			"enabled": true,
		})
	var deferred_ops: Array[Dictionary] = _deferred_relation_ops(_state_snapshot(store), step)
	if not operations.is_empty():
		var commit_result: AppResult = _commit_operations(store, "event_%s_effect" % event_id, operations)
		if not commit_result.is_ok:
			return commit_result
	return AppResult.success({"deferred_ops": deferred_ops})


## Marks an event as finished through the main-existing set_flag operation,
## writing the `event_<id>_done` flag (the contract's WP08 completion marker;
## WP04's completed_events op is owned by the post-merge integration layer).
func complete_event(event_id: String, store: Object = null) -> AppResult:
	var operations: Array[Dictionary] = [
		{
			"type": StatePatch.OP_SET_FLAG,
			"flag_id": EVENT_DONE_FLAG_FORMAT % event_id,
			"enabled": true,
		},
	]
	return _commit_operations(store, "event_%s_complete" % event_id, operations)


static func _find_option(step: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {}
	var options: Array = step.get("options", [])
	for option_variant: Variant in options:
		if typeof(option_variant) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = option_variant
		if String(candidate.get("id", "")) == option_id:
			return candidate.duplicate(true)
	return {}


static func _check_trust_requirement(state: Dictionary, option: Dictionary) -> AppResult:
	var requires_trust: int = int(option.get("requires_trust", 0))
	if requires_trust <= 0:
		return AppResult.success()
	var relationships: Dictionary = state.get("relationships", {})
	var trust: int = 0
	if relationships.has(TRUST_CHAR_ID) and typeof(relationships[TRUST_CHAR_ID]) == TYPE_DICTIONARY:
		trust = int((relationships[TRUST_CHAR_ID] as Dictionary).get("trust", 0))
	if trust < requires_trust:
		return AppResult.failure(
			"trust_insufficient",
			"Option requires trust %d but %s trust is %d." % [requires_trust, TRUST_CHAR_ID, trust]
		)
	return AppResult.success()


static func _deferred_relation_ops(state: Dictionary, option: Dictionary) -> Array[Dictionary]:
	var deferred_ops: Array[Dictionary] = []
	var relation_delta: Variant = option.get("relation_delta")
	if typeof(relation_delta) != TYPE_DICTIONARY:
		return deferred_ops
	var delta_def: Dictionary = relation_delta
	var char_id: String = String(delta_def.get("char_id", ""))
	var dim: String = String(delta_def.get("dim", ""))
	if char_id.is_empty() or dim.is_empty():
		return deferred_ops
	var relationships: Dictionary = state.get("relationships", {})
	var current: int = 0
	if relationships.has(char_id) and typeof(relationships[char_id]) == TYPE_DICTIONARY:
		current = int((relationships[char_id] as Dictionary).get(dim, 0))
	var target: int = clampi(current + int(delta_def.get("delta", 0)), RELATIONSHIP_MIN, RELATIONSHIP_MAX)
	deferred_ops.append({
		"op": "set_relationship",
		"char_id": char_id,
		"dim": dim,
		"value": target,
	})
	return deferred_ops


func _commit_operations(
		store: Object,
		source_id: String,
		operations: Array[Dictionary],
		expected_revision: int = USE_STORE_REVISION
) -> AppResult:
	var store_object: Object = store
	if store_object == null:
		store_object = _default_store()
	if expected_revision < 0:
		expected_revision = _current_revision(store_object)
	var patch: Object = store_object.call("begin_patch", source_id, expected_revision)
	for operation: Dictionary in operations:
		_apply_operation_on_patch(patch, operation)
	var commit_result: Variant = store_object.call("commit", patch)
	if commit_result is AppResult:
		return commit_result
	return AppResult.failure("invalid_store", "Store commit must return an AppResult.")


func _apply_operation_on_patch(patch: Object, operation: Dictionary) -> void:
	match String(operation.get("type", "")):
		StatePatch.OP_SET_FLAG:
			patch.call("set_flag", String(operation.get("flag_id", "")), bool(operation.get("enabled", true)))
		StatePatch.OP_ADD_ITEM:
			patch.call("add_item", String(operation.get("item_id", "")), int(operation.get("amount", 0)))
		StatePatch.OP_REMOVE_ITEM:
			patch.call("remove_item", String(operation.get("item_id", "")), int(operation.get("amount", 0)))


func _default_store() -> Object:
	return GameState


func _current_revision(store_object: Object) -> int:
	if store_object.has_method("snapshot"):
		var snapshot: Variant = store_object.call("snapshot")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return int((snapshot as Dictionary).get("revision", 0))
	return 0


## Store snapshot derivation shared with apply_effect_step's relation_delta
## clamp computation; null store falls back to the GameState autoload
## (contract §0), stores without a snapshot method yield an empty dictionary.
func _state_snapshot(store: Object) -> Dictionary:
	var store_object: Object = store
	if store_object == null:
		store_object = _default_store()
	if store_object.has_method("snapshot"):
		var snapshot: Variant = store_object.call("snapshot")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot
	return {}
