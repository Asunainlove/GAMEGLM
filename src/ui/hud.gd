class_name Hud
extends CanvasLayer

## 星壤只读 HUD（WP11）。
##
## 表现层约束：仅通过注入的 snapshot_provider 读取状态快照进行渲染，
## 绝不调用 begin_patch/commit，绝不写入任何持久状态。
## 唯一的"写"操作是引擎级 UI 状态（节点可见性与 get_tree().paused）。
## W003-A3 首次操作引导提示（HintToast）：一次性提示经 hint_seen_callback
## 由集成层落账，本层只做队列展示与只读 flags 去重。DLX-3 起提示文案与触发
## 条件外置到 data/progression/hints.json（触发点保留在集成层/HUD 输入层，
## 触发订阅与文案读表）；目标链外置到 data/progression/objectives.json——
## 新增目标/提示 = 改 JSON，不改本文件。

signal menu_resumed
signal save_requested
signal restart_requested
## W002-GAP4 建造热键栏：点击槽位请求选中该建筑（落账由集成层 select_building 完成）。
signal build_selected(building_id: String)
## W002-GAP4 背包配方区：点击"合成"请求一次精炼（落账由集成层 CraftingService 完成）。
signal craft_requested(building_id: String, recipe: Dictionary)

const POLL_INTERVAL_SECONDS: float = 0.25
const MAX_BAR_SLOTS: int = 8
const DEFAULT_NOTICE_SECONDS: float = 1.5
const UNPOWERED_DOT_COLOR: Color = Color(0.85, 0.15, 0.15)
const UNAFFORDABLE_SUFFIX: String = "（材料不足）"
const EMPTY_RECIPES_HINT: String = "暂无可用配方：需要已建成且供电的配方建筑。"

## DLX-3 目标链外置（schema schemas/objectives.schema.json）：有序条目
## {text_zh, all_of, any_of_prefix, not_flags}，objective_for 返回首个选中条目
## 文案，全部未选中兜底 FALLBACK_OBJECTIVE；文件缺失/坏文件 push_error 并兜底。
const OBJECTIVES_PATH: String = "res://data/progression/objectives.json"
const FALLBACK_OBJECTIVE: String = "探索世界"
## DLX-3 提示表路径（W003-A3 六条提示的文案与触发条件单一来源）。
const HINTS_PATH: String = "res://data/progression/hints.json"

## DLX-4 关系面板（PM-P0a 信任可见）：trust/affection 只读展示 + 信任门提示行。
## 门阈值数值单一来源为数据文件——政策门读事件选项 requires_trust（40 在
## data/events/event_policy.json 的 policy_sanctuary），共生门读结局 trust 门控
##（70 在 data/content/endings.json 的 ending_symbiosis）；本层绝不写死数值。
const POLICY_EVENT_PATH: String = "res://data/events/event_policy.json"
const ENDINGS_PATH: String = "res://data/content/endings.json"
## 关系面板固定展示的两名同伴（切片范围主角；缺记录按 0 渲染）。
const RELATION_ROW_IDS: Array[String] = ["luoxian", "misa"]
const RELATION_CHAR_NAMES: Dictionary = {"luoxian": "洛弦", "misa": "弥砂"}
## 关系维度展示刻度（GameState 的 set_relationship 已把值钳制在 0..100）。
const RELATION_DIM_SCALE: int = 100
## 门提示行模板：{char}=角色显示名，{threshold}=数据阈值，{remaining}=差值。
## 选项锁门（flag 未置位时提示）用 LOCKED_TEMPLATE，标签取选项文案冒号前段；
## 结局门（flag 置位后提示）用 REMAINING_TEMPLATE。
const GATE_LOCKED_TEMPLATE: String = "尚未赢得{char}的信任（{label}需要 {threshold}）"
const GATE_REMAINING_TEMPLATE: String = "距离共生还需 {remaining} 点信任"

## W003-A3 HintToast 展示参数：缺省停留 4s，淡入/淡出各一段。
const DEFAULT_HINT_SECONDS: float = 4.0
const HINT_FADE_IN_SECONDS: float = 0.25
const HINT_FADE_OUT_SECONDS: float = 0.35
const HINT_MIN_HOLD_SECONDS: float = 0.1
## 一次性标记 flag 名（hint_<id>_seen）；game_session 的落账回调使用同一格式。
const HINT_FLAG_FORMAT: String = "hint_%s_seen"

## 快照来源；缺省为 GameState.snapshot，测试与集成层可注入替身。
var snapshot_provider: Callable = Callable()

## 物品显示名解析；缺省返回 id 本身，集成层可注入中文映射。
var name_resolver: Callable = Callable()

## W002-GAP4 注入点（全部为只读 provider，由集成层 GameSession 绑定）：
## build_catalog() -> [{building_id, name_zh, cost_text, affordable}]
var build_catalog: Callable = Callable()
## selected_provider() -> 当前选中的 building_id（"" 表示无）
var selected_provider: Callable = Callable()
## unpowered_provider() -> [building_id]（存在断电实例的耗电建筑）
var unpowered_provider: Callable = Callable()
## recipe_provider() -> [{building_id, recipe, craftable}]
var recipe_provider: Callable = Callable()

## W003-A3 一次性提示落账回调（hint_id: String）-> void；缺省无操作。
## 表现层不写状态：由集成层注入的回调经 patch 把 hint_<id>_seen 置位。
var hint_seen_callback: Callable = Callable()

@onready var _inventory_bar: HBoxContainer = $InventoryBar
@onready var _objective_label: Label = $ObjectiveLabel
@onready var _relations_panel: HBoxContainer = $RelationsPanel
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _menu_panel: PanelContainer = $MenuPanel
@onready var _inventory_items_box: VBoxContainer = $InventoryPanel/Content/ItemsBox
@onready var _recipes_box: VBoxContainer = $InventoryPanel/Content/RecipesBox
@onready var _build_bar: HBoxContainer = $BuildBar
@onready var _hint_toast: PanelContainer = $HintToast
@onready var _hint_label: Label = $HintToast/HintLabel
@onready var _menu_help_panel: PanelContainer = $MenuPanel/Content/HelpPanel
@onready var _resume_button: Button = $MenuPanel/Content/ResumeButton
@onready var _save_button: Button = $MenuPanel/Content/SaveButton
@onready var _help_button: Button = $MenuPanel/Content/HelpButton
@onready var _restart_button: Button = $MenuPanel/Content/RestartButton

var _cached_revision: int = -1
var _poll_timer: Timer
var _notice_text: String = ""
var _notice_timer: Timer = null

## W003-A3 HintToast 运行态：队列逐条展示；_shown_hint_ids 做会话内一次性去重。
var _hint_queue: Array[Dictionary] = []
var _shown_hint_ids: Dictionary = {}
var _hint_displaying: bool = false
var _hint_fade_tween: Tween = null
var _hint_timer: Timer = null


func _ready() -> void:
	if not snapshot_provider.is_valid():
		if not snapshot_provider.is_null():
			push_warning("Hud.snapshot_provider 无效，回退到 GameState.snapshot。")
		snapshot_provider = GameState.snapshot
	if not name_resolver.is_valid():
		if not name_resolver.is_null():
			push_warning("Hud.name_resolver 无效，回退为直接显示物品 ID。")
		name_resolver = _default_name_resolver
	_resume_button.pressed.connect(_on_resume_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_help_button.pressed.connect(_on_help_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_poll_timer = Timer.new()
	_poll_timer.name = "PollTimer"
	_poll_timer.wait_time = POLL_INTERVAL_SECONDS
	_poll_timer.one_shot = false
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll_timer_timeout)
	add_child(_poll_timer)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_set_menu_open(not _menu_panel.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory"):
		_set_inventory_open(not _inventory_panel.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_overlay"):
		# W003-A3：首次 O 覆盖层的提示触发点在 HUD 内。刻意不 set_input_as_handled——
		# 覆盖层显隐的归属仍是 world（本层只提示，不消费输入）。
		_maybe_show_overlay_hint()


## 强制重渲染（忽略 revision 缓存）。
func refresh() -> void:
	var snapshot: Dictionary = _current_snapshot()
	_cached_revision = _revision_of(snapshot)
	_render(snapshot)


## 当前目标短语（DLX-3 表驱动）：返回外置目标链中首个选中条目的文案；全部
## 未选中时兜底"探索世界"。条目选中语义与 token 词汇表见
## schemas/objectives.schema.json：all_of 全部启用 ∧ not_flags 全部未启用 ∧
## any_of_prefix（非 null 时任一同前缀 flag 启用）；token 支持精确 flag id、
## 尾随 * 的 flag 前缀通配、placed_<building_id>/placed_* 放置谓词。文件缺失
## 或坏文件（加载期已 push_error）时失败安全恒返回兜底文案。
static func objective_for(snapshot: Dictionary) -> String:
	var entries: Array[Dictionary] = _objective_entries()
	if entries.is_empty():
		return FALLBACK_OBJECTIVE
	var flags: Dictionary = snapshot.get("flags", {}) as Dictionary
	var placed_ids: Array[String] = _placed_building_ids(snapshot)
	for entry: Dictionary in entries:
		if _objective_entry_selected(entry, flags, placed_ids):
			return String(entry["text_zh"])
	return FALLBACK_OBJECTIVE


# ---------------------------------------------------------------- 目标链表（DLX-3）


## 目标表缓存：bootstrap 一次性加载；失败记为已引导（轮询渲染逐帧调用
## objective_for，不得逐帧重读坏文件），显式 load_objectives_from 可重载修复。
static var _objectives: Array[Dictionary] = []
static var _objectives_bootstrapped: bool = false
static var _objectives_last_load: AppResult = null


## 目标表只读访问器（测试断言用）：未引导时惰性加载生产目标表。
static func _objective_entries() -> Array[Dictionary]:
	if not _objectives_bootstrapped:
		load_objectives_from(OBJECTIVES_PATH)
	return _objectives


## 加载指定路径的目标表：成功时缓存归一化条目；缺失/坏文件 push_error 并把
## 表回退为空（objective_for 失败安全恒返回兜底文案）。测试经本方法注入临时表。
static func load_objectives_from(path: String) -> AppResult:
	var result: AppResult = _read_and_validate_objectives(path)
	_objectives_bootstrapped = true
	_objectives_last_load = result
	if result.is_ok:
		_objectives = result.value
	else:
		_objectives = []
		push_error("Hud: objectives table rejected (%s): %s" % [path, result.message])
	return result


static func _read_and_validate_objectives(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure(
			"missing_objectives_file", "Objectives table file not found: %s" % path
		)
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_objectives_file",
			"Objectives table file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return AppResult.failure("invalid_objectives_file", "Objectives table file must contain a JSON array.")
	var entries: Array[Dictionary] = []
	var index := 0
	for entry_value: Variant in parsed:
		var problem: String = _objective_entry_error(entry_value, index)
		if not problem.is_empty():
			return AppResult.failure("invalid_objectives_file", problem)
		var entry: Dictionary = entry_value
		var not_flags: Array[String] = []
		for token: Variant in entry["not_flags"]:
			not_flags.append(String(token))
		entries.append({
			"text_zh": String(entry["text_zh"]),
			"all_of": _string_array_of(entry["all_of"]),
			"any_of_prefix": String(entry["any_of_prefix"]) if entry["any_of_prefix"] != null else null,
			"not_flags": not_flags,
		})
		index += 1
	return AppResult.success(entries)


static func _string_array_of(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


## 最小语义校验：对象形态、text_zh 非空、守卫字段类型、token 形态
##（精确稳定 ID / 尾随 * 前缀通配 / placed_ 放置谓词）。文案允许重复
##（威胁条目共享"应对漂移群威胁"）。
static func _objective_entry_error(entry_value: Variant, index: int) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "Objectives entry %d is not an object." % index
	var entry: Dictionary = entry_value
	if typeof(entry.get("text_zh")) != TYPE_STRING or String(entry["text_zh"]).is_empty():
		return "Objectives entry %d text_zh must be a non-empty string." % index
	for list_field: String in ["all_of", "not_flags"]:
		var list_value: Variant = entry.get(list_field)
		if typeof(list_value) != TYPE_ARRAY:
			return "Objectives entry %d %s must be an array." % [index, list_field]
		for token_value: Variant in list_value:
			var problem := _objective_token_error(token_value)
			if not problem.is_empty():
				return "Objectives entry %d %s: %s" % [index, list_field, problem]
	var prefix: Variant = entry.get("any_of_prefix")
	if prefix != null and (typeof(prefix) != TYPE_STRING or not _is_stable_id_shape(String(prefix))):
		return "Objectives entry %d any_of_prefix must be a snake_case prefix or null." % index
	return ""


## token 形态校验：精确 flag id / 前缀通配（尾随单个 *）/ placed_ 放置谓词。
static func _objective_token_error(token_value: Variant) -> String:
	if typeof(token_value) != TYPE_STRING:
		return "tokens must be strings."
	var token := String(token_value)
	if token.is_empty():
		return "tokens must be non-empty strings."
	if token.begins_with("placed_"):
		var suffix := token.substr(7)
		if suffix != "*" and not _is_stable_id_shape(suffix):
			return "placed token suffix must be '*' or a stable snake_case id: %s" % token
		return ""
	if token.ends_with("*"):
		var prefix := token.substr(0, token.length() - 1)
		if not _is_stable_id_shape(prefix):
			return "wildcard token must be a snake_case prefix followed by '*': %s" % token
		return ""
	if not _is_stable_id_shape(token):
		return "token must be a stable snake_case id, a '<prefix>*' wildcard, or a 'placed_' predicate: %s" % token
	return ""


static func _is_stable_id_shape(value: String) -> bool:
	return not value.is_empty() and value == value.to_lower() and value.is_valid_identifier()


## 条目选中判定（语义见 schemas/objectives.schema.json）。
static func _objective_entry_selected(
		entry: Dictionary, flags: Dictionary, placed_ids: Array[String]) -> bool:
	for token: String in entry["all_of"]:
		if not _objective_token_enabled(token, flags, placed_ids):
			return false
	for token: String in entry["not_flags"]:
		if _objective_token_enabled(token, flags, placed_ids):
			return false
	var prefix: Variant = entry.get("any_of_prefix")
	if prefix != null and not _has_any_enabled_flag_with_prefix(flags, String(prefix)):
		return false
	return true


## token 求值：placed_ 放置谓词优先（placed_ 不是 flag 前缀），其次尾随 *
## 的 flag 前缀通配，否则精确 flag。placed_* 命中任意已放置建筑。
static func _objective_token_enabled(
		token: String, flags: Dictionary, placed_ids: Array[String]) -> bool:
	if token.begins_with("placed_"):
		var suffix := token.substr(7)
		if suffix == "*":
			return not placed_ids.is_empty()
		return placed_ids.has(suffix)
	if token.ends_with("*"):
		var prefix := token.substr(0, token.length() - 1)
		return _has_any_enabled_flag_with_prefix(flags, prefix)
	return bool(flags.get(token, false))


static func _has_any_enabled_flag_with_prefix(flags: Dictionary, prefix: String) -> bool:
	for flag_variant: Variant in flags.keys():
		if String(flag_variant).begins_with(prefix) and bool(flags[flag_variant]):
			return true
	return false


static func _flag_enabled(flags: Dictionary, flag_id: String) -> bool:
	return flags.get(flag_id, false) == true


static func _placed_building_ids(snapshot: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var buildings: Variant = snapshot.get("placed_buildings", [])
	if buildings is Array:
		for building: Variant in buildings:
			if building is Dictionary:
				var building_id := str((building as Dictionary).get("building_id", ""))
				if building_id != "" and not ids.has(building_id):
					ids.append(building_id)
	return ids


# ---------------------------------------------------------------- 关系面板（DLX-4 PM-P0a）


## 快照 relationships 的只读维度取值；缺失记录/维度按 0 处理，绝不修改快照。
static func _relationship_dim(snapshot: Dictionary, char_id: String, dim: String) -> int:
	var relationships: Dictionary = snapshot.get("relationships", {}) as Dictionary
	var record: Dictionary = relationships.get(char_id, {}) as Dictionary
	return int(record.get(dim, 0))


## 关系面板数值行（纯函数，测试断言用）：固定两名同伴，每行携带
## {char_id, name_zh, trust, affection}；缺失记录按 0 渲染。
static func relation_rows(snapshot: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for char_id: String in RELATION_ROW_IDS:
		var name_value: Variant = RELATION_CHAR_NAMES.get(char_id, char_id)
		rows.append({
			"char_id": char_id,
			"name_zh": String(name_value),
			"trust": _relationship_dim(snapshot, char_id, "trust"),
			"affection": _relationship_dim(snapshot, char_id, "affection"),
		})
	return rows


## 门提示表缓存：bootstrap 一次性加载（数值来自数据文件）；失败记为已引导
##（轮询渲染逐帧调用 relations_gate_lines，不得逐帧重读坏文件），显式
## load_relation_gates_from 可重载修复（测试注入临时数据文件）。
static var _gates: Array[Dictionary] = []
static var _gates_bootstrapped: bool = false
static var _gates_last_load: AppResult = null


## 门表只读访问器（测试断言用）：未引导时惰性加载生产数据文件。
static func _gate_entries() -> Array[Dictionary]:
	if not _gates_bootstrapped:
		load_relation_gates_from(POLICY_EVENT_PATH, ENDINGS_PATH)
	return _gates


## 加载信任门数据：政策门读 policy 事件里带 requires_trust（对象形态）的选项
##（flag = 选项 set_flag，标签取选项文案冒号前段），选项锁语义——flag 未置位
## 且维度低于阈值时提示；共生门读 endings 表 trust 门控条目（flag = 该结局
## all_of_flags 首位），结局门语义——flag 置位后维度仍低于阈值时提示。
## 缺失/坏文件 push_error 并把表回退为空（失败安全：只少提示行，不渲染错值）。
static func load_relation_gates_from(policy_event_path: String, endings_path: String) -> AppResult:
	var result: AppResult = _read_and_validate_gates(policy_event_path, endings_path)
	_gates_bootstrapped = true
	_gates_last_load = result
	if result.is_ok:
		_gates = result.value
	else:
		_gates = []
		push_error("Hud: relation gate data rejected (%s, %s): %s" % [
			policy_event_path, endings_path, result.message,
		])
	return result


static func _read_and_validate_gates(policy_event_path: String, endings_path: String) -> AppResult:
	var gates: Array[Dictionary] = []
	var option_result: AppResult = _gates_from_policy_event(policy_event_path)
	if not option_result.is_ok:
		return option_result
	for gate: Dictionary in option_result.value:
		gates.append(gate)
	var endings_result: AppResult = _gates_from_endings(endings_path)
	if not endings_result.is_ok:
		return endings_result
	for gate: Dictionary in endings_result.value:
		gates.append(gate)
	return AppResult.success(gates)


## 从事件数据派生选项锁门：任何带 requires_trust（对象形态 {char_id, dim,
## value}）+ set_flag 的选项都成为一条门提示（当前生产数据即 policy_sanctuary）。
static func _gates_from_policy_event(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure("missing_gate_data_file", "Policy event file not found: %s" % path)
	var json := JSON.new()
	var parse_error: Error = json.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return AppResult.failure(
			"invalid_gate_data_file",
			"Policy event file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return AppResult.failure("invalid_gate_data_file", "Policy event file must contain a JSON object.")
	var gates: Array[Dictionary] = []
	var steps: Array = (parsed as Dictionary).get("steps", [])
	for step_value: Variant in steps:
		if typeof(step_value) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = step_value
		if String(step.get("type", "")) != "choice":
			continue
		for option_value: Variant in step.get("options", []):
			if typeof(option_value) != TYPE_DICTIONARY:
				continue
			var option: Dictionary = option_value
			var requirement: Variant = option.get("requires_trust")
			var flag_id := String(option.get("set_flag", ""))
			if typeof(requirement) != TYPE_DICTIONARY or flag_id.is_empty():
				continue
			var requirement_dict: Dictionary = requirement
			var threshold := int(requirement_dict.get("value", 0))
			var char_id := String(requirement_dict.get("char_id", ""))
			var dim := String(requirement_dict.get("dim", ""))
			if char_id.is_empty() or dim.is_empty():
				continue
			var option_text := String(option.get("text_zh", flag_id))
			var label := option_text.split("：")[0] if option_text.contains("：") else option_text
			gates.append({
				"flag_id": flag_id,
				"show_when_set": false,
				"char_id": char_id,
				"dim": dim,
				"threshold": threshold,
				"template": GATE_LOCKED_TEMPLATE,
				"label": label,
			})
	return AppResult.success(gates)


## 从结局数据派生结局门：trust 门控非空的结局条目成为一条"flag 置位后仍低于
## 阈值则提示"的门（当前生产数据即共生结局 70）。flag 取 all_of_flags 首位。
static func _gates_from_endings(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure("missing_gate_data_file", "Endings file not found: %s" % path)
	var json := JSON.new()
	var parse_error: Error = json.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		return AppResult.failure(
			"invalid_gate_data_file",
			"Endings file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return AppResult.failure("invalid_gate_data_file", "Endings file must contain a JSON array.")
	var gates: Array[Dictionary] = []
	for entry_value: Variant in parsed:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var trust: Variant = entry.get("trust")
		if typeof(trust) != TYPE_DICTIONARY:
			continue
		var trust_dict: Dictionary = trust
		var all_flags: Array = entry.get("all_of_flags", [])
		if all_flags.is_empty():
			continue
		gates.append({
			"flag_id": String(all_flags[0]),
			"show_when_set": true,
			"char_id": String(trust_dict.get("char_id", "")),
			"dim": String(trust_dict.get("dim", "")),
			"threshold": int(trust_dict.get("threshold", 0)),
			"template": GATE_REMAINING_TEMPLATE,
		})
	return AppResult.success(gates)


## 门提示行（纯函数，测试断言用）：选项锁门在 flag 未置位且维度低于阈值时
## 出现；结局门在 flag 置位后维度仍低于阈值时出现。模板占位符 {char}/
## {threshold}/{remaining}/{label} 按门条目替换；绝不修改快照。
static func relations_gate_lines(snapshot: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var flags: Dictionary = snapshot.get("flags", {}) as Dictionary
	for gate: Dictionary in _gate_entries():
		var flag_set := bool(flags.get(String(gate["flag_id"]), false))
		if flag_set != bool(gate["show_when_set"]):
			continue
		var threshold := int(gate["threshold"])
		var value := _relationship_dim(snapshot, String(gate["char_id"]), String(gate["dim"]))
		if value >= threshold:
			continue
		var name_value: Variant = RELATION_CHAR_NAMES.get(String(gate["char_id"]), String(gate["char_id"]))
		lines.append(String(gate["template"])
			.replace("{char}", String(name_value))
			.replace("{label}", String(gate.get("label", "")))
			.replace("{threshold}", str(threshold))
			.replace("{remaining}", str(threshold - value)))
	return lines


## RelationsPanel 渲染：每名同伴一行（数值 Label + 微型进度条），其后按需
## 追加门提示行。全部只读快照。
func _render_relations(snapshot: Dictionary) -> void:
	_clear_children(_relations_panel)
	for row: Dictionary in relation_rows(snapshot):
		var row_box := HBoxContainer.new()
		row_box.name = "RelationRow_%s" % str(row["char_id"])
		_append_label(row_box, "%s 信任 %d/%d ♥%d" % [
			str(row["name_zh"]), int(row["trust"]), RELATION_DIM_SCALE, int(row["affection"]),
		])
		var bar := ProgressBar.new()
		bar.name = "TrustBar_%s" % str(row["char_id"])
		bar.min_value = 0
		bar.max_value = RELATION_DIM_SCALE
		bar.value = int(row["trust"])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(72.0, 10.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_box.add_child(bar)
		_relations_panel.add_child(row_box)
	for line: String in relations_gate_lines(snapshot):
		_append_label(_relations_panel, line)


func _on_poll_timer_timeout() -> void:
	var snapshot: Dictionary = _current_snapshot()
	var revision: int = _revision_of(snapshot)
	if revision == _cached_revision:
		return
	_cached_revision = revision
	_render(snapshot)


func _current_snapshot() -> Dictionary:
	if not snapshot_provider.is_valid():
		if not snapshot_provider.is_null():
			push_warning("Hud.snapshot_provider 无效，回退到 GameState.snapshot。")
		snapshot_provider = GameState.snapshot
	var provided: Variant = snapshot_provider.call()
	if provided is Dictionary:
		return provided
	push_warning("Hud.snapshot_provider 未返回 Dictionary，使用空快照渲染。")
	return {}


func _revision_of(snapshot: Dictionary) -> int:
	return int(snapshot.get("revision", 0))


func _render(snapshot: Dictionary) -> void:
	_render_inventory_bar(snapshot)
	_render_relations(snapshot)
	_render_inventory_panel(snapshot)
	_render_build_bar()
	# 配方区跟随背包面板显隐渲染；合成落账会推进 revision，轮询路径同样会刷新。
	if _inventory_panel.visible:
		_render_recipe_rows()
	# 通知窗口期内保持提示文案，避免轮询重渲染覆盖短暂提示。
	if _notice_text.is_empty():
		_objective_label.text = objective_for(snapshot)


func _render_inventory_bar(snapshot: Dictionary) -> void:
	_clear_children(_inventory_bar)
	var entries: Array[Dictionary] = _inventory_entries(snapshot)
	var overflow_kinds: int = 0
	for index: int in entries.size():
		if index >= MAX_BAR_SLOTS:
			overflow_kinds += 1
			continue
		var entry: Dictionary = entries[index]
		_append_label(_inventory_bar, "%s ×%d" % [entry["name"], entry["amount"]])
	if overflow_kinds > 0:
		_append_label(_inventory_bar, "+%d" % overflow_kinds)


func _render_inventory_panel(snapshot: Dictionary) -> void:
	_clear_children(_inventory_items_box)
	var entries: Array[Dictionary] = _inventory_entries(snapshot)
	if entries.is_empty():
		_append_label(_inventory_items_box, "背包空空如也。")
		return
	for entry: Dictionary in entries:
		_append_label(_inventory_items_box, "%s ×%d" % [entry["name"], entry["amount"]])


func _inventory_entries(snapshot: Dictionary) -> Array[Dictionary]:
	var stock: Dictionary = {}
	var inventory: Variant = snapshot.get("inventory", {})
	if inventory is Dictionary:
		stock = inventory as Dictionary
	var ids: Array[String] = []
	for item_id: String in stock.keys():
		if int(stock[item_id]) > 0:
			ids.append(item_id)
	ids.sort()
	var entries: Array[Dictionary] = []
	for item_id: String in ids:
		entries.append({
			"id": item_id,
			"name": _resolve_name(item_id),
			"amount": int(stock[item_id]),
		})
	return entries


# ---------------------------------------------------------------- 建造热键栏（W002-GAP4）


## BuildBar：按注入目录渲染 6 个建造槽（序号 + 中文名 + 成本摘要）。
## 选中槽位按下态高亮；断电建筑槽位右上角小红点；材料不足槽位加（材料不足）。
## 点击槽位发 build_selected 信号——表现层不直接改选中状态。
func _render_build_bar() -> void:
	_clear_children(_build_bar)
	var catalog: Array = _provider_array(build_catalog)
	var selected := _selected_building_id()
	var unpowered := _string_set(_provider_array(unpowered_provider))
	for index: int in catalog.size():
		var entry := catalog[index] as Dictionary
		if entry == null:
			continue
		var building_id := str(entry.get("building_id", ""))
		var button := Button.new()
		button.name = "BuildSlot_%s" % building_id
		button.toggle_mode = true
		button.button_pressed = building_id != "" and building_id == selected
		var cost_text := str(entry.get("cost_text", ""))
		if not bool(entry.get("affordable", false)):
			cost_text += UNAFFORDABLE_SUFFIX
		button.text = "%d %s\n%s" % [index + 1, str(entry.get("name_zh", building_id)), cost_text]
		if unpowered.has(building_id):
			button.add_child(_make_unpowered_dot())
		button.pressed.connect(_on_build_slot_pressed.bind(building_id))
		_build_bar.add_child(button)


func _make_unpowered_dot() -> ColorRect:
	var dot := ColorRect.new()
	dot.name = "UnpoweredDot"
	dot.color = UNPOWERED_DOT_COLOR
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -12.0
	dot.offset_top = 2.0
	dot.offset_right = -4.0
	dot.offset_bottom = 10.0
	return dot


func _on_build_slot_pressed(building_id: String) -> void:
	build_selected.emit(building_id)
	# 选中变化不经 revision（不提交 patch），延迟一帧重建以立即移动高亮，
	# 且避免在信号发射过程中释放发射按钮本身。
	_render_build_bar.call_deferred()


# ---------------------------------------------------------------- 背包配方区（W002-GAP4）


## RecipesBox：按注入配方列表渲染"输出名：输入×n → 输出×m [合成]"行；
## 不可合成的行按钮置灰。点击发 craft_requested 信号，落账由集成层完成。
## provider 未注入（非集成环境）时不渲染任何内容。
func _render_recipe_rows() -> void:
	_clear_children(_recipes_box)
	if not recipe_provider.is_valid():
		return
	var entries := _provider_array(recipe_provider)
	if entries.is_empty():
		_append_label(_recipes_box, EMPTY_RECIPES_HINT)
		return
	for entry_value: Variant in entries:
		var entry := entry_value as Dictionary
		if entry == null:
			continue
		var building_id := str(entry.get("building_id", ""))
		var recipe := entry.get("recipe", {}) as Dictionary
		if recipe == null or recipe.is_empty():
			continue
		var row := HBoxContainer.new()
		var inputs_text := _recipe_inputs_text(recipe)
		var output_text := "%s×%d" % [
			_resolve_name(str(recipe.get("output_item_id", ""))),
			int(recipe.get("output_count", 1)),
		]
		_append_label(row, "%s：%s → %s" % [
			_resolve_name(str(recipe.get("output_item_id", ""))),
			inputs_text,
			output_text,
		])
		var craft_button := Button.new()
		craft_button.text = "合成"
		craft_button.disabled = not bool(entry.get("craftable", false))
		craft_button.pressed.connect(_on_craft_pressed.bind(building_id, recipe))
		row.add_child(craft_button)
		_recipes_box.add_child(row)


func _recipe_inputs_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var pairs: Array = [
		["input_item_id", "input_count"],
		["extra_input_item_id", "extra_input_count"],
	]
	for pair: Array in pairs:
		var item_id := str(recipe.get(pair[0], ""))
		if item_id == "":
			continue
		parts.append("%s×%d" % [_resolve_name(item_id), int(recipe.get(pair[1], 1))])
	return " + ".join(parts)


func _on_craft_pressed(building_id: String, recipe: Dictionary) -> void:
	craft_requested.emit(building_id, recipe)
	# 合成提交由集成层同步完成；延迟一帧重渲染行区与背包（避免释放发射按钮）。
	_refresh_after_craft.call_deferred()


func _refresh_after_craft() -> void:
	refresh()


# ---------------------------------------------------------------- provider 工具


## 读取注入 provider 的结果；无效 Callable 或非数组返回安全空数组。
func _provider_array(provider: Callable) -> Array:
	if not provider.is_valid():
		return []
	var provided: Variant = provider.call()
	if provided is Array:
		return provided
	return []


func _selected_building_id() -> String:
	if not selected_provider.is_valid():
		return ""
	var provided: Variant = selected_provider.call()
	return str(provided) if typeof(provided) == TYPE_STRING else ""


func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		result[str(value)] = true
	return result


func _resolve_name(item_id: String) -> String:
	if not name_resolver.is_valid():
		return item_id
	var resolved: Variant = name_resolver.call(item_id)
	if resolved is String:
		return resolved
	return item_id


func _default_name_resolver(item_id: String) -> String:
	return item_id


func _set_menu_open(open: bool) -> void:
	_menu_panel.visible = open
	get_tree().paused = open


func _set_inventory_open(open: bool) -> void:
	_inventory_panel.visible = open
	if open:
		refresh()


func _on_resume_pressed() -> void:
	_set_menu_open(false)
	menu_resumed.emit()


func _on_save_pressed() -> void:
	# 表现层只发意图信号；落账由集成层经 SaveService 完成。
	save_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_help_pressed() -> void:
	_menu_help_panel.visible = not _menu_help_panel.visible


## 短暂提示：把 ObjectiveLabel 文案替换为 text，seconds 秒后恢复目标短语。
## 轮询重渲染在通知窗口期内不覆盖提示（见 _render）。仅引擎级 UI 状态。
func flash_notice(text_value: String, seconds: float = DEFAULT_NOTICE_SECONDS) -> void:
	_notice_text = text_value
	_objective_label.text = text_value
	if _notice_timer == null:
		_notice_timer = Timer.new()
		_notice_timer.name = "NoticeTimer"
		_notice_timer.one_shot = true
		_notice_timer.timeout.connect(_on_notice_timeout)
		add_child(_notice_timer)
	_notice_timer.stop()
	_notice_timer.wait_time = maxf(seconds, 0.0)
	_notice_timer.start()


## 立即结束短暂提示并恢复目标短语。
func clear_notice() -> void:
	if _notice_timer != null:
		_notice_timer.stop()
	_on_notice_timeout()


func _on_notice_timeout() -> void:
	_notice_text = ""
	_objective_label.text = objective_for(_current_snapshot())


# ---------------------------------------------------------------- 首次操作引导提示（W003-A3 / DLX-3）


## 提示表缓存：bootstrap 一次性加载；失败记为已引导，显式 load_hints_from
## 可重载修复（测试注入临时表）。
static var _hints: Array[Dictionary] = []
static var _hints_bootstrapped: bool = false
static var _hints_last_load: AppResult = null


## 提示表只读访问器（测试断言用）：未引导时惰性加载生产提示表。
static func _hint_entries() -> Array[Dictionary]:
	if not _hints_bootstrapped:
		load_hints_from(HINTS_PATH)
	return _hints


## 加载指定路径的提示表：成功时缓存归一化条目；缺失/坏文件 push_error 并把
## 表回退为空（hint_text/hints_for_trigger 失败安全返回空）。测试经本方法注入
## 临时表。
static func load_hints_from(path: String) -> AppResult:
	var result: AppResult = _read_and_validate_hints(path)
	_hints_bootstrapped = true
	_hints_last_load = result
	if result.is_ok:
		_hints = result.value
	else:
		_hints = []
		push_error("Hud: hints table rejected (%s): %s" % [path, result.message])
	return result


static func _read_and_validate_hints(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return AppResult.failure(
			"missing_hints_file", "Hints table file not found: %s" % path
		)
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return AppResult.failure(
			"invalid_hints_file",
			"Hints table file is not valid JSON at line %d." % json.get_error_line()
		)
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_ARRAY:
		return AppResult.failure("invalid_hints_file", "Hints table file must contain a JSON array.")
	var entries: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for entry_value: Variant in parsed:
		var problem: String = _hint_entry_error(entry_value, seen_ids)
		if not problem.is_empty():
			return AppResult.failure("invalid_hints_file", problem)
		var entry: Dictionary = entry_value
		entries.append({
			"id": String(entry["id"]),
			"text_zh": String(entry["text_zh"]),
			"trigger": String(entry["trigger"]),
		})
	return AppResult.success(entries)


## 最小语义校验：对象形态、id 稳定且唯一、text_zh 非空、trigger 形态
##（固定触发点 / built:<building_id> / built:* 通配）。
static func _hint_entry_error(entry_value: Variant, seen_ids: Dictionary) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "Hints entry is not an object."
	var entry: Dictionary = entry_value
	var id_value: Variant = entry.get("id")
	if typeof(id_value) != TYPE_STRING or not _is_stable_id_shape(String(id_value)):
		return "Hints entry is missing a stable snake_case id."
	var hint_id := String(id_value)
	if seen_ids.has(hint_id):
		return "Hints entry id is duplicated: %s" % hint_id
	if typeof(entry.get("text_zh")) != TYPE_STRING or String(entry["text_zh"]).is_empty():
		return "Hints entry %s text_zh must be a non-empty string." % hint_id
	var trigger: Variant = entry.get("trigger")
	if typeof(trigger) != TYPE_STRING:
		return "Hints entry %s trigger must be a string." % hint_id
	var trigger_text := String(trigger)
	const FIXED_TRIGGERS: PackedStringArray = ["boot", "craft_failed", "overlay", "mine_entered", "encounter_start"]
	if FIXED_TRIGGERS.has(trigger_text):
		seen_ids[hint_id] = true
		return ""
	if trigger_text.begins_with("built:"):
		var target := trigger_text.substr(6)
		if target == "*" or _is_stable_id_shape(target):
			seen_ids[hint_id] = true
			return ""
	return "Hints entry %s trigger must be boot/craft_failed/overlay/mine_entered/encounter_start or built:<id>|built:*." % hint_id


## 按触发点查询提示条目（触发订阅单一来源）：trigger 与触发点同名即命中；
## built:<id> 仅当触发点为 built 且 building_id 一致时命中，built:* 通配任意
## 建筑。坏表/无匹配返回空数组。
static func hints_for_trigger(trigger_point: String, building_id: String = "") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for hint: Dictionary in _hint_entries():
		var trigger := String(hint["trigger"])
		if trigger.begins_with("built:"):
			if trigger_point != "built":
				continue
			var target := trigger.substr(6)
			if target != "*" and target != building_id:
				continue
		elif trigger != trigger_point:
			continue
		matches.append(hint)
	return matches


## 按稳定 hint id 读文案（DLX-3 文案单一来源为提示表）；未知 id 返回空串。
static func hint_text(hint_id: String) -> String:
	for hint: Dictionary in _hint_entries():
		if String(hint["id"]) == hint_id:
			return String(hint["text_zh"])
	return ""


## 一次性提示入队（按稳定 hint id）：屏幕中下方 HintToast 逐条淡入淡出展示
##（默认停留 4s）。一次性语义按 hint id 去重：同一会话内已展示/已入队的不复播；
## 快照 flags 中 hint_<id>_seen 已置位（读档/重开）的同样跳过。首次接受时经
## 注入的 hint_seen_callback 上报 id，由集成层落账——表现层绝不直接写持久状态。
## 空 id（坏表兜底产物）直接忽略。
func show_hint_with_id(hint_id: String, text_value: String, seconds: float = DEFAULT_HINT_SECONDS) -> void:
	if hint_id.is_empty():
		return
	if _shown_hint_ids.has(hint_id):
		return
	_shown_hint_ids[hint_id] = true
	if _hint_flag_enabled(hint_id):
		return
	if hint_seen_callback.is_valid():
		hint_seen_callback.call(hint_id)
	_hint_queue.append({
		"id": hint_id,
		"text": text_value,
		"seconds": seconds,
	})
	_pump_hint_queue()


## 旧调用形态兼容入口：以文案文本哈希为一次性 id（hint_<id>_seen 的 id 与
## 表内稳定 id 无关联）。生产路径一律走 show_hint_with_id（集成层/表触发）。
func show_hint(text_value: String, seconds: float = DEFAULT_HINT_SECONDS) -> void:
	show_hint_with_id(hint_id_for(text_value), text_value, seconds)


## 文案 → 一次性 id 的退化派生（仅 show_hint 旧入口使用）：文本哈希保证任意
## 调用满足"同条不重复"；表驱动触发的稳定 id 由提示表与 show_hint_with_id
## 提供，不再经文案反查。
static func hint_id_for(text_value: String) -> String:
	return "text_%d" % text_value.hash()


## 只读快照 flags 判定一次性标记；绝不修改快照。
func _hint_flag_enabled(hint_id: String) -> bool:
	var flags: Dictionary = _current_snapshot().get("flags", {}) as Dictionary
	return bool(flags.get(HINT_FLAG_FORMAT % hint_id, false))


## 首次 O 覆盖层提示（HUD 内触发点；文案与触发条件读提示表）。暂停期间
## world 不响应 O 键，提示与实际行为保持一致——暂停时同样跳过。
func _maybe_show_overlay_hint() -> void:
	if get_tree() != null and get_tree().paused:
		return
	for hint: Dictionary in hints_for_trigger("overlay"):
		show_hint_with_id(String(hint["id"]), String(hint["text_zh"]))


## 队列泵：空闲且队列非空时展示队首；正在展示则等待完成方法回调再泵。
func _pump_hint_queue() -> void:
	if _hint_displaying or _hint_queue.is_empty():
		return
	var entry: Dictionary = _hint_queue.pop_front() as Dictionary
	_display_hint(entry)


func _display_hint(entry: Dictionary) -> void:
	_hint_displaying = true
	_hint_label.text = str(entry.get("text", ""))
	_hint_toast.visible = true
	_hint_toast.modulate.a = 0.0
	_play_hint_fade(1.0, HINT_FADE_IN_SECONDS)
	var hold_seconds := maxf(float(entry.get("seconds", DEFAULT_HINT_SECONDS)), HINT_MIN_HOLD_SECONDS)
	_ensure_hint_timer().start(hold_seconds)


## 停留超时 → 开始淡出。生产由 HintTimer.timeout 触发；测试可直接调（可控 timer）。
func _on_hint_hold_timeout() -> void:
	if not _hint_displaying:
		return
	_play_hint_fade(0.0, HINT_FADE_OUT_SECONDS)


## 淡出完成 → 隐藏并立即展示队列下一条。生产由淡出 tween.finished 触发；
## 测试可直接调（与 _on_hint_hold_timeout 配对即为一次完整完成路径）。
func _on_hint_fade_out_finished() -> void:
	if not _hint_displaying:
		return
	_hint_displaying = false
	_hint_toast.visible = false
	_hint_toast.modulate.a = 1.0
	_pump_hint_queue()


func _play_hint_fade(target_alpha: float, duration: float) -> void:
	_kill_hint_fade()
	_hint_fade_tween = create_tween()
	_hint_fade_tween.tween_property(_hint_toast, "modulate:a", target_alpha, duration)
	if target_alpha == 0.0:
		_hint_fade_tween.finished.connect(_on_hint_fade_out_finished, CONNECT_ONE_SHOT)


func _kill_hint_fade() -> void:
	if _hint_fade_tween != null and _hint_fade_tween.is_valid():
		_hint_fade_tween.kill()
	_hint_fade_tween = null


func _ensure_hint_timer() -> Timer:
	if _hint_timer == null:
		_hint_timer = Timer.new()
		_hint_timer.name = "HintTimer"
		_hint_timer.one_shot = true
		_hint_timer.timeout.connect(_on_hint_hold_timeout)
		add_child(_hint_timer)
	return _hint_timer


func _append_label(parent: Node, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()
