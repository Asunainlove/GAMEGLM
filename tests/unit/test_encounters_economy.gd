extends GutTest

## W002-GAP4 道具经济测试（TDD：先 RED 后 GREEN）：
## - EncounterDirector.spent_items：对比开局装配与战后剩余，聚合实际消耗。
## - EncounterDirector.finish：victory/defeat 均把实际消耗经 remove_item 回写库存。
## - encounter_husk_ambush 数据：精英 veinwarden_echo 上场（章程"一个精英"）。
## - mist 渠道：织机配方产出 sedative_mist，经 start 装配进遭遇（闭环）。

const DIRECTOR_SCRIPT_PATH: String = "res://src/encounters/encounter_director.gd"
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const ENCOUNTERS_JSON_PATH: String = "res://data/encounters/encounters.json"
const BUILDINGS_JSON_PATH: String = "res://data/content/buildings.json"

var _director: Script = null


func before_all() -> void:
	_director = load(DIRECTOR_SCRIPT_PATH)


func _require_director() -> bool:
	if _director == null:
		fail_test("Missing required W002-GAP4 implementation: %s" % DIRECTOR_SCRIPT_PATH)
		return false
	return true


# --- 夹具 -----------------------------------------------------------------------


const UNIT_DEFS: Dictionary = {
	"u_luoxian": {
		"id": "u_luoxian", "kind": "ally", "name_zh": "洛弦",
		"max_hp": 40, "stability_max": 10, "track": "front", "speed": 6,
		"action_ids": ["a_strike"],
	},
	"u_misa": {
		"id": "u_misa", "kind": "ally", "name_zh": "弥砂",
		"max_hp": 30, "stability_max": 12, "track": "mid", "speed": 5,
		"action_ids": ["a_trap", "a_strike"],
	},
	"u_swarm": {
		"id": "u_swarm", "kind": "enemy_normal", "name_zh": "漂游幼群",
		"max_hp": 12, "stability_max": 6, "track": "front", "speed": 4,
		"action_ids": ["a_strike"],
		"drops": [{"item_id": "starsoil_dust", "amount": 2}],
	},
}

const ACTION_DEFS: Dictionary = {
	"a_strike": {
		"id": "a_strike", "kind": "attack", "name_zh": "破尘击",
		"targeting": "single_enemy", "power": 6, "stability_damage": 2,
	},
	"a_trap": {
		"id": "a_trap", "kind": "item", "name_zh": "陷阱触发",
		"targeting": "single_enemy", "power": 5, "stability_damage": 3,
		"cost": {"item_id": "shock_trap", "count": 1},
	},
}

const ITEM_DEFS: Dictionary = {
	"sedative_mist": {"id": "sedative_mist", "kind": "sandbox_item", "battle_usable": true},
	"shock_trap": {"id": "shock_trap", "kind": "sandbox_item", "battle_usable": true},
}


func _encounter_def() -> Dictionary:
	return {
		"id": "encounter_test_economy",
		"name_zh": "道具经济测试遭遇",
		"trigger_flag": "encounter_test_economy_due",
		"on_victory_flag": "encounter_test_economy_won",
		"allies": [
			{"unit_id": "u_luoxian", "track": "front"},
			{"unit_id": "u_misa", "track": "mid", "item_ids": ["sedative_mist", "shock_trap"]},
		],
		"enemies": [{"unit_id": "u_swarm", "track": "front"}],
		"seed": 4242,
	}


func _content(inventory: Dictionary) -> Dictionary:
	return {
		"unit_defs": UNIT_DEFS.duplicate(true),
		"action_defs": ACTION_DEFS.duplicate(true),
		"item_defs": ITEM_DEFS.duplicate(true),
		"inventory": inventory,
	}


# --- spent_items（静态纯函数）------------------------------------------------------


func test_spent_items_counts_engine_consumption() -> void:
	if not _require_director():
		return
	var config: Dictionary = _director.start(_encounter_def(), _content({"shock_trap": 2}))
	var battle: Dictionary = COMBAT_ENGINE_SCRIPT.create_battle(config)
	# 洛弦先手（speed 6）先行动一次，轮到弥砂（a1）再消耗 1 个陷阱。
	battle = COMBAT_ENGINE_SCRIPT.submit_action(battle, "a0|u_luoxian", "a_strike", "e0|u_swarm")
	battle = COMBAT_ENGINE_SCRIPT.submit_action(battle, "a1|u_misa", "a_trap", "e0|u_swarm")
	var spent: Dictionary = _director.spent_items(config.get("allies", []), battle.get("units", []))
	assert_eq(spent, {"shock_trap": 1}, "One trap_snap must count as one spent shock_trap.")


func test_spent_items_empty_without_consumption() -> void:
	if not _require_director():
		return
	var config: Dictionary = _director.start(_encounter_def(), _content({"shock_trap": 2}))
	var battle: Dictionary = COMBAT_ENGINE_SCRIPT.create_battle(config)
	var spent: Dictionary = _director.spent_items(config.get("allies", []), battle.get("units", []))
	assert_true(spent.is_empty(), "No actions means nothing was spent.")


# --- finish 回写（真实 GameState patch 管线）---------------------------------------


func test_finish_writes_back_spent_items_on_victory() -> void:
	if not _require_director():
		return
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	_give(store, "shock_trap", 2)

	var config: Dictionary = _director.start(_encounter_def(), _content({"shock_trap": 2}))
	var battle: Dictionary = COMBAT_ENGINE_SCRIPT.create_battle(config)
	battle = _drive_to_end(battle, true)
	assert_eq(COMBAT_ENGINE_SCRIPT.outcome(battle).get("result", ""), "victory")

	var outcome: Dictionary = COMBAT_ENGINE_SCRIPT.outcome(battle)
	outcome["items_spent"] = _director.spent_items(
		config.get("allies", []), battle.get("units", []))
	assert_eq(outcome["items_spent"], {"shock_trap": 1})
	var state: Dictionary = store.snapshot()
	var result: AppResult = _director.new().finish(state, _encounter_def(), outcome, store)
	assert_true(result.is_ok, result.message)

	var inventory: Dictionary = store.snapshot()["inventory"]
	assert_eq(int(inventory.get("shock_trap", 0)), 1, "Battle consumption must write back: 2 - 1 = 1.")
	assert_eq(int(inventory.get("starsoil_dust", 0)), 2, "Enemy drops still land via add_item.")
	assert_eq(
		str((store.snapshot()["battle_outcomes"] as Dictionary).get("encounter_test_economy", {}).get("result", "")),
		"victory"
	)


func test_finish_writes_back_spent_items_on_defeat() -> void:
	if not _require_director():
		return
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	_give(store, "shock_trap", 1)

	var config: Dictionary = _director.start(_encounter_def(), _content({"shock_trap": 1}))
	var battle: Dictionary = COMBAT_ENGINE_SCRIPT.create_battle(config)
	# 压低盟友生命、抬高敌人生命制造战败：弥砂必须先消耗掉那 1 个陷阱。
	for unit_value: Variant in battle.get("units", []):
		var unit: Dictionary = unit_value
		if str(unit.get("side", "")) == "ally":
			unit["hp"] = 1
		elif str(unit.get("unit_id", "")) == "u_swarm":
			unit["hp"] = 999
			unit["max_hp"] = 999
	battle = _drive_to_end(battle, true)
	var outcome: Dictionary = COMBAT_ENGINE_SCRIPT.outcome(battle)
	assert_eq(outcome.get("result", ""), "defeat", "Two 1-hp allies must fall to the beefy enemy.")
	outcome["items_spent"] = _director.spent_items(
		config.get("allies", []), battle.get("units", []))
	assert_eq(outcome["items_spent"], {"shock_trap": 1}, "Misa must have spent her trap before falling.")
	var result: AppResult = _director.new().finish(store.snapshot(), _encounter_def(), outcome, store)
	assert_true(result.is_ok, result.message)

	var snapshot: Dictionary = store.snapshot()
	assert_eq(int((snapshot["inventory"] as Dictionary).get("shock_trap", 0)), 0, "Defeat must still write back consumption.")
	assert_eq(
		str((snapshot["battle_outcomes"] as Dictionary).get("encounter_test_economy", {}).get("result", "")),
		"defeat"
	)


func test_finish_without_spent_items_keeps_legacy_shape() -> void:
	if not _require_director():
		return
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	var outcome: Dictionary = {"result": "victory", "turns": 2, "drops": []}
	var result: AppResult = _director.new().finish(store.snapshot(), _encounter_def(), outcome, store)
	assert_true(result.is_ok, "Outcome without items_spent must keep working (compat).")
	assert_eq(int(store.snapshot()["revision"]), 1)


# --- 数据：精英上场与 mist 渠道 ------------------------------------------------------


func _load_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	assert_eq(parser.parse(text), OK, "%s must parse." % path)
	var parsed: Variant = parser.get_data()
	assert_true(typeof(parsed) == TYPE_ARRAY, "%s must be an array." % path)
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func test_husk_ambush_fields_elite_and_keeps_mist_loadout() -> void:
	var encounters: Array = _load_json_array(ENCOUNTERS_JSON_PATH)
	var husk: Dictionary = {}
	for entry: Variant in encounters:
		var encounter: Dictionary = entry
		if str(encounter.get("id", "")) == "encounter_husk_ambush":
			husk = encounter
	assert_false(husk.is_empty(), "encounter_husk_ambush must exist.")
	var enemies: Array = husk.get("enemies", [])
	assert_eq(enemies.size(), 2, "husk_ambush must field exactly two enemies.")
	if enemies.size() == 2:
		assert_eq(str((enemies[0] as Dictionary).get("unit_id", "")), "shard_husk")
		assert_eq(str((enemies[0] as Dictionary).get("track", "")), "mid")
		assert_eq(str((enemies[1] as Dictionary).get("unit_id", "")), "veinwarden_echo", "The frozen elite must appear in an encounter.")
		assert_eq(str((enemies[1] as Dictionary).get("track", "")), "mid")
	for enemy_value: Variant in enemies:
		assert_ne(str((enemy_value as Dictionary).get("unit_id", "")), "drift_swarmling", "drift_swarmling is replaced by the elite.")
	var misa: Dictionary = (husk.get("allies", [{}]) as Array)[1] as Dictionary
	var mist_count := 0
	for item_id: Variant in misa.get("item_ids", []) as Array:
		if str(item_id) == "sedative_mist":
			mist_count += 1
	assert_eq(mist_count, 1, "husk_ambush keeps exactly 1 sedative_mist in the loadout.")


func test_loom_recipe_produces_mist_channel_and_start_equips_it() -> void:
	# 数据侧：织机配方表包含 2×辉砂晶片 → 1×定神雾（契约 §7 mist 渠道）。
	var buildings: Array = _load_json_array(BUILDINGS_JSON_PATH)
	var loom: Dictionary = {}
	for entry: Variant in buildings:
		var building: Dictionary = entry
		if str(building.get("id", "")) == "resonance_loom":
			loom = building
	assert_false(loom.is_empty(), "resonance_loom must exist.")
	var recipes: Array = loom.get("recipes", [])
	var has_mist_recipe := false
	for recipe_value: Variant in recipes:
		var recipe: Dictionary = recipe_value
		if str(recipe.get("output_item_id", "")) == "sedative_mist" \
				and int(recipe.get("input_count", 0)) == 2 \
				and str(recipe.get("input_item_id", "")) == "lumen_shard":
			has_mist_recipe = true
	assert_true(has_mist_recipe, "Loom must craft 2x lumen_shard -> 1x sedative_mist.")

	# 运行侧：合成所得 mist 进背包后，start 必须把它装配到弥砂的战斗道具里。
	if not _require_director():
		return
	var config: Dictionary = _director.start(_encounter_def(), _content({"sedative_mist": 1, "shock_trap": 1}))
	var misa_items: Dictionary = (config.get("allies", [{}, {}]) as Array)[1].get("items", {})
	assert_true(
		misa_items.has("sedative_mist"),
		"Inventory sedative_mist must be equipped for battle (mist channel closes)."
	)
	assert_true(
		misa_items.has("shock_trap"),
		"Granted trap from event_first_anchor channel stays equipped when owned."
	)


func _give(store: Node, item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_gap4_econ_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


## 按引擎回合序推进到战斗结束：弥砂首个行动消耗陷阱（spend_trap），其余盟友
## 行动取声明序首个；敌方回合由 submit_action 内置 AI 自动结算。
func _drive_to_end(battle: Dictionary, spend_trap: bool) -> Dictionary:
	var guard := 0
	var trap_spent := false
	while not COMBAT_ENGINE_SCRIPT.is_finished(battle) and guard < 64:
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(battle)
		if active.is_empty():
			break
		if str(active.get("side", "")) != "ally":
			break
		var action := "a_strike"
		if spend_trap and not trap_spent and str(active.get("unit_id", "")) == "u_misa":
			action = "a_trap"
			trap_spent = true
		battle = COMBAT_ENGINE_SCRIPT.submit_action(battle, str(active.get("key", "")), action, "e0|u_swarm")
		guard += 1
	return battle
