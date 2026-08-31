extends GutTest

## DLX-3 提示外置测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
##
## 任务书（DL5）：A3 的 6 条提示文案与触发条件迁入 data/progression/hints.json
##（{id, text_zh, trigger}，trigger ∈ boot / built:<building_id> / craft_failed /
## overlay / mine_entered / encounter_start），hud.gd / game_session.gd 按表订阅
##（触发点保留在集成层，触发条件与文案读表）；落账机制 hint_<id>_seen + 回调
## 不变。文案期望值冻结自迁移前 Hud 常量（逐字节）。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"
const DEFAULT_HINTS_PATH: String = "res://data/progression/hints.json"

## 冻结自迁移前 Hud 提示常量的逐字节文案（迁移快照）。
const FROZEN_HINT_TEXTS: Dictionary = {
	"move": "WASD/方向键移动 · 左键采集矿脉 · 右键/F 放置建筑",
	"place": "右键/F 放置 {building} · 数字键 1-{hotkey_max} 切换建筑",
	"craft": "材料不足 · 背包面板（I）可查看配方合成",
	"overlay": "矿脉覆盖层 · 高亮矿脉可左键采集，便于规划路线",
	"mine": "深处有强烈共鸣 · 稳压装置随时待命",
	"battle": "回合制战斗 · 点击行动按钮指令队伍",
}

var _hud: Hud = null
var _hint_spy: HintSeenSpy = null
var _fake: FakeSnapshotProvider = null
var _temp_paths: Array[String] = []


class HintSeenSpy:
	var ids: Array[String] = []

	func on_hint_seen(hint_id: String) -> void:
		ids.append(hint_id)


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	if _hud != null and is_instance_valid(_hud):
		_hud.free()
	_hud = null
	_hint_spy = null
	# 恢复默认提示表，防止临时表状态泄漏到其他测试文件。
	Hud.load_hints_from(DEFAULT_HINTS_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


func _make_hint_spy_hud() -> Hud:
	_hint_spy = HintSeenSpy.new()
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {"revision": 1, "inventory": {}, "flags": {}, "placed_buildings": []}
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must load.")
	if scene == null:
		return null
	_hud = scene.instantiate() as Hud
	_hud.snapshot_provider = _fake.get_snapshot
	hud_seen_callback_setup(_hud)
	add_child_autofree(_hud)
	return _hud


func hud_seen_callback_setup(hud: Hud) -> void:
	hud.hint_seen_callback = _hint_spy.on_hint_seen


# ---------------------------------------------------------------- 表装载


func test_default_hints_table_loads_with_frozen_texts() -> void:
	var loaded: AppResult = Hud.load_hints_from(DEFAULT_HINTS_PATH)
	assert_true(loaded.is_ok, "默认提示表必须可加载：%s" % loaded.message)
	var entries: Array[Dictionary] = Hud._hint_entries()
	assert_eq(entries.size(), 6, "迁移提示表必须包含 6 条提示。")
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(String(entry["id"]))
		assert_eq(
			String(entry["text_zh"]), String(FROZEN_HINT_TEXTS[String(entry["id"])]),
			"提示 %s 文案必须与迁移前逐字节一致。" % String(entry["id"])
		)
	assert_eq(
		ids, ["move", "place", "craft", "overlay", "mine", "battle"] as Array[String],
		"迁移提示表的 id 集合必须与 A3 既有 6 条一致。"
	)


func test_hint_text_reads_table() -> void:
	assert_true(Hud.load_hints_from(DEFAULT_HINTS_PATH).is_ok, "前置：默认提示表可加载。")
	for hint_id: String in FROZEN_HINT_TEXTS.keys():
		assert_eq(Hud.hint_text(hint_id), String(FROZEN_HINT_TEXTS[hint_id]))
	assert_eq(Hud.hint_text("definitely_absent"), "", "未知 hint id 必须返回空串。")


# ---------------------------------------------------------------- 触发表匹配


func test_hints_for_trigger_matches_table_triggers() -> void:
	assert_true(Hud.load_hints_from(DEFAULT_HINTS_PATH).is_ok, "前置：默认提示表可加载。")
	assert_eq(_ids_of(Hud.hints_for_trigger("boot")), ["move"] as Array[String])
	assert_eq(_ids_of(Hud.hints_for_trigger("craft_failed")), ["craft"] as Array[String])
	assert_eq(_ids_of(Hud.hints_for_trigger("overlay")), ["overlay"] as Array[String])
	assert_eq(_ids_of(Hud.hints_for_trigger("mine_entered")), ["mine"] as Array[String])
	assert_eq(_ids_of(Hud.hints_for_trigger("encounter_start")), ["battle"] as Array[String])
	# built:* 通配：任意建筑进入放置流都命中 place 提示。
	assert_eq(_ids_of(Hud.hints_for_trigger("built", "anchor_block")), ["place"] as Array[String])
	assert_eq(_ids_of(Hud.hints_for_trigger("built", "resonance_loom")), ["place"] as Array[String])
	# 未知触发点恒为空。
	assert_eq(_ids_of(Hud.hints_for_trigger("unknown_point")), [] as Array[String])


func _ids_of(entries: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(String(entry["id"]))
	return ids


# ---------------------------------------------------------------- 失败安全


func test_missing_hints_file_fails_safe_and_pushes_error() -> void:
	var result: AppResult = Hud.load_hints_from(
		"res://data/progression/definitely_missing_hints.json")
	assert_false(result.is_ok, "缺失提示表必须加载失败。")
	assert_eq(result.code, "missing_hints_file")
	assert_push_error("Hud: hints table rejected")
	assert_eq(Hud.hint_text("move"), "", "坏表下 hint_text 必须失败安全返回空串。")
	assert_eq(Hud.hints_for_trigger("boot").size(), 0, "坏表下触发查询必须为空。")


func test_malformed_hints_files_are_rejected() -> void:
	var bad_cases: Array = [
		["syntax_error", "{\"id\": not json"],
		["not_an_array", "{\"id\": \"move\"}"],
		["entry_not_object", "[\"move\"]"],
		["missing_id", "[{\"text_zh\": \"t\", \"trigger\": \"boot\"}]"],
		["non_stable_id", "[{\"id\": \"Move\", \"text_zh\": \"t\", \"trigger\": \"boot\"}]"],
		["duplicate_id", "[{\"id\": \"move\", \"text_zh\": \"t\", \"trigger\": \"boot\"}, {\"id\": \"move\", \"text_zh\": \"t2\", \"trigger\": \"boot\"}]"],
		["missing_text", "[{\"id\": \"move\", \"trigger\": \"boot\"}]"],
		["empty_text", "[{\"id\": \"move\", \"text_zh\": \"\", \"trigger\": \"boot\"}]"],
		["missing_trigger", "[{\"id\": \"move\", \"text_zh\": \"t\"}]"],
		["unknown_trigger", "[{\"id\": \"move\", \"text_zh\": \"t\", \"trigger\": \"fly_me_to_the_moon\"}]"],
		["built_trigger_bad_id", "[{\"id\": \"move\", \"text_zh\": \"t\", \"trigger\": \"built:Anchor Block\"}]"],
		["built_trigger_empty_id", "[{\"id\": \"move\", \"text_zh\": \"t\", \"trigger\": \"built:\"}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_hints(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = Hud.load_hints_from(path)
		assert_false(result.is_ok, "坏提示表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Hud: hints table rejected")


func _write_temp_hints(case_name: String, text: String) -> String:
	var path: String = "user://dlx3_hints_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时提示表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


# ---------------------------------------------------------------- 纯数据扩展


func test_pure_data_hint_extension_needs_no_code_change() -> void:
	assert_true(Hud.load_hints_from(DEFAULT_HINTS_PATH).is_ok, "前置：默认提示表可加载。")
	# 纯数据扩展证明：临时提示表追加一条 boot 触发提示 → 触发查询与文案读表
	# 立即可见——新增提示 = 改 JSON，不改 hud/game_session。
	var extended: Array = [
		{"id": "move", "text_zh": String(FROZEN_HINT_TEXTS["move"]), "trigger": "boot"},
		{"id": "dlx3_whisper", "text_zh": "灰烬在风里低语", "trigger": "boot"},
	]
	var path := _write_temp_hints("extended", JSON.stringify(extended, "  "))
	assert_true(Hud.load_hints_from(path).is_ok, "扩展提示表必须可加载。")
	assert_eq(Hud.hint_text("dlx3_whisper"), "灰烬在风里低语")
	var boot_ids := _ids_of(Hud.hints_for_trigger("boot"))
	assert_true(boot_ids.has("dlx3_whisper"), "新增提示必须按 JSON 声明进入触发订阅。")
	assert_eq(boot_ids.size(), 2, "同一触发点可承载多条提示。")


# ---------------------------------------------------------------- show_hint_with_id


func _complete_current_hint(hud: Hud) -> void:
	hud._on_hint_hold_timeout()
	hud._on_hint_fade_out_finished()


func test_show_hint_with_id_displays_reports_and_dedups() -> void:
	var hud: Hud = _make_hint_spy_hud()
	var toast: Control = hud.get_node("HintToast") as Control
	var label: Label = hud.get_node("HintToast/HintLabel") as Label

	hud.show_hint_with_id("move", String(FROZEN_HINT_TEXTS["move"]))
	assert_true(toast.visible, "show_hint_with_id 必须显示提示条。")
	assert_eq(label.text, String(FROZEN_HINT_TEXTS["move"]))

	hud.show_hint_with_id("move", String(FROZEN_HINT_TEXTS["move"]))
	assert_eq(_hint_spy.ids, ["move"] as Array[String], "同一 hint id 只上报一次落账。")

	_complete_current_hint(hud)
	hud.show_hint_with_id("move", String(FROZEN_HINT_TEXTS["move"]))
	assert_false(toast.visible, "会话内一次性：同 id 不得复播。")


func test_show_hint_with_id_skips_when_flag_already_seen() -> void:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {"revision": 1, "inventory": {}, "flags": {"hint_move_seen": true}, "placed_buildings": []}
	_hint_spy = HintSeenSpy.new()
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	_hud = scene.instantiate() as Hud
	_hud.snapshot_provider = _fake.get_snapshot
	_hud.hint_seen_callback = _hint_spy.on_hint_seen
	add_child_autofree(_hud)

	_hud.show_hint_with_id("move", String(FROZEN_HINT_TEXTS["move"]))
	assert_false(
		(_hud.get_node("HintToast") as Control).visible,
		"快照 flags 已置 hint_<id>_seen 时不得再次提示。"
	)
	assert_true(_hint_spy.ids.is_empty(), "已看过的提示不得触发落账回调。")


func test_show_hint_with_id_ignores_empty_id() -> void:
	var hud: Hud = _make_hint_spy_hud()
	hud.show_hint_with_id("", "任意文案")
	assert_false(
		(hud.get_node("HintToast") as Control).visible,
		"空 hint id（坏表兜底产物）必须被忽略。"
	)
	assert_true(_hint_spy.ids.is_empty())


func test_overlay_trigger_reads_hints_table() -> void:
	assert_true(Hud.load_hints_from(DEFAULT_HINTS_PATH).is_ok, "前置：默认提示表可加载。")
	var hud: Hud = _make_hint_spy_hud()
	var event := InputEventAction.new()
	event.action = "toggle_overlay"
	event.pressed = true
	hud._unhandled_input(event)
	assert_true((hud.get_node("HintToast") as Control).visible, "首次 O 覆盖层必须弹提示。")
	assert_eq(
		(hud.get_node("HintToast/HintLabel") as Label).text,
		String(FROZEN_HINT_TEXTS["overlay"]),
		"覆盖层提示文案必须来自提示表。"
	)
	assert_eq(_hint_spy.ids, ["overlay"] as Array[String], "落账 id 必须来自提示表条目。")
