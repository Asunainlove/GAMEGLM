extends GutTest

## G6P-1 任务 3：战斗单位资产适配契约测试（TDD：先于实现编写）。
##
## 契约：
## - 资产缺失（生产基态 / 注入空目录）→ 单位节点保持灰盒（Box ColorRect +
##   Label），节点结构与 W003-A4 基线逐字节一致，零告警；
## - 注入合同帧（A8 §7.2 battle/units/<unit_id>/<unit_id>_<state>_<NN>.png，
##   8 帧：idle2/attack3/hit1/death2）→ Box 被精灵节点替换，血量/状态 Label
##   保留叠加，精灵底边中心对齐灰盒底边（原点 +20 px，A8 §2 挂点契约）；
## - 失稳单位的闪紫反馈在精灵形态下经 self_modulate 脉动（同一纯函数）。
## 测试经 asset_base_dir 注入 user:// 临时帧目录（生产恒为 res://assets/art）。

const BATTLE_SCENE_PATH: String = "res://scenes/battle.tscn"
const GAME_STATE_SCRIPT: Script = preload("res://src/state/game_state.gd")

const UNIT_STATES: Array = ["idle", "attack", "hit", "death"]
const UNIT_FRAME_COUNTS: Dictionary = {"idle": 2, "attack": 3, "hit": 1, "death": 2}

var _temp_dir: String = ""
var _finished_events: Array[Dictionary] = []


func before_each() -> void:
	_finished_events.clear()
	StubEngine.battle_template = {}
	StubEngine.submit_calls = 0
	_temp_dir = "user://g6p1_battle_assets_%d" % Time.get_ticks_usec()


func after_each() -> void:
	_remove_dir_recursive(_temp_dir)
	_temp_dir = ""


# --- 桩引擎（仅表现层测试使用；签名与 CombatEngine 一致）--------------------------


class StubEngine:
	static var battle_template: Dictionary = {}
	static var submit_calls: int = 0

	static func create_battle(_config: Dictionary) -> Dictionary:
		return battle_template.duplicate(true)

	static func submit_action(
			battle: Dictionary, _unit_key: String, _action_id: String, _target_key: String
	) -> Dictionary:
		submit_calls += 1
		return battle.duplicate(true)

	static func is_finished(battle: Dictionary) -> bool:
		return bool(battle.get("finished", false))

	static func active_unit(battle: Dictionary) -> Dictionary:
		var order: Array = battle.get("order", [])
		var index := int(battle.get("active_index", 0))
		if index < 0 or index >= order.size():
			return {}
		for unit: Dictionary in battle.get("units", []):
			if str(unit.get("key", "")) == str(order[index]):
				return unit.duplicate(true)
		return {}

	static func outcome(battle: Dictionary) -> Dictionary:
		return {
			"result": str(battle.get("result", "")),
			"turns": int(battle.get("turn", 0)),
			"drops": [],
		}


# ---------------------------------------------------------------- 工具


func _write_frame(dir: String, file_name: String, color: Color) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	assert_eq(image.save_png(dir.path_join(file_name)), OK, "帧 PNG 写入必须成功。")


func _write_unit_frames(unit_sub_dir: String, stem: String) -> void:
	var frame_dir := _temp_dir.path_join(unit_sub_dir)
	for state: String in UNIT_STATES:
		for index: int in int(UNIT_FRAME_COUNTS[state]):
			_write_frame(frame_dir, "%s_%s_%02d.png" % [stem, state, index], Color(0, 1, 0))


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


func _on_encounter_finished(encounter_id: String, outcome: Dictionary) -> void:
	_finished_events.append({"id": encounter_id, "outcome": outcome})


func _stub_battle(destabilized: bool = false) -> Dictionary:
	return {
		"battle_id": "battle_probe",
		"seed": 0,
		"turn": 1,
		"units": [{
			"key": "a0|probe", "unit_id": "probe_unit", "side": "ally", "kind": "ally",
			"name_zh": "探针单位", "track": "front", "hp": 20, "max_hp": 20, "speed": 6,
			"action_ids": [], "alive": true, "guard_ratio": 0.0,
			"destabilized": destabilized, "phases": [],
		}],
		"order": ["a0|probe"],
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"action_defs": {},
		"stub_steps": [],
	}


func _make_scene(battle: Dictionary) -> Node2D:
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	if packed == null:
		fail_test("Missing required implementation: %s" % BATTLE_SCENE_PATH)
		return null
	var scene: Node2D = packed.instantiate() as Node2D
	if scene == null:
		fail_test("battle.tscn 根节点必须为 Node2D。")
		return null
	add_child_autofree(scene)
	if scene.get("engine_script") == null:
		fail_test("BattleScene 缺少可注入属性 engine_script。")
		return null
	scene.set("store", null)
	scene.set("engine_script", StubEngine)
	scene.connect("encounter_finished", Callable(self, "_on_encounter_finished"))
	scene.set("asset_base_dir", _temp_dir)
	StubEngine.battle_template = battle
	scene.call("begin_encounter", {"id": "probe_encounter"}, {})
	return scene


func _probe_unit_node(scene: Node2D) -> Node2D:
	return scene.get_node_or_null("Tracks/Row_front/a0_probe") as Node2D


# ---------------------------------------------------------------- 契约测试


func test_missing_unit_assets_render_greybox() -> void:
	# 注入目录为空（无任何帧）→ 灰盒不变。
	var scene: Node2D = _make_scene(_stub_battle())
	if scene == null:
		return
	var unit_node: Node2D = _probe_unit_node(scene)
	assert_not_null(unit_node, "单位节点必须照常创建。")
	if unit_node == null:
		return
	assert_not_null(unit_node.get_node_or_null("Box") as ColorRect, "灰盒 Box 必须保留。")
	assert_null(unit_node.get_node_or_null("Sprite"), "缺资产不得出现精灵节点。")
	var label: Label = unit_node.get_node("Label") as Label
	assert_eq(label.text, "探针单位 20/20", "灰盒 Label 文案保持基线。")
	assert_eq(_finished_events.size(), 0, "灰盒路径不得改变信号时序。")


func test_injected_frames_replace_box_with_sprite() -> void:
	_write_unit_frames("battle/units/probe_unit", "probe_unit")
	var scene: Node2D = _make_scene(_stub_battle())
	if scene == null:
		return
	var unit_node: Node2D = _probe_unit_node(scene)
	assert_not_null(unit_node)
	if unit_node == null:
		return
	var sprite: AnimatedSprite2D = unit_node.get_node_or_null("Sprite") as AnimatedSprite2D
	assert_not_null(sprite, "命中资产必须以精灵节点替换灰盒 Box。")
	if sprite == null:
		return
	assert_null(unit_node.get_node_or_null("Box"), "精灵形态下灰盒 Box 必须移除。")
	var label: Label = unit_node.get_node("Label") as Label
	assert_not_null(label, "血量/状态 Label 必须保留叠加。")
	assert_eq(label.text, "探针单位 20/20", "Label 文案保持基线。")
	# A8 §2 挂点：精灵底边中心对齐灰盒底边（原点 +20 px）；8×8 帧 → y = 20 - 4。
	assert_eq(sprite.position, Vector2(0.0, 16.0))
	# A8 §7.3：idle 循环播放。
	assert_eq(sprite.animation, &"idle")
	assert_true(sprite.is_playing(), "idle 动画必须处于播放态。")
	var frames: SpriteFrames = sprite.sprite_frames
	for state: String in UNIT_STATES:
		assert_eq(frames.get_frame_count(state), int(UNIT_FRAME_COUNTS[state]))
	assert_eq(frames.get_animation_speed("attack"), 8.0)
	assert_false(frames.get_animation_loop("death"))


func test_destabilized_sprite_flash_driven_by_process() -> void:
	_write_unit_frames("battle/units/probe_unit", "probe_unit")
	var scene: Node2D = _make_scene(_stub_battle(true))
	if scene == null:
		return
	var unit_node: Node2D = _probe_unit_node(scene)
	assert_not_null(unit_node)
	if unit_node == null:
		return
	assert_true(bool(unit_node.get_meta("destabilized", false)), "失稳元数据保持基线语义。")
	var sprite: AnimatedSprite2D = unit_node.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite)
	if sprite == null:
		return
	scene.call("_process", 0.0)
	var modulated: Color = sprite.self_modulate
	# clock=0 → 白↔紫中点：b 高于 r/g（紫色方向脉动）。
	assert_true(
		modulated.b > modulated.r and modulated.b > modulated.g,
		"精灵形态的失稳反馈必须按白↔紫脉动。")


# --- 生产接线（#36/#37/#41/#42 v2 满 8 帧白名单）----------------------------------------


func test_production_wired_units_resolve_eight_flat_frames() -> void:
	## 扁平合同路径 assets/art/battle/units/<id>/<id>_<state>_<NN>.png
	var wired: Array[String] = ["luoxian_fighter", "misa_weaver", "drift_swarmling", "shard_husk", "veinwarden_echo"]
	for unit_id: String in wired:
		var frames: SpriteFrames = AssetAdapter.sprite_frames(
			"battle_" + unit_id, UNIT_STATES, UNIT_FRAME_COUNTS
		)
		assert_not_null(frames, "%s must resolve production SpriteFrames." % unit_id)
		if frames == null:
			continue
		for state: String in UNIT_STATES:
			assert_eq(
				frames.get_frame_count(state),
				int(UNIT_FRAME_COUNTS[state]),
				"%s/%s frame count." % [unit_id, state],
			)
		assert_eq(frames.get_animation_speed("idle"), 2.0)
		assert_true(frames.get_animation_loop("idle"))
		assert_eq(frames.get_animation_speed("attack"), 8.0)
		assert_false(frames.get_animation_loop("attack"))


func test_production_allowlist_wires_approved_units_keeps_unapproved_graybox() -> void:
	## 生产目录：白名单单位 → Sprite；未批 Boss（lumen_leviathan）→ 灰盒，且不记缺失告警。
	var battle := {
		"battle_id": "battle_wire_probe",
		"seed": 0,
		"turn": 1,
		"units": [
			{
				"key": "a0|luoxian_fighter", "unit_id": "luoxian_fighter", "side": "ally",
				"kind": "ally", "name_zh": "洛弦", "track": "front", "hp": 40, "max_hp": 40,
				"speed": 5, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "a1|misa_weaver", "unit_id": "misa_weaver", "side": "ally",
				"kind": "ally", "name_zh": "弥砂", "track": "mid", "hp": 30, "max_hp": 30,
				"speed": 6, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "e0|drift_swarmling", "unit_id": "drift_swarmling", "side": "enemy",
				"kind": "enemy_normal", "name_zh": "漂游幼群", "track": "front", "hp": 18,
				"max_hp": 18, "speed": 7, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "e1|shard_husk", "unit_id": "shard_husk", "side": "enemy",
				"kind": "enemy_normal", "name_zh": "碎壳", "track": "mid", "hp": 22,
				"max_hp": 22, "speed": 4, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "e2|veinwarden_echo", "unit_id": "veinwarden_echo", "side": "enemy",
				"kind": "enemy_elite", "name_zh": "脉守回响", "track": "rear", "hp": 50,
				"max_hp": 50, "speed": 3, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
			{
				"key": "e3|lumen_leviathan", "unit_id": "lumen_leviathan", "side": "enemy",
				"kind": "enemy_boss", "name_zh": "流明巨兽", "track": "front", "hp": 120,
				"max_hp": 120, "speed": 2, "action_ids": [], "alive": true, "guard_ratio": 0.0,
				"destabilized": false, "phases": [],
			},
		],
		"order": ["a0|luoxian_fighter"],
		"active_index": 0,
		"log": [],
		"finished": false,
		"result": "",
		"action_defs": {},
		"stub_steps": [],
	}
	var packed: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	var scene: Node2D = packed.instantiate() as Node2D
	add_child_autofree(scene)
	scene.set("store", null)
	scene.set("engine_script", StubEngine)
	# 生产默认目录（不注入 temp）——触发白名单。
	scene.set("asset_base_dir", "res://assets/art")
	StubEngine.battle_template = battle
	scene.call("begin_encounter", {"id": "wire_probe"}, {})

	var luoxian: Node2D = scene.get_node_or_null("Tracks/Row_front/a0_luoxian_fighter") as Node2D
	var misa: Node2D = scene.get_node_or_null("Tracks/Row_mid/a1_misa_weaver") as Node2D
	var swarm: Node2D = scene.get_node_or_null("Tracks/Row_front/e0_drift_swarmling") as Node2D
	var husk: Node2D = scene.get_node_or_null("Tracks/Row_mid/e1_shard_husk") as Node2D
	var echo: Node2D = scene.get_node_or_null("Tracks/Row_rear/e2_veinwarden_echo") as Node2D
	var levi: Node2D = scene.get_node_or_null("Tracks/Row_front/e3_lumen_leviathan") as Node2D
	assert_not_null(luoxian)
	assert_not_null(misa)
	assert_not_null(swarm)
	assert_not_null(husk)
	assert_not_null(echo)
	assert_not_null(levi)
	if luoxian == null or misa == null or swarm == null or husk == null or echo == null or levi == null:
		return

	assert_not_null(luoxian.get_node_or_null("Sprite") as AnimatedSprite2D)
	assert_null(luoxian.get_node_or_null("Box"))
	assert_not_null(misa.get_node_or_null("Sprite") as AnimatedSprite2D)
	assert_null(misa.get_node_or_null("Box"))
	var swarm_sprite: AnimatedSprite2D = swarm.get_node_or_null("Sprite") as AnimatedSprite2D
	assert_not_null(swarm_sprite)
	assert_true(swarm_sprite.flip_h, "Enemy sprites must face left (A8).")
	assert_null(swarm.get_node_or_null("Box"))
	var husk_sprite: AnimatedSprite2D = husk.get_node_or_null("Sprite") as AnimatedSprite2D
	assert_not_null(husk_sprite, "shard_husk must be wired.")
	assert_true(husk_sprite.flip_h, "Enemy shard_husk must face left (A8).")
	assert_null(husk.get_node_or_null("Box"))
	var echo_sprite: AnimatedSprite2D = echo.get_node_or_null("Sprite") as AnimatedSprite2D
	assert_not_null(echo_sprite, "veinwarden_echo must be wired.")
	assert_true(echo_sprite.flip_h, "Enemy veinwarden_echo must face left (A8).")
	assert_null(echo.get_node_or_null("Box"))
	# Elite 192×192: anchor height follows texture (no extra scale factor).
	var echo_frames: SpriteFrames = echo_sprite.sprite_frames
	assert_eq(
		int(BattleScene.unit_sprite_anchor_height(echo_frames)),
		192,
		"veinwarden_echo idle texture height must be elite 192.",
	)
	assert_not_null(levi.get_node_or_null("Box") as ColorRect, "Unapproved Boss stays graybox.")
	assert_null(levi.get_node_or_null("Sprite"), "lumen_leviathan must not be wired.")

	var luoxian_sprite: AnimatedSprite2D = luoxian.get_node("Sprite") as AnimatedSprite2D
	var frames: SpriteFrames = luoxian_sprite.sprite_frames
	for state: String in UNIT_STATES:
		assert_eq(frames.get_frame_count(state), int(UNIT_FRAME_COUNTS[state]))
	var husk_frames: SpriteFrames = husk_sprite.sprite_frames
	for state: String in UNIT_STATES:
		assert_eq(husk_frames.get_frame_count(state), int(UNIT_FRAME_COUNTS[state]), "shard_husk/%s" % state)
	for state: String in UNIT_STATES:
		assert_eq(echo_frames.get_frame_count(state), int(UNIT_FRAME_COUNTS[state]), "veinwarden_echo/%s" % state)
