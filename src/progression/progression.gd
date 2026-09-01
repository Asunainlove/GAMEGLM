class_name Progression
extends RefCounted

## WP14 剧情推进与世界回应纯逻辑（契约 docs/plans/contracts/module-contracts.md §0/§5/§7）。
## due_event / world_response_ops / boss_hp_multiplier / ending_ready 为纯函数，
## 只读快照字典，任何缺失键按空值处理。react 通过注入 store（契约 §0：null →
## GameState autoload）提交单个 set_flag patch；done 标记复用 EventRunner 的
## `event_%s_done` 模板（事件 id 已带 event_ 前缀，实际 flag 为双前缀形态，
## 如 event_event_prologue_landing_done）。deferred_to_patch 是 EventRunner
## deferred_ops（{"op": "set_relationship", ...}）的消费桥，逐条映射到
## patch.set_relationship；WP04 的 set_relationship 已合并进 StatePatch。
## source_id = progression_<signal>_<revision>，同 signal+revision 重放经
## applied_patch_sources 幂等返回 already_applied。
## DLX-2：due_event 的有序事件链外置到 data/progression/event_chain.json
## （schema schemas/progression-chain.schema.json），bootstrap 一次加载并做
## 最小校验（数组/对象形态、id 唯一稳定、守卫字段类型），缺失或坏文件
## push_error 并回退为空链（due_event 失败安全恒返回 ""）。链是"优先级序"，
## 新增事件 = 改 JSON，不改本文件。event_envoy_trust（DLX-1 tick 过渡钩子
## 事件，requires_flag=approach_diplomatic）并入为链首条目，复现旧钩子
## "先于 due_event"的优先级——删除钩子后同一 state 的全局触发序列逐事件
## 一致（等价证明见 ops/evidence/DLX-2.md）。approach_/station_mode_ 前缀
## 常量仍是链数据所引前缀词汇表的规范来源。
## DLX-3：_react_built 删除逐 id match，改为通用规则——输入 building_def：
## place_flag 存在→set_flag（place_flag_powered=true 时需供电）；effect_flag
## 存在且 powered→set_flag；powered=false 且 effect_flag 存在→不置（单调保持）。
## building_def 由调用方经 payload 携带（GameSession 从 ContentDB 取选中定义）。
## G7P-2 M12：删除"payload 无 def 时自装载反应表"的回退路径，payload def 为
## 唯一权威——缺失 def → 空 def → no_op（失败安全恒零写入），单一判定路径
## 消除双路径漂移面。
## G7P-2 S1：ending_ready 的遭遇胜利旗标集外置到 data/progression/ending_gate.json
## （schema schemas/ending-gate.schema.json，与 event_chain 同一 bootstrap 模式）：
## 缺失/坏文件 push_error 并回退空表 → ending_ready 失败安全恒 false（永不满足，
## 不是空真）。station_mode_* 前缀守卫保留在本模块（链前缀词汇表规范来源）；
## 新增结局门条件 = 改 JSON，不改本文件。防漂移同步测试
## tests/unit/test_progression_ending_gate.gd 锁定门旗标 ⊆ 遭遇 on_victory_flag。

const EVENT_DONE_FLAG_FORMAT: String = "event_%s_done"
const FIRST_MINING_FLAG: String = "first_mining_done"
const LEVIATHAN_DUE_FLAG: String = "encounter_leviathan_due"
const FIRST_DRIFT_WON_FLAG: String = "encounter_first_drift_won"
const HUSK_AMBUSH_WON_FLAG: String = "encounter_husk_ambush_won"
const LEVIATHAN_WON_FLAG: String = "encounter_leviathan_won"
const BOSS_ESCALATED_FLAG: String = "boss_condition_escalated"
const STATION_MODE_PREFIX: String = "station_mode_"
const APPROACH_PREFIX: String = "approach_"
const POLICY_PREFIX: String = "policy_"
const BOSS_BASE_MULTIPLIER: float = 1.0
const BOSS_ESCALATED_MULTIPLIER: float = 1.2
## DLX-2：外置事件链文件路径（bootstrap 缺省加载；测试可经 load_chain_from
## 注入临时链文件）。
const EVENT_CHAIN_PATH: String = "res://data/progression/event_chain.json"
## G7P-2 S1：结局门控旗标表路径（bootstrap 缺省加载；测试可经
## load_ending_gate_from 注入临时门表）。
const ENDING_GATE_PATH: String = "res://data/progression/ending_gate.json"

## DLX-2 链缓存：bootstrap 一次性加载；失败同样记为已引导（tick 每帧调用
## due_event，不得逐帧重读坏文件），显式 load_chain_from 可重新加载修复。
static var _chain: Array[Dictionary] = []
static var _chain_bootstrapped: bool = false
static var _chain_last_load: AppResult = null

## G7P-2 S1 结局门表缓存：requires_all 旗标集（归一化 {"requires_all": [...]}）。
## 加载语义与链缓存一致：失败记为已引导，空表 = 永不满足；
## load_ending_gate_from 可重新加载修复（测试注入临时表）。
static var _ending_gate: Dictionary = {}
static var _ending_gate_bootstrapped: bool = false
static var _ending_gate_last_load: AppResult = null


## 按契约 §7 事件顺序返回应触发的事件 id：第一个未 done 且前置满足者；
## 全部完成返回 ""。done = flags[EVENT_DONE_FLAG_FORMAT % 事件 id] == true。
## DLX-2：有序链外置于 data/progression/event_chain.json（bootstrap 一次
## 缓存；文件缺失/坏文件 push_error 并回退空链 → 恒返回 ""）。链是"优先级
## 序"：前置未满足者被跳过，不阻塞后位；新增事件 = 改 JSON，不改本文件。
## 双守卫设计（如 diplomat_envoy 要求 diplomatic_stance 且 echo_chamber_active）
## 沿用 W003-A1 语义：第二守卫只在事件经对话链真实达成时置位，直接 patch
## 单一 flag 的测试路径不会误触发新事件。守卫逐条等价证明见
## ops/evidence/DLX-2.md。
static func due_event(state: Dictionary) -> String:
	for entry: Dictionary in _event_chain():
		var event_id: String = String(entry["id"])
		if _flag_enabled(state, EVENT_DONE_FLAG_FORMAT % event_id):
			continue
		if not _prerequisites_met(state, entry):
			continue
		return event_id
	return ""


## 信号反应：signal ∈ mined/built/event_completed/encounter_won/policy_chosen。
## mined 与 encounter_leviathan_due 为一次性（已置则成功跳过）；patch 的
## source_id = progression_<signal>_<revision> 保证同快照重放幂等。
## 返回 value = {"operations": <提交的 op 字典>, "skipped": bool}（失败时为 null）。
static func react(
		state: Dictionary,
		signal_name: String,
		payload: Dictionary,
		store: Object = null
) -> AppResult:
	match signal_name:
		"mined":
			return _react_mined(state, store)
		"built":
			return _react_built(state, payload, store)
		"event_completed":
			return _react_event_completed(payload)
		"encounter_won":
			return _react_leviathan_gate(state, payload, "encounter_id", "encounter_won", store)
		"policy_chosen":
			return _react_leviathan_gate(state, payload, "policy_id", "policy_chosen", store)
		_:
			return AppResult.failure("unknown_signal", "Unknown progression signal: %s" % signal_name)


## 纯函数：世界回应 patch 操作描述（op 字典数组），未知触发返回空数组。
static func world_response_ops(state: Dictionary, trigger: String) -> Array[Dictionary]:
	var flag_by_trigger: Dictionary = {
		"station_mode_exploit": "world_response_exploited",
		"policy_extraction_quota": BOSS_ESCALATED_FLAG,
		"approach_diplomatic": "diplomatic_stance",
	}
	var ops: Array[Dictionary] = []
	if flag_by_trigger.has(trigger):
		ops.append({"op": "set_flag", "flag_id": String(flag_by_trigger[trigger]), "enabled": true})
	return ops


## Boss 血量倍率：boss_condition_escalated 置位时 1.2，否则 1.0。
static func boss_hp_multiplier(state: Dictionary) -> float:
	if _flag_enabled(state, BOSS_ESCALATED_FLAG):
		return BOSS_ESCALATED_MULTIPLIER
	return BOSS_BASE_MULTIPLIER


## 结局就绪：任一 station_mode_* 且门表 requires_all 全置（G7P-2 S1 起旗标集
## 来自 data/progression/ending_gate.json）。门表缺失/坏文件（空表）时失败安全
## 恒 false——空表 = 永不满足，不是空真。
static func ending_ready(state: Dictionary) -> bool:
	if not _has_any_enabled_flag_with_prefix(state, STATION_MODE_PREFIX):
		return false
	var requires_all := _ending_gate_requires_all()
	if requires_all.is_empty():
		return false
	for flag_id: String in requires_all:
		if not _flag_enabled(state, flag_id):
			return false
	return true


## 结局门旗标集只读访问器：未引导时惰性加载生产门表（生产由 GameSession bootstrap
## 显式引导；直调 ending_ready 的既有测试路径经此触发加载）。
static func _ending_gate_requires_all() -> Array[String]:
	if not _ending_gate_bootstrapped:
		load_ending_gate_from(ENDING_GATE_PATH)
	var flags: Array[String] = []
	for flag_value: Variant in _ending_gate.get("requires_all", []):
		flags.append(String(flag_value))
	return flags


## 加载指定路径的结局门表：成功时缓存归一化 {"requires_all": Array[String]}；
## 缺失/坏文件 push_error 并把门表回退为空（ending_ready 失败安全恒 false）。
## 测试经本方法注入临时门表。
static func load_ending_gate_from(path: String) -> AppResult:
	var result: AppResult = _read_and_validate_ending_gate(path)
	_ending_gate_bootstrapped = true
	_ending_gate_last_load = result
	if result.is_ok:
		_ending_gate = result.value
	else:
		_ending_gate = {}
		push_error("Progression: ending gate rejected (%s): %s" % [path, result.message])
	return result


static func _read_and_validate_ending_gate(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure(
			"missing_ending_gate_file", "Ending gate file not found: %s" % path
		)
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_ending_gate_file",
			"Ending gate file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_ending_gate_file", "Ending gate file must contain a JSON object.")
	var gate: Dictionary = parsed
	var requires_all: Variant = gate.get("requires_all")
	if typeof(requires_all) != TYPE_ARRAY:
		return AppResult.failure(
			"invalid_ending_gate_file", "Ending gate requires_all must be an array."
		)
	if (requires_all as Array).is_empty():
		return AppResult.failure(
			"invalid_ending_gate_file", "Ending gate requires_all must not be empty."
		)
	var flags: Array[String] = []
	for flag_value: Variant in requires_all:
		if typeof(flag_value) != TYPE_STRING or not _is_stable_id(String(flag_value)):
			return AppResult.failure(
				"invalid_ending_gate_file",
				"Ending gate requires_all entries must be stable snake_case flag ids."
			)
		flags.append(String(flag_value))
	return AppResult.success({"requires_all": flags} as Dictionary)


## EventRunner deferred_ops 消费桥：把 {"op": "set_relationship", "char_id",
## "dim", "value"} 逐条映射到 patch.set_relationship（值钳制由 GameState 提交时
## 统一执行）。非字典条目跳过，保持与 EventRunner 相同的防御风格。
static func deferred_to_patch(ops: Array, patch: Variant) -> void:
	for op_variant: Variant in ops:
		if typeof(op_variant) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = op_variant
		patch.set_relationship(
			String(op.get("char_id", "")),
			String(op.get("dim", "")),
			int(op.get("value", 0))
		)


# ---------------------------------------------------------------- 事件链内部


## 外置链缓存访问器：未引导时惰性 bootstrap 兜底（生产由 GameSession._ready
## 显式引导；直调 due_event 的既有测试路径经此触发加载）。返回归一化条目
## {id, requires_all: Array[String], requires_any_prefix: String|null,
## requires_ending_ready: bool}；坏文件/缺失文件时为空数组。
static func _event_chain() -> Array[Dictionary]:
	if not _chain_bootstrapped:
		bootstrap()
	return _chain


## DLX-2：加载并校验外置事件链（一次性引导入口，幂等——重复调用返回上次
## 加载结果，不重复读盘）。G7P-2 S1 起 bootstrap 同时装载结局门表：链或门表
## 任一失败即返回该失败结果（先链后门表），两者皆成功返回门表结果。
static func bootstrap() -> AppResult:
	var chain_result: AppResult = (
		_chain_last_load if _chain_bootstrapped else load_chain_from(EVENT_CHAIN_PATH)
	)
	var gate_result: AppResult = (
		_ending_gate_last_load
		if _ending_gate_bootstrapped
		else load_ending_gate_from(ENDING_GATE_PATH)
	)
	if not chain_result.is_ok:
		return chain_result
	return gate_result


## 加载指定路径的链文件：成功时缓存归一化条目；缺失/坏文件 push_error 并把
## 链回退为空（due_event 失败安全返回 ""）。测试经本方法注入临时链。
static func load_chain_from(path: String) -> AppResult:
	var result: AppResult = _read_and_validate_chain(path)
	_chain_bootstrapped = true
	_chain_last_load = result
	if result.is_ok:
		_chain = result.value
	else:
		_chain = []
		push_error("Progression: event chain rejected (%s): %s" % [path, result.message])
	return result


static func _read_and_validate_chain(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure("missing_chain_file", "Event chain file not found: %s" % path)
	var text: String = FileAccess.get_file_as_string(path)
	# 与 EventRunner 同风格：用返回的 Error 码报告解析失败，坏 fixture 不刷引擎报错。
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_chain_file",
			"Event chain file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return AppResult.failure("invalid_chain_file", "Event chain file must contain a JSON array.")
	var seen_ids: Dictionary = {}
	var entries: Array[Dictionary] = []
	var index := 0
	for entry_variant: Variant in parsed:
		var problem: String = _chain_entry_error(entry_variant, index, seen_ids)
		if not problem.is_empty():
			return AppResult.failure("invalid_chain_file", problem)
		entries.append(_normalize_chain_entry(entry_variant))
		index += 1
	return AppResult.success(entries)


## 最小语义校验：对象形态、id 稳定（snake_case）且唯一、守卫字段类型。
static func _chain_entry_error(entry_value: Variant, index: int, seen_ids: Dictionary) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "Event chain entry %d is not an object." % index
	var entry: Dictionary = entry_value
	var id_value: Variant = entry.get("id")
	if typeof(id_value) != TYPE_STRING:
		return "Event chain entry %d is missing a string id." % index
	var event_id := String(id_value)
	if not _is_stable_id(event_id):
		return "Event chain entry %d id is not a stable snake_case id: %s" % [index, event_id]
	if seen_ids.has(event_id):
		return "Event chain entry id is duplicated: %s" % event_id
	var requires_all: Variant = entry.get("requires_all")
	if typeof(requires_all) != TYPE_ARRAY:
		return "Event chain entry %s requires_all must be an array." % event_id
	for flag_variant: Variant in requires_all:
		if typeof(flag_variant) != TYPE_STRING or String(flag_variant).is_empty():
			return "Event chain entry %s requires_all must contain non-empty strings." % event_id
	var prefix: Variant = entry.get("requires_any_prefix")
	if prefix != null and (typeof(prefix) != TYPE_STRING or String(prefix).is_empty()):
		return "Event chain entry %s requires_any_prefix must be a non-empty string or null." % event_id
	if typeof(entry.get("requires_ending_ready")) != TYPE_BOOL:
		return "Event chain entry %s requires_ending_ready must be a boolean." % event_id
	seen_ids[event_id] = true
	return ""


## 归一化条目：显式四字段，requires_all 转为 String 数组，与守卫判定解耦
## JSON 原始形态。
static func _normalize_chain_entry(entry_value: Variant) -> Dictionary:
	var entry: Dictionary = entry_value
	var requires_all: Array[String] = []
	for flag_variant: Variant in entry["requires_all"]:
		requires_all.append(String(flag_variant))
	var prefix: Variant = entry.get("requires_any_prefix")
	return {
		"id": String(entry["id"]),
		"requires_all": requires_all,
		"requires_any_prefix": String(prefix) if prefix != null else null,
		"requires_ending_ready": bool(entry["requires_ending_ready"]),
	}


## 守卫语义（DLX-2 起条目来自归一化外置链，仍按"缺失键按空值处理"的契约
## 口径防御读取）：requires_all 全真；requires_any_prefix 任一前缀命中
## （null 视为无此守卫）；requires_ending_ready → Progression.ending_ready(state)。
static func _prerequisites_met(state: Dictionary, entry: Dictionary) -> bool:
	for flag_variant: Variant in entry.get("requires_all", []):
		if not _flag_enabled(state, String(flag_variant)):
			return false
	var prefix: Variant = entry.get("requires_any_prefix")
	if prefix != null and not _has_any_enabled_flag_with_prefix(state, String(prefix)):
		return false
	if bool(entry.get("requires_ending_ready", false)) and not ending_ready(state):
		return false
	return true


# ---------------------------------------------------------------- react 内部


static func _react_mined(state: Dictionary, store: Object) -> AppResult:
	if _flag_enabled(state, FIRST_MINING_FLAG):
		return AppResult.success({"operations": [] as Array[Dictionary], "skipped": true}, "already_set")
	return _commit_operations(state, "mined", [_flag_operation(FIRST_MINING_FLAG)], store)


## DLX-3 建造反应通用规则（替换旧逐 id match，行为逐字节等价——冻结矩阵见
## tests/unit/test_progression_reactions.gd 与 ops/evidence/DLX-3.md）：
## building_def 取 payload.building_def（权威输入，集成路径：GameSession 传入
## ContentDB 选中定义）。G7P-2 M12：payload 无 def 时不再回退自装载反应表——
## 空 def → 无反应字段 → 成功 no_op 零写入（失败安全，单一权威路径）。规则：
## - place_flag 存在 → set_flag；place_flag_powered=true 时需供电才置位
##   （缺省 false，放置即置——anchor_block/anchor_workshop 里程碑语义）；
## - effect_flag 存在且 powered → set_flag；powered=false → 不置（单调保持，
##   现行为：stabilizer_pylon/echo_chamber 供电门控）；
## - 无任何反应字段 → 成功 no_op 零写入（与旧 default 分支一致）。
static func _react_built(state: Dictionary, payload: Dictionary, store: Object) -> AppResult:
	var building_id: String = String(payload.get("building_id", ""))
	if not _is_stable_id(building_id):
		return AppResult.failure(
			"invalid_building_id",
			"Built payload requires a stable snake_case building_id, got %s." % building_id
		)
	var powered: bool = bool(payload.get("powered", true))
	var building_def: Dictionary = _built_def_of(payload)
	var operations: Array[Dictionary] = []
	var place_flag := String(building_def.get("place_flag", ""))
	if not place_flag.is_empty():
		if powered or not bool(building_def.get("place_flag_powered", false)):
			operations.append(_flag_operation(place_flag))
	var effect_flag := String(building_def.get("effect_flag", ""))
	if not effect_flag.is_empty() and powered:
		operations.append(_flag_operation(effect_flag))
	if operations.is_empty():
		return AppResult.success({"operations": [] as Array[Dictionary], "skipped": true}, "no_op")
	return _commit_operations(state, "built", operations, store)


## built 反应的 def 解析（G7P-2 M12 单一权威）：payload.building_def 为字典时
## 采用；缺失/形态非法 → 空 def → no_op（失败安全零写入，不再自装载回退表）。
static func _built_def_of(payload: Dictionary) -> Dictionary:
	var def_value: Variant = payload.get("building_def", {})
	if typeof(def_value) == TYPE_DICTIONARY:
		return def_value
	return {}


static func _react_event_completed(payload: Dictionary) -> AppResult:
	var event_id: String = String(payload.get("event_id", ""))
	if not _is_stable_id(event_id):
		return AppResult.failure(
			"invalid_event_id",
			"event_completed payload requires a stable snake_case event_id, got %s." % event_id
		)
	# EventRunner.complete_event 已写 event_<id>_done；此处仅校验并成功返回。
	return AppResult.success({"operations": [] as Array[Dictionary], "skipped": true, "event_id": event_id})


static func _react_leviathan_gate(
		state: Dictionary,
		payload: Dictionary,
		id_key: String,
		signal_name: String,
		store: Object
) -> AppResult:
	var subject_id: String = String(payload.get(id_key, ""))
	if not _is_stable_id(subject_id):
		return AppResult.failure(
			"invalid_%s" % id_key,
			"%s payload requires a stable snake_case %s, got %s." % [signal_name, id_key, subject_id]
		)
	if _flag_enabled(state, LEVIATHAN_DUE_FLAG):
		return AppResult.success({"operations": [] as Array[Dictionary], "skipped": true}, "already_set")
	if not _flag_enabled(state, FIRST_DRIFT_WON_FLAG) or not _flag_enabled(state, HUSK_AMBUSH_WON_FLAG):
		return AppResult.success(
			{"operations": [] as Array[Dictionary], "skipped": true},
			"conditions_unmet"
		)
	if not _has_any_enabled_flag_with_prefix(state, POLICY_PREFIX):
		return AppResult.success(
			{"operations": [] as Array[Dictionary], "skipped": true},
			"conditions_unmet"
		)
	return _commit_operations(state, signal_name, [_flag_operation(LEVIATHAN_DUE_FLAG)], store)


# ---------------------------------------------------------------- 工具与提交


static func _flag_operation(flag_id: String) -> Dictionary:
	return {"type": StatePatch.OP_SET_FLAG, "flag_id": flag_id, "enabled": true}


static func _flag_enabled(state: Dictionary, flag_id: String) -> bool:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	return bool(flags.get(flag_id, false))


static func _has_any_enabled_flag_with_prefix(state: Dictionary, prefix: String) -> bool:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	for flag_variant: Variant in flags.keys():
		if String(flag_variant).begins_with(prefix) and bool(flags[flag_variant]):
			return true
	return false


static func _is_stable_id(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


## 契约 §0 注入模式：store 为 null 时回退 GameState autoload；patch 以未类型化
## 变量（Variant）走鸭子调用，DuckStore 替身与真实 StatePatch 共用提交路径。
static func _commit_operations(
		state: Dictionary,
		signal_name: String,
		operations: Array[Dictionary],
		store: Object
) -> AppResult:
	var store_object: Object = store
	if store_object == null:
		store_object = _default_store()
	var revision: int = int(state.get("revision", 0))
	var source_id: String = "progression_%s_%d" % [signal_name, revision]
	var patch: Variant = store_object.call("begin_patch", source_id, revision)
	for operation: Dictionary in operations:
		patch.call("set_flag", String(operation["flag_id"]), bool(operation["enabled"]))
	var commit_result: Variant = store_object.call("commit", patch)
	if commit_result is AppResult:
		return commit_result
	return AppResult.failure("invalid_store", "Store commit must return an AppResult.")


static func _default_store() -> Object:
	return GameState
