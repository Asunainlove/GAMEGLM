class_name Hud
extends CanvasLayer

## 星壤只读 HUD（WP11）。
##
## 表现层约束：仅通过注入的 snapshot_provider 读取状态快照进行渲染，
## 绝不调用 begin_patch/commit，绝不写入任何持久状态。
## 唯一的"写"操作是引擎级 UI 状态（节点可见性与 get_tree().paused）。

signal menu_resumed
signal save_requested
signal restart_requested

const POLL_INTERVAL_SECONDS: float = 0.25
const MAX_BAR_SLOTS: int = 8
const DEFAULT_NOTICE_SECONDS: float = 1.5

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

@onready var _inventory_bar: HBoxContainer = $InventoryBar
@onready var _objective_label: Label = $ObjectiveLabel
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _menu_panel: PanelContainer = $MenuPanel
@onready var _inventory_items_box: VBoxContainer = $InventoryPanel/Content/ItemsBox
@onready var _menu_help_panel: PanelContainer = $MenuPanel/Content/HelpPanel
@onready var _resume_button: Button = $MenuPanel/Content/ResumeButton
@onready var _save_button: Button = $MenuPanel/Content/SaveButton
@onready var _help_button: Button = $MenuPanel/Content/HelpButton
@onready var _restart_button: Button = $MenuPanel/Content/RestartButton

var _cached_revision: int = -1
var _poll_timer: Timer
var _notice_text: String = ""
var _notice_timer: Timer = null


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


func _append_label(parent: Node, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	parent.add_child(label)


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()
