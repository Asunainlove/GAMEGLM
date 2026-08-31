extends GutTest

## W002-GAP2 集成测试：矿井/Boss 区触发链（app 层 GameSession 编排）。
##
## 覆盖：
## - 玩家格首次进入 chunk_3_1 → tick 触发 event_mine_threshold（既有事件展示
##   路径），完成后 mine_entered + encounter_leviathan_due + done 标记齐备；
## - chunk_2_1 侧不触发、done 后不重播（幂等）；
## - rock_wall 采集拒绝（not_mineable）与建造拒绝（rock_wall_cell）；
## - 走廊矿格跨 chunk 采集链完整（产出 + destroyed delta）；
## - 进入 Boss 房区域（世界格 y >= 54）记录既有 set_player_position 检查点。

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"

const MINE_CHUNK_ID: String = "chunk_3_1"
const MINE_ORIGIN: Vector2i = Vector2i(96, 32)

## 每个 before_each 生成互不重用的存档根，杜绝自动读档串场。
static var _save_root_seq: int = 0

var store: Node
var world: Node2D
var dialogue: DialogueBox
var session: GameSession


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap 必须成功：%s" % boot.message)
	_save_root_seq += 1
	var save_root: String = "user://saves_gap2_mine_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
	assert_true(SaveService.configure_root_for_tests(save_root).is_ok)
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


# --------------------------------------------------------------- 矿井入口触发链


func test_mine_threshold_event_does_not_trigger_outside_mine_chunk() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done"])
	_set_player_cell(Vector2i(95, 40))
	session.tick()
	assert_eq(
		session.active_event_id, "",
		"玩家仍在 chunk_2_1（x<96）时不得触发矿井事件。"
	)
	assert_false(
		bool((store.snapshot()["flags"] as Dictionary).get("mine_entered", false)),
		"未进入矿井不得置位 mine_entered。"
	)


func test_mine_threshold_event_triggers_on_entry_and_sets_all_flags() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done"])
	_set_player_cell(Vector2i(100, 40))
	session.tick()
	assert_eq(
		session.active_event_id, "event_mine_threshold",
		"首次进入 chunk_3_1 必须经既有事件链展示 event_mine_threshold。"
	)
	assert_true(dialogue.visible, "矿井事件必须驱动对话框。")
	_advance_lines()
	assert_eq(session.active_event_id, "", "台词与 effect 步骤播完后事件必须结束。")

	var snapshot: Dictionary = store.snapshot()
	var flags: Dictionary = snapshot["flags"]
	assert_true(bool(flags.get("mine_entered", false)), "effect 步骤必须置位 mine_entered。")
	assert_true(
		bool(flags.get("encounter_leviathan_due", false)),
		"due_encounter 语义必须置位 encounter_leviathan_due（Boss 遭遇到期）。"
	)
	assert_true(
		bool(flags.get("event_event_mine_threshold_done", false)),
		"完成标记必须使用 event_%s_done 模板。"
	)
	assert_has(snapshot["completed_events"], "event_mine_threshold")


func test_mine_threshold_event_fires_once_only() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done", "mine_entered", "event_event_mine_threshold_done"])
	_set_player_cell(Vector2i(100, 40))
	session.tick()
	assert_eq(session.active_event_id, "", "mine_entered/done 已置位时不得重播矿井事件。")
	assert_null(session.battle, "无到期遭遇时不得启动战斗。")


# --------------------------------------------------------------- rock_wall 采集与建造


func test_rock_wall_cell_rejects_mining() -> void:
	_make_session()
	var wall_cell := MINE_ORIGIN + Vector2i(0, 7)
	var result: AppResult = session.request_mine(wall_cell)
	assert_false(result.is_ok, "rock_wall 必须不可采。")
	assert_eq(result.code, "not_mineable", "hardness 0 的岩壁采集必须返回 not_mineable。")
	assert_eq(
		int(store.snapshot()["revision"]), 0,
		"拒绝采集不得推进 revision。"
	)


func test_rock_wall_cell_rejects_building() -> void:
	_make_session()
	_give_item("starsoil_dust", 4)
	var revision_before: int = int(store.snapshot()["revision"])
	assert_true(session.select_building("anchor_block"), "前置：anchor_block 必须可选。")
	var wall_cell := MINE_ORIGIN + Vector2i(0, 7)
	var result: AppResult = session.request_place(wall_cell)
	assert_false(result.is_ok, "rock_wall 必须不可建。")
	assert_eq(result.code, "rock_wall_cell")
	var snapshot: Dictionary = store.snapshot()
	assert_eq(int(snapshot["revision"]), revision_before, "拒绝建造不得推进 revision。")
	assert_true((snapshot["placed_buildings"] as Array).is_empty(), "拒绝建造不得留下建筑。")
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("starsoil_dust", 0)), 4,
		"拒绝建造不得扣材料。"
	)


func test_corridor_ore_mines_with_full_chain() -> void:
	_make_session()
	var ore_cell := MINE_ORIGIN + Vector2i(3, 8)
	var first: AppResult = session.request_mine(ore_cell)
	assert_true(first.is_ok, "走廊尘矿第一次敲击必须成功：%s" % first.message)
	var second: AppResult = session.request_mine(ore_cell)
	assert_true(second.is_ok, "走廊尘矿第二次敲击必须耗尽：%s" % second.message)

	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("starsoil_dust", 0)), 2,
		"走廊矿必须产出星壤尘。"
	)
	assert_true(
		_has_destroyed_delta((snapshot["chunk_deltas"] as Dictionary).get(MINE_CHUNK_ID, []), ore_cell),
		"chunk_deltas[chunk_3_1] 必须以世界格坐标记录 destroyed。"
	)
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("first_mining_done", false)),
		"矿井采集与既有 Progression.react(mined) 链路保持兼容。"
	)


# --------------------------------------------------------------- Boss 房检查点


func test_boss_room_entry_checkpoints_player_position() -> void:
	_make_session()
	_patch_flags(["event_event_prologue_landing_done", "mine_entered", "event_event_mine_threshold_done"])
	_set_player_cell(Vector2i(110, 53))
	session.tick()
	assert_eq(
		(store.snapshot()["player"] as Dictionary).get("position", {}),
		{"x": 0, "y": 0},
		"矿脉腔内（y<54）不得触发 Boss 房检查点（位置保持初始值）。"
	)
	_set_player_cell(Vector2i(110, 55))
	session.tick()
	assert_eq(
		(store.snapshot()["player"] as Dictionary).get("position", {}),
		{"x": 110, "y": 55},
		"进入 Boss 房区域（世界格 y>=54）必须经 set_player_position 落账玩家格。"
	)
	# 幂等：原地再次 tick 不得报错，位置保持。
	session.tick()
	assert_eq(
		(store.snapshot()["player"] as Dictionary).get("position", {}),
		{"x": 110, "y": 55},
		"重复 tick 不得破坏 Boss 房检查点。"
	)


# --------------------------------------------------------------- 工具


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


func _set_player_cell(cell: Vector2i) -> void:
	var player_node: Node2D = session.player as Node2D
	assert_not_null(player_node, "session 必须绑定 world 内的 player。")
	if player_node != null:
		player_node.position = Vector2(cell) * 32.0


func _patch_flags(flag_ids: Array) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_gap2_flags_%d" % revision, revision)
	for flag_id: String in flag_ids:
		patch.set_flag(flag_id, true)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _give_item(item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_gap2_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _has_destroyed_delta(deltas: Array, cell: Vector2i) -> bool:
	for delta_value: Variant in deltas:
		var delta := delta_value as Dictionary
		if delta == null:
			continue
		if int(delta.get("cell_x", -1)) == cell.x and int(delta.get("cell_y", -1)) == cell.y:
			return bool(delta.get("destroyed", false))
	return false


func _advance_lines(max_steps: int = 24) -> void:
	var guard := 0
	while is_instance_valid(session) and session.active_event_id != "" and dialogue.visible and guard < max_steps:
		var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
		if options_box.get_child_count() > 0:
			break
		dialogue.call("_advance")
		guard += 1
