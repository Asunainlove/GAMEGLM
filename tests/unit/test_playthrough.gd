extends GutTest

## G7P-1 全循环自动化通关测试：headless 驱动完整垂直切片闭环
## （勘探→采集→建造→精炼→三场战斗→三次选择→三结局→存读档）。
## 三条路线分别锁定 ending_mining / ending_seal / ending_symbiosis 可达性。

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")
const RELATIONS_SCRIPT: Script = preload("res://src/relations/relations.gd")

const RENDERED_CHUNK_ID: String = "chunk_0_0"
const MAX_PUMP_TICKS: int = 3000
const MAX_BATTLE_GUARD: int = 240

var store: Node
var world: Node2D
var dialogue: DialogueBox
var session: GameSession
var profile_for_test: Dictionary = {}
var _used_cells: Array[Vector2i] = []
var _save_root_seq: int = 0
var _save_root: String = ""


func before_each() -> void:
	if not ContentDB.is_bootstrapped():
		var boot: AppResult = ContentDB.bootstrap()
		assert_true(boot.is_ok, "ContentDB bootstrap must succeed: %s" % boot.message)
	_save_root_seq += 1
	_save_root = "user://saves_g7p1_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
	assert_true(SaveService.configure_root_for_tests(_save_root).is_ok)
	store = GAME_STATE_SCRIPT.new()
	world = _make_world()
	dialogue = _make_dialogue()
	_used_cells = []
	profile_for_test = {}


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


# ---------------------------------------------------------------- 场景构造

func _make_world() -> Node2D:
	var packed: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	var world_node: Node2D = packed.instantiate() as Node2D
	world_node.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world_node)
	return world_node


func _make_dialogue() -> DialogueBox:
	var packed: PackedScene = load(DIALOGUE_SCENE_PATH) as PackedScene
	var box: DialogueBox = packed.instantiate() as DialogueBox
	add_child_autofree(box)
	return box


func _make_session() -> void:
	session = GameSession.new()
	session.store = store
	session.world = world
	session.dialogue_box = dialogue
	add_child_autofree(session)


# ---------------------------------------------------------------- 驱动手法

func _snapshot() -> Dictionary:
	return store.snapshot()


func _flags() -> Dictionary:
	return _snapshot()["flags"] as Dictionary


func _inv_count(item_id: String) -> int:
	return int((_snapshot()["inventory"] as Dictionary).get(item_id, 0))


## 取一个未被使用过的矿格（跨测试阶段去重，避免重复采已破坏格）。
func _ore_cell(ore_type: String) -> Vector2i:
	var cells: Dictionary = ChunkData.generate(RENDERED_CHUNK_ID, 0)["cells"]
	for cell: Vector2i in cells:
		if cells[cell] != ore_type or _used_cells.has(cell):
			continue
		_used_cells.append(cell)
		return cell
	fail_test("chunk has no unused %s cell." % ore_type)
	return Vector2i(-1, -1)


func _mine_cell(ore_type: String, hits: int) -> void:
	var cell: Vector2i = _ore_cell(ore_type)
	for _i: int in hits:
		var result: AppResult = session.request_mine(cell)
		if not result.is_ok:
			fail_test("mine %s hit %d: %s" % [cell, _i, result.message])
			return


func _place_building(building_id: String, cell: Vector2i) -> void:
	assert_true(session.select_building(building_id), "select %s" % building_id)
	var result: AppResult = session.request_place(cell)
	assert_true(result.is_ok, "place %s: %s" % [building_id, result.message])


func _advance_lines(max_steps: int = 40) -> void:
	var guard: int = 0
	while is_instance_valid(session) and session.active_event_id != "" and dialogue.visible and guard < max_steps:
		var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
		if options_box.get_child_count() > 0:
			break
		dialogue.call("_advance")
		guard += 1


## 按 choice_id + 期望选项 flag/id 在 OptionsBox 中按下对应按钮。
func _choose(choice_id: String, option_key: String) -> bool:
	var step: Dictionary = session._active_choice_step
	if step.is_empty() or str(step.get("choice_id", "")) != choice_id:
		return false
	var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
	var options: Array = step.get("options", [])
	for index: int in options.size():
		var option: Dictionary = options[index]
		if str(option.get("set_flag", "")) == option_key or str(option.get("id", "")) == option_key:
			var button: Button = options_box.get_child(index) as Button
			if button != null and not button.disabled:
				button.pressed.emit()
				return true
	return false


## 智能战斗驱动：濒死治疗 → 道具陷阱 → 失稳脉冲 → 首个有伤行动。
func _drive_battle_smart() -> void:
	var guard: int = 0
	while session.battle != null and is_instance_valid(session.battle) and guard < MAX_BATTLE_GUARD:
		var battle_state: Dictionary = session.battle.battle_state()
		if bool(battle_state.get("finished", false)):
			break
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(battle_state)
		if active.is_empty() or str(active.get("side", "")) != "ally":
			break
		session.battle.play_ally_action(_pick_action(battle_state, active))
		guard += 1


func _pick_action(battle_state: Dictionary, active: Dictionary) -> String:
	var action_defs: Dictionary = battle_state.get("action_defs", {})
	var lowest_ratio: float = 1.0
	for unit_value: Variant in battle_state.get("units", []):
		var unit: Dictionary = unit_value as Dictionary
		if unit == null or str(unit.get("side", "")) != "ally" or not bool(unit.get("alive", false)):
			continue
		var max_hp: int = maxi(1, int(unit.get("max_hp", 1)))
		lowest_ratio = minf(lowest_ratio, float(int(unit.get("hp", max_hp))) / float(max_hp))
	var items: Dictionary = active.get("items", {})
	var action_ids: Array = active.get("action_ids", [])

	if lowest_ratio < 0.5 and int(items.get("sedative_mist", 0)) > 0 and action_ids.has("mist_calm"):
		return "mist_calm"
	if int(items.get("shock_trap", 0)) > 0 and action_ids.has("trap_snap"):
		return "trap_snap"
	if action_ids.has("resonate_pulse"):
		return "resonate_pulse"
	for action_id: String in action_ids:
		if int((action_defs.get(action_id, {}) as Dictionary).get("power", 0)) > 0:
			return action_id
	for action_id: String in action_ids:
		return action_id
	return ""


## 推进循环：tick + 对话/选择 + 战斗，直到谓词满足或预算耗尽。
func _advance_until(predicate: Callable, max_ticks: int = MAX_PUMP_TICKS) -> Dictionary:
	var ticks: int = 0
	var diag: String = ""
	while ticks < max_ticks:
		if predicate.call():
			return {"ok": true, "ticks": ticks}
		session.tick()
		ticks += 1
		if session.active_event_id != "" and is_instance_valid(dialogue) and dialogue.visible:
			var options_box: VBoxContainer = dialogue.get_node("Panel/OptionsBox")
			if options_box.get_child_count() > 0:
				var step: Dictionary = session._active_choice_step
				var choice_id: String = str(step.get("choice_id", ""))
				var wanted: String = str(profile_for_test.get(choice_id, ""))
				if wanted != "":
					if not _choose(choice_id, wanted):
						diag = "choice %s/%s blocked" % [choice_id, wanted]
						break
				else:
					var button: Button = options_box.get_child(0) as Button
					if button != null and not button.disabled:
						button.pressed.emit()
			else:
				dialogue.call("_advance")
		if session.battle != null and is_instance_valid(session.battle):
			_drive_battle_smart()
	if diag == "":
		diag = "flags=%s inv=%s rev=%d event=%s battle=%s" % [
			str(_flags().keys()), str((_snapshot()["inventory"] as Dictionary)),
			int(_snapshot()["revision"]), session.active_event_id, str(session.battle != null),
		]
	return {"ok": false, "ticks": ticks, "diag": diag}


func _until(predicate: Callable) -> Dictionary:
	return _advance_until(predicate, MAX_PUMP_TICKS)


# ---------------------------------------------------------------- 阶段编排

func _flag_when(flag_id: String) -> Callable:
	return func() -> bool:
		return bool(_flags().get(flag_id, false))


## 采集+建造主干：锚块(2,2)/工坊(3,3)成 4 连通房间，供回响舱（requires_room）供电。
func _stage_mine_and_build() -> void:
	_mine_cell("ore_dust", 2)
	assert_eq(_inv_count("starsoil_dust"), 2, "one dust cell yields 2.")
	_place_building("anchor_block", Vector2i(3, 2))
	_mine_cell("ore_dust", 2)
	_mine_cell("ore_dust", 2)
	_place_building("anchor_workshop", Vector2i(3, 3))


## 种子到位后建回响舱（2 核 + 种子）并确认供电置位。
func _stage_chamber() -> void:
	_mine_cell("ore_shard", 3)
	_mine_cell("ore_core", 4)
	_mine_cell("ore_core", 4)
	_place_building("echo_chamber", Vector2i(3, 4))


## 织机 + 合成 2 瓶定神雾（1 核入 + 4 晶片）。
func _stage_craft_mist() -> void:
	_mine_cell("ore_core", 4)
	for _i: int in 3:
		_mine_cell("ore_shard", 3)
	_place_building("resonance_loom", Vector2i(5, 5))
	for _i: int in 2:
		var before: int = _inv_count("sedative_mist")
		var entries: Array = session.recipe_entries()
		var done: bool = false
		for entry_value: Variant in entries:
			var entry: Dictionary = entry_value as Dictionary
			var recipe: Dictionary = entry.get("recipe", {}) as Dictionary
			if str(recipe.get("output_item_id", "")) == "sedative_mist":
				session.call("_on_craft_requested", str(entry.get("building_id", "")), recipe)
				done = true
				break
		assert_true(done, "loom must expose a mist recipe.")
		assert_gt(_inv_count("sedative_mist"), before, "craft must add one mist per request.")


## 从 fresh 推进到结局场景；返回泵步数（节奏基线数据）。
func _run_mainline(profile: Dictionary) -> int:
	profile_for_test = profile
	_make_session()

	var pump: Dictionary = _until(_flag_when("event_event_prologue_landing_done"))
	assert_true(pump["ok"], "prologue: %s" % str(pump.get("diag", "")))

	_stage_mine_and_build()
	pump = _until(_flag_when("event_event_first_mining_done"))
	assert_true(pump["ok"], "first_mining event: %s" % str(pump.get("diag", "")))

	pump = _until(_flag_when("encounter_first_drift_won"))
	assert_true(pump["ok"], "first drift victory: %s" % str(pump.get("diag", "")))

	pump = _until(_flag_when("event_event_misa_campfire_done"))
	assert_true(pump["ok"], "campfire + seed grant: %s" % str(pump.get("diag", "")))
	assert_gt(_inv_count("echo_seed"), 0, "campfire must grant the echo seed.")

	_stage_chamber()
	pump = _until(_flag_when("echo_chamber_active"))
	assert_true(pump["ok"], "echo chamber powered: %s" % str(pump.get("diag", "")))

	_stage_craft_mist()
	pump = _until(_flag_when("encounter_husk_ambush_won"))
	assert_true(pump["ok"], "husk ambush victory: %s" % str(pump.get("diag", "")))

	pump = _until(_flag_when("encounter_leviathan_due"))
	assert_true(pump["ok"], "leviathan due: %s" % str(pump.get("diag", "")))

	pump = _until(_flag_when("encounter_leviathan_won"))
	assert_true(pump["ok"], "leviathan victory: %s" % str(pump.get("diag", "")))

	pump = _until(func() -> bool: return session.ending != null)
	assert_true(pump["ok"], "ending scene: %s" % str(pump.get("diag", "")))
	return int(pump["ticks"])


# ---------------------------------------------------------------- 三条路线

func test_playthrough_mining_route_reaches_ending_mining() -> void:
	var ticks: int = _run_mainline({
		"station_mode": "station_mode_exploit",
		"approach": "approach_direct",
		"policy": "policy_extraction_quota",
	})
	assert_lt(ticks, MAX_PUMP_TICKS, "route must finish inside the tick budget.")
	assert_not_null(session.ending, "mining route must reach the ending scene.")
	assert_eq(str((session.ending.get_node("TitleLabel") as Label).text), "结局：开采纪元")


func test_playthrough_seal_route_reaches_ending_seal() -> void:
	# policy_sanctuary 需要 trust>=40；husk_aftermath（+12）在事件链上晚于 policy
	# 可选点（遭遇要等事件队列清空才触发），真实玩家可先战后选。sanctuary 信任门
	# 的可达性由共生路线锁定，封存路线按 quota 走（boss_condition_escalated 同样生效）。
	var ticks: int = _run_mainline({
		"station_mode": "station_mode_seal",
		"approach": "approach_diplomatic",
		"policy": "policy_extraction_quota",
	})
	assert_lt(ticks, MAX_PUMP_TICKS, "route must finish inside the tick budget.")
	assert_not_null(session.ending, "seal route must reach the ending scene.")
	assert_eq(str((session.ending.get_node("TitleLabel") as Label).text), "结局：封存之约")


func test_playthrough_symbiosis_route_reaches_ending_symbiosis() -> void:
	var ticks: int = _run_mainline({
		"station_mode": "station_mode_symbiosis",
		"approach": "approach_direct",
		"policy": "policy_sanctuary",
	})
	var trust: int = RELATIONS_SCRIPT.trust(_snapshot(), "luoxian")
	assert_true(trust >= 70, "symbiosis route must reach trust >= 70, got %d." % trust)
	assert_lt(ticks, MAX_PUMP_TICKS, "route must finish inside the tick budget.")
	assert_not_null(session.ending, "symbiosis route must reach the ending scene.")
	assert_eq(str((session.ending.get_node("TitleLabel") as Label).text), "结局：共生曙光")


# ---------------------------------------------------------------- 存读档往返

func test_playthrough_save_roundtrip_preserves_progress() -> void:
	_run_mainline({
		"station_mode": "station_mode_exploit",
		"approach": "approach_direct",
		"policy": "policy_extraction_quota",
	})
	var saved: AppResult = session.save_now()
	assert_true(saved.is_ok, saved.message)
	var loaded: AppResult = SaveService.load_slot(session.save_slot)
	assert_true(loaded.is_ok, loaded.message)
	var fresh: Node = GAME_STATE_SCRIPT.new()
	assert_true(fresh.restore_snapshot(loaded.value).is_ok, "restore must succeed.")
	var after: Dictionary = fresh.snapshot()
	fresh.free()
	var before: Dictionary = _snapshot()
	assert_eq(before["inventory"], after["inventory"], "inventory must roundtrip.")
	assert_eq(before["flags"], after["flags"], "flags must roundtrip.")
	assert_eq(before.get("player", {}), after.get("player", {}), "player position must roundtrip.")
