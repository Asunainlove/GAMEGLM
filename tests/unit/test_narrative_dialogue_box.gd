extends GutTest

## WP08 DialogueBox scene contract tests (module-contracts.md §4).
## The scene is loaded at runtime (never preloaded) so that a missing scene
## surfaces as a failing assertion instead of a silent script skip.

const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"


func _load_box() -> Node:
	var scene: PackedScene = load(DIALOGUE_SCENE_PATH) as PackedScene
	assert_not_null(scene, "DialogueBox scene must exist and load at %s." % DIALOGUE_SCENE_PATH)
	if scene == null:
		return null
	var box: Node = scene.instantiate()
	add_child_autofree(box)
	return box


func _one_line() -> Array[Dictionary]:
	var lines: Array[Dictionary] = [{"speaker": "洛弦", "text_zh": "降落舱的铰链发出轻响。"}]
	return lines


func _choice_step() -> Dictionary:
	return {
		"type": "choice",
		"choice_id": "test_relay_core",
		"prompt_zh": "中继器的能量核心开始过载，如何处置？",
		"options": [
			{"id": "test_seal_core", "text_zh": "封存核心，保全矿脉余辉。"},
			{"id": "test_tap_core", "text_zh": "抽取能量维持营地运转。"},
		],
	}


func test_dialogue_box_scene_matches_canvas_layer_contract() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	assert_eq(box.name, "DialogueBox", "Root node must be named DialogueBox.")
	assert_true(box is CanvasLayer, "DialogueBox root must be a CanvasLayer.")
	assert_false(box.visible, "DialogueBox must start hidden.")
	assert_true(box.get_node_or_null("Panel") is Control, "Panel must be a Control under the root.")
	assert_true(box.get_node_or_null("Panel/NameLabel") is Label, "Panel/NameLabel must be a Label.")
	assert_true(box.get_node_or_null("Panel/TextLabel") is Label, "Panel/TextLabel must be a Label.")
	assert_true(
		box.get_node_or_null("Panel/OptionsBox") is VBoxContainer,
		"Panel/OptionsBox must be a VBoxContainer."
	)


func test_show_lines_displays_speaker_and_text_then_emits_finished() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	watch_signals(box)
	var lines: Array[Dictionary] = [
		{"speaker": "洛弦", "text_zh": "降落舱的铰链发出轻响。"},
		{"speaker": "弥砂", "text_zh": "信号源在矿脉深处。"},
	]
	box.call("show_lines", lines)

	assert_true(box.visible, "DialogueBox becomes visible while lines are shown.")
	var name_label: Label = box.get_node("Panel/NameLabel") as Label
	var text_label: Label = box.get_node("Panel/TextLabel") as Label
	assert_eq(name_label.text, "洛弦", "NameLabel shows the current line speaker.")
	assert_eq(text_label.text, "降落舱的铰链发出轻响。", "TextLabel shows the current line text.")

	box.call("_advance")
	assert_eq(name_label.text, "弥砂")
	assert_eq(text_label.text, "信号源在矿脉深处。")
	assert_signal_not_emitted(box, "finished", "finished must wait for the last line.")

	box.call("_advance")
	assert_signal_emitted(box, "finished", "finished emits after the last line.")
	assert_false(box.visible, "DialogueBox hides after the last line.")


func test_interact_input_advances_lines_toward_finished() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	watch_signals(box)
	box.call("show_lines", _one_line())

	var press: InputEventAction = InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emitted(
		box,
		"finished",
		"A single interact press must finish a one-line dialogue."
	)
	assert_false(box.visible, "DialogueBox hides once finished.")


func test_show_choice_builds_buttons_and_emits_option_chosen() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	watch_signals(box)
	box.call("show_choice", _choice_step())

	assert_true(box.visible, "DialogueBox becomes visible for a choice step.")
	var options_box: VBoxContainer = box.get_node("Panel/OptionsBox") as VBoxContainer
	assert_eq(options_box.get_child_count(), 2, "One button per option.")
	var first_button: Button = options_box.get_child(0) as Button
	var second_button: Button = options_box.get_child(1) as Button
	assert_not_null(first_button, "Options must be rendered as Buttons.")
	assert_not_null(second_button, "Options must be rendered as Buttons.")
	if first_button != null and second_button != null:
		assert_eq(first_button.text, "封存核心，保全矿脉余辉。", "Button text uses option text_zh.")
		assert_eq(second_button.text, "抽取能量维持营地运转。", "Button text uses option text_zh.")

	assert_signal_not_emitted(box, "option_chosen", "No option signal before a press.")
	second_button.pressed.emit()
	assert_signal_emitted_with_parameters(
		box,
		"option_chosen",
		["test_tap_core"],
		0
	)
	assert_eq(options_box.get_child_count(), 0, "Options clear after a choice is made.")


func test_show_lines_clears_leftover_option_buttons() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	box.call("show_choice", _choice_step())
	box.call("show_lines", _one_line())

	var options_box: VBoxContainer = box.get_node("Panel/OptionsBox") as VBoxContainer
	assert_eq(
		options_box.get_child_count(),
		0,
		"Switching from a choice to lines must clear stale option buttons."
	)
	var name_label: Label = box.get_node("Panel/NameLabel") as Label
	var text_label: Label = box.get_node("Panel/TextLabel") as Label
	assert_eq(name_label.text, "洛弦", "Line display works after a choice step.")
	assert_eq(text_label.text, "降落舱的铰链发出轻响。")


func test_show_choice_disables_listed_options_with_trust_suffix() -> void:
	# W002-GAP1 软锁死修复：禁用表中的选项按钮 disabled 且文本带（信任不足）后缀；
	# 默认参数（无禁用表）保持旧调用兼容。
	var box: Node = _load_box()
	if box == null:
		return
	box.call("show_choice", _choice_step(), ["test_tap_core"] as Array[String])

	assert_true(box.visible, "DialogueBox stays visible for a disabled-choice display.")
	var options_box: VBoxContainer = box.get_node("Panel/OptionsBox") as VBoxContainer
	assert_eq(options_box.get_child_count(), 2, "Disabled options still render as buttons.")
	var first_button: Button = options_box.get_child(0) as Button
	var second_button: Button = options_box.get_child(1) as Button
	if first_button != null and second_button != null:
		assert_false(first_button.disabled, "Options outside the disabled list stay enabled.")
		assert_eq(first_button.text, "封存核心，保全矿脉余辉。", "Enabled option text has no suffix.")
		assert_true(second_button.disabled, "Listed options must render disabled.")
		assert_eq(
			second_button.text, "抽取能量维持营地运转。（信任不足）",
			"Disabled options must carry the trust-locked suffix."
		)


func test_show_choice_without_disabled_list_keeps_all_options_enabled() -> void:
	var box: Node = _load_box()
	if box == null:
		return
	box.call("show_choice", _choice_step())

	var options_box: VBoxContainer = box.get_node("Panel/OptionsBox") as VBoxContainer
	for button_index: int in options_box.get_child_count():
		var button: Button = options_box.get_child(button_index) as Button
		assert_false(
			button.disabled,
			"The legacy single-argument call must leave every option enabled."
		)
