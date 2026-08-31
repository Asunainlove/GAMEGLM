extends GutTest

## WP15 三结局单元测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
## 契约：docs/plans/contracts/module-contracts.md §4（ending.tscn 节点契约）、
## §5（Endings 纯逻辑 API）、§7（结局门控数值，逐字）。
## 脚本与场景一律运行时 load（绝不 preload），缺失实现以失败断言暴露而非整包
## 解析失败（与 test_progression.gd / test_narrative_dialogue_box.gd 同型）。

const ENDINGS_SCRIPT_PATH: String = "res://src/endings/endings.gd"
const ENDING_SCENE_PATH: String = "res://scenes/ending.tscn"
const ENDING_SCENE_SCRIPT_PATH: String = "res://src/endings/ending_scene.gd"
const THEME_PATH: String = "res://themes/starsoil_theme.tres"

const UNFINISHED_TEXT: String = "旅程尚未完结…"
const TITLE_MINING: String = "结局：开采纪元"
const TITLE_SEAL: String = "结局：封存之约"
const TITLE_SYMBIOSIS: String = "结局：共生曙光"

## 占位符黑名单：结局总结必须是成稿原创中文，不得遗留任何占位痕迹。
const PLACEHOLDER_TOKENS: Array[String] = [
	"TODO", "FIXME", "TBD", "XXX", "WIP", "占位", "PLACEHOLDER", "LOREM", "Lorem", "???",
]

var _endings: Script = null


func before_all() -> void:
	_endings = load(ENDINGS_SCRIPT_PATH)


func _require_endings() -> bool:
	if _endings == null:
		fail_test("Missing required WP15 implementation: %s" % ENDINGS_SCRIPT_PATH)
		return false
	return true


# ---------------------------------------------------------------- 构造工具


## station_mode_symbiosis 的最小满足态：trust 与 echo_chamber_active 可注入。
func _symbiosis_state(trust: int, echo_chamber_active: bool = true) -> Dictionary:
	return {
		"flags": {
			"station_mode_symbiosis": true,
			"echo_chamber_active": echo_chamber_active,
		},
		"relationships": {"luoxian": {"trust": trust}},
	}


## 契约 §7 逐字表驱动：三分支 + 69/70/71 信任边界 + echo_chamber_active 缺失
## /显式 false 回落 seal + 关系缺失回落 seal + 多旗标优先级 + 空 state → ""。
func _evaluate_cases() -> Array[Dictionary]:
	var all_flags_state: Dictionary = {
		"flags": {
			"station_mode_exploit": true,
			"station_mode_seal": true,
			"station_mode_symbiosis": true,
			"echo_chamber_active": true,
		},
		"relationships": {"luoxian": {"trust": 100}},
	}
	return [
		{"id": "empty_state_returns_empty", "state": {}, "expected": ""},
		{
			"id": "no_station_mode_flag_returns_empty",
			"state": {"flags": {"first_mining_done": true, "echo_chamber_active": true}},
			"expected": "",
		},
		{
			"id": "station_mode_flag_false_is_unset",
			"state": {"flags": {"station_mode_exploit": false}},
			"expected": "",
		},
		{
			"id": "exploit_returns_mining",
			"state": {"flags": {"station_mode_exploit": true}},
			"expected": "ending_mining",
		},
		{
			"id": "seal_returns_seal",
			"state": {"flags": {"station_mode_seal": true}},
			"expected": "ending_seal",
		},
		{
			"id": "symbiosis_trust_70_returns_symbiosis",
			"state": _symbiosis_state(70),
			"expected": "ending_symbiosis",
		},
		{
			"id": "symbiosis_trust_71_returns_symbiosis",
			"state": _symbiosis_state(71),
			"expected": "ending_symbiosis",
		},
		{
			"id": "symbiosis_trust_69_falls_back_to_seal",
			"state": _symbiosis_state(69),
			"expected": "ending_seal",
		},
		{
			"id": "symbiosis_trust_zero_falls_back_to_seal",
			"state": _symbiosis_state(0),
			"expected": "ending_seal",
		},
		{
			"id": "symbiosis_trust_missing_falls_back_to_seal",
			"state": {"flags": {"station_mode_symbiosis": true, "echo_chamber_active": true}},
			"expected": "ending_seal",
		},
		{
			"id": "symbiosis_echo_false_falls_back_to_seal",
			"state": _symbiosis_state(80, false),
			"expected": "ending_seal",
		},
		{
			"id": "symbiosis_echo_missing_falls_back_to_seal",
			"state": {"flags": {"station_mode_symbiosis": true}, "relationships": {"luoxian": {"trust": 99}}},
			"expected": "ending_seal",
		},
		{
			"id": "exploit_wins_when_all_station_flags_set",
			"state": all_flags_state,
			"expected": "ending_mining",
		},
	]


func _summary_ids() -> Array[String]:
	return ["ending_mining", "ending_seal", "ending_symbiosis"]


## 实例化结局场景并在进入树前注入假快照 provider（_ready 会读取它）。
func _instantiate_ending_with(provider_state: Dictionary) -> Node:
	var scene: PackedScene = load(ENDING_SCENE_PATH) as PackedScene
	if scene == null:
		fail_test("Ending scene must exist and load at %s." % ENDING_SCENE_PATH)
		return null
	var ending: Node = (scene as PackedScene).instantiate()
	ending.set("snapshot_provider", func() -> Dictionary: return provider_state)
	add_child_autofree(ending)
	return ending


# ---------------------------------------------------------------- evaluate


func test_evaluate_table_driven_branches_boundaries_and_fallbacks() -> void:
	if not _require_endings():
		return
	for case: Dictionary in _evaluate_cases():
		var actual: String = String(_endings.evaluate(case["state"]))
		assert_eq(
			actual,
			String(case["expected"]),
			"evaluate case '%s' failed." % String(case["id"])
		)


# ---------------------------------------------------------------- 文案映射


func test_ending_title_maps_contract_titles_and_empty_for_unknown() -> void:
	if not _require_endings():
		return
	assert_eq(String(_endings.ending_title("ending_mining")), TITLE_MINING, "ending_mining title must match contract wording.")
	assert_eq(String(_endings.ending_title("ending_seal")), TITLE_SEAL, "ending_seal title must match contract wording.")
	assert_eq(String(_endings.ending_title("ending_symbiosis")), TITLE_SYMBIOSIS, "ending_symbiosis title must match contract wording.")
	assert_eq(String(_endings.ending_title("ending_undefined")), "", "Unknown ids must map to an empty title.")
	assert_eq(String(_endings.ending_title("")), "", "Empty id must map to an empty title.")


func test_ending_summary_nonempty_for_all_three_endings() -> void:
	if not _require_endings():
		return
	for ending_id: String in _summary_ids():
		var summary: String = String(_endings.ending_summary(ending_id))
		assert_true(
			summary.length() >= 40,
			"Summary for %s must be a real passage (got %d chars)." % [ending_id, summary.length()]
		)


func test_ending_summary_contains_no_placeholder_tokens() -> void:
	if not _require_endings():
		return
	for ending_id: String in _summary_ids():
		var summary: String = String(_endings.ending_summary(ending_id))
		for token: String in PLACEHOLDER_TOKENS:
			assert_false(
				summary.contains(token),
				"Summary for %s must not contain placeholder token '%s'." % [ending_id, token]
			)


func test_ending_summary_empty_for_empty_and_unknown_ids() -> void:
	if not _require_endings():
		return
	assert_eq(String(_endings.ending_summary("")), "", "Empty id must map to an empty summary.")
	assert_eq(String(_endings.ending_summary("ending_undefined")), "", "Unknown ids must map to an empty summary.")


# ---------------------------------------------------------------- 场景契约


func test_ending_scene_matches_node_contract() -> void:
	var ending: Node = _instantiate_ending_with({})
	if ending == null:
		return
	assert_eq(ending.name, "Ending", "Root node must be named Ending.")
	assert_true(ending is Node2D, "Ending root must be a Node2D.")
	var script: Script = ending.get_script() as Script
	assert_not_null(script, "Ending root must carry its scene script.")
	if script != null:
		assert_eq(script.resource_path, ENDING_SCENE_SCRIPT_PATH, "Ending script path must match contract §4.")

	var title_label: Label = ending.get_node_or_null("TitleLabel") as Label
	var summary_label: Label = ending.get_node_or_null("SummaryLabel") as Label
	assert_not_null(title_label, "TitleLabel child is required by contract §4.")
	assert_not_null(summary_label, "SummaryLabel child is required by contract §4.")
	if title_label != null:
		assert_eq(
			title_label.horizontal_alignment,
			HORIZONTAL_ALIGNMENT_CENTER,
			"TitleLabel must render centered text."
		)
		assert_not_null(title_label.theme, "TitleLabel must hang the starsoil theme.")
		if title_label.theme != null:
			assert_eq(title_label.theme.resource_path, THEME_PATH, "TitleLabel theme must be themes/starsoil_theme.tres.")
	if summary_label != null:
		assert_eq(
			summary_label.horizontal_alignment,
			HORIZONTAL_ALIGNMENT_CENTER,
			"SummaryLabel must render centered text."
		)
		assert_not_null(summary_label.theme, "SummaryLabel must hang the starsoil theme.")
		if summary_label.theme != null:
			assert_eq(summary_label.theme.resource_path, THEME_PATH, "SummaryLabel theme must be themes/starsoil_theme.tres.")


# ---------------------------------------------------------------- 场景冒烟


func test_scene_renders_symbiosis_title_and_summary_with_injected_provider() -> void:
	if not _require_endings():
		return
	var state: Dictionary = {
		"flags": {"station_mode_symbiosis": true, "echo_chamber_active": true},
		"relationships": {"luoxian": {"trust": 75, "affection": 60, "ideology": 40}},
	}
	var ending: Node = _instantiate_ending_with(state)
	if ending == null:
		return
	var title_label: Label = ending.get_node("TitleLabel") as Label
	var summary_label: Label = ending.get_node("SummaryLabel") as Label
	assert_eq(title_label.text, TITLE_SYMBIOSIS, "A symbiosis-satisfying snapshot must render the symbiosis title.")
	assert_eq(
		summary_label.text,
		String(_endings.ending_summary("ending_symbiosis")),
		"SummaryLabel must render the ending summary verbatim."
	)


func test_scene_renders_unfinished_text_for_empty_state() -> void:
	var ending: Node = _instantiate_ending_with({})
	if ending == null:
		return
	var title_label: Label = ending.get_node("TitleLabel") as Label
	var summary_label: Label = ending.get_node("SummaryLabel") as Label
	assert_eq(title_label.text, UNFINISHED_TEXT, "An undetermined ending must render the unfinished hint.")
	assert_eq(summary_label.text, "", "An undetermined ending must leave the summary empty.")


func test_scene_defaults_to_game_state_snapshot_when_provider_unset() -> void:
	if not _require_endings():
		return
	var scene: PackedScene = load(ENDING_SCENE_PATH) as PackedScene
	if scene == null:
		fail_test("Ending scene must exist and load at %s." % ENDING_SCENE_PATH)
		return
	var ending: Node = (scene as PackedScene).instantiate()
	add_child_autofree(ending)

	var live_snapshot: Dictionary = GameState.snapshot()
	var live_ending_id: String = String(_endings.evaluate(live_snapshot))
	var expected_title: String = UNFINISHED_TEXT
	if not live_ending_id.is_empty():
		expected_title = String(_endings.ending_title(live_ending_id))
	var title_label: Label = ending.get_node("TitleLabel") as Label
	assert_eq(
		title_label.text,
		expected_title,
		"Without an injected provider the scene must read the shared GameState autoload snapshot."
	)


func test_snapshot_provider_defaults_to_invalid_callable() -> void:
	var scene: PackedScene = load(ENDING_SCENE_PATH) as PackedScene
	if scene == null:
		fail_test("Ending scene must exist and load at %s." % ENDING_SCENE_PATH)
		return
	var ending: Node = (scene as PackedScene).instantiate()
	autofree(ending)
	var provider: Callable = ending.get("snapshot_provider") as Callable
	assert_false(
		provider.is_valid(),
		"snapshot_provider must default to an empty (invalid) Callable."
	)


func test_show_ending_refreshes_after_provider_swap() -> void:
	if not _require_endings():
		return
	var ending: Node = _instantiate_ending_with({})
	if ending == null:
		return
	var title_label: Label = ending.get_node("TitleLabel")
	assert_eq(title_label.text, UNFINISHED_TEXT, "Precondition: unfinished text before the provider swap.")
	ending.set(
		"snapshot_provider",
		func() -> Dictionary: return _symbiosis_state(75)
	)
	ending.call("show_ending")
	assert_eq(title_label.text, TITLE_SYMBIOSIS, "show_ending must re-evaluate against the new provider.")


# ---------------------------------------------------------------- DLX-1 结局表数据化

const DLX1_FIXTURE_ROOT: String = "user://dlx1_endings_fixtures"

## DLX-1 假设结局（纯数据扩展的证明载体）：order=1 插在 mining 与 seal 之间，
## 门控 = station_mode_seal 且 harvest_charter_signed；标题/总结均为原创中文。
const HARVEST_TITLE: String = "结局：丰收协定"
const HARVEST_SUMMARY: String = "封存的界线内侧开出了第一片共耕田：矿脉的呼吸节拍成了播种的历法，你们收获的每一粒晶尘都带着回执。"


func after_each() -> void:
	# DLX-1：数据化测试会切换结局表（静态缓存跨用例存活）。每个用例后清缓存，
	# 让同文件既有场景测试与其他测试文件重新读到生产表（惰性重载）。
	if _endings != null:
		_endings.call("reset_for_tests")


func after_all() -> void:
	_remove_dir_recursive(DLX1_FIXTURE_ROOT)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child_path: String = path + "/" + entry
		if dir.current_is_dir():
			_remove_dir_recursive(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_endings_fixture(file_name: String, content: String) -> String:
	DirAccess.make_dir_recursive_absolute(DLX1_FIXTURE_ROOT)
	var path: String = DLX1_FIXTURE_ROOT + "/" + file_name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "Fixture file %s must be writable." % file_name)
	if file != null:
		file.store_string(content)
		file.close()
	return path


func _three_ending_entry(id: String, order_value: int, all_flags: Array) -> Dictionary:
	return {
		"id": id,
		"order": order_value,
		"all_of_flags": all_flags,
		"any_of_prefix": null,
		"trust": null,
		"extra_flag": null,
		"fallback_ending": null,
		"title_zh": "结局：" + id,
		"summary_zh": "测试替文：" + id + " 的结局总结，长度足以构成成稿段落。",
	}


func _four_ending_table_json() -> String:
	var symbiosis: Dictionary = _three_ending_entry("ending_symbiosis", 3, ["station_mode_symbiosis"])
	symbiosis["trust"] = {"char_id": "luoxian", "dim": "trust", "threshold": 70}
	symbiosis["extra_flag"] = "echo_chamber_active"
	symbiosis["fallback_ending"] = "ending_seal"
	var harvest: Dictionary = _three_ending_entry("ending_harvest", 1, ["station_mode_seal", "harvest_charter_signed"])
	harvest["title_zh"] = HARVEST_TITLE
	harvest["summary_zh"] = HARVEST_SUMMARY
	return JSON.stringify([
		_three_ending_entry("ending_mining", 0, ["station_mode_exploit"]),
		harvest,
		_three_ending_entry("ending_seal", 2, ["station_mode_seal"]),
		symbiosis,
	], "  ")


func test_bootstrap_loads_production_table_and_is_idempotent() -> void:
	if not _require_endings():
		return
	_endings.call("reset_for_tests")
	var first: Variant = _endings.call("bootstrap")
	assert_true(first is AppResult, "bootstrap 必须返回 AppResult。")
	assert_true((first as AppResult).is_ok, "生产表 data/content/endings.json 必须可加载。")
	# 幂等：重复 bootstrap 成功且判定结果不变。
	var again: Variant = _endings.call("bootstrap")
	assert_true((again as AppResult).is_ok, "重复 bootstrap 必须幂等成功。")
	assert_eq(
		String(_endings.evaluate(_symbiosis_state(70))),
		"ending_symbiosis",
		"缓存表必须驱动与既有行为快照一致的判定。"
	)


func test_missing_endings_file_fails_bootstrap_and_evaluate_stays_undetermined() -> void:
	if not _require_endings():
		return
	_endings.call("reset_for_tests")
	var missing_path: String = DLX1_FIXTURE_ROOT + "/never_created/endings.json"
	var result: Variant = _endings.call("bootstrap", missing_path)
	assert_true(result is AppResult, "bootstrap 必须返回 AppResult。")
	assert_false((result as AppResult).is_ok, "缺失 endings.json 必须判定失败。")
	# 文件缺失必须 push_error（assert_push_error 把该错误标记为预期）。
	assert_push_error("missing", "缺失 endings.json 必须 push_error。")
	# 失败后判定退化为"结局未定"、文案为空——绝不抛错或返回伪结局。
	assert_eq(String(_endings.evaluate(_symbiosis_state(70))), "")
	assert_eq(String(_endings.ending_title("ending_mining")), "")
	assert_eq(String(_endings.ending_summary("ending_mining")), "")


func test_fourth_ending_is_pure_data_extension_without_code_change() -> void:
	if not _require_endings():
		return
	_endings.call("reset_for_tests")
	var fixture_path: String = _write_endings_fixture("four_endings.json", _four_ending_table_json())
	var result: Variant = _endings.call("bootstrap", fixture_path)
	assert_true(result is AppResult, "bootstrap 必须返回 AppResult。")
	assert_true(
		(result as AppResult).is_ok,
		"四条目的替身表必须可加载：%s" % ((result as AppResult).message if result is AppResult else "")
	)
	var harvest_state: Dictionary = {
		"flags": {"station_mode_seal": true, "harvest_charter_signed": true},
		"relationships": {},
	}
	assert_eq(
		String(_endings.evaluate(harvest_state)),
		"ending_harvest",
		"纯数据新增的第 4 个结局必须参与按序判定（加结局=加 JSON，零代码改动）。"
	)
	assert_eq(String(_endings.ending_title("ending_harvest")), HARVEST_TITLE, "新结局标题必须查表返回。")
	assert_eq(String(_endings.ending_summary("ending_harvest")), HARVEST_SUMMARY, "新结局总结必须查表返回。")
	# order=1 的 harvest 排在 seal（order=2）之前：两者 all_of 同时满足时按 order 取 harvest。
	assert_eq(
		String(_endings.evaluate({"flags": {"station_mode_seal": true, "harvest_charter_signed": true, "station_mode_symbiosis": true}})),
		"ending_harvest",
		"order 字段必须决定判定优先级。"
	)
	assert_eq(
		String(_endings.evaluate({"flags": {"station_mode_seal": true}})),
		"ending_seal",
		"harvest 前置不满足时按序回落 seal。"
	)
	assert_eq(
		String(_endings.evaluate(_symbiosis_state(70))),
		"ending_symbiosis",
		"替身表的 trust/extra 门控必须与生产同构。"
	)
	assert_eq(
		String(_endings.evaluate(_symbiosis_state(69))),
		"ending_seal",
		"替身表的 fallback 回落必须与生产同构。"
	)


func test_duplicate_ending_id_fails_bootstrap() -> void:
	if not _require_endings():
		return
	_endings.call("reset_for_tests")
	var duplicate: Array = [
		_three_ending_entry("ending_seal", 0, ["station_mode_seal"]),
		_three_ending_entry("ending_seal", 1, ["station_mode_seal"]),
	]
	var fixture_path: String = _write_endings_fixture("duplicate_ids.json", JSON.stringify(duplicate, "  "))
	var result: Variant = _endings.call("bootstrap", fixture_path)
	assert_true(result is AppResult, "bootstrap 必须返回 AppResult。")
	assert_false((result as AppResult).is_ok, "重复结局 id 必须判定失败。")
	assert_push_error("duplicates ending id", "重复 id 必须 push_error。")


func test_unknown_fallback_ending_fails_bootstrap() -> void:
	if not _require_endings():
		return
	_endings.call("reset_for_tests")
	var dangling: Dictionary = _three_ending_entry("ending_symbiosis", 0, ["station_mode_symbiosis"])
	dangling["trust"] = {"char_id": "luoxian", "dim": "trust", "threshold": 70}
	dangling["fallback_ending"] = "ending_nonexistent"
	var fixture_path: String = _write_endings_fixture("dangling_fallback.json", JSON.stringify([dangling], "  "))
	var result: Variant = _endings.call("bootstrap", fixture_path)
	assert_true(result is AppResult, "bootstrap 必须返回 AppResult。")
	assert_false((result as AppResult).is_ok, "fallback 指向未知结局 id 必须判定失败。")
	assert_push_error("fallback_ending", "悬空 fallback 必须 push_error。")
