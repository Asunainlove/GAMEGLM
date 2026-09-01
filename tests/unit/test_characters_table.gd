extends GutTest

## G7P-2 S5：角色登记表数据化（TDD：先 RED 后 GREEN）。
##
## luoxian/misa 的 id/显示名从 Relations.VALID_CHARACTERS 与
## Hud.RELATION_ROW_IDS/RELATION_CHAR_NAMES 硬编码迁入
## data/content/characters.json（schema schemas/character.schema.json）：
## 关系白名单与 HUD 关系面板行同源读表——新增可建关系角色 = 改 JSON，
## 零代码。文件缺失/坏文件 push_error 并回退缺省 {luoxian, misa}
## （迁移行为等价，关系系统永不因坏表而全失效）。
## ContentDB 侧 characters.json 为数据保留文件（RESERVED_DATA_FILENAMES，
## 与 endings.json 同先例）并贡献 content_hash。

const RELATIONS_SCRIPT_PATH: String = "res://src/relations/relations.gd"
const PRODUCTION_CHARACTERS_PATH: String = "res://data/content/characters.json"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const CONTENT_DB_PATH: String = "res://src/content/content_db.gd"

var _relations: Script = null
var _temp_paths: Array[String] = []
var _temp_roots: Array[String] = []


func before_each() -> void:
	_relations = load(RELATIONS_SCRIPT_PATH)


func after_each() -> void:
	# 恢复生产角色表并清理临时文件，防止临时状态泄漏到其他测试文件。
	if _relations != null and _relations.has_method("load_characters_from"):
		_relations.load_characters_from(PRODUCTION_CHARACTERS_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	for tree: String in _temp_roots:
		_remove_dir_recursive(tree)
	_temp_paths.clear()
	_temp_roots.clear()


func _require_relations() -> bool:
	if _relations == null:
		fail_test("Missing required implementation: %s" % RELATIONS_SCRIPT_PATH)
		return false
	return true


func _write_temp_characters(case_name: String, text: String) -> String:
	var path: String = "user://g7p2_characters_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时角色表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


# ---------------------------------------------------------------- 生产表加载


func test_production_characters_table_loads() -> void:
	if not _require_relations():
		return
	var loaded: AppResult = _relations.load_characters_from(PRODUCTION_CHARACTERS_PATH)
	assert_true(loaded.is_ok, "生产 characters.json 必须可装载：%s" % loaded.message)
	assert_eq(_relations.characters(), [
		{"id": "luoxian", "name_zh": "洛弦", "accent_color": ""},
		{"id": "misa", "name_zh": "弥砂", "accent_color": ""},
	] as Array[Dictionary], "生产角色表必须逐字节迁移旧硬编码的两名同伴。")
	assert_eq(
		_relations.valid_characters(), ["luoxian", "misa"] as Array[String],
		"关系白名单必须与旧 VALID_CHARACTERS 常量一致。"
	)


func test_hud_relation_rows_read_names_from_table() -> void:
	if not _require_relations():
		return
	assert_true(_relations.load_characters_from(PRODUCTION_CHARACTERS_PATH).is_ok)
	var rows: Array[Dictionary] = Hud.relation_rows({"revision": 1, "relationships": {
		"luoxian": {"trust": 55, "affection": 3},
		"misa": {"trust": 30, "affection": 0},
	}})
	assert_eq(rows.size(), 2, "关系面板行数必须由角色表驱动（两名同伴）。")
	assert_eq(String(rows[0]["char_id"]), "luoxian")
	assert_eq(String(rows[0]["name_zh"]), "洛弦", "显示名必须来自角色表（旧 RELATION_CHAR_NAMES 等价）。")
	assert_eq(int(rows[0]["trust"]), 55)
	assert_eq(String(rows[1]["name_zh"]), "弥砂")


# ---------------------------------------------------------------- 第三角色纯数据扩展


func test_third_character_is_pure_data_extension_for_relations_and_hud() -> void:
	if not _require_relations():
		return
	var table := [
		{"id": "luoxian", "name_zh": "洛弦"},
		{"id": "misa", "name_zh": "弥砂"},
		{"id": "nadia", "name_zh": "娜迪娅", "accent_color": "#88AAFF"},
	]
	var path := _write_temp_characters("third", JSON.stringify(table))
	assert_true(_relations.load_characters_from(path).is_ok, "带 accent_color 的第三角色必须可装载。")
	assert_true(
		_relations.valid_characters().has("nadia"),
		"角色表登记的第三角色必须进入关系白名单。"
	)

	# 关系侧：nadia 的关系变更零代码生效（真实 GameState 提交）。
	var store: Node = GAME_STATE_SCRIPT.new()
	add_child_autofree(store)
	var result: AppResult = _relations.change(
		store.snapshot(), "nadia", "trust", 40, "g7p2_third_char_probe", store)
	assert_true(result.is_ok, result.message)
	assert_eq(
		int(((store.snapshot()["relationships"] as Dictionary)["nadia"] as Dictionary)["trust"]),
		40,
		"第三角色的关系变更必须成功提交。"
	)

	# HUD 侧：关系面板第三行零代码生效。
	var rows: Array[Dictionary] = Hud.relation_rows({"revision": 1, "relationships": {}})
	assert_eq(rows.size(), 3, "角色表第三条目必须派生第三行。")
	assert_eq(String(rows[2]["char_id"]), "nadia")
	assert_eq(String(rows[2]["name_zh"]), "娜迪娅")


# ---------------------------------------------------------------- 失败安全


func test_missing_characters_file_falls_back_to_defaults() -> void:
	if not _require_relations():
		return
	var result: AppResult = _relations.load_characters_from(
		"res://data/content/definitely_missing_characters.json")
	assert_false(result.is_ok, "缺失角色表必须加载失败。")
	assert_eq(result.code, "missing_characters_file")
	# 规范要求文件缺失 push_error；预期错误断言同时消费该错误。
	assert_push_error("Relations: character table rejected")
	assert_eq(
		_relations.valid_characters(), ["luoxian", "misa"] as Array[String],
		"坏表必须回退缺省 {luoxian, misa}（关系系统不得全失效）。"
	)


func test_malformed_characters_files_are_rejected() -> void:
	if not _require_relations():
		return
	var bad_cases: Array = [
		["syntax_error", "[{\"id\": not json"],
		["not_an_array", "{\"id\": \"luoxian\"}"],
		["entry_not_object", "[\"luoxian\"]"],
		["missing_id", "[{\"name_zh\": \"洛弦\"}]"],
		["id_not_stable", "[{\"id\": \"Luo Xian\", \"name_zh\": \"洛弦\"}]"],
		["duplicate_id", "[{\"id\": \"luoxian\", \"name_zh\": \"洛弦\"}, {\"id\": \"luoxian\", \"name_zh\": \"重名\"}]"],
		["missing_name_zh", "[{\"id\": \"luoxian\"}]"],
		["accent_color_not_string", "[{\"id\": \"luoxian\", \"name_zh\": \"洛弦\", \"accent_color\": 7}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_characters(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = _relations.load_characters_from(path)
		assert_false(result.is_ok, "坏角色表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Relations: character table rejected")


# ---------------------------------------------------------------- ContentDB 协同


func test_content_db_reserves_characters_json_and_hashes_it() -> void:
	# characters.json 与 endings.json 同为先例：ContentDB 不做 kind 分派装载
	#（保留文件），但其内容必须贡献 content_hash（角色表改动影响存档兼容性）。
	var db: Node = (load(CONTENT_DB_PATH) as Script).new()
	add_child_autofree(db)
	var root := "user://g7p2_characters_hash"
	_temp_roots.append(root)
	_remove_dir_recursive(root)
	DirAccess.make_dir_recursive_absolute(root + "/content")
	var item_file: FileAccess = FileAccess.open(root + "/content/alpha.json", FileAccess.WRITE)
	assert_not_null(item_file)
	if item_file != null:
		item_file.store_string('{"id": "starsoil_dust", "kind": "material", "name_zh": "星壤尘", "stack_limit": 99}')
		item_file.close()
	var char_file: FileAccess = FileAccess.open(root + "/content/characters.json", FileAccess.WRITE)
	assert_not_null(char_file)
	if char_file != null:
		char_file.store_string('[{"id": "luoxian", "name_zh": "洛弦"}, {"id": "misa", "name_zh": "弥砂"}]')
		char_file.close()

	var baseline: AppResult = db.bootstrap(root)
	assert_true(
		baseline.is_ok,
		"characters.json 必须作为保留文件被跳过 kind 分派（否则整包 bootstrap 失败）：%s" % baseline.message
	)
	var hash_value: String = db.content_hash()
	assert_ne(hash_value, "")

	var char_file2: FileAccess = FileAccess.open(root + "/content/characters.json", FileAccess.WRITE)
	assert_not_null(char_file2)
	if char_file2 != null:
		char_file2.store_string('[{"id": "luoxian", "name_zh": "洛弦改名"}, {"id": "misa", "name_zh": "弥砂"}]')
		char_file2.close()
	var mutated: Node = (load(CONTENT_DB_PATH) as Script).new()
	add_child_autofree(mutated)
	assert_true(mutated.bootstrap(root).is_ok)
	assert_ne(
		mutated.content_hash(), hash_value,
		"characters.json 变化必须改变总哈希。"
	)


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
