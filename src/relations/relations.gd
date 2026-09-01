class_name Relations
extends RefCounted

## WP09 关系与立场纯逻辑（契约 docs/plans/contracts/module-contracts.md §0/§5/§7）。
## get_dim/trust 为纯函数，只读快照字典，任何缺失返回 0。
## change 构造并提交**单个** set_relationship patch：数值钳制 0..100，
## 非法角色/维度在构造 patch 之前干净失败（零修改、不触碰 store）。
## source_id = relations_<reason>_<revision>（稳定 snake_case），同 reason+revision
## 重放经 GameState 的 applied_patch_sources 幂等返回 already_applied。
## store 注入模式按契约 §0：store 为 null 时使用 GameState autoload；
## 注入替身与真实 StatePatch 共用未类型化（Variant）鸭子调用路径。
## DLX-1：移除 policy_unlocked 死 API（无生产调用方；真实门控由事件数据
## requires_trust + EventRunner.option_meets_trust 承担）。
## G7P-2 S5：角色登记表外置到 data/content/characters.json（schema
## schemas/character.schema.json）——关系白名单与 Hud 关系面板行同源读表，
## 新增可建关系角色 = 改 JSON，不改本文件。文件缺失/坏文件 push_error 并
## 回退缺省 {luoxian, misa}（迁移行为等价，关系系统永不因坏表全失效）。

const MIN_SCORE: int = 0
const MAX_SCORE: int = 100
## 角色登记表路径（bootstrap 惰性加载一次；测试可经 load_characters_from 注入）。
const CHARACTERS_PATH: String = "res://data/content/characters.json"
## 缺省角色行（文件缺失/坏文件的失败安全兜底，与迁移前硬编码白名单/显示名等价）。
const DEFAULT_CHARACTERS: Array[Dictionary] = [
	{"id": "luoxian", "name_zh": "洛弦", "accent_color": ""},
	{"id": "misa", "name_zh": "弥砂", "accent_color": ""},
]
const VALID_DIMENSIONS: Array[String] = ["affection", "trust", "ideology"]

## 角色表缓存（归一化行 {id, name_zh, accent_color}）；失败记为已引导，
## load_characters_from 可重新加载修复（测试注入临时表）。
static var _characters: Array[Dictionary] = []
static var _characters_bootstrapped: bool = false
static var _characters_last_load: AppResult = null


## 角色登记表只读访问器（防御性拷贝）：未引导时惰性加载生产角色表。
static func characters() -> Array[Dictionary]:
	if not _characters_bootstrapped:
		load_characters_from(CHARACTERS_PATH)
	return _characters.duplicate(true)


## 可建关系角色 id 集（关系白名单单一来源，来自角色表）。
static func valid_characters() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in characters():
		ids.append(String(row["id"]))
	return ids


## 加载指定路径的角色登记表：成功时缓存归一化行；缺失/坏文件 push_error 并
## 回退缺省角色行（白名单保持 {luoxian, misa}）。测试经本方法注入临时表。
static func load_characters_from(path: String) -> AppResult:
	var result: AppResult = _read_and_validate_characters(path)
	_characters_bootstrapped = true
	_characters_last_load = result
	if result.is_ok:
		_characters = result.value
	else:
		_characters = DEFAULT_CHARACTERS.duplicate(true)
		push_error("Relations: character table rejected (%s): %s" % [path, result.message])
	return result


static func _read_and_validate_characters(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure(
			"missing_characters_file", "Character table file not found: %s" % path
		)
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_characters_file",
			"Character table file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return AppResult.failure("invalid_characters_file", "Character table file must contain a JSON array.")
	var rows: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for entry_value: Variant in parsed:
		var problem: String = _character_entry_error(entry_value, seen_ids)
		if not problem.is_empty():
			return AppResult.failure("invalid_characters_file", problem)
		var entry: Dictionary = entry_value
		rows.append({
			"id": String(entry["id"]),
			"name_zh": String(entry["name_zh"]),
			"accent_color": String(entry.get("accent_color", "")),
		})
	return AppResult.success(rows)


## 最小语义校验：对象形态、id 稳定（snake_case）且唯一、name_zh 非空、
## accent_color 可选字符串。
static func _character_entry_error(entry_value: Variant, seen_ids: Dictionary) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "Character table entry is not an object."
	var entry: Dictionary = entry_value
	var id_value: Variant = entry.get("id")
	if typeof(id_value) != TYPE_STRING or not _is_stable_id(String(id_value)):
		return "Character table entry is missing a stable snake_case id."
	var char_id := String(id_value)
	if seen_ids.has(char_id):
		return "Character table entry id is duplicated: %s" % char_id
	var name_value: Variant = entry.get("name_zh")
	if typeof(name_value) != TYPE_STRING or (name_value as String).is_empty():
		return "Character table entry %s name_zh must be a non-empty string." % char_id
	if entry.has("accent_color") and typeof(entry["accent_color"]) != TYPE_STRING:
		return "Character table entry %s accent_color must be a string." % char_id
	seen_ids[char_id] = true
	return ""


static func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


static func get_dim(state: Dictionary, char_id: String, dim: String) -> int:
	var relationships: Dictionary = state.get("relationships", {})
	var record: Dictionary = relationships.get(char_id, {})
	return int(record.get(dim, 0))


static func change(
		state: Dictionary,
		char_id: String,
		dim: String,
		delta: int,
		reason: String,
		store: Object = null
) -> AppResult:
	if not valid_characters().has(char_id):
		return AppResult.failure(
			"invalid_character",
			"Relationship changes are limited to registered characters (data/content/characters.json), got %s." % char_id
		)
	if not VALID_DIMENSIONS.has(dim):
		return AppResult.failure(
			"invalid_dim",
			"Relationship dimension must be affection, trust, or ideology, got %s." % dim
		)

	var revision: int = int(state.get("revision", 0))
	var target: int = clampi(get_dim(state, char_id, dim) + delta, MIN_SCORE, MAX_SCORE)
	var patch: Variant = _begin_patch(
		store, "relations_%s_%d" % [reason, revision], revision)
	patch.set_relationship(char_id, dim, target)
	return _commit(store, patch)


static func trust(state: Dictionary, char_id: String) -> int:
	return get_dim(state, char_id, "trust")


## 契约 §0 注入模式：patch 经未类型化变量（Variant）走鸭子调用，
## 以便 DuckPatch 测试替身与真实 StatePatch 共用同一提交路径。
static func _begin_patch(store: Object, source_id: String, expected_revision: int) -> Variant:
	if store == null:
		return GameState.begin_patch(source_id, expected_revision)
	return store.begin_patch(source_id, expected_revision)


static func _commit(store: Object, patch: Variant) -> AppResult:
	if store == null:
		return GameState.commit(patch)
	return store.commit(patch)
