extends GutTest

## W002-GAP4 HUD 测试：建造热键栏（BuildBar）与背包配方区（RecipesBox）。
## HUD 仍是只读表现层：数据全部来自注入的 provider Callable，唯一"写"是
## 信号（build_selected / craft_requested）与引擎级 UI 状态。
## Godot 4 教训：替身宿主必须存测试实例字段保活（Callable 只持 ObjectID）。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"

const MIST_RECIPE: Dictionary = {
	"input_item_id": "lumen_shard", "input_count": 2,
	"output_item_id": "sedative_mist", "output_count": 1,
}
const TRAP_RECIPE: Dictionary = {
	"input_item_id": "lumen_shard", "input_count": 2,
	"extra_input_item_id": "resonant_core", "extra_input_count": 1,
	"output_item_id": "shock_trap", "output_count": 1,
}

## 替身宿主：存实例字段保活。
var _catalog_host: CatalogHost = null
var _selection_host: SelectionHost = null
var _unpowered_host: UnpoweredHost = null
var _recipe_host: RecipeHost = null


class CatalogHost:
	var entries: Array = []

	func catalog() -> Array:
		return entries


class SelectionHost:
	var building_id: String = ""

	func selected() -> String:
		return building_id


class UnpoweredHost:
	var ids: Array = []

	func unpowered() -> Array:
		return ids


class RecipeHost:
	var entries: Array = []

	func recipes() -> Array:
		return entries


var _fake: FakeSnapshotProvider = null


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


var _names: Dictionary = {
	"starsoil_dust": "星壤尘",
	"lumen_shard": "辉砂晶片",
	"resonant_core": "共鸣核",
	"sedative_mist": "定神雾",
	"shock_trap": "震颤陷阱",
}


func _resolve_name(item_id: String) -> String:
	return str(_names.get(item_id, item_id))


func _make_hud() -> Hud:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {"revision": 1, "inventory": {}, "flags": {}, "placed_buildings": []}
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must load.")
	if scene == null:
		return null
	var hud: Hud = scene.instantiate() as Hud
	assert_not_null(hud, "ui_hud.tscn must instantiate as Hud.")
	if hud == null:
		return null
	hud.snapshot_provider = _fake.get_snapshot
	hud.name_resolver = _resolve_name
	add_child_autofree(hud)
	return hud


func _wire_providers(hud: Hud) -> void:
	_catalog_host = CatalogHost.new()
	_selection_host = SelectionHost.new()
	_unpowered_host = UnpoweredHost.new()
	_recipe_host = RecipeHost.new()
	hud.build_catalog = _catalog_host.catalog
	hud.selected_provider = _selection_host.selected
	hud.unpowered_provider = _unpowered_host.unpowered
	hud.recipe_provider = _recipe_host.recipes


func _catalog_entry(building_id: String, name_zh: String, cost: String, affordable: bool) -> Dictionary:
	return {
		"building_id": building_id,
		"name_zh": name_zh,
		"cost_text": cost,
		"affordable": affordable,
	}


func _default_catalog() -> Array:
	return [
		_catalog_entry("anchor_block", "锚块", "星壤尘×2", true),
		_catalog_entry("anchor_workshop", "锚居工坊", "星壤尘×4", false),
		_catalog_entry("dust_refiner", "尘精炼器", "辉砂晶片×2", true),
		_catalog_entry("stabilizer_pylon", "稳定塔", "辉砂晶片×1 共鸣核×1", true),
		_catalog_entry("resonance_loom", "共鸣织机", "共鸣核×1", true),
		_catalog_entry("echo_chamber", "回响舱", "共鸣核×2", true),
	]


func _build_buttons(hud: Hud) -> Array[Button]:
	var buttons: Array[Button] = []
	var bar: HBoxContainer = hud.get_node("%BuildBar") as HBoxContainer
	for child: Node in bar.get_children():
		if child is Button:
			buttons.append(child)
	return buttons


func _action_event(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


# --- 场景契约 ----------------------------------------------------------------------


func test_hud_declares_build_and_craft_signals() -> void:
	var hud: Hud = _make_hud()
	assert_true(hud.has_signal("build_selected"), "Hud must declare build_selected.")
	assert_true(hud.has_signal("craft_requested"), "Hud must declare craft_requested.")


func test_build_bar_is_bottom_hbox_in_scene() -> void:
	var hud: Hud = _make_hud()
	var bar: Control = hud.get_node("%BuildBar") as Control
	assert_not_null(bar, "BuildBar must exist in ui_hud.tscn.")
	if bar != null:
		assert_true(bar is HBoxContainer, "BuildBar must be an HBoxContainer.")
		assert_true(bar.visible, "BuildBar starts visible.")


func test_inventory_panel_has_recipes_box() -> void:
	var hud: Hud = _make_hud()
	var recipes_box: Control = hud.get_node("InventoryPanel/Content/RecipesBox") as Control
	assert_not_null(recipes_box, "InventoryPanel must contain a RecipesBox for crafting rows.")


# --- BuildBar 渲染 ------------------------------------------------------------------


func test_build_bar_renders_one_slot_per_catalog_entry() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_catalog_host.entries = _default_catalog()
	_selection_host.building_id = "anchor_block"
	hud.refresh()

	var buttons: Array[Button] = _build_buttons(hud)
	assert_eq(buttons.size(), 6, "BuildBar must render exactly 6 hotbar slots.")
	if buttons.size() == 6:
		assert_eq(buttons[0].name, "BuildSlot_anchor_block")
		assert_true(
			buttons[0].text.begins_with("1 "),
			"First slot must show the hotkey number 1."
		)
		assert_true(buttons[0].text.contains("锚块"), "Slot text must carry the Chinese name.")
		assert_true(buttons[0].text.contains("星壤尘×2"), "Slot text must carry the cost summary.")
		assert_true(buttons[5].text.begins_with("6 "), "Sixth slot must show hotkey 6.")


func test_build_bar_marks_unaffordable_entries() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_catalog_host.entries = _default_catalog()
	_selection_host.building_id = "anchor_block"
	hud.refresh()

	var buttons: Array[Button] = _build_buttons(hud)
	assert_eq(buttons.size(), 6)
	if buttons.size() == 6:
		assert_true(
			buttons[1].text.contains("材料不足"),
			"Unaffordable workshop slot must surface 材料不足."
		)
		assert_false(buttons[1].disabled, "Slots stay clickable so players can plan selections.")
		assert_false(buttons[0].text.contains("材料不足"))


func test_build_bar_highlights_selected_slot_and_switches() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_catalog_host.entries = _default_catalog()
	_selection_host.building_id = "dust_refiner"
	hud.refresh()

	var buttons: Array[Button] = _build_buttons(hud)
	assert_eq(buttons.size(), 6)
	if buttons.size() == 6:
		assert_true(buttons[2].button_pressed, "Selected slot must be highlighted.")
		assert_false(buttons[0].button_pressed, "Non-selected slots must not be highlighted.")

	# 选中项切换后（模拟 session.select_building），重新渲染必须移动高亮。
	_selection_host.building_id = "resonance_loom"
	hud.refresh()
	buttons = _build_buttons(hud)
	assert_true(buttons[4].button_pressed, "Highlight must follow the injected selection.")
	assert_false(buttons[2].button_pressed, "Previous highlight must be cleared.")


func test_build_bar_click_emits_build_selected_and_rehighlights() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_catalog_host.entries = _default_catalog()
	_selection_host.building_id = "anchor_block"
	hud.refresh()
	watch_signals(hud)

	# 模拟 game_session 的连接：点击后更新选择源。
	hud.build_selected.connect(func(building_id: String) -> void:
		_selection_host.building_id = building_id
	)
	var buttons: Array[Button] = _build_buttons(hud)
	buttons[2].pressed.emit()
	assert_signal_emitted_with_parameters(
		hud, "build_selected", ["dust_refiner"]
	)
	await get_tree().process_frame
	buttons = _build_buttons(hud)
	assert_true(buttons[2].button_pressed, "After the selection provider updates, re-render must highlight the clicked slot.")


func test_build_bar_shows_unpowered_dot_for_configured_buildings() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_catalog_host.entries = _default_catalog()
	_selection_host.building_id = "anchor_block"
	_unpowered_host.ids = ["dust_refiner", "resonance_loom"]
	hud.refresh()

	var buttons: Array[Button] = _build_buttons(hud)
	assert_eq(buttons.size(), 6)
	if buttons.size() == 6:
		var refiner_dot: Node = buttons[2].get_node_or_null("UnpoweredDot")
		assert_not_null(refiner_dot, "Unpowered building slot must carry an UnpoweredDot marker.")
		if refiner_dot != null and refiner_dot is ColorRect:
			assert_eq(
				(refiner_dot as ColorRect).color, Color(0.85, 0.15, 0.15),
				"UnpoweredDot must render as a small red dot."
			)
		assert_null(buttons[0].get_node_or_null("UnpoweredDot"), "Powered/neutral slots must not carry the dot.")
		assert_not_null(buttons[4].get_node_or_null("UnpoweredDot"), "Second unpowered slot must be marked too.")


func test_build_bar_without_provider_renders_no_slots() -> void:
	var hud: Hud = _make_hud()
	hud.refresh()
	assert_eq(_build_buttons(hud).size(), 0, "Missing build_catalog provider must render zero slots gracefully.")


# --- 背包配方区 ----------------------------------------------------------------------


func test_recipe_rows_render_craft_buttons_with_inputs_and_outputs() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_recipe_host.entries = [
		{"building_id": "resonance_loom", "recipe": MIST_RECIPE, "craftable": true},
		{"building_id": "resonance_loom", "recipe": TRAP_RECIPE, "craftable": false},
	]
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud.refresh()

	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	var craft_buttons: Array[Button] = []
	var row_texts: Array[String] = []
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					craft_buttons.append(row_child)
				elif row_child is Label:
					row_texts.append((row_child as Label).text)
	assert_eq(craft_buttons.size(), 2, "Each available recipe renders one craft button.")
	assert_false(craft_buttons[0].disabled, "Craftable recipe button must be enabled.")
	assert_true(craft_buttons[1].disabled, "Not-yet-craftable recipe button must be greyed out.")
	assert_true(row_texts[0].contains("定神雾"), "Recipe row must name the output item.")
	assert_true(row_texts[0].contains("辉砂晶片×2"), "Recipe row must list input amounts.")
	assert_true(row_texts[1].contains("共鸣核×1"), "Dual-input recipe must list the extra input.")
	assert_true(row_texts[1].contains("震颤陷阱"))


func test_recipe_craft_button_emits_craft_requested() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_recipe_host.entries = [
		{"building_id": "resonance_loom", "recipe": MIST_RECIPE, "craftable": true},
	]
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud.refresh()
	watch_signals(hud)

	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	var craft_button: Button = null
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					craft_button = row_child
	assert_not_null(craft_button)
	if craft_button != null:
		craft_button.pressed.emit()
	assert_signal_emitted_with_parameters(
		hud, "craft_requested", ["resonance_loom", MIST_RECIPE]
	)


func test_recipe_rows_show_empty_hint_without_available_recipes() -> void:
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_recipe_host.entries = []
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud.refresh()

	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	var texts: Array[String] = []
	for child: Node in box.get_children():
		if child is Label:
			texts.append((child as Label).text)
	assert_eq(texts.size(), 1, "Empty recipe list must render one hint label.")
	if texts.size() == 1:
		assert_true(texts[0].contains("暂无可用配方"))


func test_recipe_rows_stay_empty_without_provider() -> void:
	var hud: Hud = _make_hud()
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud.refresh()
	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	assert_eq(box.get_child_count(), 0, "Missing recipe_provider must render nothing gracefully.")


func test_craft_press_triggers_refresh_of_rows_and_inventory() -> void:
	# 合成后 revision 变化：provider 提供的 craftable 会翻转，HUD 的轮询或
	# refresh() 必须反映新状态（此处模拟 provider 更新后手动 refresh）。
	var hud: Hud = _make_hud()
	_wire_providers(hud)
	_recipe_host.entries = [
		{"building_id": "resonance_loom", "recipe": MIST_RECIPE, "craftable": false},
	]
	hud._unhandled_input(_action_event("toggle_inventory"))
	hud.refresh()
	var box: VBoxContainer = hud.get_node("InventoryPanel/Content/RecipesBox") as VBoxContainer
	var button: Button = null
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					button = row_child
	assert_not_null(button)
	if button == null:
		return
	assert_true(button.disabled, "Precondition: recipe not craftable yet.")

	_recipe_host.entries = [
		{"building_id": "resonance_loom", "recipe": MIST_RECIPE, "craftable": true},
	]
	hud.refresh()
	var refreshed: Button = null
	for child: Node in box.get_children():
		if child is HBoxContainer:
			for row_child: Node in (child as HBoxContainer).get_children():
				if row_child is Button:
					refreshed = row_child
	assert_not_null(refreshed)
	if refreshed != null:
		assert_false(refreshed.disabled, "Refresh must re-render rows with updated craftable state.")
