class_name BattleScene
extends Node2D

## WP13 战斗场景（灰盒）：契约 docs/plans/contracts/module-contracts.md §4/§5。
## begin_encounter 经 EncounterDirector.start 组装 config、用真实 CombatEngine
## create_battle 建局；每个战斗单位渲染为 ColorRect+Label 灰盒节点并按
## front/mid/rear 行排（盟友居左、敌人居右）。轮到盟友时 ActionsBox 为其
## action_ids 生成 Button（中文文案来自 action_defs）；按下后自动选目标并
## submit_action——引擎内置的敌方回合循环随后自动结算，直到轮到下一位盟友
## 或战斗结束。结束时经 EncounterDirector.finish（store 注入，null → GameState）
## 落账并发出 encounter_finished。表现层不直接改持久状态，全部经 store 注入路径。
##
## W003-A4 战斗表现增强（缺口报告 C2）：场景只消费引擎 log，不改引擎——
## - 相位横幅：log 出现 phase_change → 屏幕上方红橙横幅（2s 淡出）；
## - 回合横幅：每回合开始 → "第 N 回合" 短横幅（1s）；
## - 战报面板：UI 右侧最近 3 条 log 的中文摘要（行动名+目标+数字，error 暗色）；
## - 胜负横幅：finished → 全屏 "胜利！"/"败北……"（胜利金/败北暗紫）；横幅与
##   encounter_finished 同帧同步——信号时序不变（game_session 的卸载流程与
##   既有集成测试均依赖 finish 当帧落账+发信号），横幅期间输入锁定禁止再提交行动；
## - 失稳标记：destabilized 单位色块闪紫 + 标签"失稳"；guard 单位标签"防护"。
## 测试注入缝：engine_script 可替换为同 static 签名的桩引擎（默认真实引擎）。

signal encounter_finished(encounter_id: String, outcome: Dictionary)

const DIRECTOR_SCRIPT: Script = preload("res://src/encounters/encounter_director.gd")
const COMBAT_ENGINE_SCRIPT: Script = preload("res://src/combat/combat_engine.gd")

const TRACK_ROWS: Array[String] = ["front", "mid", "rear"]
const ROW_SPACING: float = 96.0
const ALLY_ORIGIN: Vector2 = Vector2(96.0, 120.0)
const ENEMY_ORIGIN: Vector2 = Vector2(560.0, 120.0)
const UNIT_SPACING: float = 120.0
const ALLY_COLOR: Color = Color(0.42, 0.52, 0.66)
const ENEMY_COLOR: Color = Color(0.62, 0.4, 0.38)
const BOSS_COLOR: Color = Color(0.72, 0.5, 0.2)
const MAX_AUTO_TURNS: int = 64

# --- W003-A4 表现层常量（文案全原创中文；只消费引擎 log）---------------------------

const PHASE_BANNER_FORMAT: String = "⚠ 相位失稳！%s变了样子！"
const ROUND_BANNER_FORMAT: String = "第 %d 回合"
const VICTORY_TEXT: String = "胜利！"
const DEFEAT_TEXT: String = "败北……"
const BANNER_FADE_SECONDS: float = 0.4
const FLASH_SPEED: float = 6.0
const PHASE_BANNER_COLOR: Color = Color(1.0, 0.45, 0.2)
const ROUND_BANNER_COLOR: Color = Color(0.95, 0.88, 0.62)
const VICTORY_COLOR: Color = Color(1.0, 0.84, 0.28)
const DEFEAT_COLOR: Color = Color(0.5, 0.33, 0.66)
const DESTABILIZED_COLOR: Color = Color(0.62, 0.3, 0.82)
const DESTABILIZED_TAG: String = "失稳"
const GUARD_TAG: String = "防护"
const TAG_SEPARATOR: String = "｜"
const REPORT_MAX_LINES: int = 3
const REPORT_TEXT_COLOR: Color = Color(0.92, 0.92, 0.9)
const REPORT_ERROR_COLOR: Color = Color(0.45, 0.45, 0.5)
const ERROR_CODE_TEXT: Dictionary = {
	"battle_finished": "战斗已结束",
	"unknown_unit": "未知单位",
	"not_active_unit": "该单位不在行动中",
	"unknown_action": "未知行动",
	"invalid_target": "无效目标",
	"insufficient_cost": "费用不足",
}

## 契约 §0 注入模式：落账 store，null → GameState autoload。
var store: Object = null

## G6P-1 任务 3：单位资产适配缝——渲染前经 AssetAdapter.sprite_frames 探测单位
## contract 形态（A8 §2，asset id = battle_<unit_id>，帧 8：idle2/attack3/hit1/
## death2）；命中 → AnimatedSprite2D 替换灰盒 Box（血量/状态 Label 保留叠加，
## 精灵底边中心对齐灰盒底边 +20 px，A8 §2 挂点契约）；缺失 → 现状灰盒逐字节
## 不变。asset_base_dir 可注入（测试 user://；生产 res://assets/art）。
## Boss phase2 精灵替换属后续接线包（本包只落 phase1 形态探测）。
const UNIT_SPRITE_STATES: Array[String] = ["idle", "attack", "hit", "death"]
const UNIT_SPRITE_FRAME_COUNTS: Dictionary = {"idle": 2, "attack": 3, "hit": 1, "death": 2}
const UNIT_SPRITE_BOTTOM_Y: float = 20.0
## 与 AssetAdapter.DEFAULT_BASE_DIR 同值（跨类常量默认参受限，就地镜像）。
const DEFAULT_ASSET_BASE_DIR: String = "res://assets/art"

var asset_base_dir: String = DEFAULT_ASSET_BASE_DIR

## W003-A4 测试注入缝：战斗引擎脚本（须提供与 CombatEngine 同签名的 static
## create_battle/submit_action/is_finished/active_unit/outcome）；默认真实引擎。
var engine_script: Script = COMBAT_ENGINE_SCRIPT

## W003-A10：可选 AudioDirector（由 GameSession 注入）。缺席时战斗 SFX 静默跳过。
var audio_director: Node = null

## W003-A4 表现层时序（可注入；默认＝任务书 2s/1s/2s）。
var phase_banner_seconds: float = 2.0
var round_banner_seconds: float = 1.0
var finish_banner_seconds: float = 2.0

var _encounter_def: Dictionary = {}
var _config: Dictionary = {}
var _battle: Dictionary = {}
var _last_finish_result: AppResult = null

# W003-A4 表现层内部状态（全部瞬态，不入持久状态）。
var _processed_log_count: int = 0
var _input_locked: bool = false
var _phase_tween: Tween = null
var _round_tween: Tween = null
var _flash_clock: float = 0.0

# G6P-1 单位资产装配记账（每次 _rebuild_tracks 重置；混合态一次性汇总告警）。
var _asset_loaded_units: int = 0
var _asset_missing_unit_ids: PackedStringArray = PackedStringArray()
var _asset_warning_emitted: bool = false


# --- 对外流程 --------------------------------------------------------------------


## 开局：director.start 组装 config → 引擎 create_battle → 灰盒渲染 + UI；
## 若先手为敌方单位（如 Boss 速度更高），自动结算敌方回合直到轮到盟友或结束。
func _play_sfx(sfx_id: String, volume_offset_db: float = 0.0) -> void:
	if audio_director == null or not audio_director.has_method("play_sfx"):
		return
	if audio_director.get_method_argument_count("play_sfx") >= 2:
		audio_director.call("play_sfx", sfx_id, volume_offset_db)
	else:
		audio_director.call("play_sfx", sfx_id)


func _play_bgm(track_id: String, fade_seconds: float = 1.0) -> void:
	if audio_director == null or not audio_director.has_method("play_bgm"):
		return
	if audio_director.get_method_argument_count("play_bgm") >= 2:
		audio_director.call("play_bgm", track_id, fade_seconds)
	else:
		audio_director.call("play_bgm", track_id)


func begin_encounter(encounter_def: Dictionary, content: Dictionary) -> void:
	_encounter_def = encounter_def.duplicate(true)
	_config = DIRECTOR_SCRIPT.start(_encounter_def, content)
	_battle = engine_script.create_battle(_config)
	_processed_log_count = 0
	_input_locked = false
	# 第 1 回合同样是"回合开始"：点亮回合横幅，再消费开局已有的 log 增量。
	_show_round_banner(int(_battle.get("turn", 1)))
	_consume_log_events()
	_resolve_enemy_turns()


## 当前战斗状态（转瞬态 Dictionary，非持久状态；供观察者与测试读取）。
func battle_state() -> Dictionary:
	return _battle


func last_finish_result() -> AppResult:
	return _last_finish_result


## 盟友行动入口（ActionsBox 按钮按下同样走这里）：自动选目标并提交；
## 引擎在结算后自动推进并连续结算敌方回合，直到轮到下一位盟友或战斗结束。
## W003-A4：胜负横幅期间（输入锁定）禁止再提交行动。
func play_ally_action(action_id: String) -> void:
	if _input_locked or engine_script.is_finished(_battle):
		return
	var active: Dictionary = engine_script.active_unit(_battle)
	if active.is_empty() or str(active.get("side", "")) != "ally":
		return
	var action := str(action_id)
	var target_key := _auto_target(_battle, active, action)
	_play_sfx("sfx_battle_action")
	_battle = engine_script.submit_action(_battle, str(active.get("key", "")), action, target_key)
	_consume_log_events()
	_resolve_enemy_turns()


# --- 内部回合推进 -----------------------------------------------------------------


## 引擎的 submit_action 已内置"敌方回合连续自动结算"；此循环兜底处理
## 开局先手为敌方、以及任何返回时 active 仍为敌方的边界（带安全上限）。
func _resolve_enemy_turns() -> void:
	var guard := 0
	while not engine_script.is_finished(_battle) and guard < MAX_AUTO_TURNS:
		var active: Dictionary = engine_script.active_unit(_battle)
		if active.is_empty() or str(active.get("side", "")) != "enemy":
			break
		_play_sfx("sfx_battle_action", -3.0)
		_battle = engine_script.submit_action(_battle, str(active.get("key", "")), "", "")
		_consume_log_events()
		guard += 1
	if engine_script.is_finished(_battle):
		_finish_battle()
	else:
		_refresh_view()


## 目标自动选择：single_enemy → 第一活敌（order 序）；single_ally → 最低 hp
## 活友（平局取 order 靠前，与引擎 AI 规则一致）；self / all_enemies → 空目标。
func _auto_target(battle: Dictionary, actor: Dictionary, action_id: String) -> String:
	var action_defs: Dictionary = _as_dictionary(battle.get("action_defs", {}))
	var action: Dictionary = _as_dictionary(action_defs.get(action_id, {}))
	match str(action.get("targeting", "")):
		"single_enemy":
			return _first_living_key(battle, "enemy")
		"single_ally":
			return _lowest_hp_living_key(battle, "ally")
		"self":
			# G7P-1 修复：self 型行动（防护）的目标必须是行动者自身，
			# 否则引擎判 invalid_target 且对局不再推进（防护按钮实际不可用）。
			return str(actor.get("key", ""))
		_:
			return ""


func _first_living_key(battle: Dictionary, side: String) -> String:
	for key: Variant in _as_array(battle.get("order", [])):
		var unit: Dictionary = _find_unit(battle, str(key))
		if not unit.is_empty() and bool(unit.get("alive", false)) and str(unit.get("side", "")) == side:
			return str(unit.get("key", ""))
	return ""


func _lowest_hp_living_key(battle: Dictionary, side: String) -> String:
	var best_key := ""
	var best_hp := 0
	for key: Variant in _as_array(battle.get("order", [])):
		var unit: Dictionary = _find_unit(battle, str(key))
		if unit.is_empty() or not bool(unit.get("alive", false)):
			continue
		if str(unit.get("side", "")) != side:
			continue
		var hp := int(unit.get("hp", 0))
		if best_key == "" or hp < best_hp:
			best_key = str(unit.get("key", ""))
			best_hp = hp
	return best_key


func _finish_battle() -> void:
	var outcome: Dictionary = engine_script.outcome(_battle)
	# W003-A4：胜负横幅与 finish 同帧同步——先点亮横幅并锁定输入，再照常落账、
	# 发信号（encounter_finished 时序不变，game_session 据此卸载场景）。
	_input_locked = true
	_show_finish_banner(str(outcome.get("result", "")))
	# W002-GAP4 道具经济：把盟友战斗中的实际道具消耗并入 outcome，
	# 经 director.finish 的 remove_item 通道回写库存（victory/defeat 均回写）。
	var spent: Dictionary = DIRECTOR_SCRIPT.spent_items(
		_config.get("allies", []), _battle.get("units", []))
	if not spent.is_empty():
		outcome["items_spent"] = spent
	# finish 是 EncounterDirector 的实例方法（check_triggers/start 才是静态），
	# 因此这里实例化纯逻辑 director 再落账（无状态，用完即释）。
	var director: EncounterDirector = DIRECTOR_SCRIPT.new()
	_last_finish_result = director.finish(_snapshot_state(), _encounter_def, outcome, store)
	_refresh_view()
	encounter_finished.emit(str(_encounter_def.get("id", "")), outcome)


func _snapshot_state() -> Dictionary:
	if store == null:
		return GameState.snapshot()
	if store.has_method("snapshot"):
		var value: Variant = store.call("snapshot")
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {}


# --- 灰盒渲染 ---------------------------------------------------------------------


func _refresh_view() -> void:
	_rebuild_tracks()
	_refresh_turn_label()
	_refresh_actions()
	_refresh_report()


func _track_row(track: String) -> Node2D:
	var tracks: Node2D = get_node_or_null("Tracks") as Node2D
	if tracks == null:
		return null
	var row_name := "Row_%s" % track
	var row: Node2D = tracks.get_node_or_null(row_name) as Node2D
	if row == null:
		row = Node2D.new()
		row.name = row_name
		tracks.add_child(row)
	return row


func _rebuild_tracks() -> void:
	var tracks: Node2D = get_node_or_null("Tracks") as Node2D
	if tracks == null:
		return
	for track: String in TRACK_ROWS:
		var existing_row: Node2D = _track_row(track)
		if existing_row != null:
			_clear_children(existing_row)
	_asset_loaded_units = 0
	_asset_missing_unit_ids = PackedStringArray()
	var ally_columns: Dictionary = {}
	var enemy_columns: Dictionary = {}
	for unit: Dictionary in _as_array(_battle.get("units", [])):
		var track := str(unit.get("track", "front"))
		var row: Node2D = _track_row(track)
		if row == null:
			continue
		var columns: Dictionary = ally_columns if str(unit.get("side", "")) == "ally" else enemy_columns
		var column := int(columns.get(track, 0))
		columns[track] = column + 1
		var unit_node: Node2D = _build_unit_node(unit, column)
		row.add_child(unit_node)
		unit_node.add_to_group("battle_unit")
	_maybe_warn_partial_unit_assets()


func _build_unit_node(unit: Dictionary, column: int) -> Node2D:
	var side := str(unit.get("side", ""))
	var track := str(unit.get("track", "front"))
	var row_index := TRACK_ROWS.find(track)
	if row_index < 0:
		row_index = 0
	var origin := ALLY_ORIGIN if side == "ally" else ENEMY_ORIGIN
	var unit_node := Node2D.new()
	unit_node.name = _unit_node_name(str(unit.get("key", "")))
	unit_node.position = origin + Vector2(float(column) * UNIT_SPACING, float(row_index) * ROW_SPACING)

	var color := ENEMY_COLOR
	if str(unit.get("kind", "")) == "boss":
		color = BOSS_COLOR
	elif side == "ally":
		color = ALLY_COLOR
	var destabilized := bool(unit.get("destabilized", false))
	unit_node.set_meta("base_color", color)
	unit_node.set_meta("destabilized", destabilized)

	# G6P-1：资产命中 → 精灵形态；缺失 → 现状灰盒 Box（逐字节不变）。
	var sprite := _build_unit_sprite(str(unit.get("unit_id", "")))
	if sprite != null:
		_asset_loaded_units += 1
		unit_node.add_child(sprite)
	else:
		_asset_missing_unit_ids.append(_asset_probe_name(unit))
		var box := ColorRect.new()
		box.name = "Box"
		box.position = Vector2(-28.0, -20.0)
		box.size = Vector2(56.0, 40.0)
		box.color = DESTABILIZED_COLOR if destabilized else color
		unit_node.add_child(box)

	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(-36.0, -42.0)
	label.size = Vector2(72.0, 18.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# W003-A4：失稳/防护状态标签（失稳优先，二者可并存）。
	var tags := ""
	if destabilized:
		tags += TAG_SEPARATOR + DESTABILIZED_TAG
	if float(unit.get("guard_ratio", 0.0)) > 0.0:
		tags += TAG_SEPARATOR + GUARD_TAG
	label.text = "%s %d/%d%s" % [
		str(unit.get("name_zh", "")),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		tags,
	]
	unit_node.add_child(label)
	return unit_node


## 单位资产探测：contract 形态 id = battle_<unit_id>（A8 §2 命名基准）。
## 命中 → AnimatedSprite2D（idle 循环，底边中心对齐灰盒底边 +20 px）；缺失 → null。
func _build_unit_sprite(unit_id: String) -> AnimatedSprite2D:
	if unit_id.is_empty():
		return null
	var frames := AssetAdapter.sprite_frames(
		"battle_" + unit_id, UNIT_SPRITE_STATES, UNIT_SPRITE_FRAME_COUNTS, asset_base_dir)
	if frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	var anchor_height := unit_sprite_anchor_height(frames)
	sprite.position = Vector2(0.0, UNIT_SPRITE_BOTTOM_Y - anchor_height / 2.0)
	var animation := "idle" if frames.has_animation("idle") else str(frames.get_animation_names()[0])
	sprite.play(animation)
	return sprite


## 精灵锚定高度：首帧纹理高（纯函数，测试断言用；A8 §2 底边中心锚定）。
static func unit_sprite_anchor_height(frames: SpriteFrames) -> float:
	for animation: StringName in frames.get_animation_names():
		if frames.get_frame_count(animation) > 0:
			var texture := frames.get_frame_texture(animation, 0)
			if texture != null:
				return float(texture.get_height())
	return 0.0


## 缺资产记账名（unit_id 优先，缺则回退单位 key）。
func _asset_probe_name(unit: Dictionary) -> String:
	var unit_id := str(unit.get("unit_id", ""))
	return unit_id if unit_id != "" else str(unit.get("key", ""))


## 混合态（部分单位命中、部分缺失）一次性 push_warning 汇总；全缺失（生产基态）
## 静默；已发过一次的本场景实例不再重复。
func _maybe_warn_partial_unit_assets() -> void:
	if _asset_warning_emitted or _asset_loaded_units <= 0 or _asset_missing_unit_ids.is_empty():
		return
	push_warning(unit_asset_warning(_asset_missing_unit_ids))
	_asset_warning_emitted = true


## 混合态汇总文案（纯函数，测试断言用）。
static func unit_asset_warning(missing_unit_ids: PackedStringArray) -> String:
	if missing_unit_ids.is_empty():
		return ""
	return "BattleScene: 战斗单位资产部分缺失，%d 个单位回退灰盒：%s（合同 docs/art/battle-assets.md §2）" % [
		missing_unit_ids.size(), ", ".join(missing_unit_ids),
	]


func _unit_node_name(unit_key: String) -> String:
	var sanitized := unit_key.replace("|", "_")
	return sanitized if sanitized != "" else "unit"


func _clear_children(node: Node) -> void:
	# 立即释放（而非 remove_child + queue_free）：树外节点 queue_free 无效会泄漏；
	# 灰盒与按钮都不被外部引用，同步 free 保持同帧节点计数准确。
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


# --- UI 刷新 ---------------------------------------------------------------------


func _refresh_turn_label() -> void:
	var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var label: Label = ui.get_node_or_null("TurnLabel") as Label
	if label == null:
		return
	label.text = "第 %d 回合" % int(_battle.get("turn", 0))


func _refresh_actions() -> void:
	var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var actions_box: VBoxContainer = ui.get_node_or_null("ActionsBox") as VBoxContainer
	if actions_box == null:
		return
	_clear_children(actions_box)
	if _input_locked or engine_script.is_finished(_battle):
		return
	var active: Dictionary = engine_script.active_unit(_battle)
	if active.is_empty() or str(active.get("side", "")) != "ally":
		return
	var action_defs: Dictionary = _as_dictionary(_battle.get("action_defs", {}))
	for action_id: Variant in _as_array(active.get("action_ids", [])):
		var action := str(action_id)
		var button := Button.new()
		button.text = str(_as_dictionary(action_defs.get(action, {})).get("name_zh", action))
		button.pressed.connect(_on_action_button_pressed.bind(action))
		actions_box.add_child(button)


func _on_action_button_pressed(action_id: String) -> void:
	# 延迟到空闲帧执行：refresh 会同步 free 发出 pressed 信号的按钮本身，
	# 信号发射过程中立即 free 发射者不安全，因此先让发射完成。
	play_ally_action.call_deferred(action_id)


# --- W003-A4 表现层：log 消费与横幅 -------------------------------------------------

## 消费 _battle.log 的未处理增量（场景只读 log，绝不写回）：
## phase_change → 相位横幅；round_start → 回合横幅；随后刷新战报面板。
func _consume_log_events() -> void:
	var entries: Array = _as_array(_battle.get("log", []))
	while _processed_log_count < entries.size():
		var entry: Dictionary = _as_dictionary(entries[_processed_log_count])
		_processed_log_count += 1
		match str(entry.get("type", "")):
			"phase_change":
				_play_sfx("sfx_boss_phase")
				_play_bgm("bgm_boss_final", 0.5)
				_show_phase_banner(entry)
			"damage":
				_play_sfx("sfx_battle_hit")
			"round_start":
				_show_round_banner(int(entry.get("turn", 1)))
	_refresh_report()


func _ui_layer() -> CanvasLayer:
	return get_node_or_null("UI") as CanvasLayer


func _banner_label(node_path: String) -> Label:
	var ui: CanvasLayer = _ui_layer()
	if ui == null:
		return null
	return ui.get_node_or_null(node_path) as Label


## 闪现横幅：立即整幅可见，保持 seconds - BANNER_FADE_SECONDS 后淡出并隐藏；
## 同一横幅重复点亮时先终止上一次的淡出动画，避免双动画争抢。
func _flash_banner(label: Label, text: String, seconds: float, previous: Tween) -> Tween:
	if previous != null and previous.is_valid():
		previous.kill()
	if label == null:
		return null
	label.text = text
	label.modulate.a = 1.0
	label.visible = true
	var tween := create_tween()
	tween.tween_interval(maxf(0.0, seconds - BANNER_FADE_SECONDS))
	tween.tween_property(label, "modulate:a", 0.0, BANNER_FADE_SECONDS)
	tween.tween_callback(func() -> void: label.visible = false)
	return tween


func _show_phase_banner(entry: Dictionary) -> void:
	var text := PHASE_BANNER_FORMAT % _display_name(str(entry.get("unit", "")))
	_phase_tween = _flash_banner(_banner_label("PhaseBanner"), text, phase_banner_seconds, _phase_tween)


func _show_round_banner(turn: int) -> void:
	var text := ROUND_BANNER_FORMAT % maxi(1, turn)
	_round_tween = _flash_banner(_banner_label("RoundBanner"), text, round_banner_seconds, _round_tween)


## 胜负横幅：全屏遮罩 + 居中大字（胜利金 / 败北暗紫）。与 finish 同帧点亮，
## 持续到场景卸载；时长常量仅描述设计展示时长（信号时序不变）。
func _show_finish_banner(result: String) -> void:
	var ui: CanvasLayer = _ui_layer()
	if ui == null:
		return
	var label: Label = ui.get_node_or_null("FinishBanner/FinishLabel") as Label
	if label == null:
		return
	var victory := result == "victory"
	label.text = VICTORY_TEXT if victory else DEFEAT_TEXT
	label.add_theme_color_override("font_color", VICTORY_COLOR if victory else DEFEAT_COLOR)
	label.visible = true
	var overlay: Control = ui.get_node_or_null("FinishBanner") as Control
	if overlay != null:
		overlay.visible = true


# --- W003-A4 表现层：战报面板 -------------------------------------------------------

## UI 右侧战报面板：最近 REPORT_MAX_LINES 条 log 的中文摘要；
## error 条目以暗色显示。逐条重渲（灰盒，条数极小）。
func _refresh_report() -> void:
	var ui: CanvasLayer = _ui_layer()
	if ui == null:
		return
	var panel: VBoxContainer = ui.get_node_or_null("ReportPanel") as VBoxContainer
	if panel == null:
		return
	_clear_children(panel)
	for entry: Dictionary in _report_entries():
		var line := Label.new()
		line.text = str(entry["text"])
		if bool(entry["error"]):
			line.add_theme_color_override("font_color", REPORT_ERROR_COLOR)
		else:
			line.add_theme_color_override("font_color", REPORT_TEXT_COLOR)
		panel.add_child(line)


## 战报摘要文本（供测试与面板共用）：action 与其后随 damage/heal 聚合为一行
## "行动者 → 目标：行动名 N 伤害/N 治疗"；其余 log 类型各自成行。
func report_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in _report_entries():
		lines.append(str(entry["text"]))
	return lines


func _report_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pending := ""
	for value: Variant in _as_array(_battle.get("log", [])):
		var entry: Dictionary = _as_dictionary(value)
		var entry_type := str(entry.get("type", ""))
		if entry_type == "damage" and pending != "":
			pending += " %d 伤害" % maxi(0, int(entry.get("amount", 0)))
			continue
		if entry_type == "heal" and pending != "":
			pending += " %d 治疗" % maxi(0, int(entry.get("amount", 0)))
			continue
		if pending != "":
			entries.append({"text": pending, "error": false})
			pending = ""
		match entry_type:
			"action":
				pending = _action_summary(entry)
			"damage":
				entries.append({
					"text": "%s 受到 %d 伤害" % [
						_display_name(str(entry.get("target", ""))),
						maxi(0, int(entry.get("amount", 0))),
					],
					"error": false,
				})
			"heal":
				entries.append({
					"text": "%s 恢复 %d 治疗" % [
						_display_name(str(entry.get("target", ""))),
						maxi(0, int(entry.get("amount", 0))),
					],
					"error": false,
				})
			"guard":
				entries.append({"text": "%s：进入防护" % _display_name(str(entry.get("unit", ""))), "error": false})
			"item_used":
				entries.append({
					"text": "%s：使用道具 ×%d" % [
						_display_name(str(entry.get("unit", ""))),
						maxi(1, int(entry.get("count", 1))),
					],
					"error": false,
				})
			"destabilized":
				entries.append({"text": "%s：失稳！" % _display_name(str(entry.get("unit", ""))), "error": false})
			"destabilized_recover":
				entries.append({"text": "%s：失稳恢复" % _display_name(str(entry.get("unit", ""))), "error": false})
			"turn_skipped":
				entries.append({"text": "%s：跳过回合（失稳）" % _display_name(str(entry.get("unit", ""))), "error": false})
			"action_skipped":
				entries.append({"text": "%s：行动无法结算（费用不足）" % _display_name(str(entry.get("unit", ""))), "error": false})
			"defeated":
				entries.append({"text": "%s：倒下了" % _display_name(str(entry.get("unit", ""))), "error": false})
			"phase_change":
				entries.append({"text": "%s：进入新相位" % _display_name(str(entry.get("unit", ""))), "error": false})
			"round_start":
				entries.append({"text": "第 %d 回合开始" % maxi(1, int(entry.get("turn", 1))), "error": false})
			"battle_end":
				var result_text := "胜利" if str(entry.get("result", "")) == "victory" else "败北"
				entries.append({"text": "战斗结束：%s" % result_text, "error": false})
			"error":
				entries.append({"text": "⚠ %s" % _error_text(entry), "error": true})
			_:
				pass
	if pending != "":
		entries.append({"text": pending, "error": false})
	var latest: Array[Dictionary] = []
	var start := maxi(0, entries.size() - REPORT_MAX_LINES)
	for index: int in range(start, entries.size()):
		latest.append(entries[index])
	return latest


func _action_summary(entry: Dictionary) -> String:
	var actor := _display_name(str(entry.get("unit", "")))
	var targets: Array[String] = []
	for value: Variant in _as_array(entry.get("targets", [])):
		targets.append(_display_name(str(value)))
	var action_name := _action_name(str(entry.get("action", "")))
	if targets.is_empty():
		return "%s：%s" % [actor, action_name]
	return "%s → %s：%s" % [actor, "、".join(targets), action_name]


func _action_name(action_id: String) -> String:
	var defs: Dictionary = _as_dictionary(_battle.get("action_defs", {}))
	var name_zh := str(_as_dictionary(defs.get(action_id, {})).get("name_zh", ""))
	return name_zh if name_zh != "" else action_id


func _display_name(unit_key: String) -> String:
	var unit: Dictionary = _find_unit(_battle, unit_key)
	var name_zh := str(unit.get("name_zh", ""))
	if name_zh != "":
		return name_zh
	return unit_key if unit_key != "" else "未知单位"


func _error_text(entry: Dictionary) -> String:
	return str(ERROR_CODE_TEXT.get(str(entry.get("code", "")), "行动无效"))


# --- W003-A4 表现层：失稳闪紫 -------------------------------------------------------

## 每帧刷新失稳单位的反馈：灰盒形态闪 Box 色；资产精灵形态（G6P-1）闪
## self_modulate（白↔紫，同一纯函数——基色取白色即"无色调"常态）。
func _process(delta: float) -> void:
	_flash_clock += delta
	var tree := get_tree()
	if tree == null:
		return
	for node: Variant in tree.get_nodes_in_group("battle_unit"):
		var unit_node := node as Node2D
		if unit_node == null or not bool(unit_node.get_meta("destabilized", false)):
			continue
		var box := unit_node.get_node_or_null("Box") as ColorRect
		var base: Color = unit_node.get_meta("base_color", ENEMY_COLOR)
		if box != null:
			box.color = destabilized_box_color(base, _flash_clock)
			continue
		var sprite := unit_node.get_node_or_null("Sprite") as Node2D
		if sprite != null:
			sprite.self_modulate = destabilized_box_color(Color.WHITE, _flash_clock)


## 失稳色块颜色：clock=0 → 基色与紫色的中点；clock=PI/(2*FLASH_SPEED) → 全紫；
## clock=PI/FLASH_SPEED*1.5 → 回到基色（flash 周期的低谷）。
static func destabilized_box_color(base: Color, clock: float) -> Color:
	var pulse := 0.5 + 0.5 * sin(clock * FLASH_SPEED)
	return base.lerp(DESTABILIZED_COLOR, pulse)


# --- 内部工具 ---------------------------------------------------------------------


func _find_unit(battle: Dictionary, unit_key: String) -> Dictionary:
	for unit: Dictionary in _as_array(battle.get("units", [])):
		if str(unit.get("key", "")) == unit_key:
			return unit
	return {}


static func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
