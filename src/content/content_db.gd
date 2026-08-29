extends Node

## WP01: immutable, data-driven gameplay content registry (frozen contract v1, section 3).
## Recursively loads JSON definitions from <content_dir>/content/** (items, buildings,
## combat units, combat actions dispatched by their `kind` field), <content_dir>/events/**
## and <content_dir>/encounters/**, validates them against the frozen schema semantics,
## and hands out defensive copies. Canonical JSON and hashing are implemented here,
## independently of SaveCodec.
## Note: no `class_name ContentDB` — Godot 4.7 raises "Class ContentDB hides an
## autoload singleton" for a class_name equal to the Autoload name, so consumers
## reach this node through the global `ContentDB` Autoload identifier (same
## convention as GameState and SaveService). Fresh instances for tests are made
## via load("res://src/content/content_db.gd").new().

const DEFAULT_CONTENT_DIR: String = "res://data"
const ID_REGEX_PATTERN: String = "^[a-z][a-z0-9_]*$"

const CATEGORY_ITEMS: String = "items"
const CATEGORY_BUILDINGS: String = "buildings"
const CATEGORY_COMBAT_UNITS: String = "combat_units"
const CATEGORY_COMBAT_ACTIONS: String = "combat_actions"
const CATEGORY_EVENTS: String = "events"
const CATEGORY_ENCOUNTERS: String = "encounters"

const ITEM_KINDS: Array[String] = ["material", "story_core", "sandbox_item"]
const BUILDING_KINDS: Array[String] = ["building"]
const COMBAT_UNIT_KINDS: Array[String] = ["ally", "enemy_normal", "enemy_elite", "boss"]
const COMBAT_ACTION_KINDS: Array[String] = ["attack", "skill", "item", "guard", "destabilize"]
const EVENT_KINDS: Array[String] = ["dialogue", "choice", "mixed"]
const TRACKS: Array[String] = ["front", "mid", "rear"]
const TARGETINGS: Array[String] = ["self", "single_ally", "single_enemy", "all_enemies"]
const RELATION_DIMS: Array[String] = ["affection", "trust", "ideology"]

const ITEM_FIELDS: Array[String] = ["id", "kind", "name_zh", "desc_zh", "stack_limit", "tier", "battle_usable"]
const BUILDING_FIELDS: Array[String] = ["id", "kind", "name_zh", "desc_zh", "inputs", "recipe", "requires_room", "power_draw", "power_supply", "effect_flag"]
const COMBAT_UNIT_FIELDS: Array[String] = ["id", "kind", "name_zh", "max_hp", "stability_max", "track", "speed", "action_ids", "phases", "drops"]
const COMBAT_ACTION_FIELDS: Array[String] = ["id", "kind", "name_zh", "targeting", "power", "stability_damage", "cost", "heal", "guard_ratio"]
const EVENT_FIELDS: Array[String] = ["id", "kind", "requires_flag", "once", "steps"]
const ENCOUNTER_FIELDS: Array[String] = ["id", "name_zh", "trigger_flag", "on_victory_flag", "allies", "enemies", "seed", "intro_event_id"]
const ITEM_STACK_FIELDS: Array[String] = ["item_id", "count"]
const RECIPE_FIELDS: Array[String] = ["input_item_id", "input_count", "output_item_id", "output_count"]
const PHASE_FIELDS: Array[String] = ["id", "at_hp_ratio", "action_ids"]
const DROP_FIELDS: Array[String] = ["item_id", "amount"]
const COST_FIELDS: Array[String] = ["item_id", "count"]
const OPTION_FIELDS: Array[String] = ["id", "text_zh", "set_flag", "requires_trust", "relation_delta"]
const RELATION_DELTA_FIELDS: Array[String] = ["char_id", "dim", "delta"]
const GRANT_FIELDS: Array[String] = ["item_id", "amount"]
const ALLY_FIELDS: Array[String] = ["unit_id", "track", "item_ids"]
const ENEMY_FIELDS: Array[String] = ["unit_id", "track"]

var _bootstrapped: bool = false
var _content_hash: String = ""
var _items: Dictionary = {}
var _buildings: Dictionary = {}
var _combat_units: Dictionary = {}
var _combat_actions: Dictionary = {}
var _events: Dictionary = {}
var _encounters: Dictionary = {}
var _encounter_trigger_flags: Dictionary = {}
var _id_regex: RegEx = null


func bootstrap(content_dir: String = DEFAULT_CONTENT_DIR) -> AppResult:
	if _bootstrapped:
		return AppResult.failure(
			"already_bootstrapped",
			"ContentDB has already been bootstrapped; content is immutable after bootstrap."
		)
	var store: Dictionary = _empty_store()
	var counters: Dictionary = {"files": 0, "definitions": 0}

	var content_result: AppResult = _load_tree(content_dir.path_join("content"), "", store, counters)
	if not content_result.is_ok:
		return content_result
	var events_result: AppResult = _load_tree(content_dir.path_join("events"), CATEGORY_EVENTS, store, counters)
	if not events_result.is_ok:
		return events_result
	var encounters_result: AppResult = _load_tree(content_dir.path_join("encounters"), CATEGORY_ENCOUNTERS, store, counters)
	if not encounters_result.is_ok:
		return encounters_result

	_items = store[CATEGORY_ITEMS]
	_buildings = store[CATEGORY_BUILDINGS]
	_combat_units = store[CATEGORY_COMBAT_UNITS]
	_combat_actions = store[CATEGORY_COMBAT_ACTIONS]
	_events = store[CATEGORY_EVENTS]
	_encounters = store[CATEGORY_ENCOUNTERS]
	_encounter_trigger_flags = {}
	for encounter_id_key: String in _encounters:
		var encounter_def: Dictionary = _encounters[encounter_id_key]
		if encounter_def.has("trigger_flag"):
			_encounter_trigger_flags[str(encounter_def["trigger_flag"])] = true
	_bootstrapped = true
	_content_hash = _compute_content_hash()
	return AppResult.success(
		counters["definitions"],
		"ok",
		{"file_count": counters["files"], "definition_count": counters["definitions"]}
	)


func is_bootstrapped() -> bool:
	return _bootstrapped


func content_hash() -> String:
	return _content_hash


func get_item(id: String) -> Dictionary:
	return _get_copy(_items, id, "item")


func get_building(id: String) -> Dictionary:
	return _get_copy(_buildings, id, "building")


func get_combat_unit(id: String) -> Dictionary:
	return _get_copy(_combat_units, id, "combat unit")


func get_combat_action(id: String) -> Dictionary:
	return _get_copy(_combat_actions, id, "combat action")


func get_event(id: String) -> Dictionary:
	return _get_copy(_events, id, "event")


func get_encounter(id: String) -> Dictionary:
	return _get_copy(_encounters, id, "encounter")


func ids_of(kind: String) -> Array[String]:
	var result: Array[String] = []
	if kind == "item" or ITEM_KINDS.has(kind):
		for id: String in _items:
			if kind == "item" or (_items[id] as Dictionary)["kind"] == kind:
				result.append(id)
	elif kind == "building" or kind == CATEGORY_BUILDINGS:
		_append_keys(result, _buildings)
	elif kind == "combat_unit" or kind == CATEGORY_COMBAT_UNITS:
		_append_keys(result, _combat_units)
	elif kind == "combat_action" or kind == CATEGORY_COMBAT_ACTIONS:
		_append_keys(result, _combat_actions)
	elif kind == "event" or kind == CATEGORY_EVENTS:
		_append_keys(result, _events)
	elif kind == "encounter" or kind == CATEGORY_ENCOUNTERS:
		_append_keys(result, _encounters)
	else:
		push_warning("ContentDB: ids_of received unknown kind '%s'." % kind)
	result.sort()
	return result


func validate_refs() -> AppResult:
	if not _bootstrapped:
		return AppResult.failure(
			"not_bootstrapped",
			"ContentDB must be bootstrapped before validating cross-references."
		)
	var dangling: Array[String] = []
	for building_id: String in _buildings:
		var building: Dictionary = _buildings[building_id]
		for stack: Dictionary in building.get("inputs", []):
			_check_ref(_items, stack["item_id"], "item", "building '%s' inputs" % building_id, dangling)
		if building.has("recipe"):
			var recipe: Dictionary = building["recipe"]
			_check_ref(_items, recipe["input_item_id"], "item", "building '%s' recipe input" % building_id, dangling)
			_check_ref(_items, recipe["output_item_id"], "item", "building '%s' recipe output" % building_id, dangling)
	for unit_id: String in _combat_units:
		var unit: Dictionary = _combat_units[unit_id]
		for action_id: String in unit["action_ids"]:
			_check_ref(_combat_actions, action_id, "combat action", "combat unit '%s' action_ids" % unit_id, dangling)
		for phase: Dictionary in unit.get("phases", []):
			for phase_action_id: String in phase["action_ids"]:
				_check_ref(_combat_actions, phase_action_id, "combat action", "combat unit '%s' phase '%s'" % [unit_id, phase["id"]], dangling)
		for drop: Dictionary in unit.get("drops", []):
			_check_ref(_items, drop["item_id"], "item", "combat unit '%s' drops" % unit_id, dangling)
	for action_id: String in _combat_actions:
		var action: Dictionary = _combat_actions[action_id]
		if action.has("cost") and action["cost"] != null:
			var cost: Dictionary = action["cost"]
			_check_ref(_items, cost["item_id"], "item", "combat action '%s' cost" % action_id, dangling)
	for event_id: String in _events:
		var event: Dictionary = _events[event_id]
		for step: Dictionary in event["steps"]:
			if step["type"] != "effect":
				continue
			for grant: Dictionary in step.get("grant_items", []):
				_check_ref(_items, grant["item_id"], "item", "event '%s' grant_items" % event_id, dangling)
			if step.has("due_encounter"):
				_check_ref(_encounter_trigger_flags, step["due_encounter"], "encounter trigger flag", "event '%s' due_encounter" % event_id, dangling)
	for encounter_id: String in _encounters:
		var encounter: Dictionary = _encounters[encounter_id]
		for ally: Dictionary in encounter["allies"]:
			_check_ref(_combat_units, ally["unit_id"], "combat unit", "encounter '%s' allies" % encounter_id, dangling)
			for item_id: String in ally.get("item_ids", []):
				_check_ref(_items, item_id, "item", "encounter '%s' ally items" % encounter_id, dangling)
		for enemy: Dictionary in encounter["enemies"]:
			_check_ref(_combat_units, enemy["unit_id"], "combat unit", "encounter '%s' enemies" % encounter_id, dangling)
		if encounter.has("intro_event_id"):
			_check_ref(_events, encounter["intro_event_id"], "event", "encounter '%s' intro_event_id" % encounter_id, dangling)
	if not dangling.is_empty():
		return AppResult.failure("dangling_ref", "; ".join(PackedStringArray(dangling)))
	return AppResult.success()


func _get_copy(store: Dictionary, id: String, label: String) -> Dictionary:
	if not store.has(id):
		push_warning("ContentDB: unknown %s id '%s'." % [label, id])
		return {}
	return (store[id] as Dictionary).duplicate(true)


func _append_keys(target: Array[String], store: Dictionary) -> void:
	for id: String in store:
		target.append(id)


func _empty_store() -> Dictionary:
	return {
		CATEGORY_ITEMS: {},
		CATEGORY_BUILDINGS: {},
		CATEGORY_COMBAT_UNITS: {},
		CATEGORY_COMBAT_ACTIONS: {},
		CATEGORY_EVENTS: {},
		CATEGORY_ENCOUNTERS: {},
	}


func _load_tree(tree_root: String, fixed_category: String, store: Dictionary, counters: Dictionary) -> AppResult:
	var files: Array[String] = []
	_collect_json_files(tree_root, files)
	for path: String in files:
		var parse_result: AppResult = _parse_json_file(path)
		if not parse_result.is_ok:
			return parse_result
		var store_result: AppResult = _store_definitions(parse_result.value, path, fixed_category, store, counters)
		if not store_result.is_ok:
			return store_result
	return AppResult.success()


func _collect_json_files(tree_root: String, files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(tree_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_collect_json_files(tree_root.path_join(entry), files)
		elif entry.ends_with(".json"):
			files.append(tree_root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()


func _parse_json_file(path: String) -> AppResult:
	var text: String = FileAccess.get_file_as_string(path)
	var open_error: Error = FileAccess.get_open_error()
	if open_error != OK:
		return AppResult.failure("invalid_json", "%s: cannot read file (error %d)." % [path, open_error])
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_json",
			"%s: invalid JSON at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()]
		)
	return AppResult.success(parser.data)


func _store_definitions(parsed: Variant, path: String, fixed_category: String, store: Dictionary, counters: Dictionary) -> AppResult:
	if typeof(parsed) != TYPE_ARRAY and typeof(parsed) != TYPE_DICTIONARY:
		return AppResult.failure(
			"invalid_definition",
			"%s: content must be a definition object or an array of definition objects." % path
		)
	var entries: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		entries = parsed
	else:
		entries = [parsed]
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			return AppResult.failure("invalid_definition", "%s: every definition must be a JSON object." % path)
		var definition: Dictionary = entry
		var category: String = fixed_category
		if category.is_empty():
			var dispatch: AppResult = _category_for_kind(definition, path)
			if not dispatch.is_ok:
				return dispatch
			category = dispatch.value
		var validation: AppResult = _validate_definition(definition, category, path)
		if not validation.is_ok:
			return validation
		var id: String = definition["id"]
		var bucket: Dictionary = store[category]
		if bucket.has(id):
			return AppResult.failure("duplicate_id", "%s: duplicate %s id '%s'." % [path, category, id])
		bucket[id] = definition.duplicate(true)
		counters["definitions"] += 1
	counters["files"] += 1
	return AppResult.success()


func _category_for_kind(definition: Dictionary, path: String) -> AppResult:
	if not definition.has("kind") or typeof(definition["kind"]) != TYPE_STRING:
		return AppResult.failure("invalid_definition", "%s: content definition is missing a string 'kind' field." % path)
	var kind: String = definition["kind"]
	if ITEM_KINDS.has(kind):
		return AppResult.success(CATEGORY_ITEMS)
	if BUILDING_KINDS.has(kind):
		return AppResult.success(CATEGORY_BUILDINGS)
	if COMBAT_UNIT_KINDS.has(kind):
		return AppResult.success(CATEGORY_COMBAT_UNITS)
	if COMBAT_ACTION_KINDS.has(kind):
		return AppResult.success(CATEGORY_COMBAT_ACTIONS)
	return AppResult.failure("invalid_definition", "%s: unknown content kind '%s'." % [path, kind])


func _validate_definition(definition: Dictionary, category: String, path: String) -> AppResult:
	var id_result: AppResult = _require_stable_id(definition, "id", path)
	if not id_result.is_ok:
		return id_result
	match category:
		CATEGORY_ITEMS:
			return _validate_item(definition, path)
		CATEGORY_BUILDINGS:
			return _validate_building(definition, path)
		CATEGORY_COMBAT_UNITS:
			return _validate_combat_unit(definition, path)
		CATEGORY_COMBAT_ACTIONS:
			return _validate_combat_action(definition, path)
		CATEGORY_EVENTS:
			return _validate_event(definition, path)
		CATEGORY_ENCOUNTERS:
			return _validate_encounter(definition, path)
	return _fail(path, "unknown category '%s'." % category)


func _validate_item(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, ITEM_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "kind", "name_zh", "stack_limit"], path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "kind", ITEM_KINDS, path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(definition, "name_zh", path)
	if not result.is_ok:
		return result
	result = _optional_string(definition, "desc_zh", path)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "stack_limit", path, 1, 999)
	if not result.is_ok:
		return result
	result = _optional_integer(definition, "tier", path, 0, 9)
	if not result.is_ok:
		return result
	return _optional_bool(definition, "battle_usable", path)


func _validate_building(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, BUILDING_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "kind", "name_zh", "inputs", "power_draw", "power_supply"], path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "kind", BUILDING_KINDS, path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(definition, "name_zh", path)
	if not result.is_ok:
		return result
	result = _optional_string(definition, "desc_zh", path)
	if not result.is_ok:
		return result
	result = _validate_array(definition, "inputs", path, -1)
	if not result.is_ok:
		return result
	for stack: Dictionary in definition["inputs"]:
		result = _validate_item_stack(stack, "inputs", path)
		if not result.is_ok:
			return result
	if definition.has("recipe"):
		result = _validate_recipe(definition["recipe"], path)
		if not result.is_ok:
			return result
	result = _optional_bool(definition, "requires_room", path)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "power_draw", path, 0)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "power_supply", path, 0)
	if not result.is_ok:
		return result
	return _optional_stable_id(definition, "effect_flag", path)


func _validate_combat_unit(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, COMBAT_UNIT_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "kind", "name_zh", "max_hp", "stability_max", "track", "speed", "action_ids"], path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "kind", COMBAT_UNIT_KINDS, path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(definition, "name_zh", path)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "max_hp", path, 1)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "stability_max", path, 1)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "track", TRACKS, path)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "speed", path, 1)
	if not result.is_ok:
		return result
	result = _validate_stable_id_array(definition, "action_ids", path, 1)
	if not result.is_ok:
		return result
	if definition.has("phases"):
		result = _validate_array(definition, "phases", path, 0)
		if not result.is_ok:
			return result
		if (definition["phases"] as Array).size() > 2:
			return _fail(path, "phases must contain at most 2 entries.")
		for phase: Dictionary in definition["phases"]:
			result = _validate_phase(phase, path)
			if not result.is_ok:
				return result
	if definition.has("drops"):
		result = _validate_array(definition, "drops", path, -1)
		if not result.is_ok:
			return result
		for drop: Dictionary in definition["drops"]:
			result = _validate_keyed_object(drop, DROP_FIELDS, ["item_id", "amount"], path, "drops")
			if not result.is_ok:
				return result
			result = _require_stable_id(drop, "item_id", path)
			if not result.is_ok:
				return result
			result = _require_integer(drop, "amount", path, 1)
			if not result.is_ok:
				return result
	return AppResult.success()


func _validate_combat_action(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, COMBAT_ACTION_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "kind", "name_zh", "targeting", "power", "stability_damage"], path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "kind", COMBAT_ACTION_KINDS, path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(definition, "name_zh", path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "targeting", TARGETINGS, path)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "power", path, 0)
	if not result.is_ok:
		return result
	result = _require_integer(definition, "stability_damage", path, 0)
	if not result.is_ok:
		return result
	if definition.has("cost") and definition["cost"] != null:
		result = _validate_keyed_object(definition["cost"], COST_FIELDS, ["item_id", "count"], path, "cost")
		if not result.is_ok:
			return result
		result = _require_stable_id(definition["cost"], "item_id", path)
		if not result.is_ok:
			return result
		result = _require_integer(definition["cost"], "count", path, 1)
		if not result.is_ok:
			return result
	result = _optional_integer(definition, "heal", path, 0)
	if not result.is_ok:
		return result
	return _optional_number(definition, "guard_ratio", path, 0.0, 1.0)


func _validate_event(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, EVENT_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "kind", "steps"], path)
	if not result.is_ok:
		return result
	result = _require_enum(definition, "kind", EVENT_KINDS, path)
	if not result.is_ok:
		return result
	if definition.has("requires_flag") and definition["requires_flag"] != null:
		result = _require_stable_id(definition, "requires_flag", path)
		if not result.is_ok:
			return result
	result = _optional_bool(definition, "once", path)
	if not result.is_ok:
		return result
	result = _validate_array(definition, "steps", path, 1)
	if not result.is_ok:
		return result
	for step: Dictionary in definition["steps"]:
		result = _validate_step(step, path)
		if not result.is_ok:
			return result
	return AppResult.success()


func _validate_step(step: Dictionary, path: String) -> AppResult:
	if not step.has("type") or typeof(step["type"]) != TYPE_STRING:
		return _fail(path, "every event step requires a string 'type' field.")
	var step_type: String = step["type"]
	match step_type:
		"line":
			var result: AppResult = _reject_unknown_fields(step, ["type", "speaker", "text_zh"], path)
			if not result.is_ok:
				return result
			result = _optional_nonempty_string(step, "speaker", path)
			if not result.is_ok:
				return result
			return _optional_nonempty_string(step, "text_zh", path)
		"choice":
			var result: AppResult = _reject_unknown_fields(step, ["type", "choice_id", "prompt_zh", "options"], path)
			if not result.is_ok:
				return result
			result = _optional_stable_id(step, "choice_id", path)
			if not result.is_ok:
				return result
			result = _optional_nonempty_string(step, "prompt_zh", path)
			if not result.is_ok:
				return result
			if not step.has("options"):
				return AppResult.success()
			result = _validate_array(step, "options", path, 2)
			if not result.is_ok:
				return result
			for option: Dictionary in step["options"]:
				result = _validate_choice_option(option, path)
				if not result.is_ok:
					return result
			return AppResult.success()
		"effect":
			var result: AppResult = _reject_unknown_fields(step, ["type", "flag_id", "flag_value", "grant_items", "due_encounter"], path)
			if not result.is_ok:
				return result
			result = _optional_stable_id(step, "flag_id", path)
			if not result.is_ok:
				return result
			result = _optional_bool(step, "flag_value", path)
			if not result.is_ok:
				return result
			if step.has("grant_items"):
				result = _validate_array(step, "grant_items", path, -1)
				if not result.is_ok:
					return result
				for grant: Dictionary in step["grant_items"]:
					result = _validate_keyed_object(grant, GRANT_FIELDS, ["item_id", "amount"], path, "grant_items")
					if not result.is_ok:
						return result
					result = _require_stable_id(grant, "item_id", path)
					if not result.is_ok:
						return result
					result = _require_integer(grant, "amount", path, 1)
					if not result.is_ok:
						return result
			return _optional_stable_id(step, "due_encounter", path)
	return _fail(path, "unknown event step type '%s'." % step_type)


func _validate_choice_option(option: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(option, OPTION_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(option, ["id", "text_zh"], path)
	if not result.is_ok:
		return result
	result = _require_stable_id(option, "id", path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(option, "text_zh", path)
	if not result.is_ok:
		return result
	result = _optional_stable_id(option, "set_flag", path)
	if not result.is_ok:
		return result
	result = _optional_integer(option, "requires_trust", path, 0, 100)
	if not result.is_ok:
		return result
	if option.has("relation_delta"):
		if typeof(option["relation_delta"]) != TYPE_DICTIONARY:
			return _fail(path, "relation_delta must be an object.")
		var delta: Dictionary = option["relation_delta"]
		result = _reject_unknown_fields(delta, RELATION_DELTA_FIELDS, path)
		if not result.is_ok:
			return result
		result = _optional_stable_id(delta, "char_id", path)
		if not result.is_ok:
			return result
		result = _optional_enum(delta, "dim", RELATION_DIMS, path)
		if not result.is_ok:
			return result
		result = _optional_integer(delta, "delta", path, -100, 100)
		if not result.is_ok:
			return result
	return AppResult.success()


func _validate_encounter(definition: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(definition, ENCOUNTER_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(definition, ["id", "name_zh", "trigger_flag", "allies", "enemies", "seed"], path)
	if not result.is_ok:
		return result
	result = _require_nonempty_string(definition, "name_zh", path)
	if not result.is_ok:
		return result
	result = _require_stable_id(definition, "trigger_flag", path)
	if not result.is_ok:
		return result
	result = _optional_stable_id(definition, "on_victory_flag", path)
	if not result.is_ok:
		return result
	result = _validate_array(definition, "allies", path, 1)
	if not result.is_ok:
		return result
	for ally: Dictionary in definition["allies"]:
		result = _validate_combatant(ally, ALLY_FIELDS, true, path, "allies")
		if not result.is_ok:
			return result
	result = _validate_array(definition, "enemies", path, 1)
	if not result.is_ok:
		return result
	for enemy: Dictionary in definition["enemies"]:
		result = _validate_combatant(enemy, ENEMY_FIELDS, false, path, "enemies")
		if not result.is_ok:
			return result
	result = _require_integer(definition, "seed", path, 0)
	if not result.is_ok:
		return result
	return _optional_stable_id(definition, "intro_event_id", path)


func _validate_combatant(entry: Dictionary, allowed: Array[String], with_items: bool, path: String, container: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(entry, allowed, path)
	if not result.is_ok:
		return result
	result = _require_fields(entry, ["unit_id", "track"], path)
	if not result.is_ok:
		return result
	result = _require_stable_id(entry, "unit_id", path)
	if not result.is_ok:
		return result
	result = _require_enum(entry, "track", TRACKS, path)
	if not result.is_ok:
		return result
	if with_items and entry.has("item_ids"):
		return _validate_stable_id_array(entry, "item_ids", path, 0)
	return AppResult.success()


func _validate_item_stack(stack: Dictionary, container: String, path: String) -> AppResult:
	var result: AppResult = _validate_keyed_object(stack, ITEM_STACK_FIELDS, ["item_id", "count"], path, container)
	if not result.is_ok:
		return result
	result = _require_stable_id(stack, "item_id", path)
	if not result.is_ok:
		return result
	return _require_integer(stack, "count", path, 1)


func _validate_recipe(recipe: Dictionary, path: String) -> AppResult:
	if typeof(recipe) != TYPE_DICTIONARY:
		return _fail(path, "recipe must be an object.")
	var result: AppResult = _reject_unknown_fields(recipe, RECIPE_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(recipe, RECIPE_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_stable_id(recipe, "input_item_id", path)
	if not result.is_ok:
		return result
	result = _require_stable_id(recipe, "output_item_id", path)
	if not result.is_ok:
		return result
	result = _require_integer(recipe, "input_count", path, 1)
	if not result.is_ok:
		return result
	return _require_integer(recipe, "output_count", path, 1)


func _validate_phase(phase: Dictionary, path: String) -> AppResult:
	var result: AppResult = _reject_unknown_fields(phase, PHASE_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_fields(phase, PHASE_FIELDS, path)
	if not result.is_ok:
		return result
	result = _require_stable_id(phase, "id", path)
	if not result.is_ok:
		return result
	result = _optional_number(phase, "at_hp_ratio", path, 0.0, 1.0)
	if not result.is_ok:
		return result
	return _validate_stable_id_array(phase, "action_ids", path, 1)


func _validate_keyed_object(value: Variant, allowed: Array[String], required: Array[String], path: String, container: String) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(path, "%s entries must be objects." % container)
	var result: AppResult = _reject_unknown_fields(value, allowed, path)
	if not result.is_ok:
		return result
	return _require_fields(value, required, path)


func _validate_array(definition: Dictionary, field: String, path: String, minimum_size: int) -> AppResult:
	if typeof(definition[field]) != TYPE_ARRAY:
		return _fail(path, "%s must be an array." % field)
	if minimum_size >= 0 and (definition[field] as Array).size() < minimum_size:
		return _fail(path, "%s must contain at least %d entries." % [field, minimum_size])
	return AppResult.success()


func _validate_stable_id_array(definition: Dictionary, field: String, path: String, minimum_size: int) -> AppResult:
	var result: AppResult = _validate_array(definition, field, path, minimum_size)
	if not result.is_ok:
		return result
	for entry: Variant in definition[field]:
		if typeof(entry) != TYPE_STRING or not _is_stable_id(entry):
			return _fail(path, "%s entries must be stable IDs matching %s." % [field, ID_REGEX_PATTERN])
	return AppResult.success()


func _require_fields(definition: Dictionary, required: Array[String], path: String) -> AppResult:
	for field: String in required:
		if not definition.has(field):
			return _fail(path, "missing required field '%s'." % field)
	return AppResult.success()


func _reject_unknown_fields(definition: Dictionary, allowed: Array[String], path: String) -> AppResult:
	for field: Variant in definition.keys():
		if not allowed.has(str(field)):
			return _fail(path, "unknown field '%s'." % str(field))
	return AppResult.success()


func _require_stable_id(definition: Dictionary, field: String, path: String) -> AppResult:
	if not definition.has(field) or typeof(definition[field]) != TYPE_STRING or not _is_stable_id(definition[field]):
		var received: String = "<missing>"
		if definition.has(field):
			received = str(definition[field])
		return _fail(path, "%s must be a string matching %s (received '%s')." % [field, ID_REGEX_PATTERN, received])
	return AppResult.success()


func _optional_stable_id(definition: Dictionary, field: String, path: String) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	return _require_stable_id(definition, field, path)


func _require_nonempty_string(definition: Dictionary, field: String, path: String) -> AppResult:
	if typeof(definition[field]) != TYPE_STRING or (definition[field] as String).is_empty():
		return _fail(path, "%s must be a non-empty string." % field)
	return AppResult.success()


func _optional_nonempty_string(definition: Dictionary, field: String, path: String) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	return _require_nonempty_string(definition, field, path)


func _optional_string(definition: Dictionary, field: String, path: String) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	if typeof(definition[field]) != TYPE_STRING:
		return _fail(path, "%s must be a string." % field)
	return AppResult.success()


func _require_enum(definition: Dictionary, field: String, allowed: Array[String], path: String) -> AppResult:
	var value: Variant = definition[field]
	if typeof(value) != TYPE_STRING or not allowed.has(value):
		return _fail(path, "%s must be one of: %s." % [field, ", ".join(PackedStringArray(allowed))])
	return AppResult.success()


func _optional_enum(definition: Dictionary, field: String, allowed: Array[String], path: String) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	return _require_enum(definition, field, allowed, path)


func _require_integer(definition: Dictionary, field: String, path: String, minimum: int, maximum: int = -1) -> AppResult:
	if not definition.has(field):
		return _fail(path, "missing required field '%s'." % field)
	var integral: Variant = _as_integral(definition[field])
	if integral == null:
		return _fail(path, "%s must be an integer." % field)
	var value: int = integral
	if value < minimum or (maximum >= 0 and value > maximum):
		if maximum >= 0:
			return _fail(path, "%s must be between %d and %d." % [field, minimum, maximum])
		return _fail(path, "%s must be at least %d." % [field, minimum])
	return AppResult.success()


func _optional_integer(definition: Dictionary, field: String, path: String, minimum: int, maximum: int = -1) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	return _require_integer(definition, field, path, minimum, maximum)


func _optional_number(definition: Dictionary, field: String, path: String, minimum: float, maximum: float) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	var value: Variant = definition[field]
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return _fail(path, "%s must be a number." % field)
	var number: float = float(value)
	if not is_finite(number) or number < minimum or number > maximum:
		return _fail(path, "%s must be between %s and %s." % [field, String.num(minimum, 3), String.num(maximum, 3)])
	return AppResult.success()


func _optional_bool(definition: Dictionary, field: String, path: String) -> AppResult:
	if not definition.has(field):
		return AppResult.success()
	if typeof(definition[field]) != TYPE_BOOL:
		return _fail(path, "%s must be a boolean." % field)
	return AppResult.success()


func _as_integral(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		if is_finite(number) and number == floor(number):
			return int(number)
	return null


func _is_stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_REGEX_PATTERN)
	return _id_regex.search(value) != null


func _fail(path: String, reason: String) -> AppResult:
	return AppResult.failure("invalid_definition", "%s: %s" % [path, reason])


func _check_ref(bucket: Dictionary, ref_id: Variant, label: String, source: String, dangling: Array[String]) -> void:
	if typeof(ref_id) != TYPE_STRING or not bucket.has(ref_id):
		dangling.append("%s references missing %s '%s'" % [source, label, str(ref_id)])


func _compute_content_hash() -> String:
	var total: int = _items.size() + _buildings.size() + _combat_units.size() + _combat_actions.size() + _events.size() + _encounters.size()
	if total == 0:
		return ""
	var organized: Dictionary = {
		CATEGORY_ITEMS: _items,
		CATEGORY_BUILDINGS: _buildings,
		CATEGORY_COMBAT_UNITS: _combat_units,
		CATEGORY_COMBAT_ACTIONS: _combat_actions,
		CATEGORY_EVENTS: _events,
		CATEGORY_ENCOUNTERS: _encounters,
	}
	return _canonical_json(organized).sha256_text()


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value), "", true, true)


func _canonicalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array[String] = []
			for raw_key: Variant in source.keys():
				keys.append(str(raw_key))
			keys.sort()
			var ordered: Dictionary = {}
			for key: String in keys:
				ordered[key] = _canonicalize(source[key])
			return ordered
		TYPE_ARRAY:
			var entries: Array = []
			for entry: Variant in value:
				entries.append(_canonicalize(entry))
			return entries
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and number == floor(number):
				return int(number)
			return number
		_:
			return value
