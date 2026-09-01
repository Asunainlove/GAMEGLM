extends GutTest

## DLX-4 任务 1：HUD 关系面板（RelationsPanel）TDD 测试（先于实现编写，RED → GREEN）。
##
## PM-P0a 缺陷：trust 40（政策门）/70（共生门）是全局最重要数值，HUD 却无任何
## 关系展示——玩家不理解政策选项为何禁用、共生结局为何回落。本文件约束：
## - RelationsPanel 渲染 洛弦/弥砂 的 trust/affection 只读数值与微型进度条；
## - 政策门/共生门提示行出现与消失条件；
## - 门阈值数值必须从数据文件读取（event_policy.json 的 requires_trust 与
##   endings.json 的 trust 门控），不得在实现里写死 40/70；
## - 表现层只读 snapshot，绝不修改注入的快照。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"
const THEME_PATH: String = "res://themes/starsoil_theme.tres"
## G7P-2 S3 合法更新：政策门提示改扫描 data/events/*.json 全目录（多文件化），
## 生产门集不变（仅 event_policy.json 携带 requires_trust 对象选项）。
const EVENTS_DIR: String = "res://data/events"
const ENDINGS_PATH: String = "res://data/content/endings.json"

var _fake: FakeSnapshotProvider = null
var _hud: Hud = null
var _temp_paths: Array[String] = []
var _temp_dirs: Array[String] = []


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	_hud = null
	_fake = null
	# 恢复默认门提示数据，防止临时表状态泄漏到其他测试文件。
	Hud.load_relation_gates_from(EVENTS_DIR, ENDINGS_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()
	for temp_dir: String in _temp_dirs:
		_remove_dir_recursive(temp_dir)
	_temp_dirs.clear()


func _make_hud(payload: Dictionary) -> Hud:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = payload
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must exist and load.")
	if scene == null:
		return null
	_hud = scene.instantiate() as Hud
	assert_not_null(_hud, "ui_hud.tscn must instantiate as Hud.")
	if _hud == null:
		return null
	_hud.snapshot_provider = _fake.get_snapshot
	add_child_autofree(_hud)
	return _hud


func _payload(relationships: Dictionary, flags: Dictionary) -> Dictionary:
	return {
		"revision": 1,
		"inventory": {},
		"flags": flags,
		"placed_buildings": [],
		"relationships": relationships,
	}


func _label_texts(panel: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in panel.get_children():
		if child is Label:
			texts.append((child as Label).text)
		for nested_text: String in _label_texts(child):
			texts.append(nested_text)
	return texts


func _progress_bars(panel: Node) -> Array[ProgressBar]:
	var bars: Array[ProgressBar] = []
	for child: Node in panel.get_children():
		if child is ProgressBar:
			bars.append(child)
		bars.append_array(_progress_bars(child))
	return bars


func _lines_containing(panel: Node, needle: String) -> Array[String]:
	var matches: Array[String] = []
	for text_value: String in _label_texts(panel):
		if text_value.contains(needle):
			matches.append(text_value)
	return matches


func _write_temp_json(case_name: String, text: String) -> String:
	var path: String = "user://dlx4_relations_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时数据文件必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


## G7P-2 S3：门数据注入改为"临时事件目录 + 事件文件"形态（多文件扫描）。
func _write_temp_events_dir(file_name: String, text: String) -> String:
	var dir: String = "user://dlx4_gate_events_%d" % Time.get_ticks_usec()
	var make_error: Error = DirAccess.make_dir_recursive_absolute(dir)
	assert_eq(make_error, OK, "临时事件目录必须可创建：%s" % dir)
	_temp_dirs.append(dir)
	var path: String = dir.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时事件文件必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


func _remove_dir_recursive(tree: String) -> void:
	if not DirAccess.dir_exists_absolute(tree):
		return
	var dir := DirAccess.open(tree)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_remove_dir_recursive(tree + "/%s" % entry)
		else:
			DirAccess.remove_absolute(tree + "/%s" % entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(tree)


# ---------------------------------------------------------------- 场景契约


func test_scene_has_relations_panel_contract() -> void:
	var hud: Hud = _make_hud(_payload({}, {}))
	assert_not_null(hud.get_node_or_null("RelationsPanel"), "ui_hud.tscn 必须提供 RelationsPanel 节点。")
	var panel: Control = hud.get_node("RelationsPanel") as Control
	assert_true(panel is HBoxContainer, "RelationsPanel 必须是 HBoxContainer。")
	assert_true(panel.visible, "RelationsPanel 初始必须可见（P0 信任进度常驻展示）。")
	var theme: Theme = load(THEME_PATH) as Theme
	assert_eq(panel.theme, theme, "RelationsPanel 必须携带 themes/starsoil_theme.tres。")


# ---------------------------------------------------------------- 关系数值渲染


func test_relation_rows_render_trust_and_affection_with_progress_bars() -> void:
	var hud: Hud = _make_hud(_payload(
		{
			"luoxian": {"trust": 55, "affection": 3, "ideology": 0},
			"misa": {"trust": 30, "affection": 0},
		},
		{}
	))
	var panel: Control = hud.get_node("RelationsPanel")
	var texts: Array[String] = _label_texts(panel)
	assert_true(texts.has("洛弦 信任 55/100 ♥3"), "洛弦行必须渲染 trust/affection 数值，实际：%s" % [texts])
	assert_true(texts.has("弥砂 信任 30/100 ♥0"), "弥砂行必须渲染 trust/affection 数值，实际：%s" % [texts])
	var bars: Array[ProgressBar] = _progress_bars(panel)
	assert_eq(bars.size(), 2, "两个角色各必须有一条微型进度条。")
	if bars.size() == 2:
		assert_eq(bars[0].value, 55.0, "洛弦进度条必须反映 trust 值。")
		assert_eq(bars[1].value, 30.0, "弥砂进度条必须反映 trust 值。")
		for bar: ProgressBar in bars:
			assert_eq(bar.max_value, 100.0, "进度条上限必须为 100。")
			assert_false(bar.show_percentage, "微型进度条不得显示百分比文本。")


func test_relation_rows_default_to_zero_when_relationships_missing() -> void:
	var hud: Hud = _make_hud(_payload({}, {}))
	var texts: Array[String] = _label_texts(hud.get_node("RelationsPanel"))
	assert_true(texts.has("洛弦 信任 0/100 ♥0"), "缺失关系记录时洛弦行必须按 0 渲染。")
	assert_true(texts.has("弥砂 信任 0/100 ♥0"), "缺失关系记录时弥砂行必须按 0 渲染。")


# ---------------------------------------------------------------- 政策门提示（数据驱动）


func test_sanctuary_gate_hint_shows_below_threshold_with_data_number() -> void:
	var hud: Hud = _make_hud(_payload({"luoxian": {"trust": 10, "affection": 0}}, {}))
	var lines: Array[String] = _lines_containing(hud.get_node("RelationsPanel"), "尚未赢得洛弦的信任")
	assert_eq(lines.size(), 1, "trust 低于政策门时必须出现一条政策门提示。")
	if lines.size() == 1:
		assert_true(
			lines[0].contains("40"),
			"提示行数值必须来自数据文件（event_policy.json requires_trust），实际：%s" % lines[0]
		)


func test_sanctuary_gate_hint_disappears_when_policy_flag_set() -> void:
	var hud: Hud = _make_hud(_payload(
		{"luoxian": {"trust": 10, "affection": 0}},
		{"policy_sanctuary": true}
	))
	assert_true(
		_lines_containing(hud.get_node("RelationsPanel"), "尚未赢得洛弦的信任").is_empty(),
		"政策 flag 置位后政策门提示必须消失。"
	)


func test_sanctuary_gate_hint_boundary_at_threshold() -> void:
	var at_gate: Hud = _make_hud(_payload({"luoxian": {"trust": 40, "affection": 0}}, {}))
	assert_true(
		_lines_containing(at_gate.get_node("RelationsPanel"), "尚未赢得洛弦的信任").is_empty(),
		"trust 恰好达到门阈值时提示必须消失。"
	)
	at_gate.free()
	_hud = null
	var below_gate: Hud = _make_hud(_payload({"luoxian": {"trust": 39, "affection": 0}}, {}))
	assert_eq(
		_lines_containing(below_gate.get_node("RelationsPanel"), "尚未赢得洛弦的信任").size(), 1,
		"trust 恰好低于门阈值时提示必须存在。"
	)


# ---------------------------------------------------------------- 共生门提示（数据驱动）


func test_symbiosis_gate_hint_shows_after_mode_choice_below_threshold() -> void:
	var hud: Hud = _make_hud(_payload(
		{"luoxian": {"trust": 58, "affection": 0}},
		{"station_mode_symbiosis": true}
	))
	var lines: Array[String] = _lines_containing(hud.get_node("RelationsPanel"), "距离共生还需")
	assert_eq(lines.size(), 1, "共生路线选择后 trust 低于结局门必须出现共生门提示。")
	if lines.size() == 1:
		assert_true(
			lines[0].contains("12"),
			"共生门提示必须给出数据推导的剩余点数（70 - 58 = 12），实际：%s" % lines[0]
		)


func test_symbiosis_gate_hint_disappears_at_threshold_and_without_flag() -> void:
	var at_gate: Hud = _make_hud(_payload(
		{"luoxian": {"trust": 70, "affection": 0}},
		{"station_mode_symbiosis": true}
	))
	assert_true(
		_lines_containing(at_gate.get_node("RelationsPanel"), "距离共生还需").is_empty(),
		"trust 达到共生门后提示必须消失。"
	)
	at_gate.free()
	_hud = null
	var no_flag: Hud = _make_hud(_payload({"luoxian": {"trust": 58, "affection": 0}}, {}))
	assert_true(
		_lines_containing(no_flag.get_node("RelationsPanel"), "距离共生还需").is_empty(),
		"未选择共生路线时不得出现共生门提示。"
	)


# ---------------------------------------------------------------- 门数据装载（FileAccess 直读数据文件）


func test_gate_table_loads_thresholds_from_production_data_files() -> void:
	var result: AppResult = Hud.load_relation_gates_from(EVENTS_DIR, ENDINGS_PATH)
	assert_true(result.is_ok, "生产数据文件必须能装载门提示表：%s" % result.message)
	var entries: Array[Dictionary] = Hud._gate_entries()
	assert_eq(entries.size(), 2, "生产数据必须派生出政策门 + 共生门两条。")
	var by_flag: Dictionary = {}
	for entry: Dictionary in entries:
		by_flag[String(entry["flag_id"])] = entry
	assert_true(by_flag.has("policy_sanctuary"), "政策门必须挂 policy_sanctuary flag。")
	assert_true(by_flag.has("station_mode_symbiosis"), "共生门必须挂 station_mode_symbiosis flag。")
	var sanctuary: Dictionary = by_flag.get("policy_sanctuary", {}) as Dictionary
	assert_eq(int(sanctuary.get("threshold", -1)), 40, "政策门阈值必须读自 event_policy.json 的 requires_trust。")
	assert_eq(String(sanctuary.get("char_id", "")), "luoxian", "政策门必须按 requires_trust 的 char_id 归属洛弦。")
	assert_eq(String(sanctuary.get("dim", "")), "trust", "政策门维度必须读自 requires_trust.dim。")
	assert_false(bool(sanctuary.get("show_when_set", true)), "政策门是选项锁：flag 未置位时提示。")
	var symbiosis: Dictionary = by_flag.get("station_mode_symbiosis", {}) as Dictionary
	assert_eq(int(symbiosis.get("threshold", -1)), 70, "共生门阈值必须读自 endings.json 的 trust 门控。")
	assert_true(bool(symbiosis.get("show_when_set", false)), "共生门是结局门：flag 置位后提示。")


func test_gate_data_is_injectable_and_value_driven() -> void:
	var policy_event: Dictionary = {
		"id": "event_policy_test",
		"kind": "mixed",
		"steps": [
			{"type": "line", "speaker": "测试者", "text_zh": "占位。"},
			{"type": "choice", "choice_id": "policy_test", "prompt_zh": "选择？", "options": [
				{
					"id": "policy_test_free",
					"text_zh": "自由案：不受信任约束。",
					"set_flag": "policy_test_free",
				},
				{
					"id": "policy_test_guarded",
					"text_zh": "守护案：留出回声的余地。",
					"set_flag": "policy_test_guarded",
					"requires_trust": {"char_id": "misa", "dim": "trust", "value": 25},
				},
			]},
		],
	}
	var endings: Array = [
		{
			"id": "ending_test_dawn",
			"order": 0,
			"all_of_flags": ["station_mode_symbiosis"],
			"trust": {"char_id": "misa", "dim": "trust", "threshold": 65},
			"extra_flag": "echo_chamber_active",
		},
	]
	var policy_path := _write_temp_events_dir("event_policy_test.json", JSON.stringify(policy_event, "  "))
	var endings_path := _write_temp_json("endings", JSON.stringify(endings, "  "))
	assert_true(Hud.load_relation_gates_from(policy_path.get_base_dir(), endings_path).is_ok, "临时门数据必须可装载。")

	var locked: Hud = _make_hud(_payload({"misa": {"trust": 10, "affection": 0}}, {}))
	var locked_lines: Array[String] = _lines_containing(locked.get_node("RelationsPanel"), "尚未赢得弥砂的信任")
	assert_eq(locked_lines.size(), 1, "注入数据：misa trust 10 低于 25 必须出现政策门提示。")
	if locked_lines.size() == 1:
		assert_true(locked_lines[0].contains("25"), "提示数值必须来自注入数据，实际：%s" % locked_lines[0])
		assert_true(locked_lines[0].contains("守护案"), "提示标签必须取自选项文案的冒号前段，实际：%s" % locked_lines[0])
	locked.free()
	_hud = null

	var symbiotic: Hud = _make_hud(_payload(
		{"misa": {"trust": 50, "affection": 0}},
		{"station_mode_symbiosis": true}
	))
	var symbiotic_lines: Array[String] = _lines_containing(symbiotic.get_node("RelationsPanel"), "距离共生还需")
	assert_eq(symbiotic_lines.size(), 1, "注入数据：共生 flag 置位且 trust 50 低于 65 必须出现共生门提示。")
	if symbiotic_lines.size() == 1:
		assert_true(symbiotic_lines[0].contains("15"), "剩余点数必须按注入阈值推导（65 - 50），实际：%s" % symbiotic_lines[0])


func test_gate_hints_derive_from_all_event_files_in_dir() -> void:
	# G7P-2 S3：目录内两个事件文件各带一个信任门选项 → 两条门提示自动派生
	#（新增信任门事件 = data/events 加 JSON 文件，零代码）。
	var first: Dictionary = {
		"id": "event_gate_first", "kind": "choice",
		"steps": [{"type": "choice", "choice_id": "gate_first", "prompt_zh": "选择？", "options": [
			{"id": "gate_first_opt", "text_zh": "头一门：需要弥砂点头。",
			 "set_flag": "g7p2_gate_first",
			 "requires_trust": {"char_id": "misa", "dim": "trust", "value": 25}},
		]}],
	}
	var second: Dictionary = {
		"id": "event_gate_second", "kind": "choice",
		"steps": [{"type": "choice", "choice_id": "gate_second", "prompt_zh": "选择？", "options": [
			{"id": "gate_second_opt", "text_zh": "第二门：需要洛弦点头。",
			 "set_flag": "g7p2_gate_second",
			 "requires_trust": {"char_id": "luoxian", "dim": "trust", "value": 45}},
		]}],
	}
	var dir: String = "user://dlx4_gate_events_multi_%d" % Time.get_ticks_usec()
	assert_eq(DirAccess.make_dir_recursive_absolute(dir), OK)
	_temp_dirs.append(dir)
	for entry: Array in [["event_gate_first.json", first], ["event_gate_second.json", second]]:
		var file: FileAccess = FileAccess.open(dir.path_join(String(entry[0])), FileAccess.WRITE)
		assert_not_null(file)
		if file != null:
			file.store_string(JSON.stringify(entry[1], "  "))
			file.close()
			_temp_paths.append(dir.path_join(String(entry[0])))
	assert_true(
		Hud.load_relation_gates_from(dir, ENDINGS_PATH).is_ok,
		"多文件事件目录必须整包装载成功。"
	)
	var derived_flags: Dictionary = {}
	for gate: Dictionary in Hud._gate_entries():
		derived_flags[String(gate["flag_id"])] = true
	assert_true(derived_flags.has("g7p2_gate_first"), "第一个事件文件的门必须自动派生。")
	assert_true(derived_flags.has("g7p2_gate_second"), "第二个事件文件的门必须自动派生。")


func test_bad_gate_files_fail_safe_without_breaking_rows() -> void:
	var result: AppResult = Hud.load_relation_gates_from("res://missing_events_dir", "res://missing_endings.json")
	assert_false(result.is_ok, "缺失数据文件必须报告失败。")
	assert_push_error("Hud: relation gate data rejected")
	var hud: Hud = _make_hud(_payload({"luoxian": {"trust": 10, "affection": 0}}, {}))
	assert_true(
		_lines_containing(hud.get_node("RelationsPanel"), "尚未赢得").is_empty(),
		"坏表必须失败安全：不渲染任何门提示行。"
	)
	var texts: Array[String] = _label_texts(hud.get_node("RelationsPanel"))
	assert_true(texts.has("洛弦 信任 10/100 ♥0"), "坏表不得影响关系数值行渲染。")


# ---------------------------------------------------------------- 只读约束


func test_relations_render_never_mutates_snapshot() -> void:
	var payload: Dictionary = _payload(
		{
			"luoxian": {"trust": 55, "affection": 3},
			"misa": {"trust": 30, "affection": 0},
		},
		{"policy_sanctuary": false}
	)
	var hud: Hud = _make_hud(payload)
	var before: Dictionary = _fake.payload.duplicate(true)
	hud.refresh()
	assert_eq(_fake.payload, before, "RelationsPanel 渲染绝不能修改注入的快照。")
