extends GutTest

## W000-P04 集成闭环测试（app 层装配 + GameSession 六条链路）。
##
## 除场景装配冒烟外，全部链路经注入的独立 GameState 实例（真实 patch 管线）
## 驱动，不污染全局 autoload。采集/建造/事件/遭遇/存档各链路只使用冻结契约
## API（docs/plans/contracts/module-contracts.md §5/§7）。

const APP_SCENE_PATH: String = "res://scenes/app.tscn"
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")

const RENDERED_CHUNK_ID: String = "chunk_0_0"
const EXPECTED_DEFINITION_COUNT: int = 40
const MAX_BATTLE_GUARD: int = 200

## 每个 before_each 生成互不重用的存档根，杜绝自动读档串场。
static var _save_root_seq: int = 0

## 场景重载 spy 宿主：必须存测试实例字段保活（Callable 只持 ObjectID）。
var _reload_spy: SceneReloadSpy = null

## 当前隔离存档根；经 SaveService.configure_root_for_tests 注入，删档断言走
## SaveService.delete_slot（与生产同一 SaveService 存根路径）。
var _save_root: String = ""


class SceneReloadSpy:
	var calls: int = 0

	func reload_current_scene() -> void:
		calls += 1

var store: Node
var world: Node2D
var dialogue: DialogueBox
var session: GameSession


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap must succeed: %s" % boot.message)
	_save_root_seq += 1
	_save_root = "user://saves_wp04_integration_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
	assert_true(SaveService.configure_root_for_tests(_save_root).is_ok)
	store = GAME_STATE_SCRIPT.new()
	world = _make_world()
	dialogue = _make_dialogue()


func after_each() -> void:
	if is_instance_valid(session):
		session.free()
	if is_instance_valid(world):
		world.free()
	if is_instance_valid(dialogue):
		dialogue.free()
	if is_instance_valid(store):
		store.free()
	session = null
	world = null
	dialogue = null
	store = null


# ---------------------------------------------------------------- 场景装配


func test_app_scene_assembles_world_hud_dialogue_and_session() -> void:
	var packed := load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "app.tscn must load.")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	add_child_autofree(app)
	var world_node: Node = app.get_node_or_null("WorldHost/World")
	assert_not_null(world_node, "WorldHost 下必须实例化 res://scenes/world.tscn。")
	assert_true(world_node is Node2D, "World 实例必须是 Node2D。")
	assert_not_null(app.get_node_or_null("UILayer/Hud"), "UILayer 下必须实例化 res://scenes/ui_hud.tscn。")
	var dialogue_box: Node = app.get_node_or_null("ModalLayer/DialogueBox")
	assert_not_null(dialogue_box, "ModalLayer 下必须实例化 res://scenes/dialogue_box.tscn。")
	if dialogue_box != null:
		assert_false(dialogue_box.visible, "DialogueBox 必须初始隐藏。")
	assert_not_null(app.get_node_or_null("GameSession"), "app 必须挂载 GameSession 编排器。")


func test_session_ready_bootstraps_content_with_forty_definitions() -> void:
	_make_session()
	assert_true(ContentDB.is_bootstrapped(), "GameSession 就绪后 ContentDB 必须 bootstrapped。")
	assert_eq(_total_definition_count(), EXPECTED_DEFINITION_COUNT)


# ---------------------------------------------------------------- 采集链


func test_mine_chain_yields_dust_destroys_cell_and_reacts() -> void:
	_make_session()
	var ore_cell := _ore_cell("ore_dust")

	var first: AppResult = session.request_mine(ore_cell)
	assert_true(first.is_ok, first.message)
	var transient: Dictionary = store.snapshot()
	assert_eq(int(transient["revision"]), 0, "未耗尽的敲击是暂态，不得提交 patch。")
	assert_eq(int((transient["inventory"] as Dictionary).get("starsoil_dust", 0)), 0)

	var second: AppResult = session.request_mine(ore_cell)
	assert_true(second.is_ok, second.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int((snapshot["inventory"] as Dictionary).get("starsoil_dust", 0)), 2)
	var deltas: Array = (snapshot["chunk_deltas"] as Dictionary).get(RENDERED_CHUNK_ID, [])
	assert_true(_has_destroyed_delta(deltas, ore_cell), "耗尽后 chunk_deltas 必须记录 destroyed。")
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("first_mining_done", false)),
		"耗尽采集必须触发 Progression.react(mined)。"
	)


func test_mine_chain_leaves_soil_cells_untouched() -> void:
	_make_session()
	var soil_cell := _soil_cell()
	var result: AppResult = session.request_mine(soil_cell)
	assert_false(result.is_ok, "土壤格不可采集，请求必须失败。")
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int(snapshot["revision"]), 0, "失败采集不得推进 revision。")
	assert_true((snapshot["chunk_deltas"] as Dictionary).is_empty(), "土壤格不得产生持久变化。")
	assert_true((snapshot["inventory"] as Dictionary).is_empty(), "土壤格不得产出物品。")


func test_player_mine_signal_drives_session_chain() -> void:
	_make_session()
	var player: Node = session.player
	assert_not_null(player, "session 必须绑定 world 内的 player。")
	var ore_cell := _ore_cell("ore_dust")
	player.emit_signal("mine_requested", ore_cell)
	player.emit_signal("mine_requested", ore_cell)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int((snapshot["inventory"] as Dictionary).get("starsoil_dust", 0)), 2)
	assert_true(_has_destroyed_delta(
		(snapshot["chunk_deltas"] as Dictionary).get(RENDERED_CHUNK_ID, []), ore_cell))


# ---------------------------------------------------------------- 建造链


func test_place_chain_builds_anchor_and_deducts_materials() -> void:
	_make_session()
	_give_item("starsoil_dust", 10)
	var soil_cell := _soil_cell()
	var result: AppResult = session.request_place(soil_cell)
	assert_true(result.is_ok, result.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int((snapshot["inventory"] as Dictionary).get("starsoil_dust", 0)), 8)
	assert_true(_has_building(snapshot, "anchor_block", soil_cell), "placed_buildings 必须包含 anchor_block。")
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("first_anchor_placed", false)),
		"建造成功必须触发 Progression.react(built)。"
	)


func test_place_chain_without_materials_changes_nothing() -> void:
	_make_session()
	var soil_cell := _soil_cell()
	var result: AppResult = session.request_place(soil_cell)
	assert_false(result.is_ok, "材料不足时建造必须失败。")
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int(snapshot["revision"]), 0, "失败建造不得推进 revision。")
	assert_true((snapshot["placed_buildings"] as Array).is_empty(), "失败建造不得留下建筑。")
	assert_true((snapshot["inventory"] as Dictionary).is_empty(), "失败建造不得扣材料。")


func test_place_chain_gates_effect_flag_on_powered_build() -> void:
	_make_session()
	_give_item("starsoil_dust", 10)
	_give_item("resonant_core", 2)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("echo_chamber", Vector2i(20, 22)).is_ok)
	var snapshot: Dictionary = store.snapshot()
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("echo_chamber_active", false)),
		"工坊供电充足且成房间时，回响舱必须置位 effect_flag。"
	)
	assert_true(session.unpowered_effect_flags.is_empty(), "供电充足时不得记录断电 effect 建筑。")


func test_place_chain_withholds_effect_flag_without_supply() -> void:
	_make_session()
	_give_item("resonant_core", 2)
	_preplace_building("anchor_block", Vector2i(20, 20))
	assert_true(_place_at("echo_chamber", Vector2i(20, 21)).is_ok)
	var snapshot: Dictionary = store.snapshot()
	assert_false(
		bool((snapshot["flags"] as Dictionary).get("echo_chamber_active", false)),
		"无电源时新建回响舱不得置位 effect_flag。"
	)
	assert_true(
		session.unpowered_effect_flags.has("echo_chamber"),
		"断电的 effect 建筑必须被单调巡检记录。"
	)


func test_place_chain_withholds_effect_flag_without_room() -> void:
	_make_session()
	_give_item("resonant_core", 2)
	_preplace_building("anchor_workshop", Vector2i(20, 20))
	# Chebyshev 距离 2 满足放置邻接，但 4 连通距离 4 未成房间。
	assert_true(_place_at("echo_chamber", Vector2i(22, 22)).is_ok)
	var snapshot: Dictionary = store.snapshot()
	assert_false(
		bool((snapshot["flags"] as Dictionary).get("echo_chamber_active", false)),
		"供给充足但未成房间时，回响舱不得置位 effect_flag。"
	)


func test_place_chain_does_not_recommit_flag_for_unpowered_duplicate_effect_building() -> void:
	_make_session()
	_give_item("starsoil_dust", 10)
	_give_item("resonant_core", 4)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("echo_chamber", Vector2i(20, 22)).is_ok)
	var snapshot: Dictionary = store.snapshot()
	assert_true(bool((snapshot["flags"] as Dictionary).get("echo_chamber_active", false)))
	var revision_before: int = int(snapshot["revision"])

	# 工坊供给 10 已被首座回响舱(draw 8)占去 8，只剩 2：第二座回响舱(draw 8)
	# 断电。判定对象是"本次新建建筑"，不得因同 id 旧实例在 powered_ids 中而
	# 把 powered=true 误报给 Progression（那样会多提交一个冗余 flag patch，
	# revision 将 +2 而非建造 patch 本身的 +1）。
	assert_true(_place_at("echo_chamber", Vector2i(20, 23)).is_ok)
	var after: Dictionary = store.snapshot()
	assert_eq(
		int(after["revision"]), revision_before + 1,
		"断电的新建回响舱只应提交建造 patch 本身，不得再触发 effect_flag 落账 patch。"
	)
	assert_true(
		bool((after["flags"] as Dictionary).get("echo_chamber_active", false)),
		"已置位 effect_flag 保持单调，不因新实例断电而撤销。"
	)
	assert_true(
		session.unpowered_effect_flags.has("echo_chamber"),
		"断电的新实例必须被单调巡检记录。"
	)


# ---------------------------------------------------------------- 事件链


func test_event_chain_runs_prologue_and_marks_done() -> void:
	_make_session()
	session.tick()
	assert_eq(session.active_event_id, "event_prologue_landing", "tick 必须启动首个到期事件。")
	assert_true(dialogue.visible, "对话框必须随事件显示。")
	_advance_lines()
	assert_eq(session.active_event_id, "", "台词播完后事件必须结束。")
	assert_false(dialogue.visible, "事件结束后对话框必须隐藏。")
	var snapshot: Dictionary = store.snapshot()
	assert_true(bool((snapshot["flags"] as Dictionary).get("event_event_prologue_landing_done", false)))
	assert_true((snapshot["completed_events"] as Array).has("event_prologue_landing"))


func test_event_chain_choice_applies_flags_world_response_and_completion() -> void:
	_make_session()
	_patch_flags([
		"event_event_prologue_landing_done",
		"event_event_first_mining_done",
		"event_event_first_anchor_done",
		"event_event_workshop_guide_done",
		"echo_chamber_active",
	])
	session.tick()
	assert_eq(session.active_event_id, "event_station_mode", "满足前置时必须推进到驻地抉择事件。")
	_advance_lines()
	var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
	assert_eq(options_box.get_child_count(), 3, "choice 步骤必须生成三个选项按钮。")
	(options_box.get_child(0) as Button).pressed.emit()
	assert_eq(session.active_event_id, "", "选择后事件必须完成。")
	# 暂停编排器避免下一帧 tick 启动后续事件，再等一帧让 queue_free 的选项按钮释放。
	session.set_process(false)
	await get_tree().process_frame
	var snapshot: Dictionary = store.snapshot()
	var flags: Dictionary = snapshot["flags"]
	assert_true(bool(flags.get("station_mode_exploit", false)), "EventRunner 必须置位选项 flag。")
	assert_true(bool(flags.get("world_response_exploited", false)), "Progression.world_response_ops 必须落账。")
	assert_true(
		bool(flags.get("event_event_station_mode_done", false)),
		"完成标记必须使用 EventRunner 的 event_%s_done 模板。"
	)
	assert_true((snapshot["completed_events"] as Array).has("event_station_mode"))


# ---------------------------------------------------------------- 遭遇链


func test_encounter_chain_starts_battle_on_due_flag() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done", "encounter_first_drift_due"])
	session.tick()
	assert_not_null(session.battle, "tick 必须检出到期遭遇并实例化战斗场景。")
	if session.battle != null:
		assert_true(session.battle.is_inside_tree(), "战斗场景必须已挂入模态层。")
		var battle_state: Dictionary = session.battle.battle_state()
		assert_false(battle_state.is_empty(), "begin_encounter 后战斗状态必须非空。")
		assert_gt((battle_state["units"] as Array).size(), 0, "战斗状态必须包含单位。")


func test_encounter_chain_victory_sets_on_victory_flag() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done", "encounter_first_drift_due"])
	session.tick()
	assert_not_null(session.battle)
	_drive_battle()
	assert_null(session.battle, "战斗结束后必须卸载战斗场景。")
	var snapshot: Dictionary = store.snapshot()
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("encounter_first_drift_won", false)),
		"胜利后 on_victory_flag 必须置位。"
	)
	assert_has(snapshot["battle_outcomes"], "encounter_first_drift", "战果必须落账。")


func test_encounter_chain_defeat_unloads_battle_and_keeps_due_flag() -> void:
	_make_session()
	# event_leviathan_pact 与 Boss 遭遇共用 due flag；标记其完成让 tick 直达遭遇链。
	_patch_flags(["event_event_prologue_landing_done", "event_event_leviathan_pact_done", "encounter_leviathan_due"])
	session.tick()
	assert_not_null(session.battle)
	_drive_battle()
	assert_null(session.battle, "战败后同样必须卸载战斗场景。")
	var snapshot: Dictionary = store.snapshot()
	var outcome: Dictionary = (snapshot["battle_outcomes"] as Dictionary).get("encounter_leviathan", {})
	assert_eq(str(outcome.get("result", "")), "defeat", "自动对局对 Boss 应以战败记录。")
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("encounter_leviathan_due", false)),
		"战败后 due flag 必须保留以便重试。"
	)


# ---------------------------------------------------------------- 存档链


func test_save_chain_roundtrips_inventory_and_flags() -> void:
	_make_session()
	var ore_cell := _ore_cell("ore_dust")
	session.request_mine(ore_cell)
	session.request_mine(ore_cell)
	var saved: AppResult = session.save_now()
	assert_true(saved.is_ok, saved.message)
	var loaded: AppResult = SaveService.load_slot(session.save_slot)
	assert_true(loaded.is_ok, loaded.message)
	var fresh: Node = GAME_STATE_SCRIPT.new()
	var restored: AppResult = fresh.restore_snapshot(loaded.value)
	var payload: Dictionary = fresh.snapshot()
	fresh.free()
	assert_true(restored.is_ok, restored.message)
	assert_eq(int((payload["inventory"] as Dictionary).get("starsoil_dust", 0)), 2)
	assert_true(bool((payload["flags"] as Dictionary).get("first_mining_done", false)))
	assert_eq(int((payload["chunk_deltas"][RENDERED_CHUNK_ID] as Array).size()), 1)


func test_ready_restores_autosave_into_fresh_store() -> void:
	_make_session()
	_give_item("starsoil_dust", 3)
	assert_true(session.save_now().is_ok, "预置 auto 槽存档必须成功。")

	var fresh_store: Node = GAME_STATE_SCRIPT.new()
	var fresh_session := GameSession.new()
	fresh_session.store = fresh_store
	fresh_session.world = world
	fresh_session.dialogue_box = dialogue
	add_child_autofree(fresh_session)
	var payload: Dictionary = fresh_store.snapshot()
	fresh_session.free()
	fresh_store.free()
	assert_eq(
		int((payload["inventory"] as Dictionary).get("starsoil_dust", 0)), 3,
		"启动读档流必须把 auto 槽快照 restore 进全新 store。"
	)


# ---------------------------------------------------------------- 主菜单保存与重启链


func test_manual_save_request_persists_manual_slot_and_flashes_notice() -> void:
	var hud := _make_hud()
	_make_session_with_hud(hud)
	_give_item("starsoil_dust", 5)

	hud.save_requested.emit()

	var loaded: AppResult = SaveService.load_slot("manual")
	assert_true(loaded.is_ok, "save_requested 必须经 SaveService 写入 manual 槽。")
	assert_eq(int((loaded.value["inventory"] as Dictionary).get("starsoil_dust", 0)), 5)
	var objective: Label = hud.get_node("ObjectiveLabel") as Label
	assert_eq(objective.text, "已保存", "手动保存后 ObjectiveLabel 必须闪现'已保存'。")
	hud.clear_notice()
	assert_eq(objective.text, Hud.objective_for(store.snapshot()), "提示结束后必须恢复目标文案。")


func test_restart_request_clears_save_slots_and_reloads_scene() -> void:
	var hud := _make_hud()
	_make_session_with_hud(hud)
	_give_item("starsoil_dust", 2)
	assert_true(session.save_now().is_ok, "auto 槽预置存档必须成功。")
	assert_true(SaveService.save_slot("manual", store.snapshot()).is_ok, "manual 槽预置存档必须成功。")
	_reload_spy = SceneReloadSpy.new()
	session.scene_reloader = _reload_spy.reload_current_scene

	hud.restart_requested.emit()

	assert_eq(_reload_spy.calls, 1, "restart_requested 必须触发场景重载。")
	assert_false(SaveService.load_slot(session.save_slot).is_ok, "重启后 auto 槽必须被清空。")
	assert_false(SaveService.load_slot("manual").is_ok, "重启后 manual 槽必须被清空。")
	var reset_snapshot: Dictionary = store.snapshot()
	assert_eq(int(reset_snapshot["revision"]), 0, "重启后持久状态必须归零（W001-P06）。")
	assert_true((reset_snapshot["inventory"] as Dictionary).is_empty(), "重启后背包必须清空。")
	assert_true((reset_snapshot["flags"] as Dictionary).is_empty(), "重启后 flags 必须清空。")
	assert_true(
		(reset_snapshot["applied_patch_sources"] as Array).is_empty(),
		"重启后 applied_patch_sources 必须清空（新鲜约束重新满足）。"
	)


# ---------------------------------------------------------------- 启动屏淡出


func test_startup_screen_fades_out_and_remains_in_tree() -> void:
	var packed := load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "app.tscn must load.")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	add_child_autofree(app)
	var startup: Control = app.get_node_or_null("UILayer/StartupScreen") as Control
	assert_not_null(startup, "UILayer/StartupScreen 必须存在。")
	if startup == null:
		return
	assert_true(startup.visible, "启动屏初始必须可见。")

	app.call("finish_startup_fade")

	assert_false(startup.visible, "淡出完成后启动屏必须隐藏。")
	assert_true(startup.is_inside_tree(), "淡出后启动屏节点必须保留。")
	assert_not_null(
		app.get_node_or_null("UILayer/StartupScreen/Layout/Title"),
		"淡出后启动屏文案必须保留。"
	)


func test_startup_screen_does_not_block_input_during_fade() -> void:
	# 淡出（约 2s）不得阻塞输入：启动屏根与其布局容器都必须 IGNORE 鼠标，
	# 否则全屏 ColorRect / 居中 VBoxContainer 会在淡出窗口期吞掉点击。
	var packed := load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "app.tscn must load.")
	if packed == null:
		return
	var app: Node = packed.instantiate()
	add_child_autofree(app)
	var startup: Control = app.get_node_or_null("UILayer/StartupScreen") as Control
	assert_not_null(startup)
	if startup != null:
		assert_eq(
			startup.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"StartupScreen must ignore mouse input during the fade."
		)
	var layout: Control = app.get_node_or_null("UILayer/StartupScreen/Layout") as Control
	assert_not_null(layout)
	if layout != null:
		assert_eq(
			layout.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"StartupScreen layout must not swallow clicks while fading."
		)


# ---------------------------------------------------------------- 结局链


func test_ending_chain_shows_ending_when_ready_and_quiet() -> void:
	_make_session()
	_patch_flags([
		"station_mode_exploit",
		"encounter_first_drift_won",
		"encounter_husk_ambush_won",
		"encounter_leviathan_won",
		"event_event_prologue_landing_done",
		"event_event_first_mining_done",
		"event_event_first_anchor_done",
		"event_event_workshop_guide_done",
		"event_event_station_mode_done",
		"event_event_approach_done",
		"event_event_policy_done",
		"event_event_leviathan_pact_done",
		"event_event_ending_luoxian_done",
		"event_event_ending_misa_done",
	])
	assert_true(Progression.ending_ready(store.snapshot()), "前置置位后 ending_ready 必须为真。")
	session.tick()
	assert_not_null(session.ending, "结局就绪且无到期事件/战斗时必须实例化结局场景。")
	if session.ending != null:
		assert_true(session.ending.is_inside_tree())
	var title: Label = session.ending.get_node("TitleLabel")
	assert_not_null(title)
	if title != null:
		assert_eq(title.text, "结局：开采纪元", "exploit 路线必须呈现开采纪元结局。")


# ---------------------------------------------------------------- 工具


func _make_world() -> Node2D:
	var packed := load(WORLD_SCENE_PATH) as PackedScene
	var world_node := packed.instantiate() as Node2D
	world_node.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world_node)
	return world_node


func _make_dialogue() -> DialogueBox:
	var packed := load(DIALOGUE_SCENE_PATH) as PackedScene
	var box := packed.instantiate() as DialogueBox
	add_child_autofree(box)
	return box


func _make_session() -> void:
	session = GameSession.new()
	session.store = store
	session.world = world
	session.dialogue_box = dialogue
	add_child_autofree(session)


func _make_hud() -> Hud:
	var packed := load("res://scenes/ui_hud.tscn") as PackedScene
	var hud := packed.instantiate() as Hud
	hud.snapshot_provider = Callable(store, "snapshot")
	add_child_autofree(hud)
	return hud


func _make_session_with_hud(hud: Hud) -> void:
	session = GameSession.new()
	session.store = store
	session.world = world
	session.dialogue_box = dialogue
	session.hud = hud
	add_child_autofree(session)


func _place_at(building_id: String, cell: Vector2i) -> AppResult:
	assert_true(
		session.select_building(building_id),
		"select_building(%s) must succeed." % building_id
	)
	return session.request_place(cell)


func _preplace_building(building_id: String, cell: Vector2i) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch(
		"test_wp05_preplace_%s_%d" % [building_id, revision], revision
	)
	patch.place_building(building_id, RENDERED_CHUNK_ID, cell.x, cell.y)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _total_definition_count() -> int:
	var total: int = 0
	for kind: String in ["item", "building", "combat_unit", "combat_action", "event", "encounter"]:
		total += ContentDB.ids_of(kind).size()
	return total


func _ore_cell(ore_type: String) -> Vector2i:
	var cells: Dictionary = ChunkData.generate(RENDERED_CHUNK_ID, 0)["cells"]
	for cell: Vector2i in cells:
		if cells[cell] == ore_type:
			return cell
	fail_test("generated chunk has no %s cell." % ore_type)
	return Vector2i(-1, -1)


func _soil_cell() -> Vector2i:
	var cells: Dictionary = ChunkData.generate(RENDERED_CHUNK_ID, 0)["cells"]
	for y: int in 32:
		for x: int in 32:
			if not cells.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(31, 31)


func _has_destroyed_delta(deltas: Array, cell: Vector2i) -> bool:
	for delta_value: Variant in deltas:
		var delta := delta_value as Dictionary
		if delta == null:
			continue
		if int(delta.get("cell_x", -1)) == cell.x and int(delta.get("cell_y", -1)) == cell.y:
			return bool(delta.get("destroyed", false))
	return false


func _has_building(snapshot: Dictionary, building_id: String, cell: Vector2i) -> bool:
	for building_value: Variant in snapshot.get("placed_buildings", []):
		var building := building_value as Dictionary
		if building == null:
			continue
		if (
			str(building.get("building_id", "")) == building_id
			and int(building.get("cell_x", -1)) == cell.x
			and int(building.get("cell_y", -1)) == cell.y
		):
			return true
	return false


func _give_item(item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_wp04_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _patch_flags(flag_ids: Array) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_wp04_flags_%d" % revision, revision)
	for flag_id: String in flag_ids:
		patch.set_flag(flag_id, true)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _advance_lines(max_steps: int = 24) -> void:
	var guard := 0
	while is_instance_valid(session) and session.active_event_id != "" and dialogue.visible and guard < max_steps:
		var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
		if options_box.get_child_count() > 0:
			break
		dialogue.call("_advance")
		guard += 1


func _drive_battle() -> void:
	var guard := 0
	while session.battle != null and guard < MAX_BATTLE_GUARD:
		var battle_state: Dictionary = session.battle.battle_state()
		if bool(battle_state.get("finished", false)):
			break
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(battle_state)
		if active.is_empty() or str(active.get("side", "")) != "ally":
			break
		session.battle.play_ally_action(_deterministic_action(battle_state, active))
		guard += 1


func _deterministic_action(battle_state: Dictionary, active: Dictionary) -> String:
	var action_defs: Dictionary = battle_state.get("action_defs", {})
	var fallback := ""
	for action_id: String in active.get("action_ids", []):
		var action: Dictionary = action_defs.get(action_id, {})
		if action.is_empty():
			continue
		if fallback == "":
			fallback = action_id
		if int(action.get("power", 0)) > 0:
			return action_id
	return fallback
