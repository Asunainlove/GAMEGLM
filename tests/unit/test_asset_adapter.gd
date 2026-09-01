extends GutTest

## G6P-1 任务 1：统一资产解析器契约测试（TDD：先于实现编写，观察 RED 后实现）。
##
## AssetAdapter 是 G6 正式美术零代码 drop-in 的唯一解析入口：
## - 资产缺失 → 一律返回 null（调用方回退灰盒，适配层绝不报错刷屏）；
## - 资产存在 → 按 docs/art 合同目录与命名优先探测，任务书平铺路径兜底；
## - res:// 走导入系统（编辑器/导出一致），非 res://（user:// 测试注入）走
##   原生 PNG 读取；两层统一由 texture_at 收口。
## 测试经 base_dir 参数注入 user:// 临时目录（生产 base_dir 恒为 res://assets/art，
## 该目录本包不创建——未 approved 资产不得入库，适配层只负责加载）。

const ADAPTER: Script = preload("res://src/assets/asset_adapter.gd")
const GUT_GREEN_PNG: String = "res://addons/gut/images/green.png"

## A8 战斗合同（docs/art/battle-assets.md §2/§7.1）单位帧清单。
const UNIT_STATES: Array = ["idle", "attack", "hit", "death"]
const UNIT_FRAME_COUNTS: Dictionary = {"idle": 2, "attack": 3, "hit": 1, "death": 2}

var _temp_dir: String = ""


func before_each() -> void:
	_temp_dir = "user://g6p1_adapter_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir_recursive(_temp_dir)
	_temp_dir = ""


# ---------------------------------------------------------------- 工具


func _write_png(dir: String, file_name: String, size: Vector2i, color: Color) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var path := dir.path_join(file_name)
	var err := image.save_png(path)
	assert_eq(err, OK, "PNG 写入必须成功：%s" % path)
	return path


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


func _write_unit_frames(base: String, unit_sub_dir: String, stem: String, color: Color) -> void:
	var frame_dir := base.path_join(unit_sub_dir)
	for state: String in UNIT_STATES:
		for index: int in int(UNIT_FRAME_COUNTS[state]):
			_write_png(frame_dir, "%s_%s_%02d.png" % [stem, state, index], Vector2i(8, 8), color)


# ---------------------------------------------------------------- texture


func test_default_base_dir_is_contract_root() -> void:
	assert_eq(str(ADAPTER.DEFAULT_BASE_DIR), "res://assets/art")


func test_texture_returns_null_for_missing_asset() -> void:
	# 生产基态：res://assets/art 尚不存在（未 approved 资产不入库）。
	assert_null(ADAPTER.texture("env_world_soil_base"), "生产基态必须返回 null（灰盒回退）。")
	assert_null(ADAPTER.texture("env_world_soil_base", _temp_dir), "注入空目录必须返回 null。")
	assert_null(ADAPTER.texture("", _temp_dir), "空 id 必须安全返回 null。")


func test_texture_at_loads_res_imported_texture() -> void:
	var texture: Texture2D = ADAPTER.texture_at(GUT_GREEN_PNG)
	assert_not_null(texture, "res:// 已导入 PNG 必须经导入系统加载。")
	if texture != null:
		assert_true(texture is Texture2D)


func test_texture_at_returns_null_for_missing_path() -> void:
	assert_null(ADAPTER.texture_at("res://assets/art/world/tiles/missing.png"))
	assert_null(ADAPTER.texture_at(_temp_dir.path_join("missing.png")))
	assert_null(ADAPTER.texture_at(""))


func test_texture_at_loads_user_png() -> void:
	var path := _write_png(_temp_dir, "flat.png", Vector2i(4, 4), Color(1, 0, 0))
	var texture: Texture2D = ADAPTER.texture_at(path)
	assert_not_null(texture)
	if texture != null:
		assert_eq(_pixel_of(texture), Color(1, 0, 0))


func test_texture_prefers_contract_sub_dir_over_flat_dir() -> void:
	# A7 §9 物品图标合同落位 ui/icons/uia_ico_<item>.png 优先于任务书平铺 ui/。
	_write_png(_temp_dir.path_join("ui/icons"), "uia_ico_probe_item.png", Vector2i(6, 6), Color(1, 0, 0))
	_write_png(_temp_dir.path_join("ui"), "ui_item_probe_item.png", Vector2i(6, 6), Color(0, 1, 0))
	var texture: Texture2D = ADAPTER.texture("ui_item_probe_item", _temp_dir)
	assert_not_null(texture, "合同落位资产必须可解析。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(1, 0, 0), "合同子目录落位必须优先于平铺目录。")


func test_texture_accepts_contract_size_suffix_variant() -> void:
	# A7 §10.1 命名 uia_<类别>_<名称>[_<尺寸>]：-S/32 尺寸变体作为第二候选。
	_write_png(_temp_dir.path_join("ui/icons"), "uia_ico_probe_item_32.png", Vector2i(6, 6), Color(0, 0, 1))
	var texture: Texture2D = ADAPTER.texture("ui_item_probe_item", _temp_dir)
	assert_not_null(texture, "尺寸后缀变体必须可解析。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(0, 0, 1))


func test_texture_falls_back_to_category_flat_dir() -> void:
	_write_png(_temp_dir.path_join("ui"), "ui_item_probe_item.png", Vector2i(6, 6), Color(0, 1, 0))
	var texture: Texture2D = ADAPTER.texture("ui_item_probe_item", _temp_dir)
	assert_not_null(texture, "分类平铺目录兜底必须生效。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(0, 1, 0))


func test_texture_maps_env_prefix_to_world_category() -> void:
	_write_png(_temp_dir.path_join("world"), "env_world_probe.png", Vector2i(6, 6), Color(1, 1, 0))
	var texture: Texture2D = ADAPTER.texture("env_world_probe", _temp_dir)
	assert_not_null(texture, "env_ 前缀必须映射到 world 分类目录。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(1, 1, 0))


func test_texture_maps_char_prefix_to_characters_category() -> void:
	_write_png(_temp_dir.path_join("characters"), "char_probe.png", Vector2i(6, 6), Color(1, 0, 1))
	var texture: Texture2D = ADAPTER.texture("char_probe", _temp_dir)
	assert_not_null(texture, "char_ 前缀必须映射到 characters 分类目录。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(1, 0, 1))


func test_texture_unknown_prefix_probes_flat_base_dir() -> void:
	_write_png(_temp_dir, "custom_thing.png", Vector2i(6, 6), Color(0, 0, 0))
	var texture: Texture2D = ADAPTER.texture("custom_thing", _temp_dir)
	assert_not_null(texture, "未知前缀必须按 base_dir 平铺探测。")
	if texture != null:
		assert_eq(_pixel_of(texture), Color(0, 0, 0))


# ---------------------------------------------------------------- sprite_frames


func test_sprite_frames_assembles_contract_frames() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle/units/probe_foe", "probe_foe", Color(1, 0, 0))
	var frames: SpriteFrames = ADAPTER.sprite_frames(
		"battle_probe_foe", UNIT_STATES, UNIT_FRAME_COUNTS, base)
	assert_not_null(frames, "合同落位齐全的帧组必须装配成功。")
	if frames == null:
		return
	for state: String in UNIT_STATES:
		assert_true(frames.has_animation(state), "动画 %s 必须存在。" % state)
		assert_eq(frames.get_frame_count(state), int(UNIT_FRAME_COUNTS[state]))
	assert_eq(frames.get_animation_names().size(), UNIT_STATES.size(), "不得混入多余动画。")
	# A8 §7.3 帧节奏：idle 2fps 循环，attack 8fps 不循环，hit/death 6fps 不循环。
	assert_eq(frames.get_animation_speed("idle"), 2.0)
	assert_true(frames.get_animation_loop("idle"))
	assert_eq(frames.get_animation_speed("attack"), 8.0)
	assert_false(frames.get_animation_loop("attack"))
	assert_eq(frames.get_animation_speed("hit"), 6.0)
	assert_false(frames.get_animation_loop("hit"))
	assert_eq(frames.get_animation_speed("death"), 6.0)
	assert_false(frames.get_animation_loop("death"))
	var first_texture: Texture2D = frames.get_frame_texture("idle", 0)
	assert_not_null(first_texture)
	if first_texture != null:
		assert_eq(first_texture.get_size(), Vector2(8, 8))
		assert_eq(_pixel_of(first_texture), Color(1, 0, 0))


func test_sprite_frames_prefers_units_dir_over_phase1_and_flat() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle/units/probe_foe", "probe_foe", Color(1, 0, 0))
	_write_unit_frames(base, "battle/units/probe_foe/phase1", "probe_foe", Color(0, 1, 0))
	_write_unit_frames(base, "battle", "battle_probe_foe", Color(0, 0, 1))
	var frames: SpriteFrames = ADAPTER.sprite_frames(
		"battle_probe_foe", UNIT_STATES, UNIT_FRAME_COUNTS, base)
	assert_not_null(frames)
	if frames != null:
		var texture: Texture2D = frames.get_frame_texture("idle", 0)
		assert_eq(_pixel_of(texture), Color(1, 0, 0), "units/ 平铺目录必须优先于 phase1 与平铺。")


func test_sprite_frames_accepts_boss_phase1_dir() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle/units/probe_boss/phase1", "probe_boss", Color(0, 1, 1))
	var frames: SpriteFrames = ADAPTER.sprite_frames(
		"battle_probe_boss", UNIT_STATES, UNIT_FRAME_COUNTS, base)
	assert_not_null(frames, "Boss phase1/ 目录落位必须可解析。")
	if frames != null:
		assert_eq(_pixel_of(frames.get_frame_texture("idle", 0)), Color(0, 1, 1))


func test_sprite_frames_accepts_flat_task_dir() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle", "battle_probe_foe", Color(1, 1, 0))
	var frames: SpriteFrames = ADAPTER.sprite_frames(
		"battle_probe_foe", UNIT_STATES, UNIT_FRAME_COUNTS, base)
	assert_not_null(frames, "任务书平铺目录兜底必须生效。")
	if frames != null:
		assert_eq(_pixel_of(frames.get_frame_texture("idle", 0)), Color(1, 1, 0))


func test_sprite_frames_returns_null_when_any_frame_missing() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle/units/probe_foe", "probe_foe", Color(1, 0, 0))
	DirAccess.remove_absolute(base.path_join("battle/units/probe_foe/probe_foe_attack_01.png"))
	var frames: SpriteFrames = ADAPTER.sprite_frames(
		"battle_probe_foe", UNIT_STATES, UNIT_FRAME_COUNTS, base)
	assert_null(frames, "任一帧缺失必须整体回退 null（不产出半成品帧组）。")


func test_sprite_frames_returns_null_when_frame_count_map_incomplete() -> void:
	var base := _temp_dir
	_write_unit_frames(base, "battle/units/probe_foe", "probe_foe", Color(1, 0, 0))
	var incomplete: Dictionary = {"idle": 2}
	assert_null(
		ADAPTER.sprite_frames("battle_probe_foe", UNIT_STATES, incomplete, base),
		"帧数表缺状态必须整体失败（合同不完整不装配）。")
	var zero: Dictionary = {"idle": 2, "attack": 0, "hit": 1, "death": 2}
	assert_null(
		ADAPTER.sprite_frames("battle_probe_foe", UNIT_STATES, zero, base),
		"帧数为 0 的状态必须整体失败。")


func test_sprite_frames_returns_null_for_empty_inputs() -> void:
	assert_null(ADAPTER.sprite_frames("", UNIT_STATES, UNIT_FRAME_COUNTS, _temp_dir))
	assert_null(ADAPTER.sprite_frames("battle_probe_foe", [], UNIT_FRAME_COUNTS, _temp_dir))


# ---------------------------------------------------------------- probe


func test_probe_reports_directory_existence() -> void:
	DirAccess.make_dir_recursive_absolute(_temp_dir)
	assert_true(ADAPTER.probe(_temp_dir), "存在的 user:// 目录必须返回 true。")
	assert_false(ADAPTER.probe("user://g6p1_adapter_missing_dir"), "缺失目录必须返回 false。")
	assert_true(ADAPTER.probe("res://tests/unit"), "res:// 项目目录必须可探测。")
	assert_false(ADAPTER.probe("res://assets/art"), "生产基态 assets/art 不存在（未入库资产）。")
