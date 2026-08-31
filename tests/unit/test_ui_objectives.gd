extends GutTest

## DLX-3 目标链外置测试（TDD：先于实现编写，观察 RED 后再实现 GREEN）。
##
## 任务书（DL5）：objective_for 的里程碑链 + _CHOICE_FLAGS 迁入
## data/progression/objectives.json（有序条目 {text_zh, all_of, any_of_prefix,
## not_flags}），hud.gd 改为查表取首个选中条目；行为等价（同一 state → 同一
## 目标句）。条目 token 词汇表（声明式，非表达式）：
## - 精确 flag id（如 "encounter_leviathan_won"）；
## - flag 前缀通配 "<prefix>*"（如 "event_*"，仅尾随一个 *）；
## - 放置谓词 "placed_<building_id>" / "placed_*"（保留前缀，映射
##   snapshot.placed_buildings，替代旧 _placed_building_ids.has 特判）。
## 条目选中 = all_of 全部启用 ∧ not_flags 全部未启用 ∧ any_of_prefix（非
## null 时任一同前缀 flag 启用）。本文件矩阵期望值冻结自迁移前 objective_for
## 的真实输出；test_ui_hud.gd 既有 10 行矩阵零修改为第二证。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"
const DEFAULT_OBJECTIVES_PATH: String = "res://data/progression/objectives.json"
const FALLBACK_OBJECTIVE: String = "探索世界"

var _hud: Hud = null
var _temp_paths: Array[String] = []


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	if _hud != null and is_instance_valid(_hud):
		_hud.free()
	_hud = null
	# 恢复默认目标表，防止临时表状态泄漏到其他测试文件。
	Hud.load_objectives_from(DEFAULT_OBJECTIVES_PATH)
	for temp_path: String in _temp_paths:
		DirAccess.remove_absolute(temp_path)
	_temp_paths.clear()


func _make_hud(payload: Dictionary) -> Hud:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = payload
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must load.")
	if scene == null:
		return null
	_hud = scene.instantiate() as Hud
	_hud.snapshot_provider = _fake.get_snapshot
	add_child_autofree(_hud)
	return _hud


var _fake: FakeSnapshotProvider = null


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


func _snap(flags: Dictionary, building_ids: Array) -> Dictionary:
	var placed: Array = []
	for building_id: String in building_ids:
		placed.append({
			"building_id": building_id,
			"chunk_id": "chunk_0_0",
			"cell_x": 0,
			"cell_y": 0,
		})
	return {
		"revision": 1,
		"inventory": {},
		"flags": flags,
		"placed_buildings": placed,
	}


# ---------------------------------------------------------------- 表装载


func test_default_objectives_table_loads() -> void:
	var loaded: AppResult = Hud.load_objectives_from(DEFAULT_OBJECTIVES_PATH)
	assert_true(loaded.is_ok, "默认目标表必须可加载：%s" % loaded.message)
	var entries: Array[Dictionary] = Hud._objective_entries()
	assert_eq(entries.size(), 13, "迁移目标表必须包含 13 个有序条目。")
	var texts: Array[String] = []
	for entry: Dictionary in entries:
		texts.append(String(entry["text_zh"]))
	assert_eq(
		texts,
		[
			"面对辉砂巨兽", "应对漂移群威胁", "应对漂移群威胁", "探索世界",
			"勘探琉砂海，采集星壤尘", "放置第一座锚块", "建立锚居工坊",
			"应对漂移群威胁", "做出驻地抉择", "推进方法与政策抉择",
			"推进方法与政策抉择", "面对辉砂巨兽", "见证余辉结局",
		] as Array[String],
		"迁移目标表的条目顺序与文案必须逐条对齐旧里程碑链。"
	)


# ---------------------------------------------------------------- 行为等价矩阵


func test_objective_for_matches_frozen_migration_matrix() -> void:
	assert_true(
		Hud.load_objectives_from(DEFAULT_OBJECTIVES_PATH).is_ok,
		"前置：默认目标表可加载。"
	)
	# 期望值冻结自迁移前 objective_for 真实输出（旧硬编码链）。
	var matrix: Array = [
		# 未决遭遇威胁优先，胜利后不再复现（回落进度链）。
		[_snap({"encounter_husk_ambush_due": true, "encounter_husk_ambush_won": true}, []), "勘探琉砂海，采集星壤尘"],
		# 放置即进度：仅工坊在场（未采过矿）也在勘探步。
		[_snap({}, ["anchor_workshop"]), "勘探琉砂海，采集星壤尘"],
		# place_flag 路径（first_anchor_placed flag）等价于 anchor_block 在场判定。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"first_anchor_placed": true,
		}, []), "放置第一座锚块"],
		# 事件 done + 建筑在场混合判定。
		[_snap({"event_event_first_mining_done": true}, ["anchor_block"]), "建立锚居工坊"],
		# 后期 flag 不越级：矿业未起步时仍显示勘探目标。
		[_snap({"station_mode_symbiosis": true, "approach_diplomatic": true}, []), "勘探琉砂海，采集星壤尘"],
		# approach 完成而 policy 未完成。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"event_event_first_anchor_done": true,
			"event_event_workshop_guide_done": true,
			"encounter_first_drift_won": true,
			"event_event_station_mode_done": true,
			"approach_direct": true,
		}, []), "推进方法与政策抉择"],
		# policy 完成而 approach 未完成。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"event_event_first_anchor_done": true,
			"event_event_workshop_guide_done": true,
			"encounter_first_drift_won": true,
			"event_event_station_mode_done": true,
			"policy_sanctuary": true,
		}, []), "推进方法与政策抉择"],
		# Boss 胜利 + 契约事件完成后进入结局目标。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"event_event_first_anchor_done": true,
			"event_event_workshop_guide_done": true,
			"encounter_first_drift_won": true,
			"event_event_station_mode_done": true,
			"approach_direct": true,
			"policy_extraction_quota": true,
			"encounter_leviathan_won": true,
			"event_event_leviathan_pact_done": true,
		}, []), "见证余辉结局"],
		# 结局事件为互斥分支：完成其一即视为终局达成，目标回落兜底探索
		#（与迁移前一致：r11 仅在两个结局事件都未完成时显示）。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"event_event_first_anchor_done": true,
			"event_event_workshop_guide_done": true,
			"encounter_first_drift_won": true,
			"event_event_station_mode_done": true,
			"approach_direct": true,
			"policy_extraction_quota": true,
			"encounter_leviathan_won": true,
			"event_event_leviathan_pact_done": true,
			"event_event_ending_luoxian_done": true,
		}, []), "探索世界"],
		# 提示落账 flag 与 mine_entered 不是进度标记：无进度时仍是探索。
		[_snap({"hint_move_seen": true, "mine_entered": true}, []), "探索世界"],
		# 全部完成 → 兜底探索。
		[_snap({
			"event_event_prologue_landing_done": true,
			"event_event_first_mining_done": true,
			"event_event_first_anchor_done": true,
			"event_event_workshop_guide_done": true,
			"encounter_first_drift_won": true,
			"event_event_station_mode_done": true,
			"approach_direct": true,
			"policy_extraction_quota": true,
			"encounter_leviathan_won": true,
			"event_event_leviathan_pact_done": true,
			"event_event_ending_luoxian_done": true,
			"event_event_ending_misa_done": true,
		}, ["anchor_block", "anchor_workshop"]), "探索世界"],
	]
	for row: Array in matrix:
		assert_eq(
			Hud.objective_for(row[0] as Dictionary), String(row[1]),
			"objective_for 必须与迁移前逐 state 等价。"
		)


# ---------------------------------------------------------------- 失败安全


func test_missing_objectives_file_fails_safe_and_pushes_error() -> void:
	var result: AppResult = Hud.load_objectives_from(
		"res://data/progression/definitely_missing_objectives.json")
	assert_false(result.is_ok, "缺失目标表必须加载失败。")
	assert_eq(result.code, "missing_objectives_file")
	# 规范要求文件缺失 push_error；预期错误断言同时消费该错误。
	assert_push_error("Hud: objectives table rejected")
	assert_eq(
		Hud.objective_for(_snap({}, [])), FALLBACK_OBJECTIVE,
		"目标表缺失时 objective_for 必须兜底为探索世界。"
	)
	assert_eq(Hud.objective_for({}), FALLBACK_OBJECTIVE)


func test_malformed_objectives_files_are_rejected() -> void:
	var bad_cases: Array = [
		["syntax_error", "{\"text_zh\": not json"],
		["not_an_array", "{\"text_zh\": \"面对辉砂巨兽\"}"],
		["entry_not_object", "[\"面对辉砂巨兽\"]"],
		["missing_text", "[{\"all_of\": []}]"],
		["empty_text", "[{\"text_zh\": \"\", \"all_of\": []}]"],
		["all_of_wrong_type", "[{\"text_zh\": \"t\", \"all_of\": \"a\"}]"],
		["all_of_non_string_member", "[{\"text_zh\": \"t\", \"all_of\": [7]}]"],
		["not_flags_wrong_type", "[{\"text_zh\": \"t\", \"all_of\": [], \"not_flags\": true}]"],
		["prefix_wrong_type", "[{\"text_zh\": \"t\", \"all_of\": [], \"any_of_prefix\": 3}]"],
		["token_empty", "[{\"text_zh\": \"t\", \"all_of\": [\"\"]}]"],
		["token_not_stable_id", "[{\"text_zh\": \"t\", \"all_of\": [\"First Flag\"]}]"],
		["token_wildcard_not_trailing", "[{\"text_zh\": \"t\", \"all_of\": [\"event*_x\"]}]"],
		["token_wildcard_bad_prefix", "[{\"text_zh\": \"t\", \"all_of\": [\"Event_*\"]}]"],
		["token_placed_suffix_bad", "[{\"text_zh\": \"t\", \"all_of\": [\"placed_锚块\"]}]"],
	]
	for case_entry: Array in bad_cases:
		var path := _write_temp_objectives(String(case_entry[0]), String(case_entry[1]))
		var result: AppResult = Hud.load_objectives_from(path)
		assert_false(result.is_ok, "坏目标表 %s 必须被拒绝。" % String(case_entry[0]))
		assert_false(result.message.is_empty(), "拒绝信息必须说明原因。")
		assert_push_error("Hud: objectives table rejected")
		assert_eq(
			Hud.objective_for(_snap({}, [])), FALLBACK_OBJECTIVE,
			"坏目标表加载后 objective_for 必须失败安全。"
		)


func _write_temp_objectives(case_name: String, text: String) -> String:
	var path: String = "user://dlx3_objectives_%s_%d.json" % [case_name, Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "临时目标表必须可写：%s" % path)
	if file != null:
		file.store_string(text)
		file.close()
	_temp_paths.append(path)
	return path


# ---------------------------------------------------------------- 纯数据扩展


func test_pure_data_objective_extension_needs_no_code_change() -> void:
	assert_true(
		Hud.load_objectives_from(DEFAULT_OBJECTIVES_PATH).is_ok,
		"前置：默认目标表可加载。"
	)
	# 纯数据扩展证明：临时目标表新增条目（哨兵 flag 门控 + 兜底探索）后，
	# 新目标句随 flag 置位出现——零代码扩展。
	var extended: Array = [
		{"text_zh": "跋涉灰烬荒原", "all_of": ["dlx3_gate_open"], "any_of_prefix": null, "not_flags": []},
		{"text_zh": FALLBACK_OBJECTIVE, "all_of": [], "any_of_prefix": null, "not_flags": []},
	]
	var path := _write_temp_objectives("extended", JSON.stringify(extended, "  "))
	assert_true(Hud.load_objectives_from(path).is_ok, "扩展目标表必须可加载。")
	var blocked: Dictionary = _snap({"dlx3_gate_open": false}, [])
	assert_eq(
		Hud.objective_for(blocked), FALLBACK_OBJECTIVE,
		"门控未满足时必须让路到兜底条目。"
	)
	var opened: Dictionary = _snap({"dlx3_gate_open": true}, [])
	assert_eq(
		Hud.objective_for(opened), "跋涉灰烬荒原",
		"新增条目必须按 JSON 声明选中（新增目标 = 改 JSON）。"
	)


# ---------------------------------------------------------------- HUD 渲染接线


func test_hud_objective_label_renders_table_objective() -> void:
	assert_true(
		Hud.load_objectives_from(DEFAULT_OBJECTIVES_PATH).is_ok,
		"前置：默认目标表可加载。"
	)
	var hud: Hud = _make_hud(_snap({"event_event_prologue_landing_done": true}, []))
	var label: Label = hud.get_node("ObjectiveLabel") as Label
	assert_eq(label.text, "勘探琉砂海，采集星壤尘", "ObjectiveLabel 必须渲染表驱动目标句。")
