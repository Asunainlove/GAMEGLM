class_name EncounterDirector
extends RefCounted

## WP13 遭遇编排纯逻辑（契约 docs/plans/contracts/module-contracts.md §0/§5/§7）。
## check_triggers/start 为静态纯函数（不调用引擎、不触碰持久状态）；finish 为
## 实例方法，落账经可注入 store（契约 §0：store 为 null 时用 GameState autoload；
## patch 调用走未类型化 Variant 鸭子路径，与 DuckPatch 测试替身及真实
## StatePatch 共用同一提交路径，合并集成后由 GameState 统一校验全部操作）。
##
## start 只组装 CombatEngine config：
## - allies 的 items：按 encounter_def 里 item_ids 的出现次数计数，数量取
##   min(出现次数, inventory 存量, 上限 2)；仅装配 battle_usable 的沙盒道具
##   （content.item_defs 提供时按数据判定，缺失时回退契约 §7 冻结的两个
##   沙盒战斗道具 ID）。
## - finish：victory → 单 patch（record_battle_outcome + drops 逐项 add_item +
##   set_flag(on_victory_flag)）；defeat → patch 仅含 record_battle_outcome
##   （due 旗标保留，遭遇可重试）。两种结果都会先把战斗中实际消耗的道具经
##   remove_item 回写库存（W002-GAP4：outcome.items_spent 由 battle_scene 经
##   spent_items 对比开局装配与战后剩余算出）。source_id =
##   encounter_<id>_<result>_<revision>。

const MAX_ITEMS_PER_TYPE: int = 2
const FROZEN_SANDBOX_BATTLE_ITEMS: Array[String] = ["sedative_mist", "shock_trap"]


# --- 触发检查（静态纯函数）------------------------------------------------------


## 数组序返回首个应触发的遭遇 id；无则 ""。触发条件（全部满足）：
## state.flags[trigger_flag] == true 且 state.flags[on_victory_flag] != true
## 且 state.battle_outcomes 无本遭遇 id。
static func check_triggers(state: Dictionary, encounters: Array) -> String:
	var flags: Dictionary = _as_dictionary(state.get("flags", {}))
	var battle_outcomes: Dictionary = _as_dictionary(state.get("battle_outcomes", {}))
	for entry: Variant in encounters:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var encounter: Dictionary = entry
		var encounter_id := str(encounter.get("id", ""))
		if encounter_id == "" or battle_outcomes.has(encounter_id):
			continue
		var trigger_flag := str(encounter.get("trigger_flag", ""))
		if trigger_flag == "" or not (flags.get(trigger_flag) == true):
			continue
		var on_victory_flag := str(encounter.get("on_victory_flag", ""))
		if on_victory_flag != "" and flags.get(on_victory_flag) == true:
			continue
		return encounter_id
	return ""


# --- 组装引擎 config（静态纯函数，绝不调用引擎）---------------------------------


## content = {"unit_defs": {...}, "action_defs": {...}, "inventory": {...},
## "hp_multiplier": float = 1.0, "item_defs": {...} 可选（battle_usable 判定）}。
## 返回 CombatEngine.create_battle 所需 config 并附带 "encounter_id"；
## 深拷贝 defs/inventory 派生数据，content 事后改写不泄漏进 config。
static func start(encounter_def: Dictionary, content: Dictionary) -> Dictionary:
	var allies: Array = []
	for entry: Variant in _as_array(encounter_def.get("allies", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = entry
		allies.append({
			"unit_id": str(source.get("unit_id", "")),
			"track": str(source.get("track", "front")),
			"items": _ally_items(
				_as_array(source.get("item_ids", [])),
				_as_dictionary(content.get("inventory", {})),
				_as_dictionary(content.get("item_defs", {}))
			),
		})
	var enemies: Array = []
	for entry: Variant in _as_array(encounter_def.get("enemies", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = entry
		enemies.append({
			"unit_id": str(source.get("unit_id", "")),
			"track": str(source.get("track", "front")),
		})
	return {
		"encounter_id": str(encounter_def.get("id", "")),
		"allies": allies,
		"enemies": enemies,
		"seed": int(encounter_def.get("seed", 0)),
		"unit_defs": _as_dictionary(content.get("unit_defs", {})).duplicate(true),
		"action_defs": _as_dictionary(content.get("action_defs", {})).duplicate(true),
		"hp_multiplier": float(content.get("hp_multiplier", 1.0)),
	}


## item_ids 按出现次数计数；数量 = min(出现次数, inventory 存量, 上限 2)，
## 仅装配 battle_usable 的沙盒道具；数量为 0 的不进 items 字典。
static func _ally_items(item_ids: Array, inventory: Dictionary, item_defs: Dictionary) -> Dictionary:
	var occurrences: Dictionary = {}
	for value: Variant in item_ids:
		var item_id := str(value)
		if item_id == "":
			continue
		occurrences[item_id] = int(occurrences.get(item_id, 0)) + 1
	var items: Dictionary = {}
	for item_id: String in occurrences:
		if not _is_battle_usable(item_id, item_defs):
			continue
		var amount := mini(
			mini(int(occurrences[item_id]), int(inventory.get(item_id, 0))),
			MAX_ITEMS_PER_TYPE
		)
		if amount <= 0:
			continue
		items[item_id] = amount
	return items


static func _is_battle_usable(item_id: String, item_defs: Dictionary) -> bool:
	var definition: Dictionary = _as_dictionary(item_defs.get(item_id, {}))
	if not definition.is_empty():
		return bool(definition.get("battle_usable", false))
	# item_defs 未提供该定义时，回退契约 §7 冻结的两个沙盒战斗道具 ID。
	return FROZEN_SANDBOX_BATTLE_ITEMS.has(item_id)


## 战斗道具实际消耗：对比遭遇开始装配的初始 items（config.allies[i].items，
## 顺序与引擎建局一致：盟友在前、key 形如 a<index>|<unit_id>）与战斗结束
## units（side=ally）的剩余 items，按 item_id 聚合消耗量（W002-GAP4 回写通道）。
static func spent_items(initial_allies: Array, battle_units: Array) -> Dictionary:
	var spent: Dictionary = {}
	var ally_index := 0
	for unit_value: Variant in battle_units:
		var unit := _as_dictionary(unit_value)
		if unit.is_empty() or str(unit.get("side", "")) != "ally":
			continue
		var initial: Dictionary = {}
		if ally_index < initial_allies.size():
			initial = _as_dictionary(_as_dictionary(initial_allies[ally_index]).get("items", {}))
		ally_index += 1
		var remaining := _as_dictionary(unit.get("items", {}))
		for item_id: String in initial:
			var diff := int(initial[item_id]) - int(remaining.get(item_id, 0))
			if diff > 0:
				spent[item_id] = int(spent.get(item_id, 0)) + diff
	return spent


# --- 落账（实例方法，store 注入）-------------------------------------------------


## victory → 单 patch：record_battle_outcome(<encounter_id>, "victory", turns)
## + drops 逐项 add_item + set_flag(on_victory_flag, true)。
## defeat → patch 只含 record_battle_outcome(..., "defeat", turns)（due 旗标
## 保留，遭遇可重试）。两种结果均先把 outcome.items_spent（item_id → 实际
## 消耗量）逐项 remove_item 回写库存，消耗先于战利品入账。
## source_id = encounter_<id>_<victory|defeat>_<revision>。
func finish(state: Dictionary, encounter_def: Dictionary, outcome: Dictionary, store: Object = null) -> AppResult:
	var encounter_id := str(encounter_def.get("id", ""))
	if not _is_stable_id(encounter_id):
		return AppResult.failure(
			"invalid_encounter_def",
			"Encounter def must carry a stable snake_case id, got '%s'." % encounter_id
		)
	var result := str(outcome.get("result", ""))
	if result != "victory" and result != "defeat":
		return AppResult.failure(
			"invalid_outcome",
			"Encounter outcome result must be victory or defeat, got '%s'." % result
		)

	var revision := int(state.get("revision", 0))
	var patch: Variant = _begin_patch(
		store, "encounter_%s_%s_%d" % [encounter_id, result, revision], revision)
	patch.record_battle_outcome(encounter_id, result, int(outcome.get("turns", 0)))
	# W002-GAP4 道具经济：战斗中实际消耗的道具回写库存（victory 与 defeat 一致）。
	var items_spent := _as_dictionary(outcome.get("items_spent", {}))
	for spent_value: Variant in items_spent:
		var spent_item_id := str(spent_value)
		var spent_amount := int(items_spent.get(spent_value, 0))
		if not _is_stable_id(spent_item_id) or spent_amount <= 0:
			continue
		patch.remove_item(spent_item_id, spent_amount)
	if result == "victory":
		for drop: Variant in _as_array(outcome.get("drops", [])):
			if typeof(drop) != TYPE_DICTIONARY:
				continue
			var drop_def: Dictionary = drop
			var amount := int(drop_def.get("amount", 0))
			var item_id := str(drop_def.get("item_id", ""))
			if item_id == "" or amount <= 0:
				continue
			patch.add_item(item_id, amount)
		var on_victory_flag := str(encounter_def.get("on_victory_flag", ""))
		if on_victory_flag != "":
			patch.set_flag(on_victory_flag, true)
	return _commit(store, patch)


## 契约 §0 注入模式：patch 经未类型化变量（Variant）走鸭子调用，
## 以便 DuckPatch 测试替身与真实 StatePatch 共用同一提交路径。
func _begin_patch(store: Object, source_id: String, expected_revision: int) -> Variant:
	if store == null:
		return GameState.begin_patch(source_id, expected_revision)
	return store.begin_patch(source_id, expected_revision)


func _commit(store: Object, patch: Variant) -> AppResult:
	if store == null:
		return GameState.commit(patch)
	return store.commit(patch)


# --- 内部工具 --------------------------------------------------------------------


static func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
