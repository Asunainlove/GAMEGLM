extends GutTest

## DLX-3 集成层测试：建筑热键泛化 + 提示触发表驱动（任务 2/3 会话侧）。
##
## 热键泛化（任务 2.3）：BUILDING_HOTBAR_SIZE 常量退役，热键上限改为
## min(max(6, 建筑定义数), 9)——数字键 1-9 为备用键位上限；>6 建筑时第 7 个
## 建筑可用数字键选中（经 building_ids_provider 注入模拟 7 定义目录）。
## 提示触发（任务 2.2）：game_session 保留触发点调用，触发条件与文案读
## data/progression/hints.json；放置提示的"数字键 1-N"按实际热键数生成，
## 6 建筑场景输出与迁移前逐字节一致。

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"

## 每个 before_each 生成互不重用的存档根：GameSession._ready 会尝试读 auto 槽
##（W000-P04 读档链），共享 user:// 存档会让残留存档的 hint_*_seen 等 flag
## 提前置位，提示触发点被去重跳过（与 test_integration.gd 同一隔离口径）。
static var _save_root_seq: int = 0

var store: Node
var world: Node2D
var dialogue: DialogueBox
var session: GameSession
var hud: Hud


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap must succeed: %s" % boot.message)
	_save_root_seq += 1
	var save_root: String = "user://saves_dlx3_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
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
	if is_instance_valid(hud):
		hud.free()
	session = null
	world = null
	dialogue = null
	store = null
	hud = null


# ---------------------------------------------------------------- 热键泛化


func test_hotbar_size_bounds() -> void:
	# 下限 6（既有 6 建筑布局承诺），上限 9（备用数字键 1-9）。
	assert_eq(GameSession.hotbar_size_for(0), 6, "未引导/空目录时下限 6。")
	assert_eq(GameSession.hotbar_size_for(6), 6, "6 建筑时与迁移前一致。")
	assert_eq(GameSession.hotbar_size_for(7), 7, "第 7 个建筑必须获得热键。")
	assert_eq(GameSession.hotbar_size_for(9), 9)
	assert_eq(GameSession.hotbar_size_for(12), 9, "数字键 1-9 为上限。")


func _key_event(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	return key


func test_hotbar_selects_seventh_building_when_catalog_grows() -> void:
	_make_session_with_hud()
	# 注入 7 建筑目录（第 7 位复用真实定义 dust_refiner，select_building 可成功）。
	var ids: Array[String] = ContentDB.ids_of("building")
	assert_eq(ids.size(), 6, "前置：生产目录为 6 建筑。")
	var grown: Array[String] = ids.duplicate()
	grown.append("dust_refiner")
	var provider_host := CatalogHost.new()
	provider_host.ids = grown
	session.building_ids_provider = provider_host.building_ids

	session._unhandled_input(_key_event(KEY_7))
	assert_eq(
		session.selected_building_id, "dust_refiner",
		">6 建筑时第 7 个建筑必须可用数字键 7 选中。"
	)

	session._unhandled_input(_key_event(KEY_0))
	assert_eq(session.selected_building_id, "dust_refiner", "数字键 0 不在热键范围。")


func test_hotbar_keeps_six_building_behavior_with_default_catalog() -> void:
	_make_session_with_hud()
	session._unhandled_input(_key_event(KEY_1))
	assert_eq(session.selected_building_id, "anchor_block", "数字键 1 选中目录第 1 建筑（迁移前行为）。")
	# 目录按字母序：anchor_block(1), anchor_workshop(2), dust_refiner(3),
	# echo_chamber(4), resonance_loom(5), stabilizer_pylon(6)。
	session._unhandled_input(_key_event(KEY_6))
	assert_eq(session.selected_building_id, "stabilizer_pylon", "数字键 6 选中目录第 6 建筑（迁移前行为）。")
	session._unhandled_input(_key_event(KEY_7))
	assert_eq(
		session.selected_building_id, "stabilizer_pylon",
		"6 建筑目录下数字键 7 必须被忽略（与迁移前一致）。"
	)


class CatalogHost:
	var ids: Array[String] = []

	func building_ids() -> Array[String]:
		return ids


# ---------------------------------------------------------------- 提示触发表驱动


func test_place_hint_text_is_templated_by_hotkey_count() -> void:
	_make_session_with_hud()
	assert_true(session.select_building("anchor_workshop"), "select_building 必须成功。")
	# 文案与触发条件读提示表；"数字键 1-N" 按实际热键数生成（6 建筑场景 N=6，
	# 输出与迁移前逐字节一致）。
	assert_eq(
		_hint_label().text, "右键/F 放置 锚居工坊 · 数字键 1-6 切换建筑",
		"放置提示必须由模板按建筑名与热键数生成。"
	)
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("hint_place_seen", false)),
		"落账机制不变：hint_place_seen 经回调落账。"
	)


func test_boot_hint_text_reads_hints_table() -> void:
	_make_session_with_hud()
	session._show_move_hint_if_due()
	assert_eq(
		_hint_label().text, Hud.hint_text("move"),
		"开局总提示文案必须读提示表。"
	)
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("hint_move_seen", false)),
		"落账机制不变：hint_move_seen 经回调落账。"
	)


func test_craft_failed_hint_reads_hints_table() -> void:
	_make_session_with_hud()
	# 背包默认为空：放置即材料不足，无需预置扣减。
	var soil_cell := _soil_cell()
	var result: AppResult = session.request_place(soil_cell)
	assert_false(result.is_ok, "材料不足建造必须失败。")
	assert_eq(result.code, "insufficient_item")
	assert_eq(_hint_label().text, Hud.hint_text("craft"), "合成提示文案必须读提示表。")
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("hint_craft_seen", false)),
		"落账机制不变：hint_craft_seen 经回调落账。"
	)


func test_mine_entered_hint_reads_hints_table() -> void:
	_make_session_with_hud()
	_patch_flags(["event_event_prologue_landing_done", "mine_entered"])
	session.tick()
	assert_eq(_hint_label().text, Hud.hint_text("mine"), "矿井提示文案必须读提示表。")
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("hint_mine_seen", false)),
		"落账机制不变：hint_mine_seen 经回调落账。"
	)


func test_encounter_start_hint_reads_hints_table() -> void:
	_make_session_with_hud()
	_patch_flags(["event_event_prologue_landing_done", "encounter_first_drift_due"])
	session.tick()
	assert_not_null(session.battle, "到期遭遇必须照常开战。")
	assert_eq(_hint_label().text, Hud.hint_text("battle"), "战斗提示文案必须读提示表。")
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("hint_battle_seen", false)),
		"落账机制不变：hint_battle_seen 经回调落账。"
	)


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


func _make_hud() -> Hud:
	var packed := load("res://scenes/ui_hud.tscn") as PackedScene
	var hud_node := packed.instantiate() as Hud
	hud_node.snapshot_provider = Callable(store, "snapshot")
	add_child_autofree(hud_node)
	return hud_node


func _make_session_with_hud() -> void:
	hud = _make_hud()
	session = GameSession.new()
	session.store = store
	session.world = world
	session.dialogue_box = dialogue
	session.hud = hud
	add_child_autofree(session)


func _hint_label() -> Label:
	return hud.get_node("HintToast/HintLabel") as Label


func _soil_cell() -> Vector2i:
	var cells: Dictionary = ChunkData.generate("chunk_0_0", 0)["cells"]
	for y: int in 32:
		for x: int in 32:
			if not cells.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(31, 31)


func _give_item(item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_dlx3_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	assert_true(store.commit(patch).is_ok)


func _patch_flags(flag_ids: Array) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_dlx3_flags_%d" % revision, revision)
	for flag_id: String in flag_ids:
		patch.set_flag(flag_id, true)
	assert_true(store.commit(patch).is_ok)
