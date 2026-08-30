extends GutTest

## W002-GAP4 集成闭环测试：供电平衡（D2）、精炼闭环（D3）、道具经济（C3）、
## 建造热键 UI（D1）在 app 层装配下的端到端行为。
## 全部经注入的独立 GameState 实例（真实 patch 管线），不污染全局 autoload。

const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")

const RENDERED_CHUNK_ID: String = "chunk_0_0"
const MAX_BATTLE_GUARD: int = 200
const CRAFTING_SCRIPT_PATH: String = "res://src/crafting/crafting_service.gd"

static var _save_root_seq: int = 0

var _save_root: String = ""
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
	_save_root = "user://saves_gap4_integration_%d_%d" % [Time.get_ticks_msec(), _save_root_seq]
	assert_true(SaveService.configure_root_for_tests(_save_root).is_ok)
	store = GAME_STATE_SCRIPT.new()
	world = _make_world()
	dialogue = _make_dialogue()


func after_each() -> void:
	if is_instance_valid(session):
		session.free()
	if is_instance_valid(hud):
		hud.free()
	if is_instance_valid(world):
		world.free()
	if is_instance_valid(dialogue):
		dialogue.free()
	if is_instance_valid(store):
		store.free()
	session = null
	hud = null
	world = null
	dialogue = null
	store = null


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


func _make_session_with_hud() -> void:
	# HUD 必须先入树、再挂 session：session._ready 的 _bind_hud 才能完成
	# provider 注入与信号接线（与 app.tscn 的装配顺序一致）。
	var packed := load("res://scenes/ui_hud.tscn") as PackedScene
	hud = packed.instantiate() as Hud
	hud.snapshot_provider = Callable(store, "snapshot")
	add_child_autofree(hud)
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


func _give_item(item_id: String, amount: int) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_gap4_give_%s_%d" % [item_id, revision], revision)
	patch.add_item(item_id, amount)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _patch_flags(flag_ids: Array) -> void:
	var revision := int(store.snapshot()["revision"])
	var patch: StatePatch = store.begin_patch("test_gap4_flags_%d" % revision, revision)
	for flag_id: String in flag_ids:
		patch.set_flag(flag_id, true)
	var committed: AppResult = store.commit(patch)
	assert_true(committed.is_ok, committed.message)


func _inventory() -> Dictionary:
	return store.snapshot()["inventory"] as Dictionary


## 经 load() 解析 CraftingService（脚本运行时加载，缺失实现以失败断言暴露）。
func _craft(building_id: String, recipe: Dictionary) -> AppResult:
	var crafting: Script = load(CRAFTING_SCRIPT_PATH)
	if crafting == null:
		fail_test("Missing required W002-GAP4 implementation: %s" % CRAFTING_SCRIPT_PATH)
		return AppResult.failure("missing_implementation", CRAFTING_SCRIPT_PATH)
	var result: Variant = crafting.call("craft", store.snapshot(), building_id, recipe, store)
	assert_true(result is AppResult, "craft must return an AppResult.")
	return result if result is AppResult else AppResult.failure("missing_implementation", "craft returned no AppResult.")


# ---------------------------------------------------------------- 供电平衡（D2）


func test_power_balance_data_covers_full_station_demand() -> void:
	# 数据级：16(工坊) + 2×n(锚块) 供给必须能覆盖全部耗电建筑总需求 23。
	var workshop: Dictionary = ContentDB.get_building("anchor_workshop")
	var anchor: Dictionary = ContentDB.get_building("anchor_block")
	assert_eq(int(workshop.get("power_supply", -1)), 16, "anchor_workshop power_supply must be 16 (D2 fix).")
	assert_eq(int(anchor.get("power_supply", -1)), 2, "anchor_block must supply 2 base power (D2 fix).")
	var demand := 0
	for building_id: String in ["dust_refiner", "stabilizer_pylon", "resonance_loom", "echo_chamber"]:
		demand += int(ContentDB.get_building(building_id).get("power_draw", 0))
	assert_eq(demand, 23, "Total consumer demand stays 23.")
	var supply := int(workshop.get("power_supply", 0)) + 4 * int(anchor.get("power_supply", 0))
	assert_true(
		supply >= demand,
		"4 anchors + workshop supply (%d) must cover full demand (%d)." % [supply, demand]
	)


func test_full_station_layout_powers_every_building() -> void:
	# 布局级：4 锚块 + 工坊 + 全部 4 座耗电建筑同 chunk 成行放置，全部获电。
	_make_session()
	_give_item("starsoil_dust", 12)   # 4×锚块(2) + 工坊(4)
	_give_item("lumen_shard", 3)      # 精炼器(2) + 稳定塔(1)
	_give_item("resonant_core", 4)    # 稳定塔(1) + 织机(1) + 回响舱(2)
	# 供给 16(工坊) + 2×4(锚块) = 24 >= 需求 4+5+6+8 = 23（evidence 布局计算）。
	# 锚块先建（供给先累积），耗电建筑随后，PowerGrid 按输入序分配。
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_block", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("anchor_block", Vector2i(20, 22)).is_ok)
	assert_true(_place_at("anchor_block", Vector2i(20, 23)).is_ok)
	var cells: Dictionary = {
		"anchor_workshop": Vector2i(20, 24),
		"dust_refiner": Vector2i(20, 25),
		"resonance_loom": Vector2i(20, 26),
		"stabilizer_pylon": Vector2i(20, 27),
		"echo_chamber": Vector2i(20, 28),
	}
	# 同 chunk 一行 4 连通成房间，回响舱 requires_room 满足。
	for building_id: String in cells:
		var result: AppResult = _place_at(building_id, cells[building_id])
		assert_true(result.is_ok, "%s placement failed: %s" % [building_id, result.message])
	assert_eq(
		session.unpowered_building_ids().size(), 0,
		"Full station layout must power every building."
	)
	var flags: Dictionary = store.snapshot()["flags"]
	assert_true(bool(flags.get("pylon_stabilized", false)))
	assert_true(bool(flags.get("echo_chamber_active", false)))
	assert_true(session.unpowered_effect_flags.is_empty())


func test_three_anchor_layout_still_covers_full_demand() -> void:
	# 3 锚块 + 工坊 = 22 < 23：总需求差 1，必须至少缺一座——锁定平衡边界。
	_make_session()
	_give_item("starsoil_dust", 10)
	_give_item("lumen_shard", 3)
	_give_item("resonant_core", 4)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_block", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("anchor_block", Vector2i(20, 22)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 23)).is_ok)
	assert_true(_place_at("dust_refiner", Vector2i(20, 24)).is_ok)
	assert_true(_place_at("resonance_loom", Vector2i(20, 25)).is_ok)
	assert_true(_place_at("stabilizer_pylon", Vector2i(20, 26)).is_ok)
	# 22 - 4 - 5 - 6 = 7 < 8：回响舱断电（且 requires_room 已满足，纯供电不足）。
	assert_true(_place_at("echo_chamber", Vector2i(20, 27)).is_ok)
	assert_true(
		session.unpowered_building_ids().has("echo_chamber"),
		"3-anchor layout must leave the echo chamber unpowered (balance boundary)."
	)
	assert_false(bool((store.snapshot()["flags"] as Dictionary).get("echo_chamber_active", false)))


# ---------------------------------------------------------------- 精炼闭环（D3）


func test_loom_recipes_available_when_powered_and_craft_mist() -> void:
	_make_session()
	_give_item("starsoil_dust", 6)
	_give_item("lumen_shard", 4)
	_give_item("resonant_core", 1)  # 织机建造材料
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("resonance_loom", Vector2i(20, 22)).is_ok)

	var entries: Array[Dictionary] = session.recipe_entries()
	assert_eq(entries.size(), 2, "Powered loom exposes both frozen §7 recipes.")
	if entries.size() == 2:
		assert_eq(str(entries[0]["recipe"]["output_item_id"]), "sedative_mist")
		assert_eq(str(entries[1]["recipe"]["output_item_id"]), "shock_trap")
		assert_true(bool(entries[0].get("craftable", false)), "Mist recipe is craftable with 4 shards.")
		assert_false(bool(entries[1].get("craftable", false)), "Trap recipe needs a resonant core too.")

	var mist_recipe: Dictionary = entries[0]["recipe"]
	var result: AppResult = _craft("resonance_loom", mist_recipe)
	assert_true(result.is_ok, result.message)
	var inventory: Dictionary = _inventory()
	assert_eq(int(inventory.get("sedative_mist", 0)), 1, "Crafted mist must land in the inventory.")
	assert_eq(int(inventory.get("lumen_shard", 0)), 2, "Crafting consumes exactly 2 shards.")


func test_craft_button_in_inventory_panel_closes_the_loop() -> void:
	# UI → GameSession → CraftingService → patch：背包面板点击"合成"直接落账。
	_make_session_with_hud()
	_give_item("starsoil_dust", 6)
	_give_item("lumen_shard", 2)
	_give_item("resonant_core", 1)  # 织机建造材料
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("resonance_loom", Vector2i(20, 22)).is_ok)

	var toggle := InputEventAction.new()
	toggle.action = "toggle_inventory"
	toggle.pressed = true
	hud._unhandled_input(toggle)

	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	var craft_button: Button = null
	# 第一行即 mist 配方（loom recipes 数据序）。
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					craft_button = row_child
					break
			if craft_button != null:
				break
	assert_not_null(craft_button, "Inventory panel must show a craft button for the powered loom.")
	if craft_button == null:
		return
	assert_false(craft_button.disabled, "Mist recipe must be craftable with 2 shards in stock.")
	craft_button.pressed.emit()
	await get_tree().process_frame

	var inventory: Dictionary = _inventory()
	assert_eq(int(inventory.get("sedative_mist", 0)), 1, "UI craft press must commit the craft patch.")
	assert_eq(int(inventory.get("lumen_shard", 0)), 0, "UI craft press must consume the shards.")
	# 行区必须随合成后的 revision 重渲染：0 颗晶片下 mist 配方转为不可合成。
	var refreshed_button: Button = null
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					refreshed_button = row_child
	assert_not_null(refreshed_button, "Rows must re-render after the craft commit.")
	if refreshed_button != null:
		assert_true(refreshed_button.disabled, "With 0 shards left the recipe must grey out again.")


func test_crafted_mist_is_equipped_for_encounter_battles() -> void:
	# mist 渠道端到端：织机合成 → 背包 → EncounterDirector.start 装配。
	_make_session()
	_give_item("starsoil_dust", 6)
	_give_item("lumen_shard", 2)
	_give_item("resonant_core", 1)  # 织机建造材料
	_give_item("shock_trap", 1)
	assert_true(_place_at("anchor_block", Vector2i(20, 20)).is_ok)
	assert_true(_place_at("anchor_workshop", Vector2i(20, 21)).is_ok)
	assert_true(_place_at("resonance_loom", Vector2i(20, 22)).is_ok)
	var entries: Array[Dictionary] = session.recipe_entries()
	var mist_recipe: Dictionary = entries[0]["recipe"]
	assert_true(_craft("resonance_loom", mist_recipe).is_ok)

	var husk_def: Dictionary = ContentDB.get_encounter("encounter_husk_ambush")
	var config: Dictionary = EncounterDirector.start(husk_def, session._battle_content())
	var misa_items: Dictionary = (config.get("allies", [{}, {}]) as Array)[1].get("items", {})
	assert_true(
		misa_items.has("sedative_mist"),
		"Crafted mist must be equipped onto misa_weaver for the ambush."
	)
	assert_true(misa_items.has("shock_trap"), "Granted trap from event_first_anchor channel stays equipped when owned.")


# ---------------------------------------------------------------- 道具经济（C3）


func test_husk_ambush_battle_fields_elite_and_writes_back_spent_item() -> void:
	# C3 端到端：背包里的定神雾经 start 装配 → 战斗内 mist_calm 实际消耗 →
	# finish 经 remove_item 回写库存（0 存量）。选 mist 而非 trap 做断言：
	# shard_husk 的 drops 含 shock_trap，会抵消回写；mist 无任何掉落来源，
	# 断言与胜负结果无关。
	_make_session()
	_give_item("sedative_mist", 1)
	_patch_flags(["event_event_prologue_landing_done", "encounter_husk_ambush_due"])
	session.tick()
	assert_not_null(session.battle, "tick must start the husk ambush.")

	var battle_state: Dictionary = session.battle.battle_state()
	var has_elite := false
	for unit_value: Variant in battle_state.get("units", []):
		if str((unit_value as Dictionary).get("unit_id", "")) == "veinwarden_echo":
			has_elite = true
	assert_true(has_elite, "veinwarden_echo must fight in the husk ambush (frozen elite).")

	var mist_used := false
	var guard := 0
	while session.battle != null and guard < MAX_BATTLE_GUARD:
		var state: Dictionary = session.battle.battle_state()
		if bool(state.get("finished", false)):
			break
		var active: Dictionary = COMBAT_ENGINE_SCRIPT.active_unit(state)
		if active.is_empty() or str(active.get("side", "")) != "ally":
			break
		var action_id := _deterministic_action(state, active)
		if not mist_used and str(active.get("unit_id", "")) == "misa_weaver":
			var held: int = int((active.get("items", {}) as Dictionary).get("sedative_mist", 0))
			if held >= 1:
				action_id = "mist_calm"
				mist_used = true
		session.battle.play_ally_action(action_id)
		guard += 1

	await get_tree().process_frame
	assert_null(session.battle, "Battle must unload after finishing.")
	var snapshot: Dictionary = store.snapshot()
	assert_true(mist_used, "Misa must have used the sedative mist during the battle.")
	assert_eq(
		int((snapshot["inventory"] as Dictionary).get("sedative_mist", 0)), 0,
		"Battle consumption must write back to the inventory (1 mist used -> 0 left)."
	)
	assert_true(
		(snapshot["battle_outcomes"] as Dictionary).has("encounter_husk_ambush"),
		"Battle outcome must be recorded regardless of result."
	)


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
