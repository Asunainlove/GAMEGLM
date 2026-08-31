extends GutTest

## WP01 ContentDB contract tests (frozen contract v1, section 3).
## Every test instantiates its own ContentDB (never the autoload singleton)
## and loads JSON fixtures written under user://starsoil_test_content/.

const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"
const FIXTURE_ROOT: String = "user://starsoil_test_content"
const MISSING_DIR: String = "user://starsoil_test_content_missing_dir"
const EFFECT_DELTA_ROOT: String = "user://starsoil_test_content_effect_delta"
const EFFECT_DELTA_BAD_ROOT: String = "user://starsoil_test_content_effect_delta_bad"
const FLAG_LINE_ROOT: String = "user://starsoil_test_content_flag_line"
const FLAG_LINE_BAD_ROOT: String = "user://starsoil_test_content_flag_line_bad"

var _db_script: Script


func before_all() -> void:
	_db_script = load(CONTENT_DB_PATH) as Script
	for tree: String in [
		FIXTURE_ROOT,
		FIXTURE_ROOT + "_mutated",
		FIXTURE_ROOT + "_dangling",
		FIXTURE_ROOT + "_invalid_kind",
		FIXTURE_ROOT + "_invalid_id",
		FIXTURE_ROOT + "_duplicate",
		FIXTURE_ROOT + "_bad_json",
		FIXTURE_ROOT + "_missing_field",
		FIXTURE_ROOT + "_empty_dir",
		FIXTURE_ROOT + "_hash_a",
		FIXTURE_ROOT + "_hash_b",
		EFFECT_DELTA_ROOT,
		EFFECT_DELTA_BAD_ROOT,
		FLAG_LINE_ROOT,
		FLAG_LINE_BAD_ROOT,
	]:
		_remove_dir_recursive(tree)
	_write_fixture_tree(FIXTURE_ROOT, "")
	_write_fixture_tree(FIXTURE_ROOT + "_mutated", "mutated")
	_write_fixture_tree(FIXTURE_ROOT + "_dangling", "dangling")
	_write_fixture_tree(FIXTURE_ROOT + "_invalid_kind", "invalid_kind")
	_write_fixture_tree(FIXTURE_ROOT + "_invalid_id", "invalid_id")
	_write_fixture_tree(FIXTURE_ROOT + "_duplicate", "duplicate")
	_write_fixture_tree(FIXTURE_ROOT + "_bad_json", "bad_json")
	_write_fixture_tree(FIXTURE_ROOT + "_missing_field", "missing_field")
	_write_fixture_tree(FIXTURE_ROOT + "_empty_dir", "empty_dir")
	_write_text_file(FIXTURE_ROOT + "_hash_a/content/alpha.json", '{"id": "starsoil_dust", "kind": "material", "name_zh": "星壤尘", "stack_limit": 99}')
	_write_text_file(FIXTURE_ROOT + "_hash_b/content/beta.json", '{"stack_limit": 99, "kind": "material", "name_zh": "星壤尘", "id": "starsoil_dust"}')
	_write_json(EFFECT_DELTA_ROOT + "/events/event_test_bond.json", _fixture_event_effect_delta())
	_write_json(EFFECT_DELTA_BAD_ROOT + "/events/event_test_bond_bad.json", _fixture_event_effect_delta_bad_dim())
	_write_json(FLAG_LINE_ROOT + "/events/event_test_flag_line.json", _fixture_event_flag_line())
	_write_json(FLAG_LINE_BAD_ROOT + "/events/event_test_flag_line_bad.json", _fixture_event_flag_line_bad())


func after_all() -> void:
	for tree: String in [
		FIXTURE_ROOT,
		FIXTURE_ROOT + "_mutated",
		FIXTURE_ROOT + "_dangling",
		FIXTURE_ROOT + "_invalid_kind",
		FIXTURE_ROOT + "_invalid_id",
		FIXTURE_ROOT + "_duplicate",
		FIXTURE_ROOT + "_bad_json",
		FIXTURE_ROOT + "_missing_field",
		FIXTURE_ROOT + "_empty_dir",
		FIXTURE_ROOT + "_hash_a",
		FIXTURE_ROOT + "_hash_b",
		EFFECT_DELTA_ROOT,
		EFFECT_DELTA_BAD_ROOT,
		FLAG_LINE_ROOT,
		FLAG_LINE_BAD_ROOT,
	]:
		_remove_dir_recursive(tree)


func test_content_db_script_exists() -> void:
	assert_not_null(_db_script, "ContentDB script must load: " + CONTENT_DB_PATH)


func test_missing_content_directory_bootstraps_empty_successfully() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(MISSING_DIR)
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "ok")
	assert_true(db.is_bootstrapped())
	assert_eq(db.content_hash(), "")
	assert_eq(db.ids_of("material"), _strings([]))
	assert_eq(db.ids_of("building"), _strings([]))
	assert_eq(db.get_item("starsoil_dust"), {})
	assert_true(db.validate_refs().is_ok)


func test_bootstrap_loads_all_six_categories_from_fixture_tree() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT)
	assert_true(result.is_ok, result.message)
	assert_true(db.is_bootstrapped())

	var item: Dictionary = db.get_item("starsoil_dust")
	assert_eq(item["kind"], "material")
	assert_eq(item["name_zh"], "星壤尘")
	assert_eq(item["stack_limit"], 999)

	var building: Dictionary = db.get_building("dust_refiner")
	assert_eq(building["power_draw"], 4)
	assert_eq(building["recipe"]["input_item_id"], "starsoil_dust")
	assert_eq(building["recipe"]["output_item_id"], "resonant_core")

	var unit: Dictionary = db.get_combat_unit("lumen_leviathan")
	assert_eq(unit["kind"], "boss")
	assert_eq(unit["phases"].size(), 1)
	assert_eq(unit["phases"][0]["id"], "leviathan_p2")

	var action: Dictionary = db.get_combat_action("sedative_mist_puff")
	assert_eq(action["kind"], "item")
	assert_eq(action["cost"]["item_id"], "sedative_mist")

	var event: Dictionary = db.get_event("event_prologue_landing")
	assert_eq(event["kind"], "dialogue")
	assert_eq(event["steps"].size(), 3)

	var encounter: Dictionary = db.get_encounter("encounter_first_drift")
	assert_eq(encounter["trigger_flag"], "encounter_first_drift_due")
	assert_eq(encounter["allies"][0]["unit_id"], "luoxian_fighter")


func test_ids_of_covers_item_kinds_and_all_categories() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT).is_ok)

	assert_eq(db.ids_of("material"), _strings(["lumen_shard", "resonant_core", "starsoil_dust"]))
	assert_eq(db.ids_of("story_core"), _strings(["echo_seed"]))
	assert_eq(db.ids_of("sandbox_item"), _strings(["sedative_mist", "shock_trap"]))
	assert_eq(db.ids_of("item").size(), 6)
	assert_eq(db.ids_of("building").size(), 6)
	assert_true(db.ids_of("building").has("echo_chamber"))
	assert_eq(db.ids_of("combat_unit").size(), 6)
	assert_eq(db.ids_of("combat_action").size(), 10)
	assert_eq(db.ids_of("event").size(), 3)
	assert_eq(db.ids_of("encounter"), _strings(["encounter_first_drift", "encounter_leviathan"]))
	assert_eq(db.ids_of("nonsense_kind"), _strings([]))


func test_getters_return_defensive_copies() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT).is_ok)

	var building: Dictionary = db.get_building("dust_refiner")
	building["kind"] = "corrupted"
	building["recipe"]["input_count"] = 999
	building["inputs"][0]["count"] = 777

	var fresh: Dictionary = db.get_building("dust_refiner")
	assert_eq(fresh["kind"], "building")
	assert_eq(fresh["recipe"]["input_count"], 3)
	assert_eq(fresh["inputs"][0]["count"], 5)

	var encounter: Dictionary = db.get_encounter("encounter_first_drift")
	encounter["allies"][0]["item_ids"].append("shock_trap")
	assert_eq((db.get_encounter("encounter_first_drift")["allies"][0]["item_ids"] as Array).size(), 1)


func test_missing_id_returns_empty_dictionary_for_every_getter() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT).is_ok)
	assert_eq(db.get_item("does_not_exist"), {})
	assert_eq(db.get_building("does_not_exist"), {})
	assert_eq(db.get_combat_unit("does_not_exist"), {})
	assert_eq(db.get_combat_action("does_not_exist"), {})
	assert_eq(db.get_event("does_not_exist"), {})
	assert_eq(db.get_encounter("does_not_exist"), {})


func test_content_hash_is_stable_sensitive_and_empty_without_content() -> void:
	var first: Node = _new_db()
	if first == null:
		return
	var second: Node = _new_db()
	var mutated: Node = _new_db()
	var empty: Node = _new_db()
	assert_true(first.bootstrap(FIXTURE_ROOT).is_ok)
	assert_true(second.bootstrap(FIXTURE_ROOT).is_ok)
	assert_true(mutated.bootstrap(FIXTURE_ROOT + "_mutated").is_ok)
	assert_true(empty.bootstrap(MISSING_DIR).is_ok)

	var hash_value: String = first.content_hash()
	assert_eq(hash_value.length(), 64)
	assert_eq(hash_value, hash_value.to_lower())
	assert_eq(second.content_hash(), hash_value)
	assert_ne(mutated.content_hash(), hash_value)
	assert_eq(empty.content_hash(), "")

	var scrambled: Node = _new_db()
	assert_true(scrambled.bootstrap(FIXTURE_ROOT + "_hash_a").is_ok)
	var scrambled_twin: Node = _new_db()
	assert_true(scrambled_twin.bootstrap(FIXTURE_ROOT + "_hash_b").is_ok)
	assert_ne(scrambled.content_hash(), "")
	assert_eq(scrambled.content_hash(), scrambled_twin.content_hash())


func test_repeated_bootstrap_is_rejected_without_state_change() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT).is_ok)
	var hash_before: String = db.content_hash()

	var replay: AppResult = db.bootstrap(FIXTURE_ROOT)
	assert_false(replay.is_ok)
	assert_eq(replay.code, "already_bootstrapped")
	assert_true(db.is_bootstrapped())
	assert_eq(db.content_hash(), hash_before)
	assert_eq(db.get_item("starsoil_dust")["name_zh"], "星壤尘")


func test_validate_refs_accepts_fully_linked_fixture() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT).is_ok)
	var result: AppResult = db.validate_refs()
	assert_true(result.is_ok, result.message)


func test_validate_refs_requires_bootstrap() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.validate_refs()
	assert_false(result.is_ok)
	assert_eq(result.code, "not_bootstrapped")


func test_validate_refs_rejects_dangling_references() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	assert_true(db.bootstrap(FIXTURE_ROOT + "_dangling").is_ok)
	var result: AppResult = db.validate_refs()
	assert_false(result.is_ok)
	assert_eq(result.code, "dangling_ref")
	assert_true(result.message.contains("missing_item"), result.message)


func test_bootstrap_rejects_unknown_item_kind() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_invalid_kind")
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_definition")
	assert_true(result.message.contains("kind"), result.message)
	assert_false(db.is_bootstrapped())
	assert_eq(db.content_hash(), "")


func test_bootstrap_rejects_id_outside_stable_regex() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_invalid_id")
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_definition")
	assert_true(result.message.contains("Bad_ID"), result.message)
	assert_false(db.is_bootstrapped())


func test_bootstrap_rejects_duplicate_ids_across_files() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_duplicate")
	assert_false(result.is_ok)
	assert_eq(result.code, "duplicate_id")
	assert_false(db.is_bootstrapped())
	assert_eq(db.get_item("starsoil_dust"), {})


func test_bootstrap_rejects_malformed_json_naming_file_and_reason() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_bad_json")
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_json")
	assert_true(result.message.contains("broken.json"), result.message)
	assert_true(result.message.contains("invalid JSON"), result.message)
	assert_false(db.is_bootstrapped())
	assert_eq(db.content_hash(), "")


func test_bootstrap_rejects_missing_required_field() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_missing_field")
	assert_false(result.is_ok)
	assert_eq(result.code, "invalid_definition")
	assert_true(result.message.contains("stack_limit"), result.message)
	assert_false(db.is_bootstrapped())
	assert_eq(db.get_item("starsoil_dust"), {})


func test_bootstrap_of_existing_but_empty_directory_succeeds_empty() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FIXTURE_ROOT + "_empty_dir")
	assert_true(result.is_ok, result.message)
	assert_eq(result.code, "ok")
	assert_true(db.is_bootstrapped())
	assert_eq(db.content_hash(), "")
	assert_eq(db.ids_of("item"), _strings([]))
	assert_eq(db.get_item("starsoil_dust"), {})
	assert_true(db.validate_refs().is_ok)


# ---------------------------------------------------------------- effect 步骤 relation_delta（W002-GAP1）


func test_bootstrap_accepts_effect_step_relation_delta() -> void:
	# W002-GAP1：effect 步骤新增可选 relation_delta，与 choice option 同形同规则。
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(EFFECT_DELTA_ROOT)
	assert_true(result.is_ok, result.message)
	var event: Dictionary = db.get_event("event_test_bond")
	assert_false(event.is_empty(), "The effect-delta fixture event must load.")
	var effect_step: Dictionary = event["steps"][2]
	var delta: Dictionary = effect_step["relation_delta"]
	assert_eq(str(delta.get("char_id")), "luoxian", "relation_delta char_id loads verbatim.")
	assert_eq(str(delta.get("dim")), "trust", "relation_delta dim loads verbatim.")
	assert_eq(int(delta.get("delta")), 12, "relation_delta delta loads verbatim.")


func test_bootstrap_rejects_effect_step_relation_delta_with_unknown_dim() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(EFFECT_DELTA_BAD_ROOT)
	assert_false(result.is_ok, "Effect-step relation_delta must follow the choice dim enum rules.")
	assert_eq(result.code, "invalid_definition")
	assert_true(result.message.contains("dim"), result.message)
	assert_false(db.is_bootstrapped())


func _fixture_event_effect_delta() -> Dictionary:
	return {
		"id": "event_test_bond",
		"kind": "dialogue",
		"once": true,
		"steps": [
			{"type": "line", "speaker": "洛弦", "text_zh": "篝火剩最后一点火星了。"},
			{"type": "line", "speaker": "弥砂", "text_zh": "那就再聊一会儿，反正明天风小。"},
			{"type": "effect", "relation_delta": {"char_id": "luoxian", "dim": "trust", "delta": 12}},
		],
	}


func _fixture_event_effect_delta_bad_dim() -> Dictionary:
	var event: Dictionary = _fixture_event_effect_delta()
	event["id"] = "event_test_bond_bad"
	(event["steps"][2] as Dictionary)["relation_delta"] = {"char_id": "luoxian", "dim": "loyalty", "delta": 12}
	return event


# ---------------------------------------------------------------- line 步骤条件字段（W003-A2）


func test_bootstrap_accepts_line_step_flag_conditions() -> void:
	# W003-A2：line 步骤新增可选 requires_flag / requires_flag_absent（稳定 ID），
	# 展示层按 flags 过滤；ContentDB step 校验必须原样接受并保留字段。
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FLAG_LINE_ROOT)
	assert_true(result.is_ok, result.message)
	var event: Dictionary = db.get_event("event_test_flag_line")
	assert_false(event.is_empty(), "The flag-line fixture event must load.")
	var gated: Dictionary = event["steps"][1]
	assert_eq(str(gated.get("requires_flag")), "world_response_exploited", "requires_flag loads verbatim.")
	var absent_gated: Dictionary = event["steps"][2]
	assert_eq(
		str(absent_gated.get("requires_flag_absent")), "world_response_exploited",
		"requires_flag_absent loads verbatim."
	)


func test_bootstrap_rejects_line_step_flag_condition_with_bad_id() -> void:
	var db: Node = _new_db()
	if db == null:
		return
	var result: AppResult = db.bootstrap(FLAG_LINE_BAD_ROOT)
	assert_false(result.is_ok, "Line-step flag conditions must follow the stable-id regex.")
	assert_eq(result.code, "invalid_definition")
	assert_true(result.message.contains("requires_flag"), result.message)
	assert_false(db.is_bootstrapped())


func _fixture_event_flag_line() -> Dictionary:
	return {
		"id": "event_test_flag_line",
		"kind": "mixed",
		"once": true,
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


func _fixture_event_flag_line_bad() -> Dictionary:
	var event: Dictionary = _fixture_event_flag_line()
	event["id"] = "event_test_flag_line_bad"
	(event["steps"][1] as Dictionary)["requires_flag"] = "Bad_Flag_Id"
	return event


func _new_db() -> Node:
	assert_not_null(_db_script, "ContentDB script must load: " + CONTENT_DB_PATH)
	if _db_script == null:
		return null
	var db: Node = _db_script.new()
	add_child_autofree(db)
	return db


func _strings(values: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(values)
	return typed


func _write_fixture_tree(godot_root: String, variant: String) -> void:
	if variant == "empty_dir":
		var make_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(godot_root))
		assert_eq(make_error, OK, "Failed to create empty fixture directory for %s." % godot_root)
		return
	var items: Array = _fixture_core_items()
	if variant == "mutated":
		(items[0] as Dictionary)["stack_limit"] = 998
	if variant == "invalid_kind":
		items = [{
			"id": "starsoil_dust",
			"kind": "weapon",
			"name_zh": "星壤尘",
			"stack_limit": 99,
		}]
	if variant == "duplicate":
		items = [_fixture_core_items()[0]]
	if variant == "bad_json":
		_write_text_file(godot_root + "/content/broken.json", '{"id": "broken_item", "kind": ')
		return
	if variant == "missing_field":
		_write_json(godot_root + "/content/items.json", [
			{"id": "starsoil_dust", "kind": "material", "name_zh": "星壤尘"},
		])
		return
	_write_json(godot_root + "/content/items.json", items)
	if variant == "duplicate":
		_write_json(godot_root + "/content/extra/duplicate.json", _fixture_core_items()[0])
	if variant == "invalid_id":
		_write_json(godot_root + "/content/bad_id.json", [{
			"id": "Bad_ID",
			"kind": "material",
			"name_zh": "坏标识",
			"stack_limit": 9,
		}])

	if variant != "invalid_kind" and variant != "invalid_id":
		_write_json(godot_root + "/content/sandbox/sandbox_items.json", _fixture_sandbox_items())
		_write_json(godot_root + "/content/buildings.json", _fixture_buildings(variant))
		_write_json(godot_root + "/content/combat_units.json", _fixture_combat_units())
		_write_json(godot_root + "/content/combat_actions.json", _fixture_combat_actions())
		_write_json(godot_root + "/events/event_prologue_landing.json", _fixture_event_prologue())
		_write_json(godot_root + "/events/event_station_mode.json", _fixture_event_station_mode())
		_write_json(godot_root + "/events/event_approach.json", _fixture_event_approach())
		_write_json(godot_root + "/encounters/encounters.json", _fixture_encounters())


func _fixture_core_items() -> Array:
	return [
		{"id": "starsoil_dust", "kind": "material", "name_zh": "星壤尘", "desc_zh": "采集获得的基础粉末。", "stack_limit": 999, "tier": 0},
		{"id": "lumen_shard", "kind": "material", "name_zh": "辉砂晶片", "stack_limit": 999, "tier": 1},
		{"id": "resonant_core", "kind": "material", "name_zh": "共鸣核", "stack_limit": 99, "tier": 2},
		{"id": "echo_seed", "kind": "story_core", "name_zh": "余辉之种", "stack_limit": 1, "tier": 3},
	]


func _fixture_sandbox_items() -> Array:
	return [
		{"id": "sedative_mist", "kind": "sandbox_item", "name_zh": "定神雾", "stack_limit": 9, "battle_usable": true},
		{"id": "shock_trap", "kind": "sandbox_item", "name_zh": "震颤陷阱", "stack_limit": 9, "battle_usable": true},
	]


func _fixture_buildings(variant: String) -> Array:
	var dust_refiner: Dictionary = {
		"id": "dust_refiner",
		"kind": "building",
		"name_zh": "尘精炼器",
		"inputs": [{"item_id": "starsoil_dust", "count": 5}],
		"recipe": {"input_item_id": "starsoil_dust", "input_count": 3, "output_item_id": "resonant_core", "output_count": 1},
		"power_draw": 4,
		"power_supply": 0,
	}
	if variant == "dangling":
		(dust_refiner["recipe"] as Dictionary)["output_item_id"] = "missing_item"
	return [
		{"id": "anchor_block", "kind": "building", "name_zh": "锚块", "inputs": [], "power_draw": 0, "power_supply": 0},
		{"id": "anchor_workshop", "kind": "building", "name_zh": "锚居工坊", "inputs": [{"item_id": "starsoil_dust", "count": 5}], "power_draw": 0, "power_supply": 10},
		dust_refiner,
		{"id": "stabilizer_pylon", "kind": "building", "name_zh": "稳定塔", "inputs": [{"item_id": "lumen_shard", "count": 2}], "power_draw": 6, "power_supply": 0, "effect_flag": "pylon_stabilized"},
		{"id": "resonance_loom", "kind": "building", "name_zh": "共鸣织机", "inputs": [{"item_id": "lumen_shard", "count": 2}], "recipe": {"input_item_id": "lumen_shard", "input_count": 2, "output_item_id": "sedative_mist", "output_count": 1}, "power_draw": 5, "power_supply": 0},
		{"id": "echo_chamber", "kind": "building", "name_zh": "回响舱", "inputs": [{"item_id": "resonant_core", "count": 1}, {"item_id": "lumen_shard", "count": 2}], "requires_room": true, "power_draw": 8, "power_supply": 0, "effect_flag": "echo_chamber_active"},
	]


func _fixture_combat_units() -> Array:
	return [
		{"id": "luoxian_fighter", "kind": "ally", "name_zh": "洛弦", "max_hp": 40, "stability_max": 10, "track": "front", "speed": 7, "action_ids": ["resonant_slash", "brace"]},
		{"id": "misa_weaver", "kind": "ally", "name_zh": "弥砂", "max_hp": 30, "stability_max": 12, "track": "mid", "speed": 5, "action_ids": ["weave_mend", "brace"]},
		{"id": "drift_swarmling", "kind": "enemy_normal", "name_zh": "漂游群雏", "max_hp": 18, "stability_max": 6, "track": "front", "speed": 6, "action_ids": ["drift_bite"]},
		{"id": "shard_husk", "kind": "enemy_normal", "name_zh": "晶屑空壳", "max_hp": 26, "stability_max": 8, "track": "mid", "speed": 4, "action_ids": ["shard_spit"]},
		{"id": "veinwarden_echo", "kind": "enemy_elite", "name_zh": "矿脉回响", "max_hp": 48, "stability_max": 12, "track": "mid", "speed": 5, "action_ids": ["vein_lash", "drift_bite"], "drops": [{"item_id": "lumen_shard", "amount": 2}]},
		{"id": "lumen_leviathan", "kind": "boss", "name_zh": "辉砂巨渊兽", "max_hp": 120, "stability_max": 20, "track": "front", "speed": 6, "action_ids": ["leviathan_sweep", "drift_bite"], "phases": [{"id": "leviathan_p2", "at_hp_ratio": 0.5, "action_ids": ["leviathan_sweep", "abyssal_pulse"]}]},
	]


func _fixture_combat_actions() -> Array:
	return [
		{"id": "resonant_slash", "kind": "attack", "name_zh": "共鸣斩", "targeting": "single_enemy", "power": 6, "stability_damage": 2},
		{"id": "weave_mend", "kind": "skill", "name_zh": "织光慰藉", "targeting": "single_ally", "power": 0, "stability_damage": 0, "heal": 8},
		{"id": "brace", "kind": "guard", "name_zh": "锚定姿态", "targeting": "self", "power": 0, "stability_damage": 0, "guard_ratio": 0.5},
		{"id": "drift_bite", "kind": "attack", "name_zh": "漂游噬咬", "targeting": "single_enemy", "power": 4, "stability_damage": 2},
		{"id": "shard_spit", "kind": "attack", "name_zh": "晶屑喷射", "targeting": "all_enemies", "power": 3, "stability_damage": 1},
		{"id": "vein_lash", "kind": "destabilize", "name_zh": "矿脉鞭击", "targeting": "single_enemy", "power": 5, "stability_damage": 6},
		{"id": "leviathan_sweep", "kind": "attack", "name_zh": "渊兽横扫", "targeting": "all_enemies", "power": 7, "stability_damage": 3},
		{"id": "abyssal_pulse", "kind": "skill", "name_zh": "深渊脉动", "targeting": "all_enemies", "power": 9, "stability_damage": 4},
		{"id": "sedative_mist_puff", "kind": "item", "name_zh": "定神雾散布", "targeting": "all_enemies", "power": 2, "stability_damage": 3, "cost": {"item_id": "sedative_mist", "count": 1}},
		{"id": "shock_trap_spike", "kind": "item", "name_zh": "震颤陷阱触发", "targeting": "single_enemy", "power": 5, "stability_damage": 4, "cost": {"item_id": "shock_trap", "count": 1}},
	]


func _fixture_event_prologue() -> Dictionary:
	return {
		"id": "event_prologue_landing",
		"kind": "dialogue",
		"once": true,
		"steps": [
			{"type": "line", "speaker": "洛弦", "text_zh": "着陆了。这里的土壤会发光。"},
			{"type": "line", "speaker": "弥砂", "text_zh": "星壤的余辉还在回应我们。"},
			{"type": "effect", "grant_items": [{"item_id": "starsoil_dust", "amount": 3}]},
		],
	}


func _fixture_event_station_mode() -> Dictionary:
	return {
		"id": "event_station_mode",
		"kind": "choice",
		"steps": [
			{"type": "choice", "choice_id": "station_mode", "prompt_zh": "中继站的三种未来摆在你面前。", "options": [
				{"id": "station_mode_exploit", "text_zh": "最大化开采。"},
				{"id": "station_mode_seal", "text_zh": "封存矿脉。"},
				{"id": "station_mode_symbiosis", "text_zh": "尝试共生。"},
			]},
			{"type": "effect", "due_encounter": "encounter_leviathan_due"},
		],
	}


func _fixture_event_approach() -> Dictionary:
	return {
		"id": "event_approach",
		"kind": "mixed",
		"steps": [
			{"type": "line", "speaker": "弥砂", "text_zh": "你想怎么接近它？"},
			{"type": "choice", "choice_id": "approach", "prompt_zh": "选择接近方式。", "options": [
				{"id": "approach_direct", "text_zh": "直接进去。"},
				{"id": "approach_diplomatic", "text_zh": "先观察再接触。", "set_flag": "approach_observed", "relation_delta": {"char_id": "luoxian", "dim": "trust", "delta": 10}},
			]},
		],
	}


func _fixture_encounters() -> Array:
	return [
		{
			"id": "encounter_first_drift",
			"name_zh": "初遇漂游群",
			"trigger_flag": "encounter_first_drift_due",
			"on_victory_flag": "encounter_first_drift_won",
			"allies": [
				{"unit_id": "luoxian_fighter", "track": "front", "item_ids": ["sedative_mist"]},
				{"unit_id": "misa_weaver", "track": "mid"},
			],
			"enemies": [{"unit_id": "drift_swarmling", "track": "front"}],
			"seed": 20260828,
			"intro_event_id": "event_prologue_landing",
		},
		{
			"id": "encounter_leviathan",
			"name_zh": "辉砂巨渊兽",
			"trigger_flag": "encounter_leviathan_due",
			"on_victory_flag": "encounter_leviathan_won",
			"allies": [
				{"unit_id": "luoxian_fighter", "track": "front"},
				{"unit_id": "misa_weaver", "track": "mid", "item_ids": ["sedative_mist", "shock_trap"]},
			],
			"enemies": [{"unit_id": "lumen_leviathan", "track": "front"}],
			"seed": 99,
		},
	]


func _write_json(godot_path: String, value: Variant) -> void:
	_write_text_file(godot_path, JSON.stringify(value, "\t"))


func _write_text_file(godot_path: String, text: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(godot_path)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	assert_eq(make_error, OK, "Failed to create fixture directory for %s." % godot_path)
	var file: FileAccess = FileAccess.open(absolute, FileAccess.WRITE)
	assert_not_null(file, "Failed to open fixture file %s." % godot_path)
	if file != null:
		file.store_string(text)
		file.flush()


func _remove_dir_recursive(godot_path: String) -> void:
	var dir: DirAccess = DirAccess.open(godot_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child: String = godot_path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(child)
			else:
				assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(child)), OK)
		entry = dir.get_next()
	dir.list_dir_end()
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(godot_path)), OK)
