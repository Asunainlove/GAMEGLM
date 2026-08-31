extends GutTest

## WP12 content data pack tests (frozen contract v1, section 7).
## Loads the real content pack under res://data, asserts per-file schema
## semantics (required fields, stable-ID regex, enums), cross references
## (items / actions / units / encounters / events), verbatim section-7
## parameters, pack counts, and that the merged production validators
## (ContentDB bootstrap + validate_refs) accept the whole pack.
## Also proves the CombatEngine migration-point shape: base action_ids plus
## phases[{id, at_hp_ratio, action_ids}] drive the boss phase switch and
## sandbox items flow through the item-action cost path.

const DATA_ROOT: String = "res://data"
const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"
const ID_REGEX_PATTERN: String = "^[a-z][a-z0-9_]*$"

const EXPECTED_ITEM_IDS: Array[String] = [
	"starsoil_dust", "lumen_shard", "resonant_core", "echo_seed", "sedative_mist", "shock_trap",
]
const EXPECTED_BUILDING_IDS: Array[String] = [
	"anchor_block", "anchor_workshop", "dust_refiner", "stabilizer_pylon", "resonance_loom", "echo_chamber",
]
const EXPECTED_UNIT_IDS: Array[String] = [
	"luoxian_fighter", "misa_weaver", "drift_swarmling", "shard_husk", "veinwarden_echo", "lumen_leviathan",
]
const EXPECTED_ACTION_IDS: Array[String] = [
	"strike", "guard", "resonate_pulse", "thread_bind", "shard_jolt",
	"vein_quake", "lumen_surge", "mist_calm", "trap_snap",
]
const EXPECTED_ENCOUNTER_IDS: Array[String] = [
	"encounter_first_drift", "encounter_husk_ambush", "encounter_leviathan",
]
const EXPECTED_EVENT_IDS: Array[String] = [
	"event_prologue_landing", "event_first_mining", "event_first_anchor",
	"event_workshop_guide", "event_station_mode", "event_approach",
	"event_policy", "event_leviathan_pact", "event_ending_luoxian", "event_ending_misa",
]
const FROZEN_CHOICE_FLAGS: Array[String] = [
	"station_mode_exploit", "station_mode_seal", "station_mode_symbiosis",
	"approach_direct", "approach_diplomatic",
	"policy_extraction_quota", "policy_sanctuary",
]
const ITEM_KINDS: Array[String] = ["material", "story_core", "sandbox_item"]
const BUILDING_KINDS: Array[String] = ["building"]
const UNIT_KINDS: Array[String] = ["ally", "enemy_normal", "enemy_elite", "boss"]
const ACTION_KINDS: Array[String] = ["attack", "skill", "item", "guard", "destabilize"]
const EVENT_KINDS: Array[String] = ["dialogue", "choice", "mixed"]
const TRACKS: Array[String] = ["front", "mid", "rear"]
const TARGETINGS: Array[String] = ["self", "single_ally", "single_enemy", "all_enemies"]
const RELATION_DIMS: Array[String] = ["affection", "trust", "ideology"]
const CHARACTER_IDS: Array[String] = ["luoxian", "misa"]

## Ally sandbox item loadouts per encounter, expressed as occurrence counts
## of the ally's item_ids array (each occurrence carries one unit of the item).
const EXPECTED_ALLY_ITEM_COUNTS: Dictionary = {
	"encounter_first_drift": {"sedative_mist": 1},
	"encounter_husk_ambush": {"sedative_mist": 1, "shock_trap": 1},
	"encounter_leviathan": {"sedative_mist": 2, "shock_trap": 1},
}


var _items: Array = []
var _buildings: Array = []
var _units: Array = []
var _actions: Array = []
var _encounters: Array = []
var _events_by_id: Dictionary = {}
var _load_failures: Array[String] = []
var _id_regex: RegEx = null


func before_all() -> void:
	_id_regex = RegEx.create_from_string(ID_REGEX_PATTERN)
	_items = _load_pack_array("content/items.json")
	_buildings = _load_pack_array("content/buildings.json")
	_units = _load_pack_array("content/combat_units.json")
	_actions = _load_pack_array("content/combat_actions.json")
	_encounters = _load_pack_array("encounters/encounters.json")
	_load_events()


# --- 加载 -----------------------------------------------------------------------


func test_all_pack_files_exist_and_parse() -> void:
	assert_eq(_load_failures, [] as Array[String], "every data file must exist and parse as JSON")


func _load_pack_array(relative_path: String) -> Array:
	var path := DATA_ROOT.path_join(relative_path)
	if not FileAccess.file_exists(path):
		_add_load_failure("%s: file is missing (WP12 must deliver it)." % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_add_load_failure("%s: invalid JSON at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return []
	var parsed: Variant = parser.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		_fail("%s: content must be a JSON array of definitions." % path)
		return []
	for entry: Variant in parsed as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			_fail("%s: every definition must be a JSON object." % path)
			return []
	var normalized: Array = _normalize_numbers(parsed)
	return normalized


## Godot's JSON parser yields floats for every numeric literal; fold integral
## floats back into ints so verbatim parameter comparisons compare int to int.
func _normalize_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var out: Dictionary = {}
			for key: Variant in source:
				out[str(key)] = _normalize_numbers(source[key])
			return out
		TYPE_ARRAY:
			var source_array: Array = value
			var out_array: Array = []
			for element: Variant in source_array:
				out_array.append(_normalize_numbers(element))
			return out_array
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and number == floorf(number):
				return int(number)
			return number
		_:
			return value


func _load_events() -> void:
	var dir := DirAccess.open(DATA_ROOT.path_join("events"))
	if dir == null:
		_add_load_failure("%s: events directory is missing (WP12 must deliver it)." % DATA_ROOT.path_join("events"))
		return
	var file_names: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			file_names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	for file_name: String in file_names:
		var path := DATA_ROOT.path_join("events").path_join(file_name)
		var text := FileAccess.get_file_as_string(path)
		var parser := JSON.new()
		if parser.parse(text) != OK:
			_add_load_failure("%s: invalid JSON at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
			continue
		var parsed: Variant = parser.get_data()
		if typeof(parsed) != TYPE_DICTIONARY:
			_add_load_failure("%s: EventRunner requires one JSON object per event file." % path)
			continue
		var event_def: Dictionary = parsed
		var event_id := str(event_def.get("id", ""))
		if event_id.is_empty():
			_add_load_failure("%s: event file is missing an id." % path)
			continue
		if _events_by_id.has(event_id):
			_fail("%s: duplicate event id '%s'." % [path, event_id])
			continue
		_events_by_id[event_id] = _normalize_numbers(event_def)


func _add_load_failure(message: String) -> void:
	_load_failures.append(message)


# --- 通用校验辅助 -----------------------------------------------------------------


func _assert_stable_id(value: Variant, context: String) -> void:
	if typeof(value) != TYPE_STRING:
		assert_true(false, "%s: expected a stable-id string, got type %d." % [context, typeof(value)])
		return
	assert_true(
		_id_regex.search(value as String) != null,
		"%s: id '%s' must match %s." % [context, value, ID_REGEX_PATTERN]
	)


func _assert_nonempty_string(def: Dictionary, field: String, context: String) -> void:
	var value: Variant = def.get(field)
	assert_true(
		typeof(value) == TYPE_STRING and not (value as String).is_empty(),
		"%s: field '%s' must be a non-empty string (got '%s')." % [context, field, str(value)]
	)


func _assert_int(def: Dictionary, field: String, minimum: int, maximum: int, context: String) -> void:
	var value: Variant = def.get(field)
	var is_number := typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
	var in_range: bool = is_number and int(value) >= minimum and (maximum < 0 or int(value) <= maximum)
	var bound := ">= %d" % minimum if maximum < 0 else "in [%d, %d]" % [minimum, maximum]
	assert_true(in_range, "%s: field '%s' must be an integer %s (got '%s')." % [context, field, bound, str(value)])


func _assert_enum(def: Dictionary, field: String, allowed: Array[String], context: String) -> void:
	var value: Variant = def.get(field)
	assert_true(
		typeof(value) == TYPE_STRING and allowed.has(value as String),
		"%s: field '%s' must be one of %s (got '%s')." % [context, field, str(allowed), str(value)]
	)


func _assert_optional_bool(def: Dictionary, field: String, context: String) -> void:
	if not def.has(field):
		return
	assert_true(
		typeof(def[field]) == TYPE_BOOL,
		"%s: field '%s' must be a boolean (got '%s')." % [context, field, str(def[field])]
	)


func _assert_entry_present(entries: Array, id: String, pack_label: String) -> Dictionary:
	var found := _by_id(entries, id)
	assert_false(found.is_empty(), "%s: definition '%s' must exist." % [pack_label, id])
	return found


func _by_id(entries: Array, id: String) -> Dictionary:
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("id", "")) == id:
			return entry as Dictionary
	return {}


func _defs_by_id(entries: Array) -> Dictionary:
	var defs: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			var def: Dictionary = entry
			defs[str(def.get("id", ""))] = def
	return defs


func _assert_unique_ids(entries: Array, pack_label: String) -> void:
	var seen: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := str((entry as Dictionary).get("id", ""))
		assert_false(seen.has(id), "%s: id '%s' must not be duplicated." % [pack_label, id])
		seen.append(id)


# --- 物品 data/content/items.json -------------------------------------------------


func test_items_pack_count_and_schema() -> void:
	assert_eq(_items.size(), 6, "items.json must contain exactly 6 items (contract §7).")
	_assert_unique_ids(_items, "items.json")
	for entry: Variant in _items:
		var item: Dictionary = entry
		var context := "items.json[%s]" % str(item.get("id", "?"))
		_assert_stable_id(item.get("id"), context + ".id")
		_assert_enum(item, "kind", ITEM_KINDS, context)
		_assert_nonempty_string(item, "name_zh", context)
		_assert_nonempty_string(item, "desc_zh", context)
		_assert_int(item, "stack_limit", 1, 999, context)
		if item.has("tier"):
			_assert_int(item, "tier", 0, 9, context)
		_assert_optional_bool(item, "battle_usable", context)


func test_items_match_contract_section7() -> void:
	var dust := _assert_entry_present(_items, "starsoil_dust", "items.json")
	assert_eq(str(dust.get("kind", "")), "material", "starsoil_dust kind")
	assert_eq(int(dust.get("stack_limit", -1)), 99, "starsoil_dust stack_limit")
	assert_eq(int(dust.get("tier", -1)), 0, "starsoil_dust tier")
	assert_false(bool(dust.get("battle_usable", false)), "starsoil_dust is not battle usable")

	var shard := _assert_entry_present(_items, "lumen_shard", "items.json")
	assert_eq(str(shard.get("kind", "")), "material", "lumen_shard kind")
	assert_eq(int(shard.get("stack_limit", -1)), 99, "lumen_shard stack_limit")
	assert_eq(int(shard.get("tier", -1)), 1, "lumen_shard tier")

	var core := _assert_entry_present(_items, "resonant_core", "items.json")
	assert_eq(str(core.get("kind", "")), "material", "resonant_core kind")
	assert_eq(int(core.get("stack_limit", -1)), 99, "resonant_core stack_limit")
	assert_eq(int(core.get("tier", -1)), 2, "resonant_core tier")

	var seed := _assert_entry_present(_items, "echo_seed", "items.json")
	assert_eq(str(seed.get("kind", "")), "story_core", "echo_seed kind")
	assert_eq(int(seed.get("stack_limit", -1)), 1, "echo_seed stack_limit")
	assert_eq(int(seed.get("tier", -1)), 3, "echo_seed tier")

	var mist := _assert_entry_present(_items, "sedative_mist", "items.json")
	assert_eq(str(mist.get("kind", "")), "sandbox_item", "sedative_mist kind")
	assert_eq(int(mist.get("stack_limit", -1)), 9, "sedative_mist stack_limit")
	assert_true(bool(mist.get("battle_usable", false)), "sedative_mist battle_usable must be true")

	var trap := _assert_entry_present(_items, "shock_trap", "items.json")
	assert_eq(str(trap.get("kind", "")), "sandbox_item", "shock_trap kind")
	assert_eq(int(trap.get("stack_limit", -1)), 9, "shock_trap stack_limit")
	assert_true(bool(trap.get("battle_usable", false)), "shock_trap battle_usable must be true")

	for id: String in EXPECTED_ITEM_IDS:
		assert_has(_ids_of(_items), id, "items.json must define contract §7 item '%s'." % id)


# --- 建筑 data/content/buildings.json ---------------------------------------------


func test_buildings_pack_count_and_schema() -> void:
	assert_eq(_buildings.size(), 6, "buildings.json must contain exactly 6 buildings (contract §7).")
	_assert_unique_ids(_buildings, "buildings.json")
	for entry: Variant in _buildings:
		var building: Dictionary = entry
		var context := "buildings.json[%s]" % str(building.get("id", "?"))
		_assert_stable_id(building.get("id"), context + ".id")
		_assert_enum(building, "kind", BUILDING_KINDS, context)
		_assert_nonempty_string(building, "name_zh", context)
		_assert_nonempty_string(building, "desc_zh", context)
		assert_true(
			typeof(building.get("inputs")) == TYPE_ARRAY,
			"%s: inputs must be an array." % context
		)
		for stack: Variant in building.get("inputs", []) as Array:
			assert_true(typeof(stack) == TYPE_DICTIONARY, "%s: inputs entries must be objects." % context)
			if typeof(stack) == TYPE_DICTIONARY:
				_assert_stable_id((stack as Dictionary).get("item_id"), context + ".inputs.item_id")
				_assert_int(stack as Dictionary, "count", 1, -1, context + ".inputs")
		if building.has("recipe"):
			var recipe: Dictionary = building.get("recipe", {})
			_assert_stable_id(recipe.get("input_item_id"), context + ".recipe.input_item_id")
			_assert_stable_id(recipe.get("output_item_id"), context + ".recipe.output_item_id")
			_assert_int(recipe, "input_count", 1, -1, context + ".recipe")
			_assert_int(recipe, "output_count", 1, -1, context + ".recipe")
			if recipe.has("extra_input_item_id") or recipe.has("extra_input_count"):
				_assert_stable_id(recipe.get("extra_input_item_id"), context + ".recipe.extra_input_item_id")
				_assert_int(recipe, "extra_input_count", 1, -1, context + ".recipe")
		# W002-GAP4：recipes 数组（元素形状同 recipe，含可选第二输入）。
		if building.has("recipes"):
			assert_true(
				typeof(building.get("recipes")) == TYPE_ARRAY and (building["recipes"] as Array).size() >= 1,
				"%s: recipes must be a non-empty array." % context
			)
			for recipe_entry: Variant in building.get("recipes", []) as Array:
				assert_true(typeof(recipe_entry) == TYPE_DICTIONARY, "%s: recipes entries must be objects." % context)
				if typeof(recipe_entry) != TYPE_DICTIONARY:
					continue
				var recipe_def: Dictionary = recipe_entry
				_assert_stable_id(recipe_def.get("input_item_id"), context + ".recipes.input_item_id")
				_assert_stable_id(recipe_def.get("output_item_id"), context + ".recipes.output_item_id")
				_assert_int(recipe_def, "input_count", 1, -1, context + ".recipes")
				_assert_int(recipe_def, "output_count", 1, -1, context + ".recipes")
				if recipe_def.has("extra_input_item_id") or recipe_def.has("extra_input_count"):
					_assert_stable_id(recipe_def.get("extra_input_item_id"), context + ".recipes.extra_input_item_id")
					_assert_int(recipe_def, "extra_input_count", 1, -1, context + ".recipes")
		_assert_optional_bool(building, "requires_room", context)
		_assert_int(building, "power_draw", 0, -1, context)
		_assert_int(building, "power_supply", 0, -1, context)
		if building.has("effect_flag"):
			_assert_stable_id(building.get("effect_flag"), context + ".effect_flag")


func test_buildings_match_contract_section7() -> void:
	for id: String in EXPECTED_BUILDING_IDS:
		assert_has(_ids_of(_buildings), id, "buildings.json must define contract §7 building '%s'." % id)

	var anchor := _assert_entry_present(_buildings, "anchor_block", "buildings.json")
	assert_eq(
		str(anchor.get("inputs", [])),
		str([{"item_id": "starsoil_dust", "count": 2}]),
		"anchor_block inputs must be starsoil_dust x2."
	)
	# W002-GAP4（D2）：锚块基础供能 2 点，参与全站供电平衡。
	assert_eq(int(anchor.get("power_supply", -1)), 2, "anchor_block power_supply must be 2 (D2).")

	var workshop := _assert_entry_present(_buildings, "anchor_workshop", "buildings.json")
	assert_eq(
		str(workshop.get("inputs", [])),
		str([{"item_id": "starsoil_dust", "count": 4}]),
		"anchor_workshop inputs must be starsoil_dust x4."
	)
	# W002-GAP4（D2）合法断言更新：供电平衡裁定 10 -> 16（evidence 布局计算）。
	assert_eq(int(workshop.get("power_supply", -1)), 16, "anchor_workshop power_supply must be 16 (D2).")

	var refiner := _assert_entry_present(_buildings, "dust_refiner", "buildings.json")
	assert_eq(int(refiner.get("power_draw", -1)), 4, "dust_refiner power_draw must be 4.")
	assert_eq(
		str(refiner.get("recipe", {})),
		str({"input_item_id": "starsoil_dust", "input_count": 3, "output_item_id": "resonant_core", "output_count": 1}),
		"dust_refiner recipe must be 3x starsoil_dust -> 1x resonant_core."
	)

	var pylon := _assert_entry_present(_buildings, "stabilizer_pylon", "buildings.json")
	assert_eq(
		str(pylon.get("inputs", [])),
		str([{"item_id": "lumen_shard", "count": 1}, {"item_id": "resonant_core", "count": 1}]),
		"stabilizer_pylon inputs must be lumen_shard x1 + resonant_core x1."
	)
	assert_eq(int(pylon.get("power_draw", -1)), 6, "stabilizer_pylon power_draw must be 6.")
	assert_eq(str(pylon.get("effect_flag", "")), "pylon_stabilized", "stabilizer_pylon effect_flag (§7).")

	var loom := _assert_entry_present(_buildings, "resonance_loom", "buildings.json")
	assert_eq(
		str(loom.get("inputs", [])),
		str([{"item_id": "resonant_core", "count": 1}]),
		"resonance_loom inputs must be resonant_core x1."
	)
	assert_eq(int(loom.get("power_draw", -1)), 5, "resonance_loom power_draw must be 5.")
	# W002-GAP4（D3）合法断言更新：织机改为 recipes 数组承载契约 §7 的两条配方。
	var loom_recipes: Array = loom.get("recipes", []) as Array
	assert_eq(loom_recipes.size(), 2, "resonance_loom must carry both §7 recipes.")
	if loom_recipes.size() == 2:
		assert_eq(
			str(loom_recipes[0]),
			str({"input_item_id": "lumen_shard", "input_count": 2, "output_item_id": "sedative_mist", "output_count": 1}),
			"resonance_loom recipe 1 must be 2x lumen_shard -> 1x sedative_mist."
		)
		assert_eq(
			str(loom_recipes[1]),
			str({
				"input_item_id": "lumen_shard", "input_count": 2,
				"extra_input_item_id": "resonant_core", "extra_input_count": 1,
				"output_item_id": "shock_trap", "output_count": 1,
			}),
			"resonance_loom recipe 2 must be 2x lumen_shard + 1x resonant_core -> 1x shock_trap (§7)."
		)
	assert_false(loom.has("recipe"), "loom uses the recipes array; the single recipe field is retired for it.")

	var chamber := _assert_entry_present(_buildings, "echo_chamber", "buildings.json")
	assert_eq(
		str(chamber.get("inputs", [])),
		str([{"item_id": "resonant_core", "count": 2}]),
		"echo_chamber inputs must be resonant_core x2."
	)
	assert_eq(int(chamber.get("power_draw", -1)), 8, "echo_chamber power_draw must be 8.")
	assert_true(bool(chamber.get("requires_room", false)), "echo_chamber requires_room must be true.")
	assert_eq(str(chamber.get("effect_flag", "")), "echo_chamber_active", "echo_chamber effect_flag (§7).")


# --- 行动 data/content/combat_actions.json ----------------------------------------


func test_actions_pack_count_and_schema() -> void:
	assert_eq(_actions.size(), 9, "combat_actions.json must contain exactly 9 actions.")
	_assert_unique_ids(_actions, "combat_actions.json")
	for entry: Variant in _actions:
		var action: Dictionary = entry
		var context := "combat_actions.json[%s]" % str(action.get("id", "?"))
		_assert_stable_id(action.get("id"), context + ".id")
		_assert_enum(action, "kind", ACTION_KINDS, context)
		_assert_nonempty_string(action, "name_zh", context)
		_assert_enum(action, "targeting", TARGETINGS, context)
		_assert_int(action, "power", 0, -1, context)
		_assert_int(action, "stability_damage", 0, -1, context)
		if action.has("cost") and action.get("cost") != null:
			var cost: Dictionary = action.get("cost", {})
			_assert_stable_id(cost.get("item_id"), context + ".cost.item_id")
			_assert_int(cost, "count", 1, -1, context + ".cost")
		if action.has("heal"):
			_assert_int(action, "heal", 0, -1, context)
		if action.has("guard_ratio"):
			assert_true(
				typeof(action["guard_ratio"]) == TYPE_FLOAT or typeof(action["guard_ratio"]) == TYPE_INT,
				"%s: guard_ratio must be a number." % context
			)


func test_actions_match_contract_section7() -> void:
	for id: String in EXPECTED_ACTION_IDS:
		assert_has(_ids_of(_actions), id, "combat_actions.json must define contract §7 action '%s'." % id)

	var expected_params: Dictionary = {
		"strike": {"kind": "attack", "targeting": "single_enemy", "power": 6, "stability_damage": 2},
		"guard": {"kind": "guard", "targeting": "self", "power": 0, "stability_damage": 0, "guard_ratio": 0.5},
		"resonate_pulse": {"kind": "destabilize", "targeting": "single_enemy", "power": 4, "stability_damage": 5},
		"thread_bind": {"kind": "skill", "targeting": "single_enemy", "power": 3, "stability_damage": 3},
		"shard_jolt": {"kind": "attack", "targeting": "single_enemy", "power": 5, "stability_damage": 3},
		"vein_quake": {"kind": "attack", "targeting": "all_enemies", "power": 7, "stability_damage": 4},
		"lumen_surge": {"kind": "attack", "targeting": "all_enemies", "power": 9, "stability_damage": 5},
	}
	for id: String in expected_params:
		var action := _assert_entry_present(_actions, id, "combat_actions.json")
		var params: Dictionary = expected_params[id]
		for field: String in params:
			assert_eq(
				action.get(field), params[field],
				"action '%s' field '%s' must match contract §7." % [id, field]
			)

	var mist_calm := _assert_entry_present(_actions, "mist_calm", "combat_actions.json")
	assert_eq(str(mist_calm.get("kind", "")), "item", "mist_calm kind")
	assert_eq(str(mist_calm.get("targeting", "")), "single_ally", "mist_calm targeting")
	assert_eq(int(mist_calm.get("heal", -1)), 12, "mist_calm heal must be 12.")
	assert_eq(
		str(mist_calm.get("cost", {})),
		str({"item_id": "sedative_mist", "count": 1}),
		"mist_calm cost must be 1x sedative_mist."
	)

	var trap_snap := _assert_entry_present(_actions, "trap_snap", "combat_actions.json")
	assert_eq(str(trap_snap.get("kind", "")), "item", "trap_snap kind")
	assert_eq(str(trap_snap.get("targeting", "")), "single_enemy", "trap_snap targeting")
	assert_eq(int(trap_snap.get("power", -1)), 10, "trap_snap power must be 10.")
	assert_eq(int(trap_snap.get("stability_damage", -1)), 6, "trap_snap stability_damage must be 6.")
	assert_eq(
		str(trap_snap.get("cost", {})),
		str({"item_id": "shock_trap", "count": 1}),
		"trap_snap cost must be 1x shock_trap."
	)


# --- 单位 data/content/combat_units.json -------------------------------------------


func test_units_pack_count_and_schema() -> void:
	assert_eq(_units.size(), 6, "combat_units.json must contain exactly 6 units (contract §7).")
	_assert_unique_ids(_units, "combat_units.json")
	for entry: Variant in _units:
		var unit: Dictionary = entry
		var context := "combat_units.json[%s]" % str(unit.get("id", "?"))
		_assert_stable_id(unit.get("id"), context + ".id")
		_assert_enum(unit, "kind", UNIT_KINDS, context)
		_assert_nonempty_string(unit, "name_zh", context)
		_assert_int(unit, "max_hp", 1, -1, context)
		_assert_int(unit, "stability_max", 1, -1, context)
		_assert_enum(unit, "track", TRACKS, context)
		_assert_int(unit, "speed", 1, -1, context)
		assert_true(
			typeof(unit.get("action_ids")) == TYPE_ARRAY and (unit.get("action_ids", []) as Array).size() >= 1,
			"%s: action_ids must be a non-empty array." % context
		)
		for action_id: Variant in unit.get("action_ids", []) as Array:
			_assert_stable_id(action_id, context + ".action_ids")
		assert_true(
			(unit.get("phases", []) as Array).size() <= 2,
			"%s: phases must contain at most 2 entries." % context
		)
		for phase: Variant in unit.get("phases", []) as Array:
			assert_true(typeof(phase) == TYPE_DICTIONARY, "%s: phases entries must be objects." % context)
			if typeof(phase) != TYPE_DICTIONARY:
				continue
			var phase_def: Dictionary = phase
			_assert_stable_id(phase_def.get("id"), context + ".phase.id")
			assert_true(
				typeof(phase_def.get("at_hp_ratio")) == TYPE_FLOAT or typeof(phase_def.get("at_hp_ratio")) == TYPE_INT,
				"%s: phase at_hp_ratio must be a number." % context
			)
			assert_true(
				typeof(phase_def.get("action_ids")) == TYPE_ARRAY
				and (phase_def.get("action_ids", []) as Array).size() >= 1,
				"%s: phase action_ids must be a non-empty array." % context
			)
			for action_id: Variant in phase_def.get("action_ids", []) as Array:
				_assert_stable_id(action_id, context + ".phase.action_ids")
		for drop: Variant in unit.get("drops", []) as Array:
			assert_true(typeof(drop) == TYPE_DICTIONARY, "%s: drops entries must be objects." % context)
			if typeof(drop) != TYPE_DICTIONARY:
				continue
			var drop_def: Dictionary = drop
			_assert_stable_id(drop_def.get("item_id"), context + ".drops.item_id")
			_assert_int(drop_def, "amount", 1, -1, context + ".drops")


func test_units_match_contract_section7() -> void:
	for id: String in EXPECTED_UNIT_IDS:
		assert_has(_ids_of(_units), id, "combat_units.json must define contract §7 unit '%s'." % id)

	var expected_units: Dictionary = {
		"luoxian_fighter": {
			"kind": "ally", "track": "front", "max_hp": 40, "stability_max": 10, "speed": 6,
			"action_ids": ["strike", "guard", "resonate_pulse"],
		},
		"misa_weaver": {
			"kind": "ally", "track": "mid", "max_hp": 30, "stability_max": 12, "speed": 5,
			"action_ids": ["thread_bind", "guard", "mist_calm", "trap_snap"],
		},
		"drift_swarmling": {
			"kind": "enemy_normal", "track": "front", "max_hp": 12, "stability_max": 6, "speed": 4,
			"action_ids": ["strike"],
			"drops": [{"item_id": "starsoil_dust", "amount": 2}],
		},
		"shard_husk": {
			"kind": "enemy_normal", "track": "mid", "max_hp": 18, "stability_max": 8, "speed": 5,
			"action_ids": ["strike", "shard_jolt"],
			"drops": [
				{"item_id": "starsoil_dust", "amount": 1},
				{"item_id": "lumen_shard", "amount": 1},
				{"item_id": "shock_trap", "amount": 1},
			],
		},
		"veinwarden_echo": {
			"kind": "enemy_elite", "track": "mid", "max_hp": 30, "stability_max": 10, "speed": 6,
			"action_ids": ["strike", "vein_quake", "guard"],
			"drops": [{"item_id": "lumen_shard", "amount": 2}],
		},
		"lumen_leviathan": {
			"kind": "boss", "track": "front", "max_hp": 60, "stability_max": 12, "speed": 7,
			"action_ids": ["strike", "vein_quake"],
			"phases": [{
				"id": "leviathan_p1", "at_hp_ratio": 0.5,
				"action_ids": ["lumen_surge", "vein_quake", "strike"],
			}],
			"drops": [{"item_id": "echo_seed", "amount": 1}, {"item_id": "resonant_core", "amount": 2}],
		},
	}
	for id: String in expected_units:
		var unit := _assert_entry_present(_units, id, "combat_units.json")
		var params: Dictionary = expected_units[id]
		for field: String in params:
			assert_eq(
				unit.get(field), params[field],
				"unit '%s' field '%s' must match contract §7 / task spec." % [id, field]
			)

	for enemy_id: String in ["drift_swarmling", "shard_husk", "veinwarden_echo", "lumen_leviathan"]:
		var enemy := _assert_entry_present(_units, enemy_id, "combat_units.json")
		assert_has(
			enemy.get("action_ids", []) as Array, "strike",
			"enemy '%s' action pool must contain a no-cost action (strike)." % enemy_id
		)


# --- 遭遇 data/encounters/encounters.json ------------------------------------------


func test_encounters_pack_count_and_schema() -> void:
	assert_eq(_encounters.size(), 3, "encounters.json must contain exactly 3 encounters (contract §7).")
	_assert_unique_ids(_encounters, "encounters.json")
	for entry: Variant in _encounters:
		var encounter: Dictionary = entry
		var context := "encounters.json[%s]" % str(encounter.get("id", "?"))
		_assert_stable_id(encounter.get("id"), context + ".id")
		_assert_nonempty_string(encounter, "name_zh", context)
		_assert_stable_id(encounter.get("trigger_flag"), context + ".trigger_flag")
		if encounter.has("on_victory_flag"):
			_assert_stable_id(encounter.get("on_victory_flag"), context + ".on_victory_flag")
		assert_true(
			typeof(encounter.get("allies")) == TYPE_ARRAY and (encounter.get("allies", []) as Array).size() >= 1,
			"%s: allies must be a non-empty array." % context
		)
		for ally: Variant in encounter.get("allies", []) as Array:
			if typeof(ally) != TYPE_DICTIONARY:
				assert_true(false, "%s: allies entries must be objects." % context)
				continue
			var ally_def: Dictionary = ally
			_assert_stable_id(ally_def.get("unit_id"), context + ".allies.unit_id")
			_assert_enum(ally_def, "track", TRACKS, context + ".allies")
			for item_id: Variant in ally_def.get("item_ids", []) as Array:
				_assert_stable_id(item_id, context + ".allies.item_ids")
		assert_true(
			typeof(encounter.get("enemies")) == TYPE_ARRAY and (encounter.get("enemies", []) as Array).size() >= 1,
			"%s: enemies must be a non-empty array." % context
		)
		for enemy: Variant in encounter.get("enemies", []) as Array:
			if typeof(enemy) != TYPE_DICTIONARY:
				assert_true(false, "%s: enemies entries must be objects." % context)
				continue
			var enemy_def: Dictionary = enemy
			_assert_stable_id(enemy_def.get("unit_id"), context + ".enemies.unit_id")
			_assert_enum(enemy_def, "track", TRACKS, context + ".enemies")
		_assert_int(encounter, "seed", 0, -1, context)


func test_encounters_match_contract_section7() -> void:
	for id: String in EXPECTED_ENCOUNTER_IDS:
		assert_has(_ids_of(_encounters), id, "encounters.json must define contract §7 encounter '%s'." % id)

	var first_drift := _assert_entry_present(_encounters, "encounter_first_drift", "encounters.json")
	assert_eq(str(first_drift.get("trigger_flag", "")), "encounter_first_drift_due", "first_drift trigger_flag (§7).")
	assert_eq(str(first_drift.get("on_victory_flag", "")), "encounter_first_drift_won", "first_drift on_victory_flag.")
	assert_eq(int(first_drift.get("seed", -1)), 1001, "first_drift seed must be 1001.")
	assert_eq(
		str(first_drift.get("enemies", [])),
		str([{"unit_id": "drift_swarmling", "track": "front"}, {"unit_id": "drift_swarmling", "track": "front"}]),
		"first_drift enemies must be drift_swarmling x2 on front."
	)

	var husk := _assert_entry_present(_encounters, "encounter_husk_ambush", "encounters.json")
	assert_eq(str(husk.get("trigger_flag", "")), "encounter_husk_ambush_due", "husk_ambush trigger_flag (§7).")
	assert_eq(str(husk.get("on_victory_flag", "")), "encounter_husk_ambush_won", "husk_ambush on_victory_flag.")
	assert_eq(int(husk.get("seed", -1)), 1002, "husk_ambush seed must be 1002.")
	# W002-GAP4（C3）合法断言更新：精英 veinwarden_echo 替换 drift_swarmling 上场，
	# 使章程锁定的"一个精英"不再是死内容（evidence 有符合性说明）。
	assert_eq(
		str(husk.get("enemies", [])),
		str([{"unit_id": "shard_husk", "track": "mid"}, {"unit_id": "veinwarden_echo", "track": "mid"}]),
		"husk_ambush enemies must be shard_husk (mid) + veinwarden_echo (mid, elite)."
	)

	var leviathan := _assert_entry_present(_encounters, "encounter_leviathan", "encounters.json")
	assert_eq(str(leviathan.get("trigger_flag", "")), "encounter_leviathan_due", "leviathan trigger_flag (§7).")
	assert_eq(str(leviathan.get("on_victory_flag", "")), "encounter_leviathan_won", "leviathan on_victory_flag.")
	assert_eq(int(leviathan.get("seed", -1)), 1003, "leviathan seed must be 1003.")
	assert_eq(
		str(leviathan.get("enemies", [])),
		str([{"unit_id": "lumen_leviathan", "track": "front"}]),
		"leviathan enemy must be lumen_leviathan on front."
	)

	for entry: Variant in _encounters:
		var encounter: Dictionary = entry
		var encounter_id := str(encounter.get("id", ""))
		var allies: Array = encounter.get("allies", [])
		assert_eq(allies.size(), 2, "%s must field both allies." % encounter_id)
		if allies.size() < 2:
			continue
		var luoxian: Dictionary = allies[0]
		var misa: Dictionary = allies[1]
		assert_eq(str(luoxian.get("unit_id", "")), "luoxian_fighter", "%s ally 1 is luoxian_fighter." % encounter_id)
		assert_eq(str(luoxian.get("track", "")), "front", "%s luoxian_fighter on front." % encounter_id)
		assert_eq(str(misa.get("unit_id", "")), "misa_weaver", "%s ally 2 is misa_weaver." % encounter_id)
		assert_eq(str(misa.get("track", "")), "mid", "%s misa_weaver on mid." % encounter_id)
		var expected: Dictionary = EXPECTED_ALLY_ITEM_COUNTS.get(encounter_id, {})
		assert_eq(
			_item_counts(misa.get("item_ids", []) as Array), expected,
			"%s misa_weaver sandbox item loadout." % encounter_id
		)


func _item_counts(item_ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item_id: Variant in item_ids:
		counts[str(item_id)] = int(counts.get(str(item_id), 0)) + 1
	return counts


# --- 事件 data/events/*.json -------------------------------------------------------


func test_events_pack_count_and_schema() -> void:
	assert_true(
		_events_by_id.size() >= 10,
		"data/events must contain at least 10 events (got %d)." % _events_by_id.size()
	)
	for id: String in EXPECTED_EVENT_IDS:
		assert_true(
			_events_by_id.has(id),
			"data/events must define contract §7 event '%s'." % id
		)
	for id: String in _events_by_id:
		_validate_event_def(_events_by_id[id], "event %s" % id)


func _validate_event_def(event_def: Dictionary, context: String) -> void:
	_assert_stable_id(event_def.get("id"), context + ".id")
	_assert_enum(event_def, "kind", EVENT_KINDS, context)
	if event_def.has("requires_flag") and event_def.get("requires_flag") != null:
		_assert_stable_id(event_def.get("requires_flag"), context + ".requires_flag")
	_assert_optional_bool(event_def, "once", context)
	var steps: Array = event_def.get("steps", [])
	assert_true(
		typeof(steps) == TYPE_ARRAY and steps.size() >= 1,
		"%s: steps must be a non-empty array." % context
	)
	var line_count := 0
	for step: Variant in steps:
		if typeof(step) != TYPE_DICTIONARY:
			assert_true(false, "%s: steps must be objects." % context)
			continue
		var step_def: Dictionary = step
		var step_type := str(step_def.get("type", ""))
		assert_true(
			["line", "choice", "effect"].has(step_type),
			"%s: step type must be line/choice/effect (got '%s')." % [context, step_type]
		)
		match step_type:
			"line":
				line_count += 1
				_assert_nonempty_string(step_def, "text_zh", context)
				if step_def.has("speaker"):
					_assert_nonempty_string(step_def, "speaker", context)
			"choice":
				_validate_choice_step(step_def, context)
			"effect":
				_validate_effect_step(step_def, context)
	# W003-A2 合法断言更新：line 步骤新增条件回应行（requires_flag/_absent，
	# 展示层按 flags 过滤），事件行数上限 4 → 6；既有事件补回应后最多 5 行。
	assert_true(
		line_count >= 2 and line_count <= 6,
		"%s: must contain 2..6 dialogue lines (got %d)." % [context, line_count]
	)


func _validate_choice_step(step_def: Dictionary, context: String) -> void:
	if step_def.has("choice_id"):
		_assert_stable_id(step_def.get("choice_id"), context + ".choice_id")
	_assert_nonempty_string(step_def, "prompt_zh", context)
	var options: Array = step_def.get("options", [])
	assert_true(
		options.size() >= 2 and options.size() <= 3,
		"%s: choice must offer 2..3 options (got %d)." % [context, options.size()]
	)
	for option: Variant in options:
		if typeof(option) != TYPE_DICTIONARY:
			assert_true(false, "%s: options must be objects." % context)
			continue
		var option_def: Dictionary = option
		var option_context := "%s.option[%s]" % [context, str(option_def.get("id", "?"))]
		_assert_stable_id(option_def.get("id"), option_context + ".id")
		_assert_nonempty_string(option_def, "text_zh", option_context)
		if option_def.has("set_flag"):
			_assert_stable_id(option_def.get("set_flag"), option_context + ".set_flag")
		if option_def.has("requires_trust"):
			_assert_int(option_def, "requires_trust", 0, 100, option_context)
		if option_def.has("relation_delta"):
			var delta: Dictionary = option_def.get("relation_delta", {})
			assert_true(
				typeof(delta) == TYPE_DICTIONARY,
				"%s: relation_delta must be a single object (schema allows exactly one)." % option_context
			)
			_assert_enum(delta, "char_id", CHARACTER_IDS, option_context + ".relation_delta")
			_assert_enum(delta, "dim", RELATION_DIMS, option_context + ".relation_delta")
			_assert_int(delta, "delta", -100, 100, option_context + ".relation_delta")


func _validate_effect_step(step_def: Dictionary, context: String) -> void:
	if step_def.has("flag_id"):
		_assert_stable_id(step_def.get("flag_id"), context + ".flag_id")
	_assert_optional_bool(step_def, "flag_value", context)
	for grant: Variant in step_def.get("grant_items", []) as Array:
		if typeof(grant) != TYPE_DICTIONARY:
			assert_true(false, "%s: grant_items entries must be objects." % context)
			continue
		var grant_def: Dictionary = grant
		_assert_stable_id(grant_def.get("item_id"), context + ".grant_items.item_id")
		_assert_int(grant_def, "amount", 1, -1, context + ".grant_items")
	if step_def.has("due_encounter"):
		_assert_stable_id(step_def.get("due_encounter"), context + ".due_encounter")


func test_frozen_choice_steps_match_contract_section7() -> void:
	var station_mode := _choice_step(_events_by_id.get("event_station_mode", {}), "station_mode")
	assert_false(station_mode.is_empty(), "event_station_mode must carry the frozen choice 'station_mode'.")
	assert_eq(station_mode.get("options", []).size(), 3, "station_mode must offer exactly 3 options.")
	var station_flags: Array[String] = ["station_mode_exploit", "station_mode_seal", "station_mode_symbiosis"]
	var seen_flags: Array[String] = []
	for option: Variant in station_mode.get("options", []) as Array:
		var flag := str((option as Dictionary).get("set_flag", ""))
		assert_true(
			station_flags.has(flag),
			"station_mode option flags must be verbatim §7 ids (got '%s')." % flag
		)
		seen_flags.append(flag)
	for flag: String in station_flags:
		assert_has(seen_flags, flag, "station_mode must offer option flag '%s' verbatim." % flag)

	var approach := _choice_step(_events_by_id.get("event_approach", {}), "approach")
	assert_false(approach.is_empty(), "event_approach must carry the frozen choice 'approach'.")
	var approach_flags: Array[String] = ["approach_direct", "approach_diplomatic"]
	var approach_ids: Array[String] = []
	for option: Variant in approach.get("options", []) as Array:
		var option_def: Dictionary = option
		approach_ids.append(str(option_def.get("id", "")))
		assert_true(
			option_def.has("relation_delta"),
			"approach option '%s' must carry exactly one relation_delta." % str(option_def.get("id", ""))
		)
	for flag: String in approach_flags:
		assert_has(approach_ids, flag, "approach must offer option '%s' verbatim (§7)." % flag)

	var policy := _choice_step(_events_by_id.get("event_policy", {}), "policy")
	assert_false(policy.is_empty(), "event_policy must carry the frozen choice 'policy'.")
	var policy_flags: Array[String] = ["policy_extraction_quota", "policy_sanctuary"]
	var policy_ids: Array[String] = []
	for option: Variant in policy.get("options", []) as Array:
		policy_ids.append(str((option as Dictionary).get("id", "")))
	for flag: String in policy_flags:
		assert_has(policy_ids, flag, "policy must offer option '%s' verbatim (§7)." % flag)

	var sanctuary := _find_option(policy, "policy_sanctuary")
	assert_false(sanctuary.is_empty(), "policy_sanctuary option must exist.")
	assert_eq(int(sanctuary.get("requires_trust", -1)), 40, "policy_sanctuary requires_trust must be 40.")
	assert_true(
		str(sanctuary.get("text_zh", "")).contains("40"),
		"policy_sanctuary text must explain the trust-40 requirement."
	)


func test_notable_event_steps_match_task_spec() -> void:
	var mining: Dictionary = _events_by_id.get("event_first_mining", {})
	var mining_effect := _first_effect(mining)
	assert_eq(
		str(mining_effect.get("due_encounter", "")), "encounter_first_drift_due",
		"event_first_mining must due encounter_first_drift."
	)

	var anchor: Dictionary = _events_by_id.get("event_first_anchor", {})
	var anchor_effect := _first_effect(anchor)
	assert_eq(
		str(anchor_effect.get("grant_items", [{}])[0].get("item_id", "")), "shock_trap",
		"event_first_anchor must grant shock_trap."
	)
	assert_eq(
		int(anchor_effect.get("grant_items", [{}])[0].get("amount", 0)), 1,
		"event_first_anchor must grant exactly 1 shock_trap."
	)

	var guide: Dictionary = _events_by_id.get("event_workshop_guide", {})
	assert_eq(
		str(_first_effect(guide).get("due_encounter", "")), "encounter_husk_ambush_due",
		"event_workshop_guide must due encounter_husk_ambush."
	)

	var pact: Dictionary = _events_by_id.get("event_leviathan_pact", {})
	assert_eq(
		str(pact.get("requires_flag", "")), "encounter_leviathan_due",
		"event_leviathan_pact must be gated by encounter_leviathan_due."
	)


func _choice_step(event_def: Dictionary, choice_id: String) -> Dictionary:
	for step: Variant in event_def.get("steps", []) as Array:
		if typeof(step) == TYPE_DICTIONARY and str((step as Dictionary).get("type", "")) == "choice":
			if str((step as Dictionary).get("choice_id", "")) == choice_id:
				return step as Dictionary
	return {}


func _find_option(choice_step: Dictionary, option_id: String) -> Dictionary:
	for option: Variant in choice_step.get("options", []) as Array:
		if typeof(option) == TYPE_DICTIONARY and str((option as Dictionary).get("id", "")) == option_id:
			return option as Dictionary
	return {}


func _first_effect(event_def: Dictionary) -> Dictionary:
	for step: Variant in event_def.get("steps", []) as Array:
		if typeof(step) == TYPE_DICTIONARY and str((step as Dictionary).get("type", "")) == "effect":
			return step as Dictionary
	return {}


# --- 交叉引用与重复 ID ---------------------------------------------------------------


func test_cross_references_resolve() -> void:
	var item_ids := _ids_of(_items)
	var action_ids := _ids_of(_actions)
	var unit_ids := _ids_of(_units)
	var encounter_ids := _ids_of(_encounters)
	var encounter_trigger_flags := _trigger_flags_of(_encounters)

	for entry: Variant in _buildings:
		var building: Dictionary = entry
		var context := "building '%s'" % str(building.get("id", "?"))
		for stack: Variant in building.get("inputs", []) as Array:
			_assert_resolves(item_ids, str((stack as Dictionary).get("item_id", "")), context + ".inputs")
		if building.has("recipe"):
			var recipe: Dictionary = building.get("recipe", {})
			_assert_resolves(item_ids, str(recipe.get("input_item_id", "")), context + ".recipe.input")
			_assert_resolves(item_ids, str(recipe.get("output_item_id", "")), context + ".recipe.output")
		# W002-GAP4：recipes 数组（含可选第二输入）的引用同样必须可解析。
		for recipe_entry: Variant in building.get("recipes", []) as Array:
			if typeof(recipe_entry) != TYPE_DICTIONARY:
				continue
			var recipe_def: Dictionary = recipe_entry
			_assert_resolves(item_ids, str(recipe_def.get("input_item_id", "")), context + ".recipes.input")
			_assert_resolves(item_ids, str(recipe_def.get("output_item_id", "")), context + ".recipes.output")
			if recipe_def.has("extra_input_item_id"):
				_assert_resolves(item_ids, str(recipe_def.get("extra_input_item_id", "")), context + ".recipes.extra_input")

	for entry: Variant in _units:
		var unit: Dictionary = entry
		var context := "unit '%s'" % str(unit.get("id", "?"))
		for action_id: Variant in unit.get("action_ids", []) as Array:
			_assert_resolves(action_ids, str(action_id), context + ".action_ids")
		for phase: Variant in unit.get("phases", []) as Array:
			for action_id: Variant in (phase as Dictionary).get("action_ids", []) as Array:
				_assert_resolves(action_ids, str(action_id), context + ".phase")
		for drop: Variant in unit.get("drops", []) as Array:
			_assert_resolves(item_ids, str((drop as Dictionary).get("item_id", "")), context + ".drops")

	for entry: Variant in _actions:
		var action: Dictionary = entry
		if action.has("cost") and action.get("cost") != null:
			_assert_resolves(
				item_ids, str((action.get("cost", {}) as Dictionary).get("item_id", "")),
				"action '%s'.cost" % str(action.get("id", "?"))
			)

	for entry: Variant in _encounters:
		var encounter: Dictionary = entry
		var context := "encounter '%s'" % str(encounter.get("id", "?"))
		for combatant: Variant in encounter.get("allies", []) + encounter.get("enemies", []) as Array:
			_assert_resolves(unit_ids, str((combatant as Dictionary).get("unit_id", "")), context)
			for item_id: Variant in (combatant as Dictionary).get("item_ids", []) as Array:
				_assert_resolves(item_ids, str(item_id), context + ".ally items")

	for id: String in _events_by_id:
		var event_def: Dictionary = _events_by_id[id]
		for step: Variant in event_def.get("steps", []) as Array:
			if str((step as Dictionary).get("type", "")) != "effect":
				continue
			for grant: Variant in (step as Dictionary).get("grant_items", []) as Array:
				_assert_resolves(item_ids, str((grant as Dictionary).get("item_id", "")), "event '%s'.grant_items" % id)
			if (step as Dictionary).has("due_encounter"):
				# 契约 §5：EventRunner.apply_effect_step 将 due_encounter 值写为 flag，
				# 由 WP13 按遭遇 trigger_flag 门控——故此处按 trigger_flag 解析（§7）。
				_assert_resolves(
					encounter_trigger_flags, str((step as Dictionary).get("due_encounter", "")),
					"event '%s'.due_encounter (encounter trigger_flag)" % id
				)


func test_free_and_frozen_flags_are_snake_case() -> void:
	# 契约 §7 冻结选择 flag 必须逐字出现；其余自由 flag 仅要求稳定 ID 形态。
	for id: String in _events_by_id:
		var event_def: Dictionary = _events_by_id[id]
		for step: Variant in event_def.get("steps", []) as Array:
			var step_def: Dictionary = step
			if str(step_def.get("type", "")) == "choice":
				for option: Variant in step_def.get("options", []) as Array:
					var flag := str((option as Dictionary).get("set_flag", ""))
					if not flag.is_empty():
						_assert_stable_id(flag, "event '%s' option set_flag" % id)
			if str(step_def.get("type", "")) == "effect" and step_def.has("flag_id"):
				_assert_stable_id(step_def.get("flag_id"), "event '%s' effect flag_id" % id)
	for entry: Variant in _buildings:
		var building: Dictionary = entry
		if building.has("effect_flag"):
			_assert_stable_id(building.get("effect_flag"), "building '%s' effect_flag" % str(building.get("id", "?")))


func test_frozen_choice_flags_appear_verbatim() -> void:
	var used_flags: Array[String] = []
	for id: String in _events_by_id:
		for step: Variant in _events_by_id[id].get("steps", []) as Array:
			var step_def: Dictionary = step
			if str(step_def.get("type", "")) != "choice":
				continue
			for option: Variant in step_def.get("options", []) as Array:
				var flag := str((option as Dictionary).get("set_flag", ""))
				if not flag.is_empty():
					used_flags.append(flag)
	for flag: String in FROZEN_CHOICE_FLAGS:
		if flag in ["approach_direct", "approach_diplomatic"]:
			# approach 选项按任务书仅携带 relation_delta，不写 flag。
			continue
		assert_has(used_flags, flag, "frozen choice flag '%s' must appear verbatim in event choices (§7)." % flag)


func test_no_duplicate_ids_within_categories() -> void:
	_assert_unique_ids(_items, "items")
	_assert_unique_ids(_buildings, "buildings")
	_assert_unique_ids(_units, "combat_units")
	_assert_unique_ids(_actions, "combat_actions")
	_assert_unique_ids(_encounters, "encounters")
	assert_eq(_events_by_id.size(), _load_events_unique_count(), "event ids must be unique across files")


func _load_events_unique_count() -> int:
	var ids := _ids_of(_events_by_id.values())
	return ids.size()


func _ids_of(entries: Array) -> Dictionary:
	var ids: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			ids[str((entry as Dictionary).get("id", ""))] = true
	return ids


func _trigger_flags_of(entries: Array) -> Dictionary:
	var flags: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			flags[str((entry as Dictionary).get("trigger_flag", ""))] = true
	return flags


func _assert_resolves(id_set: Dictionary, ref_id: String, context: String) -> void:
	assert_true(
		id_set.has(ref_id),
		"%s references undefined id '%s'." % [context, ref_id]
	)


# --- 生产校验器集成（ContentDB）与引擎消费形状（CombatEngine）------------------------


func test_content_db_bootstraps_whole_pack() -> void:
	var db_script: Script = load(CONTENT_DB_PATH) as Script
	assert_true(db_script != null, "ContentDB script must be loadable.")
	if db_script == null:
		return
	var db: Node = db_script.new()
	autofree(db)
	var result: AppResult = db.bootstrap(DATA_ROOT)
	assert_true(result.is_ok, "ContentDB.bootstrap on res://data must succeed: %s" % result.message)
	if not result.is_ok:
		return
	assert_eq(db.ids_of("item").size(), 6, "ContentDB item count.")
	assert_eq(db.ids_of("building").size(), 6, "ContentDB building count.")
	assert_eq(db.ids_of("combat_unit").size(), 6, "ContentDB combat unit count.")
	assert_eq(db.ids_of("combat_action").size(), 9, "ContentDB combat action count.")
	assert_true(db.ids_of("event").size() >= 10, "ContentDB event count >= 10.")
	assert_eq(db.ids_of("encounter").size(), 3, "ContentDB encounter count.")
	# 协调者裁定（2026-08-28）：WP01 validate_refs 的 due_encounter 语义已修订为按
	# 遭遇 trigger_flag 校验（契约 §5 EventRunner 将其写为 flag、§7 定义 trigger_flag）。
	# 数据按 trigger_flag 落地，validate_refs 必须完全通过。
	var refs: AppResult = db.validate_refs()
	assert_true(refs.is_ok, "validate_refs must pass: due_encounter values are trigger flags.")
	assert_false(db.content_hash().is_empty(), "content_hash must be non-empty for a non-empty pack.")


func test_combat_engine_consumes_pack_migration_shape() -> void:
	var unit_defs := _defs_by_id(_units)
	var action_defs := _defs_by_id(_actions)
	assert_false(unit_defs.is_empty() or action_defs.is_empty(), "pack defs must be loaded for the engine check.")
	var config: Dictionary = {
		"allies": [
			{"unit_id": "luoxian_fighter", "track": "front"},
			{"unit_id": "misa_weaver", "track": "mid", "items": {"sedative_mist": 1, "shock_trap": 1}},
		],
		"enemies": [{"unit_id": "lumen_leviathan", "track": "front"}],
		"seed": 1003,
		"unit_defs": unit_defs,
		"action_defs": action_defs,
	}
	var battle := CombatEngine.create_battle(config)
	assert_eq((battle.get("units", []) as Array).size(), 3, "battle builds 3 units from pack defs.")
	var boss: Dictionary = _unit_ref(battle, "e0|lumen_leviathan")
	assert_eq(int(boss.get("max_hp", 0)), 60, "boss max_hp comes from the pack definition.")
	boss["hp"] = 30

	var after_boss := CombatEngine.submit_action(battle, "e0|lumen_leviathan", "strike", "")
	var boss_after: Dictionary = _unit_ref(after_boss, "e0|lumen_leviathan")
	assert_eq(
		boss_after.get("action_ids", []),
		["lumen_surge", "vein_quake", "strike"],
		"boss switches to the leviathan_p1 pool at 0.5 hp (migration-point shape)."
	)
	assert_true(_log_has_phase(after_boss, "leviathan_p1"), "battle log must record the leviathan_p1 phase change.")

	var after_luoxian := CombatEngine.submit_action(after_boss, "a0|luoxian_fighter", "strike", "e0|lumen_leviathan")
	var after_trap := CombatEngine.submit_action(after_luoxian, "a1|misa_weaver", "trap_snap", "e0|lumen_leviathan")
	var misa_after: Dictionary = _unit_ref(after_trap, "a1|misa_weaver")
	assert_false(
		(misa_after.get("items", {}) as Dictionary).has("shock_trap"),
		"trap_snap consumes the shock_trap from the ally loadout."
	)
	var boss_after_trap: Dictionary = _unit_ref(after_trap, "e0|lumen_leviathan")
	assert_eq(int(boss_after_trap.get("hp", 0)), 14, "trap_snap deals its pack-defined power through the engine.")


func test_pack_supports_victory_and_drop_aggregation() -> void:
	var config: Dictionary = {
		"allies": [
			{"unit_id": "luoxian_fighter", "track": "front"},
			{"unit_id": "misa_weaver", "track": "mid", "items": {"sedative_mist": 1}},
		],
		"enemies": [{"unit_id": "lumen_leviathan", "track": "front"}],
		"seed": 1003,
		"unit_defs": _defs_by_id(_units),
		"action_defs": _defs_by_id(_actions),
	}
	var battle := CombatEngine.create_battle(config)
	_unit_ref(battle, "e0|lumen_leviathan")["hp"] = 1
	var after_boss := CombatEngine.submit_action(battle, "e0|lumen_leviathan", "strike", "")
	var finished := CombatEngine.submit_action(after_boss, "a0|luoxian_fighter", "strike", "e0|lumen_leviathan")
	assert_true(CombatEngine.is_finished(finished), "striking the 1-hp boss ends the battle.")
	var outcome := CombatEngine.outcome(finished)
	assert_eq(str(outcome.get("result", "")), "victory", "pack data must support a victory outcome.")
	assert_eq(
		outcome.get("drops", []),
		[{"item_id": "echo_seed", "amount": 1}, {"item_id": "resonant_core", "amount": 2}],
		"boss drops aggregate per the pack definition."
	)


func _unit_ref(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Variant in battle.get("units", []) as Array:
		if str((unit as Dictionary).get("key", "")) == unit_key:
			return unit as Dictionary
	return {}


func _log_has_phase(battle: Dictionary, phase_id: String) -> bool:
	for entry: Variant in battle.get("log", []) as Array:
		if str((entry as Dictionary).get("type", "")) == "phase_change" \
				and str((entry as Dictionary).get("phase", "")) == phase_id:
			return true
	return false
