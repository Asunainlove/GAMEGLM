class_name Endings
extends RefCounted

## WP15 → DLX-1 结局判定与文案：由 data/content/endings.json 读表求值（契约
## docs/plans/contracts/module-contracts.md §4/§5/§7）。evaluate 为纯函数：
## 只读快照字典，任何缺失键按空值处理，不写入持久状态。
##
## 判定表（DLX-1 数据化）：条目按 order 升序（同 order 按文件序）逐条求值，
## 每条为声明式 all-of 门控（不是表达式求值）：
##   all_of_flags 全部置位 且 any_of_prefix 命中（若设）且 trust 达标（若设）
##   且 extra_flag 置位（若设）→ 命中，返回该条 id；
##   trust/extra_flag 不满足且设有 fallback_ending → 返回 fallback id
##   （与原硬编码行为一致：回落不重评目标条目自身门控）；
##   其余情况继续下一条；全部未命中 → ""（结局未定）。
##
## 表装载：bootstrap() 经 FileAccess 读取 + 语义校验（结构、稳定 ID、重复 id、
## fallback 引用存在性），成功后缓存；文件缺失或非法 → 失败并 push_error，
## 判定退化为 ""（结局未定），文案返回 ""。首次 evaluate/ending_title/
## ending_summary 会惰性 bootstrap，生产调用方零改动。
## 新增结局 = 在 endings.json 增加一个条目（无需改代码），由
## test_fourth_ending_is_pure_data_extension_without_code_change 证明。

const DEFAULT_DATA_PATH: String = "res://data/content/endings.json"

const ENDING_MINING: String = "ending_mining"
const ENDING_SEAL: String = "ending_seal"
const ENDING_SYMBIOSIS: String = "ending_symbiosis"

const ENTRY_FIELDS: Array[String] = [
	"id", "order", "all_of_flags", "any_of_prefix",
	"trust", "extra_flag", "fallback_ending", "title_zh", "summary_zh",
]
const REQUIRED_ENTRY_FIELDS: Array[String] = ["id", "order", "all_of_flags", "title_zh", "summary_zh"]
const TRUST_FIELDS: Array[String] = ["char_id", "dim", "threshold"]
const TRUST_DIMS: Array[String] = ["affection", "trust", "ideology"]
const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"

const _STATE_UNLOADED: int = 0
const _STATE_READY: int = 1
const _STATE_FAILED: int = 2

static var _table: Array[Dictionary] = []
static var _load_state: int = _STATE_UNLOADED
static var _loaded_path: String = ""
static var _id_regex: RegEx = null


## 装载并缓存结局表。data_path 为空时使用 DEFAULT_DATA_PATH；指向同一文件的
## 重复调用幂等返回成功，显式传入其他路径时重新装载（测试数据化扩展用）。
static func bootstrap(data_path: String = "") -> AppResult:
	var target_path: String = data_path if not data_path.is_empty() else DEFAULT_DATA_PATH
	if _load_state == _STATE_READY and _loaded_path == target_path:
		return AppResult.success()
	var result: AppResult = _load_table(target_path)
	if result.is_ok:
		_table = result.value
		_load_state = _STATE_READY
		_loaded_path = target_path
	else:
		_table = []
		_load_state = _STATE_FAILED
		_loaded_path = ""
		push_error("Endings: %s" % result.message)
	return result


## 清空缓存并恢复缺省数据路径（供测试在替身表与生产表之间切换）。
static func reset_for_tests() -> void:
	_table = []
	_load_state = _STATE_UNLOADED
	_loaded_path = ""


## 按契约 §7 判定结局 id；结局未定返回 ""。
static func evaluate(state: Dictionary) -> String:
	for entry: Dictionary in _ready_table():
		if not _all_flags_enabled(state, entry.get("all_of_flags", []) as Array):
			continue
		if not _any_prefix_enabled(state, _optional_id_field(entry, "any_of_prefix")):
			continue
		if _trust_met(state, entry) and _extra_flag_met(state, entry):
			return String(entry.get("id", ""))
		var fallback: String = _optional_id_field(entry, "fallback_ending")
		if not fallback.is_empty():
			return fallback
	return ""


## 结局标题：查表返回，未知（含空）id 返回 ""。
static func ending_title(id: String) -> String:
	return _text_for(id, "title_zh")


## 结局总结：查表返回原创中文成稿，未知（含空）id 返回 ""。
static func ending_summary(id: String) -> String:
	return _text_for(id, "summary_zh")


# ---------------------------------------------------------------- 求值内部


static func _ready_table() -> Array[Dictionary]:
	if _load_state == _STATE_UNLOADED:
		bootstrap()
	return _table


static func _all_flags_enabled(state: Dictionary, flag_ids: Array) -> bool:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	for flag_variant: Variant in flag_ids:
		if not bool(flags.get(String(flag_variant), false)):
			return false
	return true


static func _any_prefix_enabled(state: Dictionary, prefix: String) -> bool:
	if prefix.is_empty():
		return true
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	for flag_id: String in flags:
		if bool(flags.get(flag_id, false)) and flag_id.begins_with(prefix):
			return true
	return false


static func _trust_met(state: Dictionary, entry: Dictionary) -> bool:
	var gate_variant: Variant = entry.get("trust")
	if gate_variant == null:
		return true
	var gate: Dictionary = gate_variant
	var relationships: Dictionary = state.get("relationships", {}) as Dictionary
	var record: Dictionary = relationships.get(String(gate["char_id"]), {}) as Dictionary
	return int(record.get(String(gate["dim"]), 0)) >= int(gate["threshold"])


static func _extra_flag_met(state: Dictionary, entry: Dictionary) -> bool:
	var extra_flag: String = _optional_id_field(entry, "extra_flag")
	if extra_flag.is_empty():
		return true
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	return bool(flags.get(extra_flag, false))


## 可空 ID 字段（any_of_prefix/extra_flag/fallback_ending）读取：缺失或显式
## null（JSON 数据允许）统一返回 ""，避免 String(null) 构造错误。
static func _optional_id_field(entry: Dictionary, field: String) -> String:
	var value: Variant = entry.get(field)
	if value == null:
		return ""
	return String(value)


static func _text_for(id: String, field: String) -> String:
	for entry: Dictionary in _ready_table():
		if String(entry.get("id", "")) == id:
			return String(entry.get(field, ""))
	return ""


# ---------------------------------------------------------------- 装载内部


static func _load_table(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return _data_failure(path, "endings table file is missing.")
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return _data_failure(path, "not valid JSON at line %d." % json.get_error_line())
	var parsed: Variant = json.get_data()
	var entries: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		entries = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		entries = [parsed]
	else:
		return _data_failure(path, "must be a JSON array of ending entries.")
	if entries.is_empty():
		return _data_failure(path, "must define at least one ending.")
	var seen: Dictionary = {}
	var table: Array[Dictionary] = []
	for index: int in entries.size():
		var entry_variant: Variant = entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			return _data_failure(path, "ending entry #%d must be an object." % index)
		var entry: Dictionary = entry_variant
		var validation: AppResult = _validate_entry(entry, seen, path, index)
		if not validation.is_ok:
			return validation
		table.append(entry)
	for entry: Dictionary in table:
		if entry.has("fallback_ending") and entry["fallback_ending"] != null:
			if not seen.has(String(entry["fallback_ending"])):
				return _data_failure(
					path,
					"ending '%s' has fallback_ending '%s' that no entry defines."
						% [String(entry["id"]), String(entry["fallback_ending"])]
				)
	return AppResult.success(_sorted_by_order(table))


static func _validate_entry(entry: Dictionary, seen: Dictionary, path: String, index: int) -> AppResult:
	var label := "ending entry #%d" % index
	for field: Variant in entry.keys():
		if not ENTRY_FIELDS.has(String(field)):
			return _data_failure(path, "%s has unknown field '%s'." % [label, String(field)])
	for field: String in REQUIRED_ENTRY_FIELDS:
		if not entry.has(field):
			return _data_failure(path, "%s is missing required field '%s'." % [label, field])
	var id := String(entry["id"])
	if not _is_stable_id(id):
		return _data_failure(path, "%s id '%s' must match %s." % [label, id, ID_PATTERN])
	if seen.has(id):
		return _data_failure(path, "%s duplicates ending id '%s'." % [label, id])
	seen[id] = true
	if not _is_int_like(entry["order"]):
		return _data_failure(path, "%s order must be an integer." % label)
	var flags: Variant = entry["all_of_flags"]
	if typeof(flags) != TYPE_ARRAY:
		return _data_failure(path, "%s all_of_flags must be an array of flag ids." % label)
	for flag_variant: Variant in flags as Array:
		var flag := String(flag_variant)
		if not _is_stable_id(flag):
			return _data_failure(path, "%s all_of_flags entry '%s' must match %s." % [label, flag, ID_PATTERN])
	for field: String in ["any_of_prefix", "extra_flag", "fallback_ending"]:
		if entry.has(field) and entry[field] != null:
			var value := String(entry[field])
			if not _is_stable_id(value):
				return _data_failure(path, "%s %s '%s' must match %s or be null." % [label, field, value, ID_PATTERN])
	if entry.has("trust") and entry["trust"] != null:
		var gate_variant: Variant = entry["trust"]
		if typeof(gate_variant) != TYPE_DICTIONARY:
			return _data_failure(path, "%s trust must be an object {char_id, dim, threshold} or null." % label)
		var gate: Dictionary = gate_variant
		for gate_field: Variant in gate.keys():
			if not TRUST_FIELDS.has(String(gate_field)):
				return _data_failure(path, "%s trust has unknown field '%s'." % [label, String(gate_field)])
		for gate_field: String in TRUST_FIELDS:
			if not gate.has(gate_field):
				return _data_failure(path, "%s trust is missing '%s'." % [label, gate_field])
		if not _is_stable_id(String(gate["char_id"])):
			return _data_failure(path, "%s trust.char_id must match %s." % [label, ID_PATTERN])
		if not TRUST_DIMS.has(String(gate["dim"])):
			return _data_failure(path, "%s trust.dim must be one of affection/trust/ideology." % label)
		if not _is_int_like(gate["threshold"]) or int(gate["threshold"]) < 0 or int(gate["threshold"]) > 100:
			return _data_failure(path, "%s trust.threshold must be an integer within 0..100." % label)
	for field: String in ["title_zh", "summary_zh"]:
		if String(entry[field]).is_empty():
			return _data_failure(path, "%s %s must be a non-empty string." % [label, field])
	return AppResult.success()


static func _sorted_by_order(table: Array[Dictionary]) -> Array[Dictionary]:
	var wrappers: Array[Dictionary] = []
	for index: int in table.size():
		wrappers.append({
			"order": int(table[index].get("order", 0)),
			"index": index,
			"entry": table[index],
		})
	wrappers.sort_custom(_order_wrapper_less_than)
	var sorted: Array[Dictionary] = []
	for wrapper: Dictionary in wrappers:
		sorted.append(wrapper["entry"])
	return sorted


static func _order_wrapper_less_than(a: Dictionary, b: Dictionary) -> bool:
	if int(a["order"]) != int(b["order"]):
		return int(a["order"]) < int(b["order"])
	return int(a["index"]) < int(b["index"])


static func _data_failure(path: String, detail: String) -> AppResult:
	return AppResult.failure("invalid_endings_data", "Endings table %s: %s" % [path, detail])


static func _is_stable_id(value: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_PATTERN)
	var match_result: RegExMatch = _id_regex.search(value)
	return match_result != null and match_result.get_string(0) == value


static func _is_int_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value)))
