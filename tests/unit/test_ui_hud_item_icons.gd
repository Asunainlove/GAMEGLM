extends GutTest

## G6P-1 任务 4：HUD 物品槽图标适配契约测试（TDD：先于实现编写）。
##
## 契约：
## - 资产缺失（生产基态）→ 物品槽渲染与基线逐字节一致（纯 Label 文本行，
##   无图标节点，布局不塌，零告警）；
## - 注入图标资产（A7 §9 合同落位 assets/art/ui/icons/uia_ico_<item_id>.png
##   优先，任务书平铺 ui_item_<item_id>.png 兜底）→ 槽文本左侧出现 24×24
##   TextureRect 图标；文本内容与顺序不变；
## - 混合态（部分物品命中、部分缺失）→ 一次性汇总告警（纯函数断言 + 实例
##   一次性标记）。
## 测试经 asset_base_dir 注入 user:// 临时目录（生产恒为 res://assets/art）。

const HUD_SCENE_PATH: String = "res://scenes/ui_hud.tscn"

const ITEM_ICON_SIZE: Vector2 = Vector2(24.0, 24.0)

## Godot 4 教训：Callable 只持 ObjectID，替身必须保存在测试实例字段中保活。
var _fake: FakeSnapshotProvider = null

var _temp_dir: String = ""


class FakeSnapshotProvider:
	var payload: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return payload


var _fake_names: Dictionary = {
	"starsoil_dust": "星壤尘",
	"lumen_shard": "辉砂晶片",
}


func before_each() -> void:
	get_tree().paused = false
	_temp_dir = "user://g6p1_hud_icons_%d" % Time.get_ticks_usec()


func after_each() -> void:
	get_tree().paused = false
	_fake = null
	_remove_dir_recursive(_temp_dir)
	_temp_dir = ""


# ---------------------------------------------------------------- 工具


func _write_png(rel_dir: String, file_name: String, size: Vector2i, color: Color) -> void:
	var dir := _temp_dir.path_join(rel_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	assert_eq(image.save_png(dir.path_join(file_name)), OK, "PNG 写入必须成功。")


func _pixel_of(texture: Texture2D) -> Color:
	var image := texture.get_image()
	return image.get_pixel(0, 0)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		if dir.current_is_dir():
			_remove_dir_recursive(path.path_join(entry))
		else:
			DirAccess.remove_absolute(path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _make_hud() -> Hud:
	_fake = FakeSnapshotProvider.new()
	_fake.payload = {
		"revision": 1,
		"inventory": {"starsoil_dust": 5, "lumen_shard": 2},
		"flags": {},
		"placed_buildings": [],
	}
	var scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(scene, "ui_hud.tscn must load.")
	if scene == null:
		return null
	var hud: Hud = scene.instantiate() as Hud
	assert_not_null(hud)
	if hud == null:
		return null
	hud.snapshot_provider = _fake.get_snapshot
	hud.name_resolver = _resolve_fake_name
	add_child_autofree(hud)
	return hud


func _resolve_fake_name(item_id: String) -> String:
	if _fake_names.has(item_id):
		return _fake_names[item_id] as String
	return item_id


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in node.get_children():
		if child is Label:
			texts.append((child as Label).text)
	return texts


# ---------------------------------------------------------------- 契约测试


func test_missing_icons_render_labels_only() -> void:
	# 灰盒契约：缺资产 = 纯 Label。正式 icons 落位后不得依赖生产树为空；
	# 注入空 asset_base_dir 强制缺图标路径。
	var hud: Hud = _make_hud()
	if hud == null:
		return
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	hud.asset_base_dir = _temp_dir
	hud.refresh()
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	var texts: Array[String] = _label_texts(bar)
	assert_eq(texts, ["辉砂晶片 ×2", "星壤尘 ×5"] as Array[String], "槽文本保持基线。")
	for child: Node in bar.get_children():
		assert_true(child is Label, "缺资产时槽位只允许 Label 节点（实际 %s）。" % child.get_class())
	assert_eq(bar.get_child_count(), 2, "缺资产不得出现图标节点。")


func test_injected_icon_shows_at_contract_path() -> void:
	# A7 §9 合同落位：ui/icons/uia_ico_<item_id>.png。
	_write_png("ui/icons", "uia_ico_starsoil_dust.png", Vector2i(32, 32), Color(1, 0, 0))
	var hud: Hud = _make_hud()
	if hud == null:
		return
	hud.asset_base_dir = _temp_dir
	hud.refresh()
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	# 排序：lumen_shard 无图标（纯 Label）在前，starsoil_dust 图标 + Label 在后。
	assert_eq(bar.get_child_count(), 3, "一个图标 + 两个文本 = 3 个节点。")
	var icon: TextureRect = bar.get_child(1) as TextureRect
	assert_not_null(icon, "命中物品必须在文本左侧出现 TextureRect 图标。")
	if icon == null:
		return
	assert_eq(icon.name, &"Icon_starsoil_dust")
	assert_eq(icon.custom_minimum_size, ITEM_ICON_SIZE, "图标必须 24×24。")
	assert_eq(
		icon.expand_mode, TextureRect.EXPAND_IGNORE_SIZE,
		"图标不得反向撑大布局。")
	assert_eq(icon.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE, "图标不得拦截鼠标输入。")
	assert_eq(_pixel_of(icon.texture), Color(1, 0, 0), "图标纹理必须来自注入资产。")
	assert_eq(
		_label_texts(bar), ["辉砂晶片 ×2", "星壤尘 ×5"] as Array[String],
		"图标出现不得改变槽文本内容与顺序。")


func test_injected_icon_accepts_flat_fallback_path() -> void:
	# 任务书平铺落位：ui/ui_item_<item_id>.png（仅 lumen_shard 命中）。
	_write_png("ui", "ui_item_lumen_shard.png", Vector2i(32, 32), Color(0, 1, 0))
	var hud: Hud = _make_hud()
	if hud == null:
		return
	hud.asset_base_dir = _temp_dir
	hud.refresh()
	var bar: HBoxContainer = hud.get_node("InventoryBar") as HBoxContainer
	assert_eq(bar.get_child_count(), 3, "一个图标 + 两个文本 = 3 个节点。")
	var icon: TextureRect = bar.get_child(0) as TextureRect
	assert_not_null(icon, "平铺落位兜底必须生效。")
	if icon == null:
		return
	assert_eq(icon.name, &"Icon_lumen_shard")
	assert_eq(_pixel_of(icon.texture), Color(0, 1, 0))


# ---------------------------------------------------------------- 混合态告警


func test_partial_icon_warning_is_pure_function() -> void:
	assert_eq(Hud.partial_icon_warning(0, PackedStringArray(["x"])), "", "全缺失基态必须静默。")
	assert_eq(Hud.partial_icon_warning(2, PackedStringArray()), "", "全量命中必须静默。")
	var mixed: String = Hud.partial_icon_warning(1, PackedStringArray(["shock_trap"]))
	assert_true(mixed.contains("shock_trap"), "混合态汇总文案必须点名缺失物品。")
	assert_true(mixed.contains("回退纯文本"))


func test_mixed_icons_raise_one_shot_warning_flag() -> void:
	_write_png("ui/icons", "uia_ico_starsoil_dust.png", Vector2i(32, 32), Color(1, 0, 0))
	var hud: Hud = _make_hud()
	if hud == null:
		return
	hud.asset_base_dir = _temp_dir
	assert_eq(
		hud.get("_icon_asset_warning_emitted"), false,
		"实例一次性标记初始为未发。")
	hud.refresh()
	assert_eq(
		hud.get("_icon_asset_warning_emitted"), true,
		"混合态（starsoil_dust 命中、lumen_shard 缺失）必须一次性置位汇总标记。")
	hud.refresh()
	# 二次刷新不再重复置位语义（标记恒 true，一次性完成）。
	assert_eq(hud.get("_icon_asset_warning_emitted"), true)
