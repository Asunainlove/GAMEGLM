extends GutTest

## DLX-4 任务 2：echo_seed（余辉之种）死内容激活——时序裁决与集成闭环测试。
##
## 裁决（PM 计划 DLX-4）：回响舱激活需要余辉之种——回响舱是共鸣结局的枢纽，
## 种是枢纽钥匙。落地：
## - items.json：echo_seed 增加 "story_key": true 声明字段（死内容哨兵）；
## - buildings.json：echo_chamber inputs 增加 echo_seed×1（放置即消耗，
##   BuildingRules 既有 inputs 语义自动生效，零代码）；
## - event_leviathan_pact.json：Boss 战前对话追加 effect grant_items
##   echo_seed×1（剧情：弥砂在矿腔深处找到种子）——时序走查：矿井入口事件
##   （event_mine_threshold）置 encounter_leviathan_due 后，game_session.tick
##   先于遭遇检查驱动 due_event 链，event_leviathan_pact_pre →
##   event_leviathan_pact 依次完成，种子在 Boss 遭遇开始前入账；
##   Boss 掉落（combat_units.json lumen_leviathan drops）保留，构成双渠道。
##
## 隔离口径与 test_integration.gd 相同：注入独立 GameState 实例 + 独立存档根。

const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const EVENT_RUNNER_SCRIPT: Script = preload("res://src/narrative/event_runner.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"
const PACT_EVENT_ID: String = "event_leviathan_pact"

static var _save_root_seq: int = 0

var store: Node
var world: Node2D
var dialogue: DialogueBox
var session: GameSession
var _save_root: String = ""


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap must succeed: %s" % boot.message)
	_save_root_seq += 1
	_save_root = "user://saves_dlx4_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
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


func _make_world() -> Node2D:
	var packed := load(WORLD_SCENE_PATH) as PackedScene
	var world_node := packed.instantiate() as Node2D
	world_node.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world_node)
	return world_node


func _make_dialogue() -> DialogueBox:
	var packed := load(DIALOGUE_SCENE_PATH) as PackedScene
	return packed.instantiate() as DialogueBox


func _make_session() -> void:
	session = GameSession.new()
	session.store = store
	session.world = world
	session.dialogue_box = dialogue
	add_child_autofree(session)


func _give_item(item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_dlx4_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _complete_event(event_id: String) -> void:
	# 与生产同通道：EventRunner.complete_event 置 event_<id>_done flag
	#（StatePatch.complete_event 只记账 completed_events，不置 done flag）。
	var runner := EventRunner.new()
	var result: AppResult = runner.complete_event(event_id, store)
	assert_true(result.is_ok, result.message)


func _place_at(building_id: String, cell: Vector2i) -> AppResult:
	assert_true(
		session.select_building(building_id),
		"select_building(%s) must succeed." % building_id
	)
	return session.request_place(cell)


# ---------------------------------------------------------------- 数据契约


func test_content_bootstrap_accepts_story_key_and_seed_input() -> void:
	# 前置：ContentDB 在本文件首个测试中 bootstrap（或复用既有引导），数据侧
	# 新字段/新输入必须通过整包校验——否则下面任何 get_* 都无从谈起。
	assert_true(ContentDB.is_bootstrapped(), "ContentDB must be bootstrapped.")
	var seed_def: Dictionary = ContentDB.get_item("echo_seed")
	assert_true(
		bool(seed_def.get("story_key", false)),
		"echo_seed 必须声明 story_key（死内容哨兵字段）。"
	)
	var chamber_def: Dictionary = ContentDB.get_building("echo_chamber")
	var has_seed_input := false
	for input_entry: Dictionary in chamber_def.get("inputs", []):
		if str(input_entry.get("item_id", "")) == "echo_seed" and int(input_entry.get("count", 0)) >= 1:
			has_seed_input = true
	assert_true(has_seed_input, "回响舱 inputs 必须包含 echo_seed×1（放置即消耗）。")


func test_boss_drop_channel_is_preserved() -> void:
	var leviathan: Dictionary = ContentDB.get_combat_unit("lumen_leviathan")
	var drops: Array = leviathan.get("drops", [])
	var has_seed_drop := false
	for drop: Dictionary in drops:
		if str(drop.get("item_id", "")) == "echo_seed" and int(drop.get("amount", 0)) >= 1:
			has_seed_drop = true
	assert_true(has_seed_drop, "Boss 掉落渠道必须保留（双渠道裁决的另一半）。")


# ---------------------------------------------------------------- 时序裁决：pact 先于 Boss 授予种子


func _pact_grant_step() -> Dictionary:
	var event_def: Dictionary = ContentDB.get_event(PACT_EVENT_ID)
	if event_def.is_empty():
		return {}
	for step_value: Variant in event_def.get("steps", []):
		var step := step_value as Dictionary
		if step == null or String(step.get("type", "")) != "effect":
			continue
		for grant: Dictionary in step.get("grant_items", []):
			if str(grant.get("item_id", "")) == "echo_seed":
				return step
	return {}


func test_pact_event_grants_echo_seed_via_effect_step() -> void:
	var event_def: Dictionary = ContentDB.get_event(PACT_EVENT_ID)
	assert_eq(
		String(event_def.get("requires_flag", "")), "encounter_leviathan_due",
		"pact 事件必须挂在 encounter_leviathan_due（矿井入口置位，先于 Boss 遭遇检查）。"
	)
	var step: Dictionary = _pact_grant_step()
	assert_false(step.is_empty(), "event_leviathan_pact 必须携带 grant_items echo_seed 的 effect 步骤。")
	if step.is_empty():
		return
	var result: AppResult = EventRunner.new().apply_effect_step(PACT_EVENT_ID, step, store)
	assert_true(result.is_ok, "pact effect 步骤必须可提交：%s" % result.message)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("echo_seed", 0)), 1,
		"pact 事件完成后余辉之种必须入账（Boss 战前）。"
	)


# ---------------------------------------------------------------- 建造链：无种建不了舱，有种建舱消耗


func test_echo_chamber_cannot_be_built_without_echo_seed() -> void:
	_make_session()
	_give_item("starsoil_dust", 6)
	_give_item("resonant_core", 2)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	var revision_before := int(store.snapshot()["revision"])
	var result: AppResult = _place_at("echo_chamber", Vector2i(20, 22))
	assert_false(result.is_ok, "缺少余辉之种时回响舱必须建造失败。")
	assert_eq(result.code, "insufficient_item", "失败原因必须是材料不足。")
	assert_eq(int(store.snapshot()["revision"]), revision_before, "失败建造不得推进 revision。")


func test_echo_chamber_consumes_echo_seed_on_placement() -> void:
	_make_session()
	_give_item("starsoil_dust", 6)
	_give_item("resonant_core", 2)
	_give_item("echo_seed", 1)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("echo_chamber", Vector2i(20, 22)).is_ok)
	var snapshot: Dictionary = store.snapshot()
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("echo_seed", 0)), 0,
		"放置回响舱必须消耗余辉之种（inputs 语义）。"
	)
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("resonant_core", 0)), 0,
		"放置回响舱必须消耗共鸣核。"
	)
	assert_true(
		bool((snapshot["flags"] as Dictionary).get("echo_chamber_active", false)),
		"工坊供电充足且成房间时回响舱必须置位 echo_chamber_active。"
	)


# ---------------------------------------------------------------- 时序闭环：pact 授种 → 建舱 → station_mode 链可推进


func test_pact_seed_enables_chamber_and_station_mode_chain() -> void:
	_make_session()
	# 1. Boss 战前对话（event_leviathan_pact）的 effect 步骤经生产通道授予种子。
	var step: Dictionary = _pact_grant_step()
	assert_false(step.is_empty(), "前置：pact 事件必须携带 grant_items 步骤。")
	var grant: AppResult = EventRunner.new().apply_effect_step(PACT_EVENT_ID, step, store)
	assert_true(grant.is_ok, grant.message)
	# 2. 备齐其余材料并建成供电充足的回响舱。
	_give_item("starsoil_dust", 6)
	_give_item("resonant_core", 2)
	var anchor_result: AppResult = _place_at("anchor_block", Vector2i(20, 20))
	assert_true(anchor_result.is_ok, "anchor_block 放置：%s" % anchor_result.message)
	var workshop_result: AppResult = _place_at("anchor_workshop", Vector2i(20, 21))
	assert_true(workshop_result.is_ok, "anchor_workshop 放置：%s" % workshop_result.message)
	var chamber_result: AppResult = _place_at("echo_chamber", Vector2i(20, 22))
	assert_true(chamber_result.is_ok, "echo_chamber 放置：%s" % chamber_result.message)
	assert_true(
		bool((store.snapshot()["flags"] as Dictionary).get("echo_chamber_active", false)),
		"回响舱激活是 station_mode 链的唯一前置。"
	)
	# 3. 链前事件标记完成（链是优先级序：done/blocked 不阻塞后位）。其中
	# first_anchor/workshop_guide/misa_campfire 是本次真实建造链解锁的事件，
	# 生产流程中玩家会先走完它们；测试按同一顺序标记完成。
	_complete_event("event_prologue_landing")
	_complete_event("event_first_anchor")
	_complete_event("event_workshop_guide")
	_complete_event("event_misa_campfire")
	# 4. due_event 必须指向矿站抉择事件——station_mode 链可推进。
	assert_eq(
		Progression.due_event(store.snapshot()), "event_station_mode",
		"种子 → 建舱 → 激活后，事件链必须推进到 event_station_mode。"
	)
