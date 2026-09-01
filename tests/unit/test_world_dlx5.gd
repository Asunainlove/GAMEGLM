extends GutTest

## DLX-5 世界布局外置（PM 计划 DL3）RED/GREEN 测试。
##
## 覆盖四条验收线：
## 1. 迁移等价快照：world_config.json 与旧 GDScript 常量逐字节一致；按 JSON
##    矩形独立重导出的 cells 与 generate_authored 输出全等（同 seed 行为不变）；
## 2. 纯数据扩区：测试内临时 world_config 追加第二个 authored region，
##    world 生成与 GameSession 触发链（入口事件/Boss 检查点/clamp）零代码生效；
## 3. 坏配置拒绝：缺失/非法矩形/缺字段 → load 失败 + push_error + 4x2 兜底；
## 4. enriched 与 authored 兼容：world_response_exploited 对 authored chunk
##    布局无影响（裁决：仅程序生成 chunk 富集）。

const CHUNK_DATA: Script = preload("res://src/world/chunk_data.gd")
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")
const WORLD_SCENE_PATH: String = "res://scenes/world.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue_box.tscn"

const SHIPPED_CONFIG_PATH: String = "res://data/world/world_config.json"
const MINE_CHUNK_ID: String = "chunk_3_1"
const EXPLOITED_FLAG: String = "world_response_exploited"

## 冻结迁移对照表：旧 chunk_data.gd 常量的逐字节快照（W002-GAP2 authored 矿井）。
const FROZEN_GRID_SIZE: Vector2i = Vector2i(4, 2)
const FROZEN_ROCK_WALL_COLOR: Color = Color(0.24, 0.2, 0.16)
const FROZEN_WALL_RECTS: Array[Rect2i] = [
	Rect2i(0, 0, 32, 8),
	Rect2i(14, 8, 18, 2),
	Rect2i(0, 10, 12, 3),
	Rect2i(14, 10, 18, 3),
	Rect2i(0, 13, 6, 9),
	Rect2i(26, 13, 6, 9),
	Rect2i(0, 22, 10, 10),
	Rect2i(20, 22, 12, 10),
]
const FROZEN_ORE_VEINS: Dictionary = {
	"ore_dust": [Rect2i(3, 8, 6, 2), Rect2i(17, 13, 6, 2)],
	"ore_shard": [Rect2i(7, 15, 4, 4), Rect2i(14, 15, 4, 4)],
	"ore_core": [Rect2i(8, 19, 3, 3), Rect2i(20, 19, 3, 3), Rect2i(24, 16, 2, 3)],
}
const FROZEN_BOSS_ROOM_RECT: Rect2i = Rect2i(10, 22, 10, 10)
const FROZEN_ENTRY_EVENT_ID: String = "event_mine_threshold"
const FROZEN_ENTERED_FLAG: String = "mine_entered"
const FROZEN_BOSS_MIN_LOCAL_Y: int = 22

static var _temp_file_seq: int = 0

var _teardown_nodes: Array[Node] = []


func before_each() -> void:
	WorldConfig.reset_for_tests()


func after_each() -> void:
	for node: Node in _teardown_nodes:
		if is_instance_valid(node):
			node.free()
	_teardown_nodes.clear()
	WorldConfig.reset_for_tests()


# --------------------------------------------------------------- 1. 迁移等价快照


func test_shipped_config_migrates_frozen_values_byte_for_byte() -> void:
	var result: AppResult = WorldConfig.bootstrap()
	assert_true(result.is_ok, "生产 world_config.json 必须装载成功：%s" % result.message)
	assert_eq(WorldConfig.grid_size(), FROZEN_GRID_SIZE, "grid_size 必须与旧 CHUNK_GRID_SIZE 常量一致。")
	assert_null(WorldConfig.seed_override(), "world_seed 缺省必须为 null（沿用 GameState 快照 seed）。")
	assert_eq(WorldConfig.rock_wall_color(), FROZEN_ROCK_WALL_COLOR, "岩壁色必须与旧渲染常量一致。")
	var regions: Array[Dictionary] = WorldConfig.regions()
	assert_eq(regions.size(), 1, "迁移期恰好一个 authored region（chunk_3_1）。")
	if regions.size() != 1:
		return
	var region: Dictionary = regions[0]
	assert_eq(str(region.get("chunk_id", "")), MINE_CHUNK_ID)
	var layout: Dictionary = region.get("layout", {}) as Dictionary
	assert_eq(layout.get("wall_rects", []) as Array, FROZEN_WALL_RECTS, "8 块岩壁矩形必须逐字节迁移。")
	assert_eq(layout.get("boss_room_rect", Rect2i()), FROZEN_BOSS_ROOM_RECT, "Boss 房矩形必须逐字节迁移。")
	var ore_rects: Array = layout.get("ore_rects", []) as Array
	assert_eq(ore_rects.size(), 7, "7 条矿脉矩形必须逐字节迁移。")
	for ore_rect_value: Variant in ore_rects:
		var ore_rect: Dictionary = ore_rect_value
		var rect: Rect2i = ore_rect.get("rect", Rect2i())
		var ore_type := str(ore_rect.get("type", ""))
		assert_true(
			FROZEN_ORE_VEINS.has(ore_type) and (FROZEN_ORE_VEINS[ore_type] as Array).has(rect),
			"矿脉矩形 (%s, %s) 必须与旧 MINE_ORE_VEINS 常量逐字节一致。" % [ore_type, rect]
		)
	var entry: Dictionary = region.get("entry", {}) as Dictionary
	assert_eq(str(entry.get("event_id", "")), FROZEN_ENTRY_EVENT_ID, "入口事件必须逐字节迁移。")
	assert_eq(str(entry.get("entered_flag", "")), FROZEN_ENTERED_FLAG, "entered flag 必须逐字节迁移。")
	assert_eq(int(region.get("boss_checkpoint_min_local_y", -1)), FROZEN_BOSS_MIN_LOCAL_Y, "Boss 检查 y>=22 必须逐字节迁移。")


func test_generate_authored_matches_independent_json_rederivation() -> void:
	# 等价证明：从迁移后的 JSON 原始矩形独立重导出 cells（不经过被测解析器），
	# 与 generate_authored 输出全等 —— 证明外置数据在 chunk_data 语义下逐格一致。
	assert_true(WorldConfig.bootstrap().is_ok)
	var parsed: Variant = _parse_json_file(SHIPPED_CONFIG_PATH)
	assert_true(parsed is Dictionary, "前置：world_config.json 必须可解析。")
	if not (parsed is Dictionary):
		return
	var raw_layout: Dictionary = ((parsed as Dictionary)["regions"] as Array)[0]["layout"]
	var expected: Dictionary = {}
	for wall_value: Variant in raw_layout["wall_rects"]:
		_fill_raw_rect(expected, wall_value, "rock_wall")
	for ore_value: Variant in raw_layout["ore_rects"]:
		var ore_rect: Dictionary = ore_value
		_fill_raw_rect(expected, ore_rect["rect"], str(ore_rect["type"]))
	# Boss 房仅标记不填格：重导出不消费 boss_room_rect，generate_authored 同样不填。
	var authored: Dictionary = CHUNK_DATA.generate_authored(
		MINE_CHUNK_ID, WorldConfig.layout_for_chunk(MINE_CHUNK_ID))
	assert_eq(str(authored.get("chunk_id", "")), MINE_CHUNK_ID)
	assert_eq(authored["cells"], expected, "generate_authored 必须与 JSON 矩形独立重导出逐格全等。")


func test_generate_authored_is_deterministic_and_independent_of_world_seed() -> void:
	assert_true(WorldConfig.bootstrap().is_ok)
	var layout: Dictionary = WorldConfig.layout_for_chunk(MINE_CHUNK_ID)
	var first: Dictionary = CHUNK_DATA.generate_authored(MINE_CHUNK_ID, layout)
	var second: Dictionary = CHUNK_DATA.generate_authored(MINE_CHUNK_ID, layout)
	assert_eq(first, second, "authored 生成是纯数据填充，同 layout 两次调用必须全等。")
	assert_true(first.has("cells"), "返回结构必须与 generate 一致（cells 字典）。")
	assert_eq(
		CHUNK_DATA.generate_authored("chunk_9_9", layout)["cells"], first["cells"],
		"authored 生成不依赖 RNG/seed，chunk_id 只透传。"
	)


func test_generate_authored_marks_boss_room_without_filling_cells() -> void:
	assert_true(WorldConfig.bootstrap().is_ok)
	var cells: Dictionary = CHUNK_DATA.generate_authored(
		MINE_CHUNK_ID, WorldConfig.layout_for_chunk(MINE_CHUNK_ID))["cells"]
	for y: int in range(FROZEN_BOSS_ROOM_RECT.position.y, FROZEN_BOSS_ROOM_RECT.end.y):
		for x: int in range(FROZEN_BOSS_ROOM_RECT.position.x, FROZEN_BOSS_ROOM_RECT.end.x):
			assert_false(
				cells.has(Vector2i(x, y)),
				"Boss 房格 (%d, %d) 必须保持开阔无矿（boss_room_rect 仅标记不填格）。" % [x, y]
			)


# --------------------------------------------------------------- 2. 纯数据扩区


func test_second_authored_region_is_pure_data_extension_for_world_and_triggers() -> void:
	var extension_chunk := "chunk_0_0"
	var entry_event := "event_drift_aftermath"
	var config := {
		"grid_size": [4, 2],
		"world_seed": null,
		"mine_rock_wall_color": [0.24, 0.2, 0.16],
		"regions": [
			{
				"chunk_id": MINE_CHUNK_ID,
				"layout": {
					"wall_rects": _raw_rects(FROZEN_WALL_RECTS),
					"ore_rects": _raw_ore_rects(FROZEN_ORE_VEINS),
					"boss_room_rect": _raw_rect(FROZEN_BOSS_ROOM_RECT),
				},
				"entry": {"event_id": FROZEN_ENTRY_EVENT_ID, "entered_flag": FROZEN_ENTERED_FLAG},
				"boss_checkpoint_min_local_y": FROZEN_BOSS_MIN_LOCAL_Y,
			},
			{
				"chunk_id": extension_chunk,
				"layout": {
					"wall_rects": [[0, 0, 32, 4], [0, 12, 32, 2]],
					"ore_rects": [{"rect": [4, 6, 3, 3], "type": "ore_core"}],
					"boss_room_rect": [10, 14, 6, 4],
				},
				"entry": {"event_id": entry_event, "entered_flag": "dlx5_region_entered"},
				"boss_checkpoint_min_local_y": 14,
			},
		],
	}
	var load_result: AppResult = WorldConfig.load_config_from(_write_temp_config(config))
	assert_true(load_result.is_ok, "临时双地区配置必须装载成功：%s" % load_result.message)

	# 集成侧：world 与 session 读同一注入 store（与 test_integration_mine 同型）。
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	var save_root := "user://saves_dlx5_ext_%d_%d" % [Time.get_ticks_msec(), _temp_file_seq]
	assert_true(SaveService.configure_root_for_tests(save_root).is_ok)
	var world: Node2D = _make_world(store)
	if world == null:
		return

	# world 侧：第二个 authored chunk 覆盖程序生成（零代码）。
	var expected_extension: Dictionary = CHUNK_DATA.generate_authored(
		extension_chunk, WorldConfig.layout_for_chunk(extension_chunk))
	assert_eq(
		_observed_cells(world, extension_chunk), expected_extension["cells"],
		"第二个 authored region 必须纯数据覆盖 chunk_0_0 的程序生成结果。"
	)

	var session := _make_session(store, world)
	_patch_flags(store, ["event_event_prologue_landing_done"])
	# 玩家格 (5,15)：在 chunk_0_0 内、本地 y>=14（新地区 Boss 检查带）。
	_set_player_cell(session, Vector2i(5, 15))
	session.tick()
	assert_eq(
		session.active_event_id, entry_event,
		"新增地区的 entry.event_id 必须经既有事件链按位置触发（零代码扩区）。"
	)
	assert_eq(
		(store.snapshot()["player"] as Dictionary).get("position", {}),
		{"x": 5, "y": 15},
		"新增地区 boss_checkpoint_min_local_y 必须驱动 set_player_position 检查点。"
	)


func test_second_region_respects_entered_and_done_flag_dedup() -> void:
	var config := {
		"grid_size": [4, 2],
		"regions": [
			{
				"chunk_id": "chunk_0_0",
				"layout": {
					"wall_rects": [],
					"ore_rects": [],
					"boss_room_rect": [0, 0, 1, 1],
				},
				"entry": {"event_id": "event_drift_aftermath", "entered_flag": "dlx5_region_entered"},
				"boss_checkpoint_min_local_y": 0,
			},
		],
	}
	assert_true(WorldConfig.load_config_from(_write_temp_config(config)).is_ok)
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	var save_root := "user://saves_dlx5_dedup_%d_%d" % [Time.get_ticks_msec(), _temp_file_seq]
	assert_true(SaveService.configure_root_for_tests(save_root).is_ok)
	var session := _make_session(store, null)
	# 无 world 场景：经 player_cell_provider 注入玩家格（GameSession 既有注入缝）。
	session.player_cell_provider = func() -> Vector2i: return Vector2i(5, 7)
	_patch_flags(store, ["event_event_prologue_landing_done", "dlx5_region_entered",
		"event_event_drift_aftermath_done"])
	session.tick()
	assert_eq(
		session.active_event_id, "",
		"entered_flag/事件 done 任一置位时新地区入口事件不得重播（幂等泛化）。"
	)
	assert_null(session.battle, "无到期遭遇时不得启动战斗。")


func test_resolve_chunk_id_clamps_by_configured_grid_size() -> void:
	var config := {
		"grid_size": [2, 1],
		"regions": [],
	}
	assert_true(WorldConfig.load_config_from(_write_temp_config(config)).is_ok)
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	var save_root := "user://saves_dlx5_clamp_%d_%d" % [Time.get_ticks_msec(), _temp_file_seq]
	assert_true(SaveService.configure_root_for_tests(save_root).is_ok)
	var session := _make_session(store, null)
	assert_eq(
		session.call("_resolve_chunk_id", Vector2i(100, 40)), "chunk_1_0",
		"越界格必须按配置网格 (2,1) clamp 到东南 chunk。"
	)
	assert_eq(
		session.call("_resolve_chunk_id", Vector2i(-5, -5)), "chunk_0_0",
		"负格必须按配置网格 clamp 到原点 chunk。"
	)


# --------------------------------------------------------------- 3. 坏配置拒绝


func test_missing_config_file_pushes_error_and_falls_back_to_frozen_grid() -> void:
	var result: AppResult = WorldConfig.load_config_from("user://dlx5_missing_world_config.json")
	assert_false(result.is_ok, "缺失 world_config 必须装载失败。")
	# 规范要求坏配置 push_error；GUT 的预期错误断言同时消费该错误。
	assert_push_error("WorldConfig: world config rejected")
	assert_eq(WorldConfig.grid_size(), FROZEN_GRID_SIZE, "坏配置必须兜底 4x2 网格。")
	assert_true(WorldConfig.regions().is_empty(), "坏配置必须兜底为无 authored region。")
	assert_null(WorldConfig.seed_override(), "坏配置必须兜底 world_seed=null（沿用快照）。")
	assert_eq(WorldConfig.rock_wall_color(), FROZEN_ROCK_WALL_COLOR, "坏配置必须兜底冻结岩壁色。")


func test_invalid_wall_rect_rejects_config_and_falls_back() -> void:
	# wall_rect 非法：宽度溢出 chunk 边界（x+w=40 > 32）。
	var config := {
		"grid_size": [4, 2],
		"regions": [
			{
				"chunk_id": "chunk_0_0",
				"layout": {
					"wall_rects": [[0, 0, 40, 2]],
					"ore_rects": [],
					"boss_room_rect": [0, 0, 1, 1],
				},
				"entry": {"event_id": "event_drift_aftermath", "entered_flag": "dlx5_entered"},
				"boss_checkpoint_min_local_y": 0,
			},
		],
	}
	var result: AppResult = WorldConfig.load_config_from(_write_temp_config(config))
	assert_false(result.is_ok, "非法 wall_rect 必须整包拒绝。")
	assert_push_error("WorldConfig: world config rejected")
	assert_eq(WorldConfig.grid_size(), FROZEN_GRID_SIZE, "拒绝后必须兜底 4x2。")
	assert_true(WorldConfig.regions().is_empty(), "拒绝后必须兜底为无 region（chunk 全程序生成）。")


func test_missing_layout_field_rejects_config_and_falls_back() -> void:
	var config := {
		"grid_size": [4, 2],
		"regions": [
			{
				"chunk_id": "chunk_0_0",
				"layout": {"wall_rects": [], "ore_rects": []},
			},
		],
	}
	var result: AppResult = WorldConfig.load_config_from(_write_temp_config(config))
	assert_false(result.is_ok, "layout 缺 boss_room_rect 字段必须拒绝。")
	assert_push_error("WorldConfig: world config rejected")
	assert_true(WorldConfig.regions().is_empty(), "拒绝后必须兜底为无 region。")


func test_world_renders_fully_procedural_after_bad_config_fallback() -> void:
	var result: AppResult = WorldConfig.load_config_from("user://dlx5_missing_world_config.json")
	assert_false(result.is_ok)
	assert_push_error("WorldConfig: world config rejected")
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	var world: Node2D = _make_world(store)
	if world == null:
		return
	assert_eq(
		_observed_cells(world, MINE_CHUNK_ID),
		CHUNK_DATA.generate(MINE_CHUNK_ID, 0, false)["cells"],
		"坏配置兜底后 chunk_3_1 必须回退程序生成（不残留 authored 布局）。"
	)


# --------------------------------------------------------------- 4. enriched 与 authored 兼容


func test_enriched_flag_does_not_change_authored_layout() -> void:
	assert_true(WorldConfig.bootstrap().is_ok)
	var store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(store)
	var plain: Node2D = _make_world(store)
	if plain == null:
		return
	var plain_cells: Dictionary = _observed_cells(plain, MINE_CHUNK_ID)
	var exploited_store: Node = GAME_STATE_SCRIPT.new()
	_teardown_nodes.append(exploited_store)
	var revision := int((exploited_store.snapshot() as Dictionary)["revision"])
	var patch: StatePatch = exploited_store.call("begin_patch", "test_dlx5_exploit_%d" % revision, revision)
	patch.set_flag(EXPLOITED_FLAG, true)
	var committed: AppResult = exploited_store.call("commit", patch)
	assert_true(committed.is_ok, committed.message)
	var exploited: Node2D = _make_world(exploited_store)
	if exploited == null:
		return
	assert_eq(
		_observed_cells(exploited, MINE_CHUNK_ID), plain_cells,
		"exploited flag 不得改变 authored chunk 布局（裁决：仅程序生成 chunk 富集）。"
	)
	assert_eq(
		_observed_cells(exploited, MINE_CHUNK_ID),
		CHUNK_DATA.generate_authored(MINE_CHUNK_ID, WorldConfig.layout_for_chunk(MINE_CHUNK_ID))["cells"],
		"authored chunk 在富集 flag 下仍与 generate_authored 全等。"
	)


# --------------------------------------------------------------- 工具


func _parse_json_file(path: String) -> Variant:
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		fail_test("JSON 解析失败: %s" % path)
		return null
	return json.get_data()


func _fill_raw_rect(cells: Dictionary, raw_rect: Variant, cell_type: String) -> void:
	var parts: Array = raw_rect
	for y: int in range(int(parts[1]), int(parts[1]) + int(parts[3])):
		for x: int in range(int(parts[0]), int(parts[0]) + int(parts[2])):
			cells[Vector2i(x, y)] = cell_type


func _raw_rect(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _raw_rects(rects: Array[Rect2i]) -> Array:
	var raw: Array = []
	for rect: Rect2i in rects:
		raw.append(_raw_rect(rect))
	return raw


func _raw_ore_rects(veins: Dictionary) -> Array:
	var raw: Array = []
	for ore_type: String in veins:
		for rect: Rect2i in veins[ore_type]:
			raw.append({"rect": _raw_rect(rect), "type": ore_type})
	return raw


func _write_temp_config(config: Dictionary) -> String:
	_temp_file_seq += 1
	var path := "user://dlx5_world_config_%d_%d.json" % [Time.get_ticks_msec(), _temp_file_seq]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(config, "  "))
	file.close()
	return path


func _make_world(store: Object) -> Node2D:
	var world_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	assert_not_null(world_scene, "world.tscn must exist and load.")
	if world_scene == null:
		return null
	var world := world_scene.instantiate() as Node2D
	assert_not_null(world)
	if world == null:
		return null
	world.set("snapshot_provider", Callable(store, "snapshot"))
	add_child_autofree(world)
	return world


## 只读扫描 chunk 的非土壤格集合（本地格 → 类型），与 generate 输出同构。
func _observed_cells(world: Node2D, chunk_id: String) -> Dictionary:
	var observed: Dictionary = {}
	var origin := ChunkData.chunk_origin(chunk_id)
	for y: int in 32:
		for x: int in 32:
			var definition: Dictionary = world.call("cell_def_at", chunk_id, Vector2i(x, y) + origin)
			var cell_type := str(definition.get("type", "soil"))
			if cell_type != "soil":
				observed[Vector2i(x, y)] = cell_type
	return observed


func _make_session(store: Object, world_node: Node2D) -> GameSession:
	var session := GameSession.new()
	session.store = store
	if world_node != null:
		session.world = world_node
	var packed := load(DIALOGUE_SCENE_PATH) as PackedScene
	var dialogue := packed.instantiate() as DialogueBox
	add_child_autofree(dialogue)
	session.dialogue_box = dialogue
	add_child_autofree(session)
	return session


func _set_player_cell(session: GameSession, cell: Vector2i) -> void:
	var player_node: Node2D = session.player as Node2D
	assert_not_null(player_node, "session 必须绑定 world 内的 player。")
	if player_node != null:
		player_node.position = Vector2(cell) * 32.0


func _patch_flags(store: Object, flag_ids: Array) -> void:
	var revision := int((store.call("snapshot") as Dictionary)["revision"])
	var patch: StatePatch = store.call("begin_patch", "test_dlx5_flags_%d" % revision, revision)
	for flag_id: String in flag_ids:
		patch.set_flag(flag_id, true)
	var committed: AppResult = store.call("commit", patch)
	assert_true(committed.is_ok, committed.message)
