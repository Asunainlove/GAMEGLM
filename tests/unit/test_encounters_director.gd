extends GutTest

## WP13 遭遇编排单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 契约：docs/plans/contracts/module-contracts.md §0（store 注入模式）、§5（EncounterDirector）、§7（遭遇 ID/旗标）。
## 脚本运行时加载（绝不 preload），缺失实现以失败断言暴露而非静默跳过。

const DIRECTOR_SCRIPT_PATH: String = "res://src/encounters/encounter_director.gd"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const ENCOUNTERS_JSON_PATH: String = "res://data/encounters/encounters.json"

## DuckPatch/DuckStore 宿主实例字段：替身必须由测试实例字段保活，
## 否则临时 RefCounted 会被立即释放、记录静默丢失。
var _duck_store: DuckStore = null

var _director: Script = null


func before_all() -> void:
	_director = load(DIRECTOR_SCRIPT_PATH)


func _require_director() -> bool:
	if _director == null:
		fail_test("Missing required WP13 implementation: %s" % DIRECTOR_SCRIPT_PATH)
		return false
	return true


func _director_instance() -> RefCounted:
	if not _require_director():
		return null
	var instance: RefCounted = _director.new() as RefCounted
	assert_not_null(instance, "EncounterDirector 必须可实例化（finish 为实例方法）。")
	return instance


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _fresh_game_state() -> Node:
	var state: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(state)
	return state


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
		"action_ids": ["a_bind"],
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
	"a_bind": {
		"id": "a_bind", "kind": "skill", "name_zh": "缚尘丝",
		"targeting": "single_enemy", "power": 3, "stability_damage": 3,
	},
}

const ITEM_DEFS: Dictionary = {
	"sedative_mist": {"id": "sedative_mist", "kind": "sandbox_item", "battle_usable": true},
	"shock_trap": {"id": "shock_trap", "kind": "sandbox_item", "battle_usable": true},
	"starsoil_dust": {"id": "starsoil_dust", "kind": "material"},
}


func _encounter_def() -> Dictionary:
	return {
		"id": "encounter_test_a",
		"name_zh": "测试遭遇",
		"trigger_flag": "encounter_test_a_due",
		"on_victory_flag": "encounter_test_a_won",
		"allies": [
			{"unit_id": "u_luoxian", "track": "front"},
			{
				"unit_id": "u_misa",
				"track": "mid",
				"item_ids": ["sedative_mist", "sedative_mist", "shock_trap", "starsoil_dust"],
			},
		],
		"enemies": [{"unit_id": "u_swarm", "track": "front"}],
		"seed": 4242,
	}


func _content(inventory: Dictionary = {"sedative_mist": 5, "shock_trap": 1}) -> Dictionary:
	return {
		"unit_defs": UNIT_DEFS.duplicate(true),
		"action_defs": ACTION_DEFS.duplicate(true),
		"item_defs": ITEM_DEFS.duplicate(true),
		"inventory": inventory.duplicate(true),
	}


func _victory_outcome() -> Dictionary:
	return {
		"result": "victory",
		"turns": 3,
		"drops": [
			{"item_id": "starsoil_dust", "amount": 4},
			{"item_id": "lumen_shard", "amount": 1},
		],
	}


func _defeat_outcome() -> Dictionary:
	return {"result": "defeat", "turns": 5, "drops": []}


# --- check_triggers：数组序、flag 门控 -----------------------------------------


func test_check_triggers_returns_empty_when_due_flag_unset() -> void:
	if not _require_director():
		return
	var state: Dictionary = {"flags": {}, "battle_outcomes": {}}
	assert_eq(_director.check_triggers(state, [_encounter_def()]), "")


func test_check_triggers_returns_id_when_due_and_not_won() -> void:
	if not _require_director():
		return
	var state: Dictionary = {
		"flags": {"encounter_test_a_due": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, [_encounter_def()]), "encounter_test_a")


func test_check_triggers_skips_when_victory_flag_set() -> void:
	if not _require_director():
		return
	var state: Dictionary = {
		"flags": {"encounter_test_a_due": true, "encounter_test_a_won": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, [_encounter_def()]), "")


func test_check_triggers_skips_when_battle_outcome_recorded() -> void:
	if not _require_director():
		return
	# 已有 battle_outcomes 记录（如战败后未置胜利旗标）→ 不重复触发，due 保留可重试
	# 的语义由触发方重新置 due flag 表达；此处锁定"已记录即不再触发"。
	var state: Dictionary = {
		"flags": {"encounter_test_a_due": true},
		"battle_outcomes": {"encounter_test_a": {"result": "defeat", "turns": 2}},
	}
	assert_eq(_director.check_triggers(state, [_encounter_def()]), "")


func test_check_triggers_picks_first_match_in_array_order() -> void:
	if not _require_director():
		return
	var first: Dictionary = _encounter_def()
	var second: Dictionary = _encounter_def()
	second["id"] = "encounter_test_b"
	second["trigger_flag"] = "encounter_test_b_due"
	second["on_victory_flag"] = "encounter_test_b_won"
	var state: Dictionary = {
		"flags": {"encounter_test_a_due": true, "encounter_test_b_due": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, [first, second]), "encounter_test_a")


func test_check_triggers_returns_second_when_only_second_due() -> void:
	if not _require_director():
		return
	var first: Dictionary = _encounter_def()
	var second: Dictionary = _encounter_def()
	second["id"] = "encounter_test_b"
	second["trigger_flag"] = "encounter_test_b_due"
	second["on_victory_flag"] = "encounter_test_b_won"
	var state: Dictionary = {
		"flags": {"encounter_test_b_due": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, [first, second]), "encounter_test_b")


func test_check_triggers_returns_empty_without_any_match() -> void:
	if not _require_director():
		return
	var second: Dictionary = _encounter_def()
	second["id"] = "encounter_test_b"
	second["trigger_flag"] = "encounter_test_b_due"
	second["on_victory_flag"] = "encounter_test_b_won"
	var state: Dictionary = {
		"flags": {"unrelated_flag": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, [second]), "")


func test_check_triggers_works_with_wp12_encounter_data() -> void:
	if not _require_director():
		return
	var text: String = FileAccess.get_file_as_string(ENCOUNTERS_JSON_PATH)
	assert_false(text.is_empty(), "encounters.json 必须可读。")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(typeof(parsed) == TYPE_ARRAY, "encounters.json 必须是数组。")
	if typeof(parsed) != TYPE_ARRAY:
		return
	var state: Dictionary = {
		"flags": {"encounter_leviathan_due": true},
		"battle_outcomes": {},
	}
	assert_eq(_director.check_triggers(state, parsed), "encounter_leviathan")


# --- start：组装引擎 config（绝不调用引擎）-------------------------------------


func test_start_assembles_engine_config() -> void:
	if not _require_director():
		return
	var config: Dictionary = _director.start(_encounter_def(), _content())
	assert_eq(str(config.get("encounter_id", "")), "encounter_test_a")
	assert_eq(int(config.get("seed", -1)), 4242)
	assert_eq(float(config.get("hp_multiplier", 0.0)), 1.0, "缺省 hp_multiplier = 1.0。")

	var allies: Array = config.get("allies", [])
	assert_eq(allies.size(), 2)
	var luoxian: Dictionary = allies[0]
	assert_eq(str(luoxian.get("unit_id", "")), "u_luoxian")
	assert_eq(str(luoxian.get("track", "")), "front")
	assert_eq(luoxian.get("items", {}), {}, "无 item_ids 的盟友不携带道具。")
	var misa: Dictionary = allies[1]
	assert_eq(str(misa.get("unit_id", "")), "u_misa")
	assert_eq(str(misa.get("track", "")), "mid")
	# 按出现次数计数并截上限 2；starsoil_dust 非 battle_usable 剔除。
	assert_eq(misa.get("items", {}), {"sedative_mist": 2, "shock_trap": 1})

	var enemies: Array = config.get("enemies", [])
	assert_eq(enemies.size(), 1)
	var enemy: Dictionary = enemies[0]
	assert_eq(str(enemy.get("unit_id", "")), "u_swarm")
	assert_eq(str(enemy.get("track", "")), "front")

	assert_eq(config.get("unit_defs", {}), UNIT_DEFS, "unit_defs 透传。")
	assert_eq(config.get("action_defs", {}), ACTION_DEFS, "action_defs 透传。")
	assert_false(config.has("units"), "start 只返回 config，不调用引擎产生战斗状态。")
	assert_false(config.has("turn"), "start 只返回 config，不调用引擎产生战斗状态。")
	assert_false(config.has("log"), "start 只返回 config，不调用引擎产生战斗状态。")


func test_start_caps_items_by_inventory_and_skips_zero() -> void:
	if not _require_director():
		return
	# 库存不足按存量截取；库存为 0 的道具不装配。
	var content: Dictionary = _content({"sedative_mist": 1, "shock_trap": 0})
	var config: Dictionary = _director.start(_encounter_def(), content)
	var misa: Dictionary = config.get("allies", [])[1]
	assert_eq(misa.get("items", {}), {"sedative_mist": 1})


func test_start_without_item_defs_equips_nothing() -> void:
	if not _require_director():
		return
	# G7P-2 S4 合法断言更新：battle_usable 判定完全数据驱动后，content 未带
	# item_defs 即无判定数据源 → 失败安全不装配任何道具（旧"回退冻结清单
	# FROZEN_SANDBOX_BATTLE_ITEMS"兜底已随数据化删除，生产路径
	# GameSession._battle_content 始终传入全量 item_defs）。
	var content: Dictionary = _content()
	content.erase("item_defs")
	var config: Dictionary = _director.start(_encounter_def(), content)
	var misa: Dictionary = config.get("allies", [])[1]
	assert_eq(misa.get("items", {}), {})


func test_start_passes_hp_multiplier_through() -> void:
	if not _require_director():
		return
	var content: Dictionary = _content()
	content["hp_multiplier"] = 1.5
	var config: Dictionary = _director.start(_encounter_def(), content)
	assert_eq(float(config.get("hp_multiplier", 0.0)), 1.5)


func test_start_config_is_isolated_from_later_content_mutation() -> void:
	if not _require_director():
		return
	var content: Dictionary = _content()
	var config: Dictionary = _director.start(_encounter_def(), content)
	content["unit_defs"]["u_luoxian"]["max_hp"] = 999
	content["inventory"]["sedative_mist"] = 0
	content["action_defs"].erase("a_strike")
	assert_eq(int(config.get("unit_defs", {}).get("u_luoxian", {}).get("max_hp", 0)), 40)
	assert_eq(int(config.get("allies", [])[1].get("items", {}).get("sedative_mist", 0)), 2)
	assert_true(config.get("action_defs", {}).has("a_strike"))


# --- finish：victory/defeat 落账（真实 GameState）-------------------------------


func test_finish_victory_records_outcome_drops_and_flag_via_real_game_state() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var result: AppResult = director.finish(state, _encounter_def(), _victory_outcome(), store)
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		snapshot.get("battle_outcomes", {}).get("encounter_test_a", {}),
		{"result": "victory", "turns": 3},
		"battle_outcomes 必须记录遭遇 id。"
	)
	assert_eq(int(snapshot.get("inventory", {}).get("starsoil_dust", 0)), 4)
	assert_eq(int(snapshot.get("inventory", {}).get("lumen_shard", 0)), 1)
	assert_eq(bool(snapshot.get("flags", {}).get("encounter_test_a_won", false)), true)
	assert_eq(int(snapshot.get("revision", 0)), int(state.get("revision", 0)) + 1)


func test_finish_defeat_records_only_outcome_via_real_game_state() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var result: AppResult = director.finish(state, _encounter_def(), _defeat_outcome(), store)
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		snapshot.get("battle_outcomes", {}).get("encounter_test_a", {}),
		{"result": "defeat", "turns": 5},
		"战败只记录结果。"
	)
	assert_eq(snapshot.get("inventory", {}), {}, "战败不得发放掉落。")
	assert_false(
		snapshot.get("flags", {}).has("encounter_test_a_won"),
		"战败不得置胜利旗标（due 保留可重试）。"
	)


func test_finish_replay_is_idempotent_via_real_game_state() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	var store: Node = _fresh_game_state()
	var state: Dictionary = store.snapshot()
	var first: AppResult = director.finish(state, _encounter_def(), _victory_outcome(), store)
	assert_true(first.is_ok, first.message)
	# 同一 state（同 revision → 同 source_id）重放 → already_applied，不推进 revision。
	var second: AppResult = director.finish(state, _encounter_def(), _victory_outcome(), store)
	assert_true(second.is_ok, second.message)
	assert_eq(second.code, "already_applied")
	assert_eq(int(store.snapshot().get("revision", 0)), 1, "重放不得推进 revision。")


# --- finish：DuckPatch 替身记录 op 序列 ------------------------------------------


func test_finish_victory_duck_patch_records_operation_sequence() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	_duck_store = DuckStore.new()
	var state: Dictionary = {"revision": 2, "flags": {}, "battle_outcomes": {}, "inventory": {}}
	# amount = 0 的掉落必须被剔除。
	var outcome: Dictionary = {
		"result": "victory",
		"turns": 3,
		"drops": [
			{"item_id": "starsoil_dust", "amount": 4},
			{"item_id": "echo_seed", "amount": 0},
		],
	}
	var result: AppResult = director.finish(state, _encounter_def(), outcome, _duck_store)
	assert_true(result.is_ok, result.message)
	assert_eq(_duck_store.begin_calls, 1, "victory 落账必须是单个 patch。")
	assert_eq(_duck_store.last_source_id, "encounter_encounter_test_a_victory_2")
	assert_eq(_duck_store.last_expected_revision, 2)
	var patch: DuckPatch = _duck_store.committed_patches[0]
	assert_eq(
		_canonical(patch.operations),
		_canonical([
			{"type": "record_battle_outcome", "battle_id": "encounter_test_a", "result": "victory", "turns": 3},
			{"type": "add_item", "item_id": "starsoil_dust", "amount": 4},
			{"type": "set_flag", "flag_id": "encounter_test_a_won", "enabled": true},
		])
	)


func test_finish_defeat_duck_patch_records_only_outcome_op() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	_duck_store = DuckStore.new()
	var state: Dictionary = {"revision": 4, "flags": {}, "battle_outcomes": {}, "inventory": {}}
	var result: AppResult = director.finish(state, _encounter_def(), _defeat_outcome(), _duck_store)
	assert_true(result.is_ok, result.message)
	assert_eq(_duck_store.last_source_id, "encounter_encounter_test_a_defeat_4")
	assert_eq(_duck_store.last_expected_revision, 4)
	var patch: DuckPatch = _duck_store.committed_patches[0]
	assert_eq(
		_canonical(patch.operations),
		_canonical([
			{"type": "record_battle_outcome", "battle_id": "encounter_test_a", "result": "defeat", "turns": 5},
		])
	)


func test_finish_rejects_unfinished_outcome_without_touching_store() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	_duck_store = DuckStore.new()
	var outcome: Dictionary = {"result": "", "turns": 1, "drops": []}
	var result: AppResult = director.finish({"revision": 1}, _encounter_def(), outcome, _duck_store)
	assert_false(result.is_ok, "未结束（result 为空）的 outcome 必须干净失败。")
	assert_eq(_duck_store.begin_calls, 0, "失败路径不得触碰 store。")


func test_finish_rejects_missing_encounter_id_without_touching_store() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	_duck_store = DuckStore.new()
	var bad_def: Dictionary = _encounter_def()
	bad_def.erase("id")
	var result: AppResult = director.finish({"revision": 1}, bad_def, _victory_outcome(), _duck_store)
	assert_false(result.is_ok, "缺失 id 的遭遇定义必须干净失败。")
	assert_eq(_duck_store.begin_calls, 0, "失败路径不得触碰 store。")


func test_finish_uses_game_state_autoload_when_store_is_null() -> void:
	var director: RefCounted = _director_instance()
	if director == null:
		return
	# store 缺省（null）→ 契约 §0 默认走 GameState autoload。全局 autoload 可能被
	# 其他测试推进过 revision，因此先取快照再落账。
	var probe_id := "encounter_wp13_default_store_probe"
	var probe_def: Dictionary = _encounter_def()
	probe_def["id"] = probe_id
	probe_def["on_victory_flag"] = "encounter_wp13_default_store_probe_won"
	var state: Dictionary = GameState.snapshot()
	var result: AppResult = director.finish(state, probe_def, _victory_outcome())
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = GameState.snapshot()
	assert_eq(
		snapshot.get("battle_outcomes", {}).get(probe_id, {}),
		{"result": "victory", "turns": 3}
	)
	assert_eq(bool(snapshot.get("flags", {}).get("encounter_wp13_default_store_probe_won", false)), true)


# --- 测试替身：契约 §0 注入 store 的 DuckPatch/DuckStore -----------------------


class DuckPatch extends RefCounted:
	## 测试替身：记录操作序列，模拟 StatePatch 的可链式调用形状。
	var source_id: String = ""
	var expected_revision: int = -1
	var operations: Array[Dictionary] = []

	func record_battle_outcome(battle_id: String, result: String, turns: int) -> DuckPatch:
		operations.append({
			"type": "record_battle_outcome",
			"battle_id": battle_id,
			"result": result,
			"turns": turns,
		})
		return self

	func add_item(item_id: String, amount: int) -> DuckPatch:
		operations.append({"type": "add_item", "item_id": item_id, "amount": amount})
		return self

	func set_flag(flag_id: String, enabled: bool) -> DuckPatch:
		operations.append({"type": "set_flag", "flag_id": flag_id, "enabled": enabled})
		return self


class DuckStore extends RefCounted:
	## 测试替身：模拟契约 §0 的注入 store（begin_patch/commit 语义）。
	var begin_calls: int = 0
	var last_source_id: String = ""
	var last_expected_revision: int = -1
	var committed_patches: Array = []

	func begin_patch(p_source_id: String, p_expected_revision: int) -> DuckPatch:
		begin_calls += 1
		last_source_id = p_source_id
		last_expected_revision = p_expected_revision
		var patch: DuckPatch = DuckPatch.new()
		patch.source_id = p_source_id
		patch.expected_revision = p_expected_revision
		committed_patches.append(patch)
		return patch

	func commit(_patch: Variant) -> AppResult:
		return AppResult.success({}, "committed")
