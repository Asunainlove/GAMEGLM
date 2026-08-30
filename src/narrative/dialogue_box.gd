class_name DialogueBox
extends CanvasLayer

## WP08 dialogue greybox UI (module-contracts.md §4). Presentation only: it
## never mutates persistent state. WP11 drives it with show_lines/show_choice
## and reacts to the finished / option_chosen signals.

signal finished
signal option_chosen(option_id: String)

const ADVANCE_ACTIONS: Array[String] = ["interact", "ui_accept"]
const DEFAULT_SPEAKER_TEXT: String = "？？？"
const CHOICE_SPEAKER_TEXT: String = "选择"
const TRUST_LOCKED_SUFFIX: String = "（信任不足）"

var _lines: Array[Dictionary] = []
var _line_index: int = 0
var _advancing: bool = false

@onready var _name_label: Label = $Panel/NameLabel
@onready var _text_label: Label = $Panel/TextLabel
@onready var _options_box: VBoxContainer = $Panel/OptionsBox


func _ready() -> void:
	visible = false


## Shows dialogue lines one by one; interact / ui_accept advances. Emits
## finished after the last line and hides the box. lines are line steps
## shaped like {"speaker": String, "text_zh": String}.
func show_lines(lines: Array[Dictionary]) -> void:
	_clear_options()
	_lines.clear()
	for line: Dictionary in lines:
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
	_clear_options()
	option_chosen.emit(option_id)


func _clear_options() -> void:
	for child: Node in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
