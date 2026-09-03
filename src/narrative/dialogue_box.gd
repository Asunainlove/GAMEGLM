class_name DialogueBox
extends CanvasLayer

## WP08 dialogue greybox UI (module-contracts.md §4). Presentation only: it
## never mutates persistent state. WP11 drives it with show_lines/show_choice
## and reacts to the finished / option_chosen signals.
## W003-A2：show_lines 按条件字段（requires_flag / requires_flag_absent）过滤
## 隐藏行；过滤只读快照，行游标与事件步游标语义均不受影响（隐藏行不占展示位）。

signal finished
signal option_chosen(option_id: String)

const ADVANCE_ACTIONS: Array[String] = ["interact", "ui_accept"]
const DEFAULT_SPEAKER_TEXT: String = "？？？"
const CHOICE_SPEAKER_TEXT: String = "选择"
const TRUST_LOCKED_SUFFIX: String = "（信任不足）"

## W003-A2 条件行过滤的状态来源（与 Hud.snapshot_provider 同款注入模式）：
## 未注入时回退 GameState autoload（生产路径 GameSession store=null → 快照即
## autoload；测试可注入独立实例的 snapshot）。只读快照，绝不写入持久状态。
var snapshot_provider: Callable = Callable()

## W003-A10：可选 AudioDirector（GameSession 注入）。
var audio_director: Node = null

var _lines: Array[Dictionary] = []
var _line_index: int = 0
var _advancing: bool = false

@onready var _name_label: Label = $Panel/NameLabel
@onready var _text_label: Label = $Panel/TextLabel
@onready var _options_box: VBoxContainer = $Panel/OptionsBox



func _play_sfx(sfx_id: String, volume_offset_db: float = 0.0) -> void:
	if audio_director == null or not audio_director.has_method("play_sfx"):
		return
	if audio_director.get_method_argument_count("play_sfx") >= 2:
		audio_director.call("play_sfx", sfx_id, volume_offset_db)
	else:
		audio_director.call("play_sfx", sfx_id)


func _ready() -> void:
	visible = false


## Shows dialogue lines one by one; interact / ui_accept advances. Emits
## finished after the last line and hides the box. lines are line steps
## shaped like {"speaker": String, "text_zh": String}，可选 requires_flag /
## requires_flag_absent（W003-A2：不满足条件的行在本层被跳过，不占展示位）。
func show_lines(lines: Array[Dictionary]) -> void:
	_clear_options()
	_lines.clear()
	var state: Dictionary = _filter_state()
	for line: Dictionary in lines:
		if not EventRunner.line_is_visible(line, state):
			continue
		_lines.append(line.duplicate(true))
	_line_index = 0
	if _lines.is_empty():
		_advancing = false
		visible = false
		finished.emit()
		return
	_advancing = true
	visible = true
	_show_current_line()


## Shows a choice step: the prompt in the text area plus one Button per option
## in OptionsBox. Pressing a button emits option_chosen(option.id) and clears
## the buttons. Options whose id is listed in disabled_option_ids render
## disabled with the（信任不足）suffix (W002-GAP1: the caller pre-checks trust
## so an insufficient option can never clear the choices and stall the event).
## The default empty list keeps legacy single-argument calls compatible.
func show_choice(step: Dictionary, disabled_option_ids: Array[String] = []) -> void:
	_advancing = false
	visible = true
	_name_label.text = String(step.get("speaker", CHOICE_SPEAKER_TEXT))
	_text_label.text = String(step.get("prompt_zh", ""))
	_clear_options()
	var options: Array = step.get("options", [])
	for option: Dictionary in options:
		var option_id := String(option.get("id", ""))
		var button := Button.new()
		button.text = String(option.get("text_zh", ""))
		if disabled_option_ids.has(option_id):
			button.disabled = true
			button.text += TRUST_LOCKED_SUFFIX
		button.pressed.connect(_on_option_pressed.bind(option_id))
		_options_box.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if not _advancing:
		return
	for action_name: String in ADVANCE_ACTIONS:
		if event.is_action_pressed(action_name):
			_advance()
			break


func _advance() -> void:
	if not _advancing:
		return
	_play_sfx("sfx_dialogue_page", -6.0)
	_line_index += 1
	if _line_index >= _lines.size():
		_advancing = false
		visible = false
		finished.emit()
		return
	_show_current_line()


func _show_current_line() -> void:
	var line: Dictionary = _lines[_line_index]
	_name_label.text = String(line.get("speaker", DEFAULT_SPEAKER_TEXT))
	_text_label.text = String(line.get("text_zh", ""))


func _on_option_pressed(option_id: String) -> void:
	_play_sfx("sfx_dialogue_choice")
	_clear_options()
	option_chosen.emit(option_id)


func _clear_options() -> void:
	for child: Node in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()


## W003-A2 条件行过滤的快照读取：注入优先，缺省回退 GameState autoload
##（与 Hud 同款语义：无效注入告警并回退）。返回完整快照字典，缺失时为空字典。
func _filter_state() -> Dictionary:
	if not snapshot_provider.is_valid():
		if not snapshot_provider.is_null():
			push_warning("DialogueBox.snapshot_provider 无效，回退到 GameState.snapshot。")
		snapshot_provider = GameState.snapshot
	var snapshot: Variant = snapshot_provider.call()
	if typeof(snapshot) == TYPE_DICTIONARY:
		return snapshot
	return {}
