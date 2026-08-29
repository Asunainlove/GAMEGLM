extends GutTest

## WP10 战斗核心单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 本地夹具照冻结契约 §7：2 盟友（luoxian_fighter/misa_weaver）+ 2 敌
## （drift_swarmling/shard_husk）+ Boss lumen_leviathan（0.5 血相位切换）；
## 行动池 strike/guard/resonate_pulse/mist_calm；沙盒道具 sedative_mist。
## 不依赖 ContentDB/GameState；脚本运行时加载（绝不 preload），
## 缺失实现以失败断言暴露而非静默跳过。

const COMBAT_ENGINE_PATH: String = "res://src/combat/combat_engine.gd"

const A_LUOXIAN: String = "a0|luoxian_fighter"
const A_MISA: String = "a1|misa_weaver"
const A_MISA_SOLO: String = "a0|misa_weaver"
const E_SWARM: String = "e0|drift_swarmling"
const E_HUSK: String = "e1|shard_husk"
const E_LEVIATHAN: String = "e0|lumen_leviathan"

const ACTION_DEFS: Dictionary = {
	"strike": {
		"id": "strike", "kind": "attack", "name_zh": "打击",
		"targeting": "single_enemy", "power": 10, "stability_damage": 0,
	},
	"guard": {
		"id": "guard", "kind": "guard", "name_zh": "守御",
		"targeting": "self", "power": 0, "stability_damage": 0, "guard_ratio": 0.5,
	},
	"resonate_pulse": {
		"id": "resonate_pulse", "kind": "skill", "name_zh": "共鸣脉冲",
		"targeting": "all_enemies", "power": 6, "stability_damage": 2,
	},
	"mist_calm": {
		"id": "mist_calm", "kind": "item", "name_zh": "定神雾",
		"targeting": "single_ally", "power": 0, "stability_damage": 0,
		"heal": 8, "cost": {"item_id": "sedative_mist", "count": 1},
	},
}

const UNIT_DEFS: Dictionary = {
	"luoxian_fighter": {
		"id": "luoxian_fighter", "kind": "ally", "name_zh": "洛弦",
		"max_hp": 40, "stability_max": 4, "track": "front", "speed": 7,
		"action_ids": ["strike", "guard"],
	},
	"misa_weaver": {
		"id": "misa_weaver", "kind": "ally", "name_zh": "弥砂",
		"max_hp": 28, "stability_max": 3, "track": "mid", "speed": 5,
		"action_ids": ["resonate_pulse", "mist_calm", "guard"],
	},
	"drift_swarmling": {
		"id": "drift_swarmling", "kind": "enemy_normal", "name_zh": "漂泊虫群",
		"max_hp": 20, "stability_max": 2, "track": "front", "speed": 6,
		"action_ids": ["strike"],
		"drops": [{"item_id": "starsoil_dust", "amount": 2}],
	},
	"shard_husk": {
		"id": "shard_husk", "kind": "enemy_normal", "name_zh": "碎屑甲壳",
		"max_hp": 24, "stability_max": 3, "track": "mid", "speed": 4,
		"action_ids": ["strike", "guard"],
		"drops": [
			{"item_id": "starsoil_dust", "amount": 1},
			{"item_id": "lumen_shard", "amount": 1},
		],
	},
	"lumen_leviathan": {
		"id": "lumen_leviathan", "kind": "boss", "name_zh": "辉光利维坦",
		"max_hp": 40, "stability_max": 5, "track": "front", "speed": 3,
		"action_ids": ["strike"],
		"phases": [{"id": "leviathan_p2", "at_hp_ratio": 0.5, "action_ids": ["resonate_pulse"]}],
		"drops": [
			{"item_id": "echo_seed", "amount": 1},
			{"item_id": "lumen_shard", "amount": 2},
		],
	},
}

var _engine: Script = null


func before_all() -> void:
	_engine = load(COMBAT_ENGINE_PATH)


# --- 夹具与断言辅助 ------------------------------------------------------------


func _require_engine() -> bool:
	if _engine == null:
		fail_test("Missing required WP10 implementation: %s" % COMBAT_ENGINE_PATH)
		return false
	return true


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _config() -> Dictionary:
	## 标准夹具：2 盟友 + 2 敌（§7）；每次调用返回全新深拷贝，测试可安全改写。
	return {
		"allies": [
			{"unit_id": "luoxian_fighter", "track": "front"},
			{"unit_id": "misa_weaver", "track": "mid", "items": {"sedative_mist": 2}},
		],
		"enemies": [
			{"unit_id": "drift_swarmling", "track": "front"},
			{"unit_id": "shard_husk", "track": "mid"},
		],
		"seed": 42,
		"unit_defs": UNIT_DEFS.duplicate(true),
		"action_defs": ACTION_DEFS.duplicate(true),
	}


func _defs_with(unit_overrides: Dictionary) -> Dictionary:
	## unit_overrides: {unit_id: {field: value}}；对 UNIT_DEFS 深拷贝后逐单位合并。
	var defs: Dictionary = UNIT_DEFS.duplicate(true)
	for unit_id: String in unit_overrides:
		var unit_def: Dictionary = defs.get(unit_id, {})
		var overrides: Dictionary = unit_overrides[unit_id]
		for key: String in overrides:
			unit_def[key] = overrides[key]
		defs[unit_id] = unit_def
	return defs


func _boss_config() -> Dictionary:
	var config: Dictionary = _config()
	config["allies"] = [{"unit_id": "luoxian_fighter", "track": "front"}]
	config["enemies"] = [{"unit_id": "lumen_leviathan", "track": "front"}]
	return config


func _misa_duel_config() -> Dictionary:
	var config: Dictionary = _config()
	config["allies"] = [{"unit_id": "misa_weaver", "track": "mid", "items": {"sedative_mist": 2}}]
	config["enemies"] = [{"unit_id": "drift_swarmling", "track": "front"}]
	return config


func _sequence_a() -> Array:
	## 标准夹具确定性序列 A：击杀虫群（含失稳 ×1.5 伤害）。
	return [
		[A_LUOXIAN, "strike", E_SWARM],
		[A_MISA, "resonate_pulse", ""],
		[A_LUOXIAN, "strike", E_SWARM],
	]


func _sequence_b() -> Array:
	## 标准夹具确定性序列 B：失稳跳过与恢复后虫群恢复行动。
	return [
		[A_LUOXIAN, "strike", E_SWARM],
		[A_MISA, "resonate_pulse", ""],
		[A_LUOXIAN, "guard", A_LUOXIAN],
		[A_MISA, "guard", A_MISA],
		[A_LUOXIAN, "strike", E_HUSK],
	]


func _run(battle: Dictionary, steps: Array) -> Dictionary:
	for step: Array in steps:
		battle = _engine.submit_action(battle, str(step[0]), str(step[1]), str(step[2]))
	return battle


func _unit(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Dictionary in battle.get("units", []):
		if str(unit.get("key", "")) == unit_key:
			return unit
	return {}


func _count_entries(log: Array, pattern: Dictionary) -> int:
	var count := 0
	for entry: Dictionary in log:
		var matched := true
		for key: String in pattern:
			if entry.get(key) != pattern[key]:
				matched = false
				break
		if matched:
			count += 1
	return count


func _has_entry(log: Array, pattern: Dictionary) -> bool:
	return _count_entries(log, pattern) > 0


func _has_action_after_round(log: Array, round_turn: int, unit_key: String) -> bool:
	var seen_round := false
	for entry: Dictionary in log:
		if not seen_round:
			if str(entry.get("type", "")) == "round_start" and int(entry.get("turn", 0)) == round_turn:
				seen_round = true
			continue
		if str(entry.get("type", "")) == "action" and str(entry.get("unit", "")) == unit_key:
			return true
	return false


func _without_log(battle: Dictionary) -> Dictionary:
	var copy: Dictionary = battle.duplicate(true)
	copy.erase("log")
	return copy


func _assert_error_submission(
		battle_before: Dictionary,
		unit_key: String,
		action_id: String,
		target_key: String,
		expected_code: String
) -> Dictionary:
	var snapshot: String = _canonical(_without_log(battle_before))
	var result: Dictionary = _engine.submit_action(battle_before, unit_key, action_id, target_key)
	var log: Array = result.get("log", [])
	assert_true(log.size() > 0, "expected an error log entry for %s" % expected_code)
	if log.size() > 0:
		var entry: Dictionary = log[log.size() - 1]
		assert_eq(str(entry.get("type", "")), "error", "last log entry type")
		assert_eq(str(entry.get("code", "")), expected_code, "error code")
	assert_eq(
		_canonical(_without_log(result)),
		snapshot,
		"error result must equal input battle besides the appended log"
	)
	return result


# --- create_battle -------------------------------------------------------------


func test_create_battle_builds_units_order_and_defaults() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	assert_eq(str(battle.get("battle_id", "")), "battle_42")
	assert_eq(int(battle.get("seed", 0)), 42)
	assert_eq(int(battle.get("turn", 0)), 1)
	assert_eq(int(battle.get("active_index", -1)), 0)
	assert_eq(bool(battle.get("finished", true)), false)
	assert_eq(str(battle.get("result", "x")), "")
	assert_eq(float(battle.get("hp_multiplier", 0.0)), 1.0)
	assert_eq(battle.get("log", []).size(), 0)

	var unit_keys: Array = []
	for unit: Dictionary in battle.get("units", []):
		unit_keys.append(str(unit.get("key", "")))
	assert_eq(unit_keys, [A_LUOXIAN, A_MISA, E_SWARM, E_HUSK], "units follow config order")

	var order: Array = battle.get("order", [])
	assert_eq(order, [A_LUOXIAN, E_SWARM, A_MISA, E_HUSK], "order is speed desc")

	var luoxian: Dictionary = _unit(battle, A_LUOXIAN)
	assert_eq(str(luoxian.get("side", "")), "ally")
	assert_eq(str(luoxian.get("track", "")), "front")
	assert_eq(int(luoxian.get("hp", 0)), 40)
	assert_eq(int(luoxian.get("max_hp", 0)), 40)
	assert_eq(int(luoxian.get("stability", 0)), 4)
	assert_eq(int(luoxian.get("stability_max", 0)), 4)
	assert_eq(int(luoxian.get("speed", 0)), 7)
	assert_eq(luoxian.get("action_ids", []), ["strike", "guard"])
	assert_eq(bool(luoxian.get("alive", false)), true)
	assert_eq(float(luoxian.get("guard_ratio", -1.0)), 0.0)
	assert_eq(luoxian.get("items", {"x": 1}), {})
	assert_eq(bool(luoxian.get("destabilized", true)), false)

	var misa: Dictionary = _unit(battle, A_MISA)
	assert_eq(misa.get("items", {}), {"sedative_mist": 2}, "config items carried onto the unit")
	assert_eq(misa.get("action_ids", []), ["resonate_pulse", "mist_calm", "guard"])

	var swarm: Dictionary = _unit(battle, E_SWARM)
	assert_eq(str(swarm.get("side", "")), "enemy")
	assert_eq(swarm.get("drops", []), [{"item_id": "starsoil_dust", "amount": 2}])
	assert_eq(swarm.get("phases", []), [])

	var husk: Dictionary = _unit(battle, E_HUSK)
	assert_eq(husk.get("drops", []).size(), 2)


func test_create_battle_copies_boss_data_and_isolates_config() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _boss_config()
	var battle: Dictionary = _engine.create_battle(config)
	var boss: Dictionary = _unit(battle, E_LEVIATHAN)
	assert_eq(boss.get("phases", []), UNIT_DEFS["lumen_leviathan"]["phases"], "phases copied")
	assert_eq(boss.get("drops", []).size(), 2, "drops copied into the unit")
	assert_eq(boss.get("action_ids", []), ["strike"])

	config["unit_defs"]["lumen_leviathan"]["phases"][0]["action_ids"][0] = "corrupted_id"
	config["action_defs"]["strike"]["power"] = 999

	var result: Dictionary = _engine.submit_action(battle, A_LUOXIAN, "strike", E_LEVIATHAN)
	assert_eq(
		_unit(result, E_LEVIATHAN).get("phases", []),
		UNIT_DEFS["lumen_leviathan"]["phases"],
		"battle keeps its own deep copy of phases"
	)
	assert_true(
		_has_entry(result.get("log", []), {"type": "damage", "source": A_LUOXIAN, "target": E_LEVIATHAN, "amount": 10}),
		"battle keeps its own deep copy of action_defs (damage stays 10)"
	)


func test_create_battle_applies_hp_multiplier_with_ceiling() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["hp_multiplier"] = 1.5
	var battle: Dictionary = _engine.create_battle(config)
	assert_eq(float(battle.get("hp_multiplier", 0.0)), 1.5)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 60)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("max_hp", 0)), 60)
	assert_eq(int(_unit(battle, A_MISA).get("max_hp", 0)), 42)
	assert_eq(int(_unit(battle, E_SWARM).get("max_hp", 0)), 30)
	assert_eq(int(_unit(battle, E_HUSK).get("max_hp", 0)), 36)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("stability_max", 0)), 4, "stability is not scaled")
	assert_eq(int(_unit(battle, A_LUOXIAN).get("speed", 0)), 7, "speed is not scaled")

	var probe_defs: Dictionary = {
		"probe_unit": {
			"id": "probe_unit", "kind": "ally", "name_zh": "探针",
			"max_hp": 25, "stability_max": 1, "track": "rear", "speed": 1,
			"action_ids": ["guard"],
		},
	}
	var probe_config: Dictionary = {
		"allies": [{"unit_id": "probe_unit", "track": "rear"}],
		"enemies": [],
		"seed": 7,
		"unit_defs": probe_defs,
		"action_defs": ACTION_DEFS.duplicate(true),
		"hp_multiplier": 1.5,
	}
	var probe_battle: Dictionary = _engine.create_battle(probe_config)
	assert_eq(
		int(_unit(probe_battle, "a0|probe_unit").get("max_hp", 0)),
		38,
		"25 * 1.5 = 37.5 must ceil to 38"
	)


func test_create_battle_breaks_speed_ties_by_key_ascending() -> void:
	if not _require_engine():
		return
	var tie_defs: Dictionary = {
		"bravo_unit": {
			"id": "bravo_unit", "kind": "ally", "name_zh": "乙",
			"max_hp": 10, "stability_max": 1, "track": "front", "speed": 5,
			"action_ids": ["guard"],
		},
		"alpha_unit": {
			"id": "alpha_unit", "kind": "ally", "name_zh": "甲",
			"max_hp": 10, "stability_max": 1, "track": "mid", "speed": 5,
			"action_ids": ["guard"],
		},
		"charlie_unit": {
			"id": "charlie_unit", "kind": "enemy_normal", "name_zh": "丙",
			"max_hp": 10, "stability_max": 1, "track": "rear", "speed": 5,
			"action_ids": ["guard"],
		},
		"delta_unit": {
			"id": "delta_unit", "kind": "enemy_normal", "name_zh": "丁",
			"max_hp": 10, "stability_max": 1, "track": "rear", "speed": 9,
			"action_ids": ["guard"],
		},
	}
	var config: Dictionary = {
		"allies": [
			{"unit_id": "bravo_unit", "track": "front"},
			{"unit_id": "alpha_unit", "track": "mid"},
		],
		"enemies": [
			{"unit_id": "charlie_unit", "track": "rear"},
			{"unit_id": "delta_unit", "track": "rear"},
		],
		"seed": 1,
		"unit_defs": tie_defs,
		"action_defs": ACTION_DEFS.duplicate(true),
	}
	var battle: Dictionary = _engine.create_battle(config)
	assert_eq(
		battle.get("order", []),
		["e1|delta_unit", "a0|bravo_unit", "a1|alpha_unit", "e0|charlie_unit"],
		"speed desc first, then key lexicographic asc"
	)


# --- 纯函数性 -------------------------------------------------------------------


func test_submit_action_never_mutates_inputs_and_create_never_mutates_config() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	var config_snapshot: String = _canonical(config)
	var battle: Dictionary = _engine.create_battle(config)
	assert_eq(_canonical(config), config_snapshot, "create_battle must not mutate config")

	var battle_snapshot: String = _canonical(battle)
	var result: Dictionary = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(_canonical(battle), battle_snapshot, "submit_action must not mutate input battle")
	assert_eq(int(_unit(result, E_SWARM).get("hp", 0)), 10, "result carries the applied damage")
	assert_true(result.get("log", []).size() > battle.get("log", []).size(), "result log grew")


# --- 伤害 / 击杀 / 胜负 / 掉落 ----------------------------------------------------


func test_strike_damage_kill_and_victory_with_drops() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["allies"] = [{"unit_id": "luoxian_fighter", "track": "front"}]
	config["enemies"] = [{"unit_id": "drift_swarmling", "track": "front"}]
	var battle: Dictionary = _engine.create_battle(config)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 10)
	assert_true(_has_entry(battle.get("log", []), {"type": "damage", "source": A_LUOXIAN, "target": E_SWARM, "amount": 10}))
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 30, "enemy AI answered with its own strike")
	assert_eq(bool(_engine.is_finished(battle)), false)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 0)
	assert_eq(bool(_unit(battle, E_SWARM).get("alive", true)), false)
	assert_eq(bool(_engine.is_finished(battle)), true)
	assert_true(_has_entry(battle.get("log", []), {"type": "defeated", "unit": E_SWARM}))
	assert_true(_has_entry(battle.get("log", []), {"type": "battle_end", "result": "victory"}))
	assert_eq(
		_engine.outcome(battle),
		{"result": "victory", "turns": 2, "drops": [{"item_id": "starsoil_dust", "amount": 2}]},
		"victory outcome aggregates the defeated enemy's drops"
	)


func test_defeat_when_all_allies_fall() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["allies"] = [{"unit_id": "luoxian_fighter", "track": "front"}]
	config["unit_defs"] = _defs_with({"luoxian_fighter": {"max_hp": 5}})
	var battle: Dictionary = _engine.create_battle(config)
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(bool(_engine.is_finished(battle)), true)
	assert_eq(
		_engine.outcome(battle),
		{"result": "defeat", "turns": 1, "drops": []},
		"defeat outcome carries no drops"
	)


func test_outcome_reports_empty_result_while_unfinished() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	assert_eq(
		_engine.outcome(battle),
		{"result": "", "turns": 1, "drops": []},
		"unfinished battle reports empty result"
	)
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(_engine.outcome(battle).get("result", "x"), "")


# --- 守卫 -----------------------------------------------------------------------


func test_guard_halves_damage() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	battle = _engine.submit_action(battle, A_MISA, "guard", A_MISA)
	assert_eq(float(_unit(battle, A_MISA).get("guard_ratio", 0.0)), 0.5)
	assert_true(_has_entry(battle.get("log", []), {"type": "guard", "unit": A_MISA, "ratio": 0.5}))
	assert_true(
		_has_entry(battle.get("log", []), {"type": "damage", "source": E_HUSK, "target": A_MISA, "amount": 5}),
		"husk strike 10 is halved to 5 by the fresh guard"
	)
	assert_eq(int(_unit(battle, A_MISA).get("hp", 0)), 13, "28 - 10 (round 1) - 5 (guarded)")


func test_guard_persists_across_round_boundary_and_clears_on_next_action() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["allies"] = [{"unit_id": "luoxian_fighter", "track": "front"}]
	config["enemies"] = [{"unit_id": "drift_swarmling", "track": "front"}]
	config["unit_defs"] = _defs_with({
		"luoxian_fighter": {"speed": 3},
		"drift_swarmling": {"speed": 9},
	})
	var battle: Dictionary = _engine.create_battle(config)

	assert_eq(battle.get("order", []), [E_SWARM, A_LUOXIAN], "faster enemy acts first")
	battle = _engine.submit_action(battle, E_SWARM, "", "")
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 30)

	battle = _engine.submit_action(battle, A_LUOXIAN, "guard", A_LUOXIAN)
	assert_eq(int(battle.get("turn", 0)), 2, "round boundary crossed inside the same submit")
	assert_eq(battle.get("order", []), [E_SWARM, A_LUOXIAN], "order rebuilt at the boundary")
	assert_true(
		_has_entry(battle.get("log", []), {"type": "damage", "source": E_SWARM, "target": A_LUOXIAN, "amount": 5}),
		"guard set in round 1 still halves the round 2 strike"
	)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 25)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(float(_unit(battle, A_LUOXIAN).get("guard_ratio", -1.0)), 0.0, "guard clears when its owner acts")
	assert_true(
		_has_entry(battle.get("log", []), {"type": "damage", "source": E_SWARM, "target": A_LUOXIAN, "amount": 10}),
		"strike after guarding takes full damage again"
	)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 15)
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 10)


# --- 失稳 -----------------------------------------------------------------------


func test_destabilized_target_takes_amp_damage() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _run(battle, _sequence_a())
	assert_true(
		_has_entry(battle.get("log", []), {"type": "destabilized", "unit": E_SWARM}),
		"resonate_pulse zeroes swarmling stability"
	)
	assert_true(
		_has_entry(battle.get("log", []), {"type": "damage", "source": A_LUOXIAN, "target": E_SWARM, "amount": 15}),
		"strike 10 on a destabilized target logs 15 (x1.5)"
	)
	assert_eq(bool(_unit(battle, E_SWARM).get("alive", true)), false)
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 0)
	assert_eq(bool(_engine.is_finished(battle)), false, "husk still stands")


func test_destabilized_unit_skips_next_turn_and_recovers() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	var steps: Array = _sequence_b()
	battle = _run(battle, steps.slice(0, 3))
	var swarm: Dictionary = _unit(battle, E_SWARM)
	assert_eq(int(swarm.get("stability", 0)), 2, "stability restored to stability_max at its own turn start")
	assert_eq(bool(swarm.get("destabilized", true)), false)
	assert_eq(bool(swarm.get("alive", false)), true)
	assert_eq(int(swarm.get("hp", 0)), 4)
	assert_true(_has_entry(battle.get("log", []), {"type": "destabilized_recover", "unit": E_SWARM}))
	assert_true(_has_entry(battle.get("log", []), {"type": "turn_skipped", "unit": E_SWARM, "reason": "destabilized"}))
	assert_eq(int(battle.get("turn", 0)), 2)
	assert_eq(str(_engine.active_unit(battle).get("key", "")), A_MISA)

	battle = _engine.submit_action(battle, A_MISA, "guard", A_MISA)
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_HUSK)
	assert_true(
		_has_action_after_round(battle.get("log", []), 3, E_SWARM),
		"swarmling acts again in round 3 after recovering"
	)
	assert_true(_has_entry(battle.get("log", []), {"type": "defeated", "unit": A_MISA}))
	assert_eq(bool(_engine.is_finished(battle)), false)
	assert_eq(int(battle.get("turn", 0)), 4)


# --- Boss 相位 ------------------------------------------------------------------


func test_boss_switches_phase_once_at_half_hp() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_boss_config())

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_LEVIATHAN)
	assert_eq(_count_entries(battle.get("log", []), {"type": "phase_change"}), 0, "0.75 ratio keeps phase 1")
	assert_eq(_unit(battle, E_LEVIATHAN).get("action_ids", []), ["strike"])
	assert_eq(int(_unit(battle, E_LEVIATHAN).get("hp", 0)), 30)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_LEVIATHAN)
	assert_eq(_count_entries(battle.get("log", []), {"type": "phase_change"}), 1, "0.5 ratio switches once")
	assert_true(_has_entry(battle.get("log", []), {"type": "phase_change", "unit": E_LEVIATHAN, "phase": "leviathan_p2"}))
	assert_eq(_unit(battle, E_LEVIATHAN).get("action_ids", []), ["resonate_pulse"])
	assert_eq(int(_unit(battle, E_LEVIATHAN).get("hp", 0)), 20)
	assert_true(
		_has_entry(battle.get("log", []), {"type": "damage", "source": E_LEVIATHAN, "target": A_LUOXIAN, "amount": 6}),
		"boss immediately uses its new phase actions"
	)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_LEVIATHAN)
	assert_eq(_count_entries(battle.get("log", []), {"type": "phase_change"}), 1, "phase switch is latched")
	assert_eq(int(_unit(battle, E_LEVIATHAN).get("hp", 0)), 10)
	assert_eq(bool(_unit(battle, A_LUOXIAN).get("destabilized", true)), false, "ally recovered at its skipped turn")
	assert_eq(
		int(_unit(battle, A_LUOXIAN).get("stability", 0)),
		2,
		"recovered to 4 at the skipped turn, then the round 4 pulse took 2 again"
	)
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 12, "three pulses of 6 (no x1.5: recovered before each)")
	assert_eq(int(battle.get("turn", 0)), 5)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_LEVIATHAN)
	assert_eq(bool(_engine.is_finished(battle)), true)
	assert_eq(
		_engine.outcome(battle),
		{
			"result": "victory",
			"turns": 5,
			"drops": [{"item_id": "echo_seed", "amount": 1}, {"item_id": "lumen_shard", "amount": 2}],
		},
		"boss drops are aggregated and sorted by item_id"
	)


# --- 敌人 AI 确定性 ----------------------------------------------------------------


func test_enemy_auto_turns_are_deterministic_across_runs() -> void:
	if not _require_engine():
		return
	var battle_one: Dictionary = _engine.create_battle(_config())
	battle_one = _run(battle_one, _sequence_a())
	var battle_two: Dictionary = _engine.create_battle(_config())
	battle_two = _run(battle_two, _sequence_a())
	assert_eq(
		_canonical(battle_one),
		_canonical(battle_two),
		"same config plus same operation sequence yields an identical battle state"
	)

	var battle_three: Dictionary = _engine.create_battle(_config())
	battle_three["seed"] = 7
	battle_three["battle_id"] = "battle_7"
	battle_three = _run(battle_three, _sequence_a())
	assert_eq(battle_one.get("log", []), battle_three.get("log", []), "AI does not depend on the seed")
	assert_eq(_engine.outcome(battle_one), _engine.outcome(battle_three))


# --- 道具消耗 --------------------------------------------------------------------


func test_item_cost_deducted_until_exhausted_then_blocks_ally() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_misa_duel_config())

	battle = _engine.submit_action(battle, E_SWARM, "", "")
	assert_eq(int(_unit(battle, A_MISA_SOLO).get("hp", 0)), 18, "faster swarmling opens with a strike")

	battle = _engine.submit_action(battle, A_MISA_SOLO, "mist_calm", A_MISA_SOLO)
	assert_eq(_unit(battle, A_MISA_SOLO).get("items", {}), {"sedative_mist": 1}, "one sedative_mist paid")
	assert_true(_has_entry(battle.get("log", []), {"type": "heal", "source": A_MISA_SOLO, "target": A_MISA_SOLO, "amount": 8}))
	assert_eq(int(_unit(battle, A_MISA_SOLO).get("hp", 0)), 16, "18 healed to 26, then struck to 16")

	battle = _engine.submit_action(battle, A_MISA_SOLO, "mist_calm", A_MISA_SOLO)
	assert_eq(_unit(battle, A_MISA_SOLO).get("items", {}), {}, "last sedative_mist paid and key erased")
	assert_eq(int(_unit(battle, A_MISA_SOLO).get("hp", 0)), 14)

	battle = _engine.submit_action(battle, A_MISA_SOLO, "mist_calm", A_MISA_SOLO)
	var log: Array = battle.get("log", [])
	assert_true(log.size() > 0)
	assert_eq(str(log[log.size() - 1].get("type", "")), "error")
	assert_eq(str(log[log.size() - 1].get("code", "")), "insufficient_cost")
	assert_eq(_unit(battle, A_MISA_SOLO).get("items", {}), {})
	assert_eq(int(_unit(battle, A_MISA_SOLO).get("hp", 0)), 14, "failed action has no effect")
	assert_eq(int(battle.get("turn", 0)), 3, "failed action does not consume the turn")
	assert_eq(str(_engine.active_unit(battle).get("key", "")), A_MISA_SOLO)


func test_enemy_ai_skips_unaffordable_item_action() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["unit_defs"] = _defs_with({"shard_husk": {"action_ids": ["mist_calm", "strike"]}})
	config["enemies"][1]["items"] = {"sedative_mist": 1}
	var battle: Dictionary = _engine.create_battle(config)

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	battle = _engine.submit_action(battle, A_MISA, "guard", A_MISA)
	assert_eq(_unit(battle, E_HUSK).get("items", {}), {}, "husk paid its only sedative_mist")
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 18, "husk healed the lowest-hp own-side unit")
	assert_true(_has_entry(battle.get("log", []), {"type": "heal", "source": E_HUSK, "target": E_SWARM, "amount": 8}))

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	battle = _engine.submit_action(battle, A_MISA, "guard", A_MISA)
	assert_eq(_count_entries(battle.get("log", []), {"type": "heal", "source": E_HUSK}), 1, "no second heal")
	var husk_actions := 0
	var last_husk_action := ""
	for entry: Dictionary in battle.get("log", []):
		if str(entry.get("type", "")) == "action" and str(entry.get("unit", "")) == E_HUSK:
			husk_actions += 1
			last_husk_action = str(entry.get("action", ""))
	assert_eq(husk_actions, 2)
	assert_eq(last_husk_action, "strike", "unaffordable item action falls back to strike")
	assert_eq(
		int(_unit(battle, A_MISA).get("hp", 0)),
		8,
		"guard set in s2 persists through s3 (swarm strike halved to 5) and s4 guard halves husk strike to 5: 18-5-5"
	)
	assert_eq(bool(_unit(battle, A_MISA).get("alive", true)), true)
	assert_eq(bool(_engine.is_finished(battle)), false)


# --- 回合推进 --------------------------------------------------------------------


func test_turn_increments_and_order_rebuild_excludes_fallen() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(int(battle.get("turn", 0)), 1)
	battle = _engine.submit_action(battle, A_MISA, "resonate_pulse", "")
	assert_eq(int(battle.get("turn", 0)), 2, "boundary crossed after the last unit of round 1")

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	battle = _engine.submit_action(battle, A_MISA, "guard", A_MISA)
	assert_eq(int(battle.get("turn", 0)), 3)
	assert_eq(
		battle.get("order", []),
		[A_LUOXIAN, A_MISA, E_HUSK],
		"rebuilt order excludes the defeated swarmling"
	)
	assert_true(
		_has_entry(battle.get("log", []), {"type": "round_start", "turn": 3}),
		"round boundary is logged"
	)


func test_active_unit_and_is_finished_helpers() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	assert_eq(bool(_engine.is_finished(battle)), false)
	assert_eq(str(_engine.active_unit(battle).get("key", "")), A_LUOXIAN)

	var returned: Dictionary = _engine.active_unit(battle)
	returned["hp"] = 999
	assert_eq(int(_unit(battle, A_LUOXIAN).get("hp", 0)), 40, "active_unit returns a copy")

	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(str(_engine.active_unit(battle).get("key", "")), A_MISA, "advances to the next ally")

	var boss_battle: Dictionary = _engine.create_battle(_boss_config())
	boss_battle = _run(boss_battle, [
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
	])
	assert_eq(bool(_engine.is_finished(boss_battle)), true)


# --- 非法行动 --------------------------------------------------------------------


func test_error_when_unit_is_not_active() -> void:
	if not _require_engine():
		return
	_assert_error_submission(_engine.create_battle(_config()), A_MISA, "guard", A_MISA, "not_active_unit")


func test_error_when_unit_is_unknown() -> void:
	if not _require_engine():
		return
	_assert_error_submission(_engine.create_battle(_config()), "e9|ghost", "strike", E_SWARM, "unknown_unit")


func test_error_when_action_not_in_unit_actions() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _assert_error_submission(battle, A_LUOXIAN, "resonate_pulse", E_SWARM, "unknown_action")
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_true(_has_entry(battle.get("log", []), {"type": "action", "unit": A_LUOXIAN, "action": "strike"}))
	assert_eq(str(_engine.active_unit(battle).get("key", "")), A_MISA, "valid action still works after an error")


func test_error_when_action_def_is_missing() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["unit_defs"] = _defs_with({"luoxian_fighter": {"action_ids": ["phantom_step"]}})
	var battle: Dictionary = _engine.create_battle(config)
	_assert_error_submission(battle, A_LUOXIAN, "phantom_step", E_SWARM, "unknown_action")


func test_error_when_target_side_or_self_is_invalid() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _assert_error_submission(battle, A_LUOXIAN, "strike", A_MISA, "invalid_target")
	battle = _assert_error_submission(battle, A_LUOXIAN, "guard", A_MISA, "invalid_target")
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	_assert_error_submission(battle, A_MISA, "mist_calm", E_SWARM, "invalid_target")
	_assert_error_submission(battle, A_MISA, "mist_calm", "", "invalid_target")


func test_error_when_targeting_defeated_unit() -> void:
	if not _require_engine():
		return
	var config: Dictionary = _config()
	config["unit_defs"] = _defs_with({
		"misa_weaver": {"action_ids": ["strike"]},
		"drift_swarmling": {"max_hp": 10},
	})
	var battle: Dictionary = _engine.create_battle(config)
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	assert_eq(bool(_unit(battle, E_SWARM).get("alive", true)), false)
	_assert_error_submission(battle, A_MISA, "strike", E_SWARM, "invalid_target")


func test_error_when_battle_already_finished() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_boss_config())
	battle = _run(battle, [
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
		[A_LUOXIAN, "strike", E_LEVIATHAN],
	])
	assert_eq(bool(_engine.is_finished(battle)), true)
	_assert_error_submission(battle, A_LUOXIAN, "strike", E_LEVIATHAN, "battle_finished")


func test_all_enemies_accepts_empty_target() -> void:
	if not _require_engine():
		return
	var battle: Dictionary = _engine.create_battle(_config())
	battle = _engine.submit_action(battle, A_LUOXIAN, "strike", E_SWARM)
	battle = _engine.submit_action(battle, A_MISA, "resonate_pulse", "")
	assert_true(_has_entry(battle.get("log", []), {"type": "damage", "source": A_MISA, "target": E_SWARM, "amount": 6}))
	assert_true(_has_entry(battle.get("log", []), {"type": "damage", "source": A_MISA, "target": E_HUSK, "amount": 6}))
	assert_eq(int(_unit(battle, E_SWARM).get("hp", 0)), 4)
	assert_eq(int(_unit(battle, E_HUSK).get("hp", 0)), 18)
