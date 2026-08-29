class_name CombatEngine
extends RefCounted

## WP10 战斗核心：纯逻辑回合制引擎（RefCounted，全部 static，无节点/场景/GameState 依赖）。
## 战斗状态即 Dictionary；`submit_action` 为纯函数（深拷贝入参后处理，入参绝不修改）。
## 契约：docs/plans/contracts/module-contracts.md §5（CombatEngine）/§7（单位与行动 ID）。
##
## 关键语义（与工作包任务书一致，歧义处的裁定记录在 ops/evidence/WP10.md）：
## - order：活单位 speed desc，同速按 key 字典序 asc；回合边界重建（剔除阵亡单位）。
## - 守卫：行动结算开始时先清零自身 guard_ratio，guard 行动随后重设；因此守卫持续
##   到该单位"下次行动开始"（跨回合边界保持）。
## - 失稳：stability_damage 使 stability <= 0 时 destabilized = true；该单位自身下个
##   行动回合开始时恢复 stability = stability_max、destabilized = false 并跳过该回合。
## - 失稳目标受伤 x1.5；守卫目标受伤 x(1 - guard_ratio)；两者叠加，向下取整，钳制 >= 0。
## - Boss 相位：结算后检查所有带 phases 的活单位，hp/max_hp <= phases[k].at_hp_ratio
##   时切换到最深满足的 phase（phase_index 单调锁存，只切一次并记 phase_change）。
## - 敌人 AI（确定性，与 seed 无关）：action_ids 声明序取第一个 cost 可支付的行动；
##   全不可支付回退第一个（回退仍不可支付则记 action_skipped、无效果）；目标取活着且
##   HP 最低者（平局取 order 靠前），self 取自身，all_enemies 取全体活敌方。
## - seed 仅用于 battle_id 命名。

const _SIDE_ALLY: String = "ally"
const _SIDE_ENEMY: String = "enemy"
const _KEY_PREFIX_ALLY: String = "a"
const _KEY_PREFIX_ENEMY: String = "e"
const _DESTABILIZE_DAMAGE_MULTIPLIER: float = 1.5


# --- 创建 ---------------------------------------------------------------------


## config = {"allies": [{"unit_id", "track", "items": {...}}], "enemies": [...],
## "seed": int, "unit_defs": {unit_id: 定义}, "action_defs": {action_id: 定义},
## "hp_multiplier": float = 1.0}。返回完整战斗状态字典（config 不被修改）。
static func create_battle(config: Dictionary) -> Dictionary:
	var seed_value := int(config.get("seed", 0))
	var hp_multiplier := float(config.get("hp_multiplier", 1.0))
	var unit_defs: Dictionary = _as_dictionary(config.get("unit_defs", {}))
	var action_defs: Dictionary = _as_dictionary(config.get("action_defs", {}))

	var units: Array = []
	units.append_array(_build_side(config.get("allies", []), _SIDE_ALLY, unit_defs, hp_multiplier))
	units.append_array(_build_side(config.get("enemies", []), _SIDE_ENEMY, unit_defs, hp_multiplier))

	return {
		"battle_id": "battle_%d" % seed_value,
		"seed": seed_value,
		"turn": 1,
		"units": units,
		"order": _build_order(units),
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"hp_multiplier": hp_multiplier,
		"action_defs": action_defs.duplicate(true),
	}


static func _build_side(entries: Array, side: String, unit_defs: Dictionary, hp_multiplier: float) -> Array:
	var prefix := _KEY_PREFIX_ALLY if side == _SIDE_ALLY else _KEY_PREFIX_ENEMY
	var units: Array = []
	for index: int in entries.size():
		var entry: Dictionary = _as_dictionary(entries[index])
		var unit_id := str(entry.get("unit_id", ""))
		var key := "%s%d|%s" % [prefix, index, unit_id]
		var unit_def: Dictionary = _as_dictionary(unit_defs.get(unit_id, {}))
		units.append(_build_unit(entry, unit_id, key, side, unit_def, hp_multiplier))
	return units


static func _build_unit(
		entry: Dictionary, unit_id: String, key: String, side: String, def: Dictionary, hp_multiplier: float
) -> Dictionary:
	var stability_max := maxi(1, int(def.get("stability_max", 1)))
	var base_max_hp := maxi(1, int(def.get("max_hp", 1)))
	var max_hp := maxi(1, ceili(float(base_max_hp) * hp_multiplier))
	return {
		"key": key,
		"unit_id": unit_id,
		"side": side,
		"kind": str(def.get("kind", "")),
		"name_zh": str(def.get("name_zh", unit_id)),
		"track": str(entry.get("track", def.get("track", "front"))),
		"hp": max_hp,
		"max_hp": max_hp,
		"stability": stability_max,
		"stability_max": stability_max,
		"speed": maxi(1, int(def.get("speed", 1))),
		"action_ids": _string_array(def.get("action_ids", [])),
		"alive": true,
		"guard_ratio": 0.0,
		"items": _as_dictionary(entry.get("items", {})).duplicate(true),
		"destabilized": false,
		"phases": _as_array(def.get("phases", [])).duplicate(true),
		"drops": _as_array(def.get("drops", [])).duplicate(true),
		"phase_index": -1,
	}


## 活单位 speed desc、同速 key 字典序 asc。
static func _build_order(units: Array) -> Array:
	var entries: Array = []
	for unit: Dictionary in units:
		if not bool(unit.get("alive", false)):
			continue
		entries.append({"key": str(unit.get("key", "")), "speed": int(unit.get("speed", 1))})
	entries.sort_custom(_order_entry_comparator)
	var keys: Array = []
	for entry: Dictionary in entries:
		keys.append(str(entry["key"]))
	return keys


static func _order_entry_comparator(a: Dictionary, b: Dictionary) -> bool:
	var speed_a := int(a["speed"])
	var speed_b := int(b["speed"])
	if speed_a != speed_b:
		return speed_a > speed_b
	return str(a["key"]) < str(b["key"])


# --- 只读查询 -----------------------------------------------------------------


static func is_finished(battle: Dictionary) -> bool:
	return bool(battle.get("finished", false))


## 返回当前行动单位（深拷贝；非法状态返回 {}）。
static func active_unit(battle: Dictionary) -> Dictionary:
	var order: Array = _as_array(battle.get("order", []))
	var index := int(battle.get("active_index", 0))
	if index < 0 or index >= order.size():
		return {}
	var unit: Dictionary = _find_unit(battle, str(order[index]))
	if unit.is_empty():
		return {}
	return unit.duplicate(true)


## {"result": "victory"/"defeat"/""（未结束）, "turns": int, "drops": [{"item_id", "amount"}]}。
## drops 聚合所有已阵亡敌人的 drops（按 item_id 升序，同 ID 求和）。
static func outcome(battle: Dictionary) -> Dictionary:
	var finished := bool(battle.get("finished", false))
	var drop_totals: Dictionary = {}
	for unit: Dictionary in _as_array(battle.get("units", [])):
		if bool(unit.get("alive", false)):
			continue
		if str(unit.get("side", "")) != _SIDE_ENEMY:
			continue
		for drop: Dictionary in _as_array(unit.get("drops", [])):
			var item_id := str(drop.get("item_id", ""))
			if item_id == "":
				continue
			drop_totals[item_id] = int(drop_totals.get(item_id, 0)) + maxi(0, int(drop.get("amount", 0)))
	var item_ids: Array = drop_totals.keys()
	item_ids.sort()
	var drops: Array = []
	for item_id: String in item_ids:
		drops.append({"item_id": item_id, "amount": int(drop_totals[item_id])})
	var result := ""
	if finished:
		result = str(battle.get("result", ""))
	return {"result": result, "turns": int(battle.get("turn", 0)), "drops": drops}


# --- 行动结算 -----------------------------------------------------------------


## 纯函数：深拷贝 battle 后处理并返回新状态；入参绝不修改。
## ally 行动需通过校验（非法返回副本并在 log 追加 {"type": "error", "code": ...}，
## 不消耗回合）；active 为 enemy 时忽略传入 action/target，由确定性 AI 决策。
static func submit_action(battle: Dictionary, unit_key: String, action_id: String, target_key: String) -> Dictionary:
	var state: Dictionary = battle.duplicate(true)
	if bool(state.get("finished", false)):
		_log_error(state, "battle_finished", unit_key, action_id, target_key)
		return state
	var actor: Dictionary = _find_unit(state, unit_key)
	if actor.is_empty():
		_log_error(state, "unknown_unit", unit_key, action_id, target_key)
		return state
	if _active_key(state) != unit_key:
		_log_error(state, "not_active_unit", unit_key, action_id, target_key)
		return state

	if str(actor.get("side", "")) == _SIDE_ALLY:
		var error_code := _validate_ally_action(state, actor, action_id, target_key)
		if error_code != "":
			_log_error(state, error_code, unit_key, action_id, target_key)
			return state
	else:
		var choice: Dictionary = _choose_ai_action(state, actor)
		action_id = str(choice.get("action", ""))
		target_key = str(choice.get("target", ""))

	_resolve_action(state, actor, action_id, target_key)
	_refresh_phases(state)
	_check_battle_end(state)
	while not bool(state.get("finished", false)):
		_advance_once(state)
		if bool(state.get("finished", false)):
			break
		var next_unit: Dictionary = _active_unit_ref(state)
		if next_unit.is_empty() or str(next_unit.get("side", "")) == _SIDE_ALLY:
			break
		var enemy_choice: Dictionary = _choose_ai_action(state, next_unit)
		_resolve_action(state, next_unit, str(enemy_choice.get("action", "")), str(enemy_choice.get("target", "")))
		_refresh_phases(state)
		_check_battle_end(state)
	return state


static func _validate_ally_action(state: Dictionary, actor: Dictionary, action_id: String, target_key: String) -> String:
	if not _as_array(actor.get("action_ids", [])).has(action_id):
		return "unknown_action"
	var action: Dictionary = _as_dictionary(_as_dictionary(state.get("action_defs", {})).get(action_id, {}))
	if action.is_empty():
		return "unknown_action"
	var actor_side := str(actor.get("side", ""))
	match str(action.get("targeting", "")):
		"self":
			if target_key != str(actor.get("key", "")):
				return "invalid_target"
		"single_ally":
			if not _is_living_on_side(state, target_key, actor_side):
				return "invalid_target"
		"single_enemy":
			var opposite := _SIDE_ENEMY if actor_side == _SIDE_ALLY else _SIDE_ALLY
			if not _is_living_on_side(state, target_key, opposite):
				return "invalid_target"
		"all_enemies":
			pass  # 目标可空
		_:
			return "unknown_action"
	if not _can_pay(actor, action):
		return "insufficient_cost"
	return ""


## 结算一次行动（actor 为 state 内单位引用）。行动开始时清零自身守卫，
## cost 可支付则扣减；随后按目标依次施加伤害 / 失稳 / 治疗并记录 log。
static func _resolve_action(state: Dictionary, actor: Dictionary, action_id: String, target_key: String) -> void:
	var action: Dictionary = _as_dictionary(_as_dictionary(state.get("action_defs", {})).get(action_id, {}))

	# 守卫持续到该单位下次行动开始：结算开始即清零（guard 行动随后重设）。
	actor["guard_ratio"] = 0.0

	var cost: Dictionary = _as_dictionary(action.get("cost", {}))
	if not cost.is_empty():
		if not _can_pay(actor, action):
			# 仅敌方 AI 回退路径可达：回退行动不可支付 → 记跳过，本回合无效果。
			_append_log(state, {
				"type": "action_skipped",
				"unit": str(actor.get("key", "")),
				"action": action_id,
				"reason": "insufficient_cost",
			})
			return
		_pay_cost(actor, cost)
		_append_log(state, {
			"type": "item_used",
			"unit": str(actor.get("key", "")),
			"item_id": str(cost.get("item_id", "")),
			"count": maxi(1, int(cost.get("count", 1))),
		})

	var targets: Array = _resolve_targets(state, actor, action, target_key)
	var target_keys: Array = []
	for target: Dictionary in targets:
		target_keys.append(str(target.get("key", "")))
	_append_log(state, {
		"type": "action",
		"unit": str(actor.get("key", "")),
		"action": action_id,
		"targets": target_keys,
	})

	var power := maxi(0, int(action.get("power", 0)))
	var stability_damage := maxi(0, int(action.get("stability_damage", 0)))
	var heal := maxi(0, int(action.get("heal", 0)))
	for target: Dictionary in targets:
		if not bool(target.get("alive", false)):
			continue
		if power > 0:
			_apply_damage(state, actor, target, power)
		if stability_damage > 0 and bool(target.get("alive", false)) and not bool(target.get("destabilized", false)):
			_apply_stability_damage(state, target, stability_damage)
		if heal > 0 and bool(target.get("alive", false)):
			_apply_heal(state, actor, target, heal)

	var guard_ratio := clampf(float(action.get("guard_ratio", 0.0)), 0.0, 1.0)
	if guard_ratio > 0.0:
		actor["guard_ratio"] = guard_ratio
		_append_log(state, {"type": "guard", "unit": str(actor.get("key", "")), "ratio": guard_ratio})


static func _apply_damage(state: Dictionary, actor: Dictionary, target: Dictionary, power: int) -> void:
	var multiplier := 1.0 - clampf(float(target.get("guard_ratio", 0.0)), 0.0, 1.0)
	if bool(target.get("destabilized", false)):
		multiplier *= _DESTABILIZE_DAMAGE_MULTIPLIER
	var effective := maxi(0, int(floor(float(power) * multiplier)))
	var remaining := int(target.get("hp", 0)) - effective
	target["hp"] = maxi(0, remaining)
	_append_log(state, {
		"type": "damage",
		"source": str(actor.get("key", "")),
		"target": str(target.get("key", "")),
		"amount": effective,
	})
	if remaining <= 0:
		target["alive"] = false
		_append_log(state, {"type": "defeated", "unit": str(target.get("key", ""))})


static func _apply_stability_damage(state: Dictionary, target: Dictionary, stability_damage: int) -> void:
	var remaining := int(target.get("stability", 0)) - stability_damage
	target["stability"] = maxi(0, remaining)
	if remaining <= 0:
		target["destabilized"] = true
		_append_log(state, {"type": "destabilized", "unit": str(target.get("key", ""))})


static func _apply_heal(state: Dictionary, actor: Dictionary, target: Dictionary, heal: int) -> void:
	var missing := int(target.get("max_hp", 0)) - int(target.get("hp", 0))
	var actual := mini(heal, maxi(0, missing))
	if actual <= 0:
		return
	target["hp"] = int(target.get("hp", 0)) + actual
	_append_log(state, {
		"type": "heal",
		"source": str(actor.get("key", "")),
		"target": str(target.get("key", "")),
		"amount": actual,
	})


static func _resolve_targets(state: Dictionary, actor: Dictionary, action: Dictionary, target_key: String) -> Array:
	var targets: Array = []
	var actor_side := str(actor.get("side", ""))
	match str(action.get("targeting", "")):
		"self":
			targets.append(actor)
		"single_ally", "single_enemy":
			var target: Dictionary = _find_unit(state, target_key)
			if not target.is_empty() and bool(target.get("alive", false)):
				targets.append(target)
		"all_enemies":
			for key: String in _as_array(state.get("order", [])):
				var unit: Dictionary = _find_unit(state, str(key))
				if unit.is_empty() or not bool(unit.get("alive", false)):
					continue
				if str(unit.get("side", "")) != actor_side:
					targets.append(unit)
		_:
			pass
	return targets


# --- Boss 相位 -----------------------------------------------------------------


## 结算后检查所有带 phases 的活单位：hp/max_hp <= phases[k].at_hp_ratio 时切换到
## 最深满足的 phase；phase_index 单调锁存（只切一次，只记一次 phase_change）。
static func _refresh_phases(state: Dictionary) -> void:
	for unit: Dictionary in _as_array(state.get("units", [])):
		if not bool(unit.get("alive", false)):
			continue
		var phases: Array = _as_array(unit.get("phases", []))
		if phases.is_empty():
			continue
		var max_hp := int(unit.get("max_hp", 0))
		if max_hp <= 0:
			continue
		var ratio := float(int(unit.get("hp", 0))) / float(max_hp)
		var phase_index := int(unit.get("phase_index", -1))
		var next_index := -1
		for k: int in range(phase_index + 1, phases.size()):
			var phase: Dictionary = _as_dictionary(phases[k])
			if ratio <= float(phase.get("at_hp_ratio", 0.0)):
				next_index = k
		if next_index < 0:
			continue
		var chosen: Dictionary = _as_dictionary(phases[next_index])
		var phase_action_ids := _string_array(chosen.get("action_ids", []))
		unit["phase_index"] = next_index
		unit["action_ids"] = phase_action_ids
		_append_log(state, {
			"type": "phase_change",
			"unit": str(unit.get("key", "")),
			"phase": str(chosen.get("id", "")),
			"action_ids": phase_action_ids.duplicate(true),
		})


# --- 推进与结束 -----------------------------------------------------------------


## 胜负判定：敌全灭 → victory；友全灭 → defeat（双方同时归零时 victory 优先，
## 实际不可达：行动者必然存活于己方）。
static func _check_battle_end(state: Dictionary) -> void:
	if bool(state.get("finished", false)):
		return
	var allies_alive := false
	var enemies_alive := false
	for unit: Dictionary in _as_array(state.get("units", [])):
		if not bool(unit.get("alive", false)):
			continue
		if str(unit.get("side", "")) == _SIDE_ALLY:
			allies_alive = true
		else:
			enemies_alive = true
	if not enemies_alive:
		state["finished"] = true
		state["result"] = "victory"
		_append_log(state, {"type": "battle_end", "result": "victory"})
	elif not allies_alive:
		state["finished"] = true
		state["result"] = "defeat"
		_append_log(state, {"type": "battle_end", "result": "defeat"})


## 推进到下一个可行动单位：active_index + 1；越界 → turn + 1、重建 order（剔除
## 阵亡单位）、active_index = 0；途中跳过阵亡单位；失稳单位在其回合开始时恢复
## stability = stability_max、destabilized = false 并跳过该回合。守卫不在回合边界
## 重置（持续到单位自身下次行动开始）。
static func _advance_once(state: Dictionary) -> void:
	while true:
		var order: Array = _as_array(state.get("order", []))
		var index := int(state.get("active_index", 0)) + 1
		if index >= order.size():
			state["turn"] = int(state.get("turn", 1)) + 1
			state["order"] = _build_order(_as_array(state.get("units", [])))
			state["active_index"] = 0
			_append_log(state, {"type": "round_start", "turn": int(state.get("turn", 1))})
		else:
			state["active_index"] = index
		var refreshed_order: Array = _as_array(state.get("order", []))
		var active_index := int(state.get("active_index", 0))
		if active_index >= refreshed_order.size():
			return  # 无可行动单位（理论不可达：结束检查先行）
		var unit: Dictionary = _find_unit(state, str(refreshed_order[active_index]))
		if unit.is_empty() or not bool(unit.get("alive", false)):
			continue
		if bool(unit.get("destabilized", false)):
			unit["stability"] = int(unit.get("stability_max", 1))
			unit["destabilized"] = false
			_append_log(state, {"type": "destabilized_recover", "unit": str(unit.get("key", ""))})
			_append_log(state, {
				"type": "turn_skipped",
				"unit": str(unit.get("key", "")),
				"reason": "destabilized",
			})
			continue
		return


# --- 敌人 AI（确定性）-----------------------------------------------------------


## action_ids 声明序取第一个 cost 可支付的行动；全不可支付回退第一个。
## 目标：single_enemy/single_ally → 活着且 HP 最低（平局取 order 靠前）；
## self → 自身；all_enemies → 全体活敌方（order 序）。与 seed 无关。
static func _choose_ai_action(state: Dictionary, actor: Dictionary) -> Dictionary:
	var action_defs: Dictionary = _as_dictionary(state.get("action_defs", {}))
	var action_ids: Array = _as_array(actor.get("action_ids", []))
	var fallback := ""
	for action_id: String in action_ids:
		var action: Dictionary = _as_dictionary(action_defs.get(action_id, {}))
		if action.is_empty():
			continue
		if fallback == "":
			fallback = action_id
		if not _can_pay(actor, action):
			continue
		return {"action": action_id, "target": _choose_ai_target(state, actor, action)}
	if fallback != "":
		var fallback_action: Dictionary = _as_dictionary(action_defs.get(fallback, {}))
		return {"action": fallback, "target": _choose_ai_target(state, actor, fallback_action)}
	return {"action": "", "target": ""}


static func _choose_ai_target(state: Dictionary, actor: Dictionary, action: Dictionary) -> String:
	var actor_side := str(actor.get("side", ""))
	match str(action.get("targeting", "")):
		"self":
			return str(actor.get("key", ""))
		"single_ally":
			return _lowest_hp_living_key(state, actor_side)
		"single_enemy":
			var opposite := _SIDE_ENEMY if actor_side == _SIDE_ALLY else _SIDE_ALLY
			return _lowest_hp_living_key(state, opposite)
		"all_enemies":
			return ""
		_:
			return ""


## 活着且 HP 最低的单位 key；平局取 order 靠前（严格小于保持先见者）。
static func _lowest_hp_living_key(state: Dictionary, side: String) -> String:
	var best_key := ""
	var best_hp := 0
	for key: String in _as_array(state.get("order", [])):
		var unit: Dictionary = _find_unit(state, str(key))
		if unit.is_empty() or not bool(unit.get("alive", false)):
			continue
		if str(unit.get("side", "")) != side:
			continue
		var hp := int(unit.get("hp", 0))
		if best_key == "" or hp < best_hp:
			best_key = str(unit.get("key", ""))
			best_hp = hp
	return best_key


static func _can_pay(actor: Dictionary, action: Dictionary) -> bool:
	var cost: Dictionary = _as_dictionary(action.get("cost", {}))
	if cost.is_empty():
		return true
	var item_id := str(cost.get("item_id", ""))
	var needed := maxi(1, int(cost.get("count", 1)))
	var held := int(_as_dictionary(actor.get("items", {})).get(item_id, 0))
	return held >= needed


static func _pay_cost(actor: Dictionary, cost: Dictionary) -> void:
	var items: Dictionary = _as_dictionary(actor.get("items", {}))
	var item_id := str(cost.get("item_id", ""))
	var remaining := int(items.get(item_id, 0)) - maxi(1, int(cost.get("count", 1)))
	if remaining > 0:
		items[item_id] = remaining
	else:
		items.erase(item_id)


# --- 内部工具 -----------------------------------------------------------------


static func _find_unit(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Dictionary in _as_array(battle.get("units", [])):
		if str(unit.get("key", "")) == unit_key:
			return unit
	return {}


static func _active_unit_ref(state: Dictionary) -> Dictionary:
	var order: Array = _as_array(state.get("order", []))
	var index := int(state.get("active_index", 0))
	if index < 0 or index >= order.size():
		return {}
	return _find_unit(state, str(order[index]))


static func _active_key(state: Dictionary) -> String:
	return str(_active_unit_ref(state).get("key", ""))


static func _is_living_on_side(state: Dictionary, unit_key: String, side: String) -> bool:
	var unit: Dictionary = _find_unit(state, unit_key)
	if unit.is_empty():
		return false
	return bool(unit.get("alive", false)) and str(unit.get("side", "")) == side


static func _log_error(state: Dictionary, code: String, unit_key: String, action_id: String, target_key: String) -> void:
	_append_log(state, {
		"type": "error",
		"code": code,
		"unit": unit_key,
		"action": action_id,
		"target": target_key,
	})


static func _append_log(state: Dictionary, entry: Dictionary) -> void:
	if not state.has("log") or typeof(state["log"]) != TYPE_ARRAY:
		state["log"] = []
	var log: Array = state["log"]
	log.append(entry)


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _string_array(value: Variant) -> Array:
	var result: Array = []
	for item: Variant in _as_array(value):
		result.append(str(item))
	return result
