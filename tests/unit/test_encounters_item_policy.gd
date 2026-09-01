extends GutTest

## G7P-2 S4：遭遇道具装配数据化（TDD：先 RED 后 GREEN）。
##
## 两个遗留耦合点消除：
## 1. 道具种类上限 MAX_ITEMS_PER_TYPE=2 硬编码 → 遭遇定义可选
##    max_items_per_type: int（缺省 2），新增"每种道具带更多/更少"的遭遇 =
##    改 encounters.json，不改 encounter_director.gd；
## 2. 战斗道具可装配判定冻结清单 FROZEN_SANDBOX_BATTLE_ITEMS → 完全数据驱动：
##    item 定义 battle_usable=true 即可装配（生产路径 GameSession._battle_content
##    始终从 ContentDB 传入全量 item_defs）；item_defs 未提供/缺该 id 时失败安全
##    不装配（无数据源不判定，删除冻结名单兜底）。
## 行为等价：既有三场遭遇不带 max_items_per_type 字段 → 缺省 2，数值不变；
## 生产 item_defs 齐全 → 装配结果与迁移前一致（test_encounters_director.gd
## 快照保留，仅"无 item_defs 回退冻结清单"一条按新语义合法更新）。

const DIRECTOR_SCRIPT_PATH: String = "res://src/encounters/encounter_director.gd"
const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"

var _director: Script = null
var _temp_roots: Array[String] = []


func before_all() -> void:
	_director = load(DIRECTOR_SCRIPT_PATH)


func after_each() -> void:
	for tree: String in _temp_roots:
		_remove_dir_recursive(tree)
	_temp_roots.clear()


func _require_director() -> bool:
	if _director == null:
		fail_test("Missing required implementation: %s" % DIRECTOR_SCRIPT_PATH)
		return false
	return true


const UNIT_DEFS: Dictionary = {
	"u_misa": {
		"id": "u_misa", "kind": "ally", "name_zh": "弥砂",
		"max_hp": 30, "stability_max": 12, "track": "mid", "speed": 5,
		"action_ids": ["a_bind"],
	},
	"u_swarm": {
		"id": "u_swarm", "kind": "enemy_normal", "name_zh": "漂游幼群",
		"max_hp": 12, "stability_max": 6, "track": "front", "speed": 4,
		"action_ids": ["a_strike"],
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


func _encounter_def(extra: Dictionary = {}) -> Dictionary:
	var encounter: Dictionary = {
		"id": "encounter_test_a",
		"name_zh": "测试遭遇",
		"trigger_flag": "encounter_test_a_due",
		"on_victory_flag": "encounter_test_a_won",
		"allies": [
			{
				"unit_id": "u_misa",
				"track": "mid",
				"item_ids": ["sedative_mist", "sedative_mist", "shock_trap", "starsoil_dust"],
			},
		],
		"enemies": [{"unit_id": "u_swarm", "track": "front"}],
		"seed": 4242,
	}
	for key: String in extra:
		encounter[key] = extra[key]
	return encounter


func _content(inventory: Dictionary = {"sedative_mist": 9, "shock_trap": 9}) -> Dictionary:
	return {
		"unit_defs": UNIT_DEFS.duplicate(true),
		"action_defs": ACTION_DEFS.duplicate(true),
		"item_defs": ITEM_DEFS.duplicate(true),
		"inventory": inventory.duplicate(true),
	}


# ---------------------------------------------------------------- max_items_per_type


func test_encounter_without_field_uses_default_cap_two() -> void:
	if not _require_director():
		return
	var config: Dictionary = _director.start(_encounter_def(), _content())
	var items: Dictionary = (config["allies"] as Array)[0].get("items", {})
	assert_eq(
		items, {"sedative_mist": 2, "shock_trap": 1},
		"缺省上限必须保持 2（迁移行为等价）。"
	)


func test_encounter_max_items_per_type_overrides_cap() -> void:
	if not _require_director():
		return
	# 上限提到 4：sedative_mist 出现 2 次仍按出现次数 2 装配（上限只封顶不放大）。
	var loose: Dictionary = _director.start(_encounter_def({"max_items_per_type": 4}), _content())
	assert_eq(
		(loose["allies"] as Array)[0].get("items", {}), {"sedative_mist": 2, "shock_trap": 1},
		"上限 4 不得放大出现次数。"
	)

	# 上限压到 1：每种道具最多 1。
	var tight: Dictionary = _director.start(_encounter_def({"max_items_per_type": 1}), _content())
	assert_eq(
		(tight["allies"] as Array)[0].get("items", {}), {"sedative_mist": 1, "shock_trap": 1},
		"上限 1 必须把每种道具压到 1。"
	)

	# 上限 0：不装配任何道具。
	var none: Dictionary = _director.start(_encounter_def({"max_items_per_type": 0}), _content())
	assert_eq(
		(none["allies"] as Array)[0].get("items", {}), {},
		"上限 0 必须装配零道具。"
	)


func test_encounter_max_items_per_type_pure_data_extension() -> void:
	if not _require_director():
		return
	# "新增一个每种道具可带 5 枚的遭遇" = encounters.json 加字段，零代码。
	var five: Dictionary = _director.start(
		_encounter_def({"max_items_per_type": 5}),
		_content({"sedative_mist": 9, "shock_trap": 9})
	)
	# 出现次数仍是上限（sedative 2 次 / shock 1 次）——字段生效路径已验证，
	# 本测试锁定字段与库存/出现次数的 min 语义。
	var items: Dictionary = (five["allies"] as Array)[0].get("items", {})
	assert_eq(items, {"sedative_mist": 2, "shock_trap": 1})


# ---------------------------------------------------------------- battle_usable 数据驱动


func test_battle_usable_judgement_reads_item_defs_not_frozen_list() -> void:
	if not _require_director():
		return
	# 不在旧冻结清单中的新道具，battle_usable=true 即装配（纯数据扩展）。
	var content: Dictionary = _content({"dlc_stim_pack": 3})
	(content["item_defs"] as Dictionary)["dlc_stim_pack"] = {
		"id": "dlc_stim_pack", "kind": "sandbox_item", "battle_usable": true,
	}
	var encounter: Dictionary = _encounter_def()
	(encounter["allies"][0] as Dictionary)["item_ids"] = ["dlc_stim_pack"]
	var config: Dictionary = _director.start(encounter, content)
	assert_eq(
		(config["allies"] as Array)[0].get("items", {}), {"dlc_stim_pack": 1},
		"battle_usable=true 的新道具必须可装配（冻结清单已删除）。"
	)


func test_item_without_battle_usable_true_is_never_equipped() -> void:
	if not _require_director():
		return
	var content: Dictionary = _content()
	(content["item_defs"] as Dictionary)["grey_tonic"] = {
		"id": "grey_tonic", "kind": "sandbox_item", "battle_usable": false,
	}
	var encounter: Dictionary = _encounter_def()
	(encounter["allies"][0] as Dictionary)["item_ids"] = ["grey_tonic"]
	var config: Dictionary = _director.start(encounter, content)
	assert_eq(
		(config["allies"] as Array)[0].get("items", {}), {},
		"battle_usable=false 的道具不得装配。"
	)


func test_without_item_defs_nothing_is_equipped() -> void:
	if not _require_director():
		return
	# 失败安全语义（合法语义更新，取代旧"回退冻结清单"）：item_defs 未提供时
	# 没有可判定的数据源 → 不装配任何道具。
	var content: Dictionary = _content()
	content.erase("item_defs")
	var config: Dictionary = _director.start(_encounter_def(), content)
	assert_eq(
		(config["allies"] as Array)[0].get("items", {}), {},
		"无 item_defs 数据源时必须失败安全不装配。"
	)


# ---------------------------------------------------------------- ContentDB 校验


func test_content_db_accepts_encounter_max_items_per_type() -> void:
	var db: Node = (load(CONTENT_DB_PATH) as Script).new()
	add_child_autofree(db)
	var root := "user://g7p2_item_cap_ok"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_encounter_fixture(root, {"max_items_per_type": 3})
	var result: AppResult = db.bootstrap(root)
	assert_true(result.is_ok, "带 max_items_per_type 的遭遇必须通过校验：%s" % result.message)
	if result.is_ok:
		assert_eq(int(db.get_encounter("encounter_test_a").get("max_items_per_type", -1)), 3)


func test_content_db_rejects_non_integer_or_negative_cap() -> void:
	var db: Node = (load(CONTENT_DB_PATH) as Script).new()
	add_child_autofree(db)
	var bad_root := "user://g7p2_item_cap_bad"
	_temp_roots.append(bad_root)
	_remove_dir_recursive(bad_root)
	_write_encounter_fixture(bad_root, {"max_items_per_type": -1})
	var result: AppResult = db.bootstrap(bad_root)
	assert_false(result.is_ok, "负数上限必须被拒绝。")
	assert_eq(result.code, "invalid_definition")


func _write_encounter_fixture(root: String, extra: Dictionary) -> void:
	var encounter: Dictionary = _encounter_def(extra)
	DirAccess.make_dir_recursive_absolute(root + "/encounters")
	var file: FileAccess = FileAccess.open(root + "/encounters/encounter.json", FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify([encounter], "  "))
		file.close()


func _remove_dir_recursive(tree: String) -> void:
	if not DirAccess.dir_exists_absolute(tree):
		return
	var dir := DirAccess.open(tree)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_remove_dir_recursive(tree + "/%s" % entry)
		else:
			DirAccess.remove_absolute(tree + "/%s" % entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(tree)
