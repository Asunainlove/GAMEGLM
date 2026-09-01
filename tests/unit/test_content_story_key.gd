extends GutTest

## G7P-2 S9：story_key 消费扫描（TDD：先 RED 后 GREEN）。
##
## DLX-4 引入的 item.story_key 是"死内容哨兵"（语义判定当时留给后续工具）。
## 本测试把判定落进 ContentDB.validate_refs：声明 story_key 的物品必须被至少
## 一处内容引用——建筑 inputs 含它，或事件 effect 的 grant_items 含它；否则
## dangling 报告 unreferenced_story_key（内容包离线即可红灯，防死内容漂移）。
## 生产数据 echo_seed（余辉之种）由 echo_chamber.inputs 引用 → 通过性断言锁定。
## 非 story_key 物品不参与本扫描（既有 validate_refs 语义零变化）。

const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"

var _db_script: Script = null
var _temp_roots: Array[String] = []


func before_all() -> void:
	_db_script = load(CONTENT_DB_PATH) as Script


func after_each() -> void:
	for tree: String in _temp_roots:
		_remove_dir_recursive(tree)
	_temp_roots.clear()


func _new_db() -> Node:
	var db: Node = _db_script.new()
	add_child_autofree(db)
	return db


func _story_item(id: String) -> Dictionary:
	return {"id": id, "kind": "story_core", "name_zh": "哨兵物品", "stack_limit": 1, "story_key": true}


func _plain_item(id: String) -> Dictionary:
	return {"id": id, "kind": "material", "name_zh": "普通物品", "stack_limit": 9}


func _building(id: String, inputs: Array) -> Dictionary:
	return {
		"id": id, "kind": "building", "name_zh": "测试建筑",
		"inputs": inputs, "power_draw": 0, "power_supply": 0,
	}


func _grant_event(id: String, item_id: String) -> Dictionary:
	return {
		"id": id, "kind": "dialogue",
		"steps": [{"type": "effect", "grant_items": [{"item_id": item_id, "amount": 1}]}],
	}


func _write_fixture(root: String, items: Array, buildings: Array, events: Array) -> void:
	DirAccess.make_dir_recursive_absolute(root + "/content")
	DirAccess.make_dir_recursive_absolute(root + "/events")
	var paths: Dictionary = {
		root + "/content/items.json": items,
		root + "/content/buildings.json": buildings,
		root + "/events/event_fixture.json": events,
	}
	for path: String in paths:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		assert_not_null(file, "fixture 必须可写：%s" % path)
		if file != null:
			file.store_string(JSON.stringify(paths[path], "  "))
			file.close()


func _bootstrapped_db(root: String) -> Node:
	_temp_roots.append(root)
	var db: Node = _new_db()
	var result: AppResult = db.bootstrap(root)
	assert_true(result.is_ok, "fixture 必须通过 bootstrap：%s" % result.message)
	if not result.is_ok:
		return null
	return db


# ---------------------------------------------------------------- 通过路径


func test_story_item_referenced_by_building_inputs_passes() -> void:
	var root := "user://g7p2_story_ok_inputs"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_fixture(
		root,
		[_story_item("echo_seed_lost")],
		[_building("seed_altar", [{"item_id": "echo_seed_lost", "count": 1}])],
		[]
	)
	var db: Node = _bootstrapped_db(root)
	if db == null:
		return
	assert_true(db.validate_refs().is_ok)


func test_story_item_referenced_by_event_grant_items_passes() -> void:
	var root := "user://g7p2_story_ok_grant"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_fixture(
		root,
		[_story_item("echo_seed_lost")],
		[_building("bare_shrine", [])],
		[_grant_event("event_seed_grant", "echo_seed_lost")]
	)
	var db: Node = _bootstrapped_db(root)
	if db == null:
		return
	assert_true(db.validate_refs().is_ok)


func test_production_data_passes_story_key_scan() -> void:
	# echo_seed（story_key=true）由 echo_chamber inputs 引用——生产数据必须通过。
	var db: Node = _new_db()
	var boot: AppResult = db.bootstrap("res://data")
	assert_true(boot.is_ok, boot.message)
	assert_true(
		db.validate_refs().is_ok,
		"生产内容包必须通过 story_key 消费扫描。"
	)


func test_plain_item_without_story_key_needs_no_consumer() -> void:
	var root := "user://g7p2_story_plain"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_fixture(
		root,
		[_plain_item("loose_dust")],
		[_building("bare_shrine", [])],
		[]
	)
	var db: Node = _bootstrapped_db(root)
	if db == null:
		return
	# 无任何引用的普通物品不受本扫描约束（既有语义零变化）。
	assert_true(db.validate_refs().is_ok)


# ---------------------------------------------------------------- 拒绝路径


func test_unreferenced_story_item_reports_unreferenced_story_key() -> void:
	var root := "user://g7p2_story_dangling"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_fixture(
		root,
		[_story_item("echo_seed_lost")],
		[_building("bare_shrine", [])],
		[]
	)
	var db: Node = _bootstrapped_db(root)
	if db == null:
		return
	var result: AppResult = db.validate_refs()
	assert_false(result.is_ok, "未被引用的 story_key 物品必须红灯。")
	assert_eq(result.code, "dangling_ref")
	assert_true(
		result.message.contains("unreferenced_story_key"),
		"报告必须携带 unreferenced_story_key 标记，实际：%s" % result.message
	)
	assert_true(
		result.message.contains("echo_seed_lost"),
		"报告必须指认具体物品 id，实际：%s" % result.message
	)


func test_story_item_consumed_only_by_recipe_still_reports() -> void:
	# 扫描范围按裁决锁定为"建筑 inputs / 事件 grant_items"两处声明式消费点；
	# 仅出现在 recipe 配方里的 story 物品（非 inputs）视为未消费。
	var root := "user://g7p2_story_recipe_only"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	_write_fixture(
		root,
		[_story_item("echo_seed_lost"), _plain_item("dust")],
		[{
			"id": "seed_crusher", "kind": "building", "name_zh": "碾种机",
			"inputs": [{"item_id": "dust", "count": 1}],
			"recipe": {
				"input_item_id": "echo_seed_lost", "input_count": 1,
				"output_item_id": "dust", "output_count": 2,
			},
			"power_draw": 0, "power_supply": 0,
		}],
		[]
	)
	var db: Node = _bootstrapped_db(root)
	if db == null:
		return
	var result: AppResult = db.validate_refs()
	assert_false(result.is_ok)
	assert_true(result.message.contains("unreferenced_story_key"), result.message)


# ---------------------------------------------------------------- 工具


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
