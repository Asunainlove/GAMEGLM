class_name Hud
extends CanvasLayer

## 星壤只读 HUD（WP11）。
##
## 表现层约束：仅通过注入的 snapshot_provider 读取状态快照进行渲染，
## 绝不调用 begin_patch/commit，绝不写入任何持久状态。
## 唯一的"写"操作是引擎级 UI 状态（节点可见性与 get_tree().paused）。
## W003-A3 首次操作引导提示（HintToast）：一次性提示经 hint_seen_callback
## 由集成层落账，本层只做队列展示与只读 flags 去重。

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

## W003-A3 首次操作引导提示文案（单一来源；game_session 触发点引用这些常量）。
const HINT_MOVE_TEXT: String = "WASD/方向键移动 · 左键采集矿脉 · 右键/F 放置建筑"
const HINT_PLACE_TEMPLATE: String = "右键/F 放置 %s · 数字键 1-6 切换建筑"
const HINT_CRAFT_TEXT: String = "材料不足 · 背包面板（I）可查看配方合成"
const HINT_OVERLAY_TEXT: String = "矿脉覆盖层 · 高亮矿脉可左键采集，便于规划路线"
const HINT_MINE_TEXT: String = "深处有强烈共鸣 · 稳压装置随时待命"
const HINT_BATTLE_TEXT: String = "回合制战斗 · 点击行动按钮指令队伍"

## W003-A3 HintToast 展示参数：缺省停留 4s，淡入/淡出各一段。
const DEFAULT_HINT_SECONDS: float = 4.0
const HINT_FADE_IN_SECONDS: float = 0.25
const HINT_FADE_OUT_SECONDS: float = 0.35
const HINT_MIN_HOLD_SECONDS: float = 0.1
## 一次性标记 flag 名（hint_<id>_seen）；game_session 的落账回调使用同一格式。
const HINT_FLAG_FORMAT: String = "hint_%s_seen"
## 模板化放置提示的归一匹配前后缀（hint id 固定为 place，与建筑名无关）。
const HINT_PLACE_PREFIX: String = "右键/F 放置 "
const HINT_PLACE_SUFFIX: String = " · 数字键 1-6 切换建筑"
## 已知文案 → 稳定 hint id 查表（hint_<id>_seen 的 id 单一来源）。
const HINT_IDS_BY_TEXT: Dictionary = {
	HINT_MOVE_TEXT: "move",
	HINT_CRAFT_TEXT: "craft",
	HINT_OVERLAY_TEXT: "overlay",
	HINT_MINE_TEXT: "mine",
	HINT_BATTLE_TEXT: "battle",
}

const _CHOICE_FLAGS: PackedStringArray = [
	"station_mode_exploit",
	"station_mode_seal",
	"station_mode_symbiosis",
	"approach_direct",
	"approach_diplomatic",
	"policy_extraction_quota",
	"policy_sanctuary",
]

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


## 当前目标短语：按里程碑链条返回首个未完成目标；无进度或全部完成时回退为探索。
## 检查类别（对应冻结契约 §7）：event_<id>_done 事件链、placed_buildings 锚块/工坊、
## encounter_<id>_won 遭遇胜利、三次选择 flags、任一 encounter_<id>_due 未决遭遇。
static func objective_for(snapshot: Dictionary) -> String:
	var flags: Dictionary = snapshot.get("flags", {})
	var placed_ids: Array[String] = _placed_building_ids(snapshot)

	# 未决遭遇优先提示为即时威胁（胜利后不再提示）。
	if _flag_enabled(flags, "encounter_leviathan_due") and not _flag_enabled(flags, "encounter_leviathan_won"):
		return "面对辉砂巨兽"
	if (
		(_flag_enabled(flags, "encounter_first_drift_due") and not _flag_enabled(flags, "encounter_first_drift_won"))
		or (_flag_enabled(flags, "encounter_husk_ambush_due") and not _flag_enabled(flags, "encounter_husk_ambush_won"))
	):
		return "应对漂移群威胁"

	if not _has_progress(flags, placed_ids):
		return "探索世界"
	if not (_flag_enabled(flags, _event_done_flag("event_first_mining")) or placed_ids.has("anchor_block")):
		return "勘探琉砂海，采集星壤尘"
	if not (placed_ids.has("anchor_block") or _flag_enabled(flags, _event_done_flag("event_first_anchor"))):
		return "放置第一座锚块"
	if not (placed_ids.has("anchor_workshop") or _flag_enabled(flags, _event_done_flag("event_workshop_guide"))):
		return "建立锚居工坊"
	if not (_flag_enabled(flags, "encounter_first_drift_won") or _flag_enabled(flags, "encounter_husk_ambush_won")):
		return "应对漂移群威胁"
	if not (
		_flag_enabled(flags, "station_mode_exploit")
		or _flag_enabled(flags, "station_mode_seal")
		or _flag_enabled(flags, "station_mode_symbiosis")
		or _flag_enabled(flags, _event_done_flag("event_station_mode"))
	):
		return "做出驻地抉择"
	var approach_done: bool = (
		_flag_enabled(flags, "approach_direct")
		or _flag_enabled(flags, "approach_diplomatic")
		or _flag_enabled(flags, _event_done_flag("event_approach"))
	)
	var policy_done: bool = (
		_flag_enabled(flags, "policy_extraction_quota")
		or _flag_enabled(flags, "policy_sanctuary")
		or _flag_enabled(flags, _event_done_flag("event_policy"))
	)
	if not (approach_done and policy_done):
		return "推进方法与政策抉择"
	if not (_flag_enabled(flags, "encounter_leviathan_won") or _flag_enabled(flags, _event_done_flag("event_leviathan_pact"))):
		return "面对辉砂巨兽"
	if not (_flag_enabled(flags, _event_done_flag("event_ending_luoxian")) or _flag_enabled(flags, _event_done_flag("event_ending_misa"))):
		return "见证余辉结局"
	return "探索世界"


## 事件完成标记名：与 EventRunner 的实际模板（event_%s_done % 事件全 id，
## 事件 id 自带 event_ 前缀，因此 flag 为双前缀形态）保持单一来源对齐。
static func _event_done_flag(event_id: String) -> String:
	return EventRunner.EVENT_DONE_FLAG_FORMAT % event_id


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


static func _has_progress(flags: Dictionary, placed_ids: Array[String]) -> bool:
	if not placed_ids.is_empty():
		return true
	for flag_id: String in flags.keys():
		if flag_id.begins_with("event_") and flag_id.ends_with("_done"):
			return true
		if flag_id.begins_with("encounter_") and flag_id.ends_with("_won"):
			return true
		if _CHOICE_FLAGS.has(flag_id):
			return true
	return false


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


# ---------------------------------------------------------------- 首次操作引导提示（W003-A3）


## 一次性提示入队：屏幕中下方 HintToast 逐条淡入淡出展示（默认停留 4s）。
## 一次性语义按稳定 hint id 去重（hint_id_for）：同一会话内已展示/已入队的不复播；
## 快照 flags 中 hint_<id>_seen 已置位（读档/重开）的同样跳过。首次接受时经注入的
## hint_seen_callback 上报 id，由集成层落账——表现层绝不直接写持久状态。
func show_hint(text_value: String, seconds: float = DEFAULT_HINT_SECONDS) -> void:
	var hint_id := hint_id_for(text_value)
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


## 文案 → 稳定 hint id（hint_<id>_seen 的 id 单一来源）。已知文案查表；模板化
## 放置提示按前后缀归一为 "place"（与 {建筑名} 无关）；未知文案退化为文本哈希，
## 保证任意调用仍满足"同条不重复"（生产触达的文案全部在查表/模板范围内）。
static func hint_id_for(text_value: String) -> String:
	if HINT_IDS_BY_TEXT.has(text_value):
		return str(HINT_IDS_BY_TEXT[text_value])
	if text_value.begins_with(HINT_PLACE_PREFIX) and text_value.ends_with(HINT_PLACE_SUFFIX):
		return "place"
	return "text_%d" % text_value.hash()


## 只读快照 flags 判定一次性标记；绝不修改快照。
func _hint_flag_enabled(hint_id: String) -> bool:
	var flags: Dictionary = _current_snapshot().get("flags", {}) as Dictionary
	return bool(flags.get(HINT_FLAG_FORMAT % hint_id, false))


## 首次 O 覆盖层提示（hud 内直接触发）。暂停期间 world 不响应 O 键，
## 提示与实际行为保持一致——暂停时同样跳过。
func _maybe_show_overlay_hint() -> void:
	if get_tree() != null and get_tree().paused:
		return
	show_hint(HINT_OVERLAY_TEXT)


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
