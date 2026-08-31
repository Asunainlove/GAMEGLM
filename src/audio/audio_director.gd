class_name AudioDirector
extends Node

## W003-A9 音频框架（纯代码节点，headless 可测）。
##
## 全游戏当前零音频资产：本框架把"可发声"准备好——所有播放入口经注入的
## resolver（Callable）取流，resolver 未注入 / 返回 null / 返回非 AudioStream
## 时 push_warning 并忽略该次请求，游戏在无任何音频资产时零崩溃、零行为差异。
##
## 挂点约定（本包不改任何调用方，接线清单见 docs/art/audio-assets.md §6）：
## - 实例化：由 app 层负责（W003-A10 标题包在 app.tscn / 标题场景中
##   `AudioDirector.new()` 并 add_child；本包未改任何场景与 project.godot）。
## - resolver 注入：app 层设置 `track_resolver` / `sfx_resolver`
##   （track_id/sfx_id -> AudioStream；典型实现是 res://assets/audio/** 下的
##   load 映射）。缺省总线布局（仅 Master）下播放器回退 Master 总线运行；
##   协调者提交 Master→BGM/SFX 总线布局后，运行时创建的本节点自动绑定目标总线。
## - 调用方注入：事件 / 战斗 / 建造 / 存档等系统通过持有本节点引用调用
##   play_bgm / play_sfx / stop_all / set_master_muted；表现层不落账，
##   音频是纯表现状态，不进 GameState / SaveService。
##
## 行为契约：
## - play_bgm：同曲重入（含换曲淡入进行中）忽略；换曲先淡出旧流再淡入新流
##   （Tween 控制 volume_db，谷底 -60 dB，headless 下同样按帧推进）。
##   fade_seconds <= 0 时立即硬切（测试与无淡入需求场景用）。
## - play_sfx：8 槽 AudioStreamPlayer 轮转（第 9 次覆盖第 1 槽，旧音自然截断）。
## - set_master_muted：操作 AudioServer 的 Master 总线静音（全局开关）。
## - bgm_history：最近 8 条 track_id（最新在末尾，观察用日志，不参与行为）；
##   stop_all 会重置当前曲目选择（重播同曲不算重入）但保留历史。

const BGM_BUS_NAME: StringName = &"BGM"
const SFX_BUS_NAME: StringName = &"SFX"
const MASTER_BUS_NAME: StringName = &"Master"
const SFX_POOL_SIZE: int = 8
const BGM_HISTORY_LIMIT: int = 8
const BGM_VOLUME_DB: float = 0.0
const FADE_FLOOR_DB: float = -60.0

## 注入点：track_id -> AudioStream（BGM 曲目解析）。
var track_resolver: Callable = Callable()

## 注入点：sfx_id -> AudioStream（音效解析）。
var sfx_resolver: Callable = Callable()

## 最近 8 条 BGM track_id（最新在末尾；观察用，测试与调试可读）。
var bgm_history: Array[String] = []

## SFX 轮转池（_ready 代码创建的 8 个槽，只读观察用）。
var sfx_players: Array[AudioStreamPlayer] = []

var _bgm_player: AudioStreamPlayer = null
var _current_track_id: String = ""
var _next_sfx_index: int = 0
var _fade_tween: Tween = null
var _master_muted: bool = false


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	_bgm_player.bus = _effective_bus(BGM_BUS_NAME)
	add_child(_bgm_player)
	var pool_root := Node.new()
	pool_root.name = "SfxPool"
	add_child(pool_root)
	for index: int in SFX_POOL_SIZE:
		var slot := AudioStreamPlayer.new()
		slot.name = "Slot%02d" % index
		slot.bus = _effective_bus(SFX_BUS_NAME)
		pool_root.add_child(slot)
		sfx_players.append(slot)


# ---------------------------------------------------------------- BGM


## 播放/切换 BGM。同曲重入忽略（换曲淡入进行中同样忽略）；换曲先淡出旧流、
## 再换流淡入新流。fade_seconds <= 0 或当前无播放时立即起播。
func play_bgm(track_id: String, fade_seconds: float = 1.0) -> void:
	if track_id.is_empty():
		push_warning("AudioDirector.play_bgm: empty track_id ignored.")
		return
	if track_id == _current_track_id and _bgm_player.playing:
		return
	var stream := _resolve_stream(track_resolver, track_id, "track")
	if stream == null:
		return
	_current_track_id = track_id
	_record_bgm_history(track_id)
	_start_bgm_fade(stream, fade_seconds)


## 当前 BGM track_id（"" 表示未在播放任何已选曲目）。
func current_bgm() -> String:
	return _current_track_id


# ---------------------------------------------------------------- SFX


## 播放一次音效：8 槽轮转，volume_offset_db 叠加到槽位音量。
## resolver 未注入 / 返回 null / 返回非 AudioStream 时告警并忽略。
func play_sfx(sfx_id: String, volume_offset_db: float = 0.0) -> void:
	if sfx_id.is_empty():
		push_warning("AudioDirector.play_sfx: empty sfx_id ignored.")
		return
	var stream := _resolve_stream(sfx_resolver, sfx_id, "sfx")
	if stream == null:
		return
	var slot := sfx_players[_next_sfx_index]
	_next_sfx_index = (_next_sfx_index + 1) % SFX_POOL_SIZE
	slot.stop()
	slot.stream = stream
	slot.volume_db = volume_offset_db
	slot.play()


## 下一次 play_sfx 将使用的槽位索引（只读观察用）。
func sfx_pool_cursor() -> int:
	return _next_sfx_index


# ---------------------------------------------------------------- 全局控制


## 停止全部播放（BGM + 全部 SFX 槽）并重置当前曲目选择：
## 之后重播同曲不会被当作重入忽略。bgm_history 保留。
func stop_all() -> void:
	_kill_bgm_fade()
	_bgm_player.stop()
	_bgm_player.volume_db = BGM_VOLUME_DB
	for slot: AudioStreamPlayer in sfx_players:
		slot.stop()
	_current_track_id = ""


## Master 总线静音开关（全局；BGM/SFX 分总线布局就位后同样被一并静音）。
func set_master_muted(muted: bool) -> void:
	_master_muted = muted
	var master_index := AudioServer.get_bus_index(String(MASTER_BUS_NAME))
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, muted)


## 只读观察：最近一次 set_master_muted 设置的静音标志。
func is_master_muted() -> bool:
	return _master_muted


# ---------------------------------------------------------------- 内部实现


## 解析流：resolver 未注入 / 返回 null / 返回非 AudioStream 时 push_warning
## 并返回 null（调用方忽略本次请求——无资产时零崩溃）。
func _resolve_stream(resolver: Callable, resource_id: String, kind: String) -> AudioStream:
	if not resolver.is_valid():
		push_warning(
			"AudioDirector: %s_resolver not injected; '%s' ignored." % [kind, resource_id]
		)
		return null
	var provided: Variant = resolver.call(resource_id)
	if provided is AudioStream:
		return provided
	push_warning(
		"AudioDirector: %s_resolver returned %s for '%s'; expected AudioStream, ignored."
			% [kind, type_string(typeof(provided)), resource_id]
	)
	return null


func _record_bgm_history(track_id: String) -> void:
	bgm_history.append(track_id)
	while bgm_history.size() > BGM_HISTORY_LIMIT:
		bgm_history.remove_at(0)


## 换曲淡出→换流→淡入；无当前播放或 fade_seconds <= 0 时立即起播。
## Tween 绑定本节点（节点释放时随之失效），headless 下按帧正常推进。
func _start_bgm_fade(stream: AudioStream, fade_seconds: float) -> void:
	_kill_bgm_fade()
	var fade := maxf(fade_seconds, 0.0)
	if fade <= 0.0 or not _bgm_player.playing:
		_bgm_player.stop()
		_bgm_player.stream = stream
		_bgm_player.volume_db = BGM_VOLUME_DB
		_bgm_player.play()
		if fade > 0.0:
			# 首播淡入：从谷底升到全量。
			_bgm_player.volume_db = FADE_FLOOR_DB
			_fade_tween = create_tween()
			_fade_tween.tween_property(_bgm_player, "volume_db", BGM_VOLUME_DB, fade)
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_bgm_player, "volume_db", FADE_FLOOR_DB, fade * 0.5)
	_fade_tween.tween_callback(_swap_bgm_stream.bind(stream))
	_fade_tween.tween_property(_bgm_player, "volume_db", BGM_VOLUME_DB, fade * 0.5)


## 淡出结束后换流：从谷底起播新流（随后的 tween_property 淡入到全量）。
func _swap_bgm_stream(stream: AudioStream) -> void:
	_bgm_player.stop()
	_bgm_player.stream = stream
	_bgm_player.volume_db = FADE_FLOOR_DB
	_bgm_player.play()


func _kill_bgm_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## 请求的总线存在时返回原名；缺省布局（仅 Master）下回退 Master。
## 用遍历而非 get_bus_index 判存在性，避免对缺失总线的错误日志。
## 协调者提交 Master→BGM/SFX 总线布局后（docs/art/audio-assets.md §1），
## 运行时创建的本节点即自动绑定目标总线。
static func _effective_bus(requested: StringName) -> StringName:
	for index: int in AudioServer.get_bus_count():
		if AudioServer.get_bus_name(index) == String(requested):
			return requested
	return MASTER_BUS_NAME
