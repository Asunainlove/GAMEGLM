class_name WorldConfig
extends RefCounted

## DLX-5 世界布局外置（PM 计划 DL3）：世界网格与 authored 地区配置的只读装载器。
##
## 数据源 data/world/world_config.json（schema schemas/world-config.schema.json）：
## - grid_size：世界网格 chunk 数（替代 world.gd / game_session.gd 的写死 4x2）；
## - world_seed：int|null，非 null 时覆盖快照 world_seed，null（缺省）沿用
##   GameState 快照（迁移值 null，行为逐字节等价）；
## - mine_rock_wall_color：岩壁单色 source 的 RGB（替代 world_renderer 常量）；
## - regions[]：authored 地区声明（chunk_id + layout 布局矩形 + entry 位置触发
##   入口事件链 + boss_checkpoint_min_local_y 位置检查点）。新增手工地区 = 加一个
##   JSON 条目，零代码改动（test_world_dlx5 纯数据扩区测试证明）。
##
## 装载契约（先例 Progression 链装载 / Endings 表装载）：
## - bootstrap() 缺省路径一次性装载缓存；显式 load_config_from(path) 供测试注入
##   临时配置（重复调用重装载，失败/成功都覆盖缓存）；
## - 文件缺失、坏 JSON、结构/字段/矩形/引用非法 → push_error 并**整体回退**：
##   4x2 网格、seed 覆盖 null、冻结岩壁色、无 authored region（chunk 全程序生成、
##   地区触发链为空）——失败安全优先于半配置运行；
## - 失败同样记为已引导（world/gameloop 每帧访问器不得逐帧重读坏文件）；
## - layout 在装载期归一化为强类型结构（wall_rects: Array[Rect2i]、
##   ore_rects: Array[{rect: Rect2i, type: String}]、boss_room_rect: Rect2i），
##   供 ChunkData.generate_authored 直接消费。
## 本模块只读快照/不写持久状态，不是 Autoload（仅 ContentDB/GameState/SaveService
## 可为 Autoload）；经 class_name 静态访问。

const DEFAULT_CONFIG_PATH: String = "res://data/world/world_config.json"
## 兜底网格：与迁移前 world.gd CHUNK_GRID_SIZE / game_session CHUNK_GRID_WIDTH/
## HEIGHT 常量逐字节一致。
const FALLBACK_GRID_SIZE: Vector2i = Vector2i(4, 2)
## 兜底岩壁色：与迁移前 world_renderer ROCK_WALL_COLOR 常量逐字节一致。
const FALLBACK_ROCK_WALL_COLOR: Color = Color(0.24, 0.2, 0.16)
## ore_rects.type 允许的矿种（与 ChunkData 矿格 def 家族一致）。
const ORE_TYPES: Array[String] = ["ore_dust", "ore_shard", "ore_core"]
const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"

const CONFIG_FIELDS: Array[String] = ["grid_size", "world_seed", "mine_rock_wall_color", "regions"]
const REGION_FIELDS: Array[String] = ["chunk_id", "layout", "entry", "boss_checkpoint_min_local_y"]
const LAYOUT_FIELDS: Array[String] = ["wall_rects", "ore_rects", "boss_room_rect"]
const ENTRY_FIELDS: Array[String] = ["event_id", "entered_flag"]

static var _bootstrapped: bool = false
static var _grid_size: Vector2i = FALLBACK_GRID_SIZE
static var _seed_override: Variant = null
static var _rock_wall_color: Color = FALLBACK_ROCK_WALL_COLOR
static var _regions: Array[Dictionary] = []
static var _id_regex: RegEx = null


## 缺省路径一次性装载（失败也记为已引导，见类注释）。已引导时幂等返回成功。
static func bootstrap() -> AppResult:
	if _bootstrapped:
		return AppResult.success()
	return load_config_from(DEFAULT_CONFIG_PATH)


## 显式装载指定路径（测试注入临时配置 / 坏配置修复后重载）。成功覆盖缓存；
## 失败 push_error 并整体回退兜底值。
static func load_config_from(path: String) -> AppResult:
	_bootstrapped = true
	var result: AppResult = _load_and_validate(path)
	if result.is_ok:
		var config: Dictionary = result.value
		_grid_size = config["grid_size"]
		_seed_override = config["world_seed"]
		_rock_wall_color = config["rock_wall_color"]
		_regions = config["regions"]
		return AppResult.success()
	push_error("WorldConfig: world config rejected (%s): %s" % [path, result.message])
	_apply_fallback()
	return result


## 清空缓存并恢复兜底值（供测试在临时配置与生产配置之间切换）。
static func reset_for_tests() -> void:
	_bootstrapped = false
	_apply_fallback()


static func grid_size() -> Vector2i:
	bootstrap()
	return _grid_size


## int|null：非 null 时 world 层用它覆盖快照 world_seed。
static func seed_override() -> Variant:
	bootstrap()
	return _seed_override


static func rock_wall_color() -> Color:
	bootstrap()
	return _rock_wall_color


## authored 地区声明（归一化后），数组顺序 = 文件顺序（触发链优先级序）。
static func regions() -> Array[Dictionary]:
	bootstrap()
	return _regions


## chunk_id 对应的 region 声明；无 authored 声明返回空字典（该 chunk 程序生成）。
static func region_for_chunk(chunk_id: String) -> Dictionary:
	for region: Dictionary in regions():
		if str(region.get("chunk_id", "")) == chunk_id:
			return region
	return {}


## chunk_id 对应 region 的 layout 归一化结果；无声明返回空字典。
static func layout_for_chunk(chunk_id: String) -> Dictionary:
	return region_for_chunk(chunk_id).get("layout", {}) as Dictionary


# ---------------------------------------------------------------- 装载内部


static func _apply_fallback() -> void:
	_grid_size = FALLBACK_GRID_SIZE
	_seed_override = null
	_rock_wall_color = FALLBACK_ROCK_WALL_COLOR
	_regions = []


static func _load_and_validate(path: String) -> AppResult:
	if not FileAccess.file_exists(path):
		return _fail(path, "world config file is missing.")
	var text: String = FileAccess.get_file_as_string(path)
	var open_error: Error = FileAccess.get_open_error()
	if open_error != OK:
		return _fail(path, "cannot read file (error %d)." % open_error)
	var json := JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		return _fail(path, "not valid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var parsed: Variant = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail(path, "must be a JSON object.")
	var config: Dictionary = parsed
	var result: AppResult = _reject_unknown_fields(config, CONFIG_FIELDS, path, "config")
	if not result.is_ok:
		return result
	result = _require_fields(config, ["grid_size", "regions"], path, "config")
	if not result.is_ok:
		return result

	var grid_result: AppResult = _parse_grid_size(config["grid_size"], path)
	if not grid_result.is_ok:
		return grid_result
	var grid: Vector2i = grid_result.value

	var seed_result: AppResult = _parse_seed_override(config.get("world_seed"), path)
	if not seed_result.is_ok:
		return seed_result

	var color_result: AppResult = _parse_rock_wall_color(config.get("mine_rock_wall_color"), path)
	if not color_result.is_ok:
		return color_result

	var regions_value: Variant = config["regions"]
	if typeof(regions_value) != TYPE_ARRAY:
		return _fail(path, "regions must be an array.")
	var regions: Array[Dictionary] = []
	var seen_chunks: Dictionary = {}
	var raw_regions: Array = regions_value
	for index: int in raw_regions.size():
		var region_result: AppResult = _parse_region(raw_regions[index], path, index, grid, seen_chunks)
		if not region_result.is_ok:
			return region_result
		regions.append(region_result.value)

	return AppResult.success({
		"grid_size": grid,
		"world_seed": seed_result.value,
		"rock_wall_color": color_result.value,
		"regions": regions,
	})


static func _parse_grid_size(value: Variant, path: String) -> AppResult:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return _fail(path, "grid_size must be an array of exactly 2 integers.")
	var entries: Array = value
	for entry: Variant in entries:
		# Godot JSON 把整数字面量解析为 float（先例 ContentDB._as_integral）。
		var integral: Variant = _as_int(entry)
		if integral == null or integral < 1:
			return _fail(path, "grid_size entries must be integers >= 1.")
	return AppResult.success(Vector2i(int(entries[0]), int(entries[1])))


static func _parse_seed_override(value: Variant, path: String) -> AppResult:
	if value == null:
		return AppResult.success(null)
	var integral: Variant = _as_int(value)
	if integral == null or integral < 0:
		return _fail(path, "world_seed must be a non-negative integer or null.")
	return AppResult.success(integral)


static func _parse_rock_wall_color(value: Variant, path: String) -> AppResult:
	if value == null:
		return AppResult.success(FALLBACK_ROCK_WALL_COLOR)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return _fail(path, "mine_rock_wall_color must be an array of exactly 3 numbers in 0..1.")
	var channels: Array = value
	for channel: Variant in channels:
		if typeof(channel) != TYPE_INT and typeof(channel) != TYPE_FLOAT:
			return _fail(path, "mine_rock_wall_color entries must be numbers in 0..1.")
		var component := float(channel)
		if component < 0.0 or component > 1.0:
			return _fail(path, "mine_rock_wall_color entries must be numbers in 0..1.")
	return AppResult.success(Color(float(channels[0]), float(channels[1]), float(channels[2])))


static func _parse_region(
		value: Variant, path: String, index: int, grid: Vector2i, seen_chunks: Dictionary) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(path, "regions[%d] must be an object." % index)
	var region: Dictionary = value
	var label := "regions[%d]" % index
	var result: AppResult = _reject_unknown_fields(region, REGION_FIELDS, path, label)
	if not result.is_ok:
		return result
	result = _require_fields(region, ["chunk_id", "layout"], path, label)
	if not result.is_ok:
		return result

	var chunk_id := str(region["chunk_id"])
	var grid_coords: Vector2i = ChunkData.grid_coords(chunk_id)
	if grid_coords.x < 0 or grid_coords.y < 0:
		return _fail(path, "%s chunk_id '%s' must match chunk_<x>_<y>." % [label, chunk_id])
	if grid_coords.x >= grid.x or grid_coords.y >= grid.y:
		return _fail(
			path,
			"%s chunk '%s' (grid %s) is outside the configured grid size %s."
				% [label, chunk_id, grid_coords, grid]
		)
	if seen_chunks.has(chunk_id):
		return _fail(path, "%s duplicates region chunk '%s'." % [label, chunk_id])
	seen_chunks[chunk_id] = true

	var layout_result: AppResult = _parse_layout(region["layout"], path, label)
	if not layout_result.is_ok:
		return layout_result

	var normalized: Dictionary = {
		"chunk_id": chunk_id,
		"layout": layout_result.value,
	}

	if region.has("entry"):
		var entry_result: AppResult = _parse_entry(region["entry"], path, label)
		if not entry_result.is_ok:
			return entry_result
		normalized["entry"] = entry_result.value

	if region.has("boss_checkpoint_min_local_y"):
		var min_y_integral: Variant = _as_int(region["boss_checkpoint_min_local_y"])
		if min_y_integral == null or min_y_integral < 0 or min_y_integral > ChunkData.CHUNK_SIZE:
			return _fail(
				path,
				"%s boss_checkpoint_min_local_y must be an integer in 0..%d." % [label, ChunkData.CHUNK_SIZE]
			)
		normalized["boss_checkpoint_min_local_y"] = int(min_y_integral)

	return AppResult.success(normalized)


static func _parse_layout(value: Variant, path: String, label: String) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(path, "%s.layout must be an object." % label)
	var layout: Dictionary = value
	var layout_label := "%s.layout" % label
	var result: AppResult = _reject_unknown_fields(layout, LAYOUT_FIELDS, path, layout_label)
	if not result.is_ok:
		return result
	result = _require_fields(layout, LAYOUT_FIELDS, path, layout_label)
	if not result.is_ok:
		return result

	var walls: Array[Rect2i] = []
	var walls_value: Variant = layout["wall_rects"]
	if typeof(walls_value) != TYPE_ARRAY:
		return _fail(path, "%s.wall_rects must be an array of [x,y,w,h] rects." % layout_label)
	for rect_value: Variant in walls_value as Array:
		var rect_result: AppResult = _parse_local_rect(rect_value, path, "%s.wall_rects" % layout_label)
		if not rect_result.is_ok:
			return rect_result
		walls.append(rect_result.value)

	var ores: Array[Dictionary] = []
	var ores_value: Variant = layout["ore_rects"]
	if typeof(ores_value) != TYPE_ARRAY:
		return _fail(path, "%s.ore_rects must be an array of {rect, type}." % layout_label)
	for ore_value: Variant in ores_value as Array:
		if typeof(ore_value) != TYPE_DICTIONARY:
			return _fail(path, "%s.ore_rects entries must be objects." % layout_label)
		var ore_rect: Dictionary = ore_value
		var ore_label := "%s.ore_rects" % layout_label
		result = _reject_unknown_fields(ore_rect, ["rect", "type"], path, ore_label)
		if not result.is_ok:
			return result
		result = _require_fields(ore_rect, ["rect", "type"], path, ore_label)
		if not result.is_ok:
			return result
		var rect_result: AppResult = _parse_local_rect(ore_rect["rect"], path, ore_label)
		if not rect_result.is_ok:
			return rect_result
		var ore_type := str(ore_rect["type"])
		if not ORE_TYPES.has(ore_type):
			return _fail(
				path,
				"%s.type '%s' must be one of: %s." % [ore_label, ore_type, ", ".join(PackedStringArray(ORE_TYPES))]
			)
		ores.append({"rect": rect_result.value, "type": ore_type})

	var boss_result: AppResult = _parse_local_rect(
		layout["boss_room_rect"], path, "%s.boss_room_rect" % layout_label)
	if not boss_result.is_ok:
		return boss_result

	return AppResult.success({
		"wall_rects": walls,
		"ore_rects": ores,
		"boss_room_rect": boss_result.value,
	})


static func _parse_entry(value: Variant, path: String, label: String) -> AppResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(path, "%s.entry must be an object." % label)
	var entry: Dictionary = value
	var entry_label := "%s.entry" % label
	var result: AppResult = _reject_unknown_fields(entry, ENTRY_FIELDS, path, entry_label)
	if not result.is_ok:
		return result
	result = _require_fields(entry, ENTRY_FIELDS, path, entry_label)
	if not result.is_ok:
		return result
	for field: String in ENTRY_FIELDS:
		var field_value := str(entry[field])
		if not _is_stable_id(field_value):
			return _fail(path, "%s.%s '%s' must match %s." % [entry_label, field, field_value, ID_PATTERN])
	return AppResult.success({
		"event_id": str(entry["event_id"]),
		"entered_flag": str(entry["entered_flag"]),
	})


## chunk 本地矩形 [x,y,w,h]：整数字面量（Godot JSON 解析为 float，须回整）、
## w/h >= 1、且整体不越过 CHUNK_SIZE 边界。
static func _parse_local_rect(value: Variant, path: String, label: String) -> AppResult:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 4:
		return _fail(path, "%s must be an array of exactly 4 integers [x,y,w,h]." % label)
	var parts: Array = value
	var integral_parts: Array = []
	for part: Variant in parts:
		var integral: Variant = _as_int(part)
		if integral == null:
			return _fail(path, "%s entries must be integers." % label)
		integral_parts.append(integral)
	var x := int(integral_parts[0])
	var y := int(integral_parts[1])
	var width := int(integral_parts[2])
	var height := int(integral_parts[3])
	if x < 0 or y < 0:
		return _fail(path, "%s position must be non-negative." % label)
	if width < 1 or height < 1:
		return _fail(path, "%s size must be at least 1." % label)
	if x + width > ChunkData.CHUNK_SIZE or y + height > ChunkData.CHUNK_SIZE:
		return _fail(path, "%s must stay inside the %dx%d chunk." % [label, ChunkData.CHUNK_SIZE, ChunkData.CHUNK_SIZE])
	return AppResult.success(Rect2i(x, y, width, height))


static func _reject_unknown_fields(source: Dictionary, allowed: Array[String], path: String, label: String) -> AppResult:
	for field: Variant in source.keys():
		if not allowed.has(str(field)):
			return _fail(path, "%s has unknown field '%s'." % [label, str(field)])
	return AppResult.success()


static func _require_fields(source: Dictionary, required: Array[String], path: String, label: String) -> AppResult:
	for field: String in required:
		if not source.has(field):
			return _fail(path, "%s is missing required field '%s'." % [label, field])
	return AppResult.success()


static func _fail(path: String, detail: String) -> AppResult:
	return AppResult.failure("invalid_world_config", "World config %s: %s" % [path, detail])


## 整数字面量归一：TYPE_INT 直通；TYPE_FLOAT 仅在值本身为整数时回 int（先例
## ContentDB._as_integral——Godot JSON 把整数字面量解析为 float）。其余 null。
static func _as_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_finite(number) and number == floor(number):
			return int(number)
	return null


static func _is_stable_id(value: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_PATTERN)
	var match_result: RegExMatch = _id_regex.search(value)
	return match_result != null and match_result.get_string(0) == value
