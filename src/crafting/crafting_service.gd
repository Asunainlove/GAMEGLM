class_name CraftingService
extends RefCounted

## W002-GAP4 精炼闭环：纯逻辑合成模块（RefCounted，无场景树 / GameState 依赖）。
##
## 数据来源：建筑定义可携带 `recipe`（单对象，兼容旧形态）或 `recipes`（数组，
## W002-GAP4 新形态，元素形状与 recipe 相同并支持可选第二输入 extra_input_*）。
## 两种形态在本模块统一归一化为 {item_id, count} 输入列表后消费。
##
## 供电判定保持本模块纯逻辑：`available_recipes` 接收调用方算好的
## `powered_ids: Array[String]`（典型来源为 PowerGrid.evaluate 的 powered_ids），
## 仅"已放置且供电"的建筑的配方可用。同一建筑多实例只去重暴露一次配方。
##
## craft 的提交遵循契约 §0 注入模式：store 为 null 时委托 GameState autoload，
## 否则 store 须暴露 snapshot/begin_patch/commit。材料检查与提交在同一 patch 内
## 原子完成：任一操作失败整个 patch 被拒绝，不留部分状态。
## source_id = crafting_<building_id>_<revision>：同一 revision 的重放提交会被
## GameState 以 already_applied 幂等吸收，不重复扣料/产出。

const RECIPE_INPUT_FIELDS: Array[String] = ["input_item_id", "input_count"]
const RECIPE_EXTRA_FIELDS: Array[String] = ["extra_input_item_id", "extra_input_count"]
const RECIPE_OUTPUT_FIELDS: Array[String] = ["output_item_id", "output_count"]


## 归一化配方输入：[{item_id, count}]。非法配方返回空数组。
static func recipe_inputs(recipe: Dictionary) -> Array[Dictionary]:
	var inputs: Array[Dictionary] = []
	var inputs_result: AppResult = _read_amount_pair(recipe, RECIPE_INPUT_FIELDS)
	if not inputs_result.is_ok:
		return inputs
	inputs.append(inputs_result.value)
	if recipe.has("extra_input_item_id") or recipe.has("extra_input_count"):
		var extra_result: AppResult = _read_amount_pair(recipe, RECIPE_EXTRA_FIELDS)
		if not extra_result.is_ok:
			return [] as Array[Dictionary]
		inputs.append(extra_result.value)
	return inputs


## 当前可用的配方列表：只统计已放置且供电（powered_ids 含该建筑 id）的建筑，
## 按放置顺序展开；同建筑的同名配方去重。元素形如
## `{"building_id": String, "recipe": Dictionary}`，recipe 为定义的深拷贝。
static func available_recipes(
		state: Dictionary,
		defs: Dictionary,
		powered_ids: Array[String]
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var placed: Array = state.get("placed_buildings", [])
	if typeof(placed) != TYPE_ARRAY:
		return entries
	for placed_value: Variant in placed:
		if typeof(placed_value) != TYPE_DICTIONARY:
			continue
		var placed_entry: Dictionary = placed_value
		var building_id := str(placed_entry.get("building_id", ""))
		if building_id == "" or not powered_ids.has(building_id):
			continue
		var definition: Dictionary = _as_dictionary(defs.get(building_id, {}))
		for recipe: Dictionary in _recipes_of(definition):
			var signature := "%s|%s|%s" % [
				building_id,
				str(recipe.get("input_item_id", "")),
				str(recipe.get("output_item_id", "")),
			]
			if seen.has(signature):
				continue
			seen[signature] = true
			entries.append({
				"building_id": building_id,
				"recipe": recipe.duplicate(true),
			})
	return entries


## 材料是否足够（纯判定，不修改状态）。非法配方一律不可合成。
static func can_craft(state: Dictionary, recipe: Dictionary) -> bool:
	var totals_result: AppResult = _input_totals(recipe)
	if not totals_result.is_ok:
		return false
	var inventory: Dictionary = _as_dictionary(state.get("inventory", {}))
	for item_id: String in totals_result.value:
		if int(inventory.get(item_id, 0)) < int(totals_result.value[item_id]):
			return false
	return true


## 执行一次合成：先做配方形状与材料检查（零修改失败），满足后以单个 patch
## 提交 remove_item(输入) + add_item(输出)。
## 失败码：`recipe_unavailable`（配方形状非法）/ `insufficient_item`（材料不足）；
## 提交层失败原样透传（revision_conflict / insufficient_item / already_applied 等）。
static func craft(
		state: Dictionary,
		building_id: String,
		recipe: Dictionary,
		store: Object = null
) -> AppResult:
	if not _is_stable_id(building_id):
		return AppResult.failure(
			"recipe_unavailable",
			"Crafting requires a stable building id, got '%s'." % building_id
		)
	var totals_result: AppResult = _input_totals(recipe)
	if not totals_result.is_ok:
		return AppResult.failure("recipe_unavailable", totals_result.message)
	var output_result: AppResult = _read_amount_pair(recipe, RECIPE_OUTPUT_FIELDS)
	if not output_result.is_ok:
		return AppResult.failure("recipe_unavailable", output_result.message)

	var inventory: Dictionary = _as_dictionary(state.get("inventory", {}))
	var missing: Array[String] = []
	for item_id: String in totals_result.value:
		if int(inventory.get(item_id, 0)) < int(totals_result.value[item_id]):
			missing.append(item_id)
	if not missing.is_empty():
		return AppResult.failure(
			"insufficient_item",
			"Crafting is missing required items: %s." % ", ".join(missing)
		)

	var revision := int(state.get("revision", 0))
	var source_id := "crafting_%s_%d" % [building_id, revision]
	var effective_store: Object = store
	if effective_store == null:
		effective_store = GameState
	var patch: Variant = effective_store.begin_patch(source_id, revision)
	for item_id: String in totals_result.value:
		patch.remove_item(item_id, int(totals_result.value[item_id]))
	patch.add_item(str(recipe["output_item_id"]), int(recipe["output_count"]))
	return effective_store.commit(patch)


# --- 内部工具 ----------------------------------------------------------------------


## 聚合同名输入（当前最多两项）为 {item_id: total_count}；形状非法时失败。
static func _input_totals(recipe: Dictionary) -> AppResult:
	var inputs := recipe_inputs(recipe)
	if inputs.is_empty():
		return AppResult.failure(
			"recipe_unavailable",
			"Recipe must carry input_item_id/input_count (and optional extra_input_*) with positive integer counts."
		)
	var totals: Dictionary = {}
	for input_entry: Dictionary in inputs:
		var item_id := str(input_entry["item_id"])
		totals[item_id] = int(totals.get(item_id, 0)) + int(input_entry["count"])
	return AppResult.success(totals)


static func _read_amount_pair(recipe: Dictionary, fields: Array[String]) -> AppResult:
	var item_id_value: Variant = recipe.get(fields[0])
	var count_value: Variant = recipe.get(fields[1])
	if typeof(item_id_value) != TYPE_STRING or not _is_stable_id(str(item_id_value)):
		return AppResult.failure("recipe_unavailable", "%s must be a stable item id." % fields[0])
	if not (typeof(count_value) in [TYPE_INT, TYPE_FLOAT]) or int(count_value) < 1:
		return AppResult.failure("recipe_unavailable", "%s must be a positive integer." % fields[1])
	return AppResult.success({"item_id": str(item_id_value), "count": int(count_value)})


## 建筑定义的配方载体：recipes 数组优先（新形态），否则退回单个 recipe（兼容）。
static func _recipes_of(definition: Dictionary) -> Array:
	var recipes: Array = []
	var recipes_value: Variant = definition.get("recipes", null)
	if typeof(recipes_value) == TYPE_ARRAY:
		for recipe_value: Variant in recipes_value:
			if typeof(recipe_value) == TYPE_DICTIONARY:
				recipes.append(recipe_value)
		if not recipes.is_empty():
			return recipes
	var recipe_value: Variant = definition.get("recipe", null)
	if typeof(recipe_value) == TYPE_DICTIONARY:
		recipes.append(recipe_value)
	return recipes


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()
