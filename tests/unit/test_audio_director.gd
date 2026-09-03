extends GutTest

## W003-A9：AudioDirector 音频框架测试（先于实现编写，RED → GREEN）。
##
## AudioDirector 是纯代码节点（_ready 自建 BgmPlayer / 8 槽 SfxPool，不经任何
## 场景），app 层实例化与调用方接线归 W003-A10+；本包不改 src/integration、
## src/ui、scenes/app.tscn、project.godot。
##
## 测试经 load() 运行时加载目标脚本并以 set()/call() 动态驱动（与 W002-GAP4
## 收敛模式一致）：缺失实现时以失败断言暴露，不触发解析噪声级联。
## 替身宿主保存在测试实例字段——Callable 只持 ObjectID，临时 RefCounted 会被
## 提前释放导致注入静默失效（见 test_ui_hud.gd 教训）。
##
## 哑流使用带 2 s 静音数据的 AudioStreamWAV：headless 无音频输出设备，但
## stream / playing / volume_db 状态照常可断言，且播放窗口内不会自然完结。

const DIRECTOR_SCRIPT_PATH: String = "res://src/audio/audio_director.gd"
const SFX_POOL_SIZE: int = 8
const BGM_HISTORY_LIMIT: int = 8
const FADE_TOTAL_SECONDS: float = 0.2
const FADE_WAIT_SECONDS: float = 0.6
const DUMMY_WAV_SECONDS: float = 10.0

var _director: Node = null
var _resolver: StreamResolver = null


## 解析替身：track_id/sfx_id -> 哑流。null_result / bogus_result 用于
## resolver 坏路径分支（返回 null / 返回非 AudioStream）。
class StreamResolver:
	var streams: Dictionary = {}
	var track_calls: int = 0
	var sfx_calls: int = 0
	var null_result: bool = false
	var bogus_result: bool = false

	func resolve_track(track_id: String) -> Variant:
		track_calls += 1
		return _value(track_id)

	func resolve_sfx(sfx_id: String) -> Variant:
		sfx_calls += 1
		return _value(sfx_id)

	func _value(resource_id: String) -> Variant:
		if null_result:
			return null
		if bogus_result:
			return "not-an-audio-stream"
		return streams.get(resource_id)


func before_each() -> void:
	_director = null
	_resolver = null


func after_each() -> void:
	if is_instance_valid(_director):
		_director.free()
	_director = null
	_resolver = null
	_remove_fake_bus("SFX")
	_remove_fake_bus("BGM")
	AudioServer.set_bus_mute(0, false)


# ---------------------------------------------------------------- 工具


func _make_director() -> Node:
	var script: Script = load(DIRECTOR_SCRIPT_PATH)
	assert_not_null(script, "Missing required W003-A9 implementation: %s" % DIRECTOR_SCRIPT_PATH)
	if script == null:
		return null
	assert_eq(script.get_global_name(), "AudioDirector", "Script must declare class_name AudioDirector.")
	var director: Node = script.new() as Node
	assert_not_null(director, "AudioDirector must extend Node.")
	if director == null:
		return null
	add_child(director)
	_director = director
	return director


func _bind_resolvers(director: Node, track_streams: Dictionary = {}, sfx_streams: Dictionary = {}) -> void:
	_resolver = StreamResolver.new()
	_resolver.streams.merge(track_streams, true)
	_resolver.streams.merge(sfx_streams, true)
	if not track_streams.is_empty():
		director.set("track_resolver", Callable(_resolver, "resolve_track"))
	if not sfx_streams.is_empty():
		director.set("sfx_resolver", Callable(_resolver, "resolve_sfx"))


func _dummy_stream() -> AudioStreamWAV:
	# 先在局部把缓冲区填满再一次性赋值：直接 resize 经 getter 取出的共享
	# 缓冲不会触发属性 setter，流内部会把数据当 0 长度（播放即完结）。
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(int(DUMMY_WAV_SECONDS) * stream.mix_rate * 2)
	stream.data = data
	return stream


func _bgm_player(director: Node) -> AudioStreamPlayer:
	return director.get_node("BgmPlayer") as AudioStreamPlayer


func _sfx_slots(director: Node) -> Array:
	var pool: Node = director.get_node_or_null("SfxPool")
	if pool == null:
		return []
	return pool.get_children()


func _add_fake_bus(bus_name: String) -> void:
	_remove_fake_bus(bus_name)
	var index := AudioServer.get_bus_count()
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)


func _remove_fake_bus(bus_name: String) -> void:
	# 从高索引向低索引移除，且永不触碰 0 号 Master。
	for index: int in range(AudioServer.get_bus_count() - 1, 0, -1):
		if AudioServer.get_bus_name(index) == bus_name:
			AudioServer.remove_bus(index)


func _history() -> Array:
	return _director.get("bgm_history") as Array


# ---------------------------------------------------------------- 节点契约


func test_ready_builds_bgm_player_and_eight_slot_sfx_pool_from_code() -> void:
	var director := _make_director()
	if director == null:
		return
	var bgm := _bgm_player(director)
	assert_not_null(bgm, "BgmPlayer child must be created in _ready (no scene).")
	if bgm != null:
		assert_true(bgm is AudioStreamPlayer, "BgmPlayer must be an AudioStreamPlayer.")
	var slots := _sfx_slots(director)
	assert_eq(slots.size(), SFX_POOL_SIZE, "SfxPool must hold exactly eight slots.")
	for index: int in slots.size():
		assert_true(slots[index] is AudioStreamPlayer, "Slot %d must be an AudioStreamPlayer." % index)
	if slots.size() == SFX_POOL_SIZE:
		assert_eq((slots[0] as Node).name, "Slot00", "First slot must be named Slot00.")
		assert_eq((slots[7] as Node).name, "Slot07", "Last slot must be named Slot07.")


func test_buses_bind_to_bgm_and_sfx_when_bus_layout_exists() -> void:
	_add_fake_bus("BGM")
	_add_fake_bus("SFX")
	var director := _make_director()
	if director == null:
		return
	var bgm := _bgm_player(director)
	if bgm != null:
		assert_eq(bgm.bus, "BGM", "BgmPlayer must bind the BGM bus when it exists.")
	var slots := _sfx_slots(director)
	assert_eq(slots.size(), SFX_POOL_SIZE)
	for index: int in slots.size():
		var slot := slots[index] as AudioStreamPlayer
		if slot != null:
			assert_eq(slot.bus, "SFX", "SFX slot %d must bind the SFX bus." % index)


func test_buses_fall_back_to_master_when_bus_layout_missing() -> void:
	# A10 may ship default_bus_layout with BGM/SFX; remove them for this case so
	# the director's missing-bus fallback path stays covered.
	_remove_fake_bus("SFX")
	_remove_fake_bus("BGM")
	var director := _make_director()
	if director == null:
		return
	var bgm := _bgm_player(director)
	assert_not_null(bgm)
	if bgm != null:
		assert_eq(bgm.bus, "Master", "Missing BGM bus must fall back to Master without crashing.")


# ---------------------------------------------------------------- play_bgm


func test_play_bgm_switches_stream_and_records_state_without_fade() -> void:
	var director := _make_director()
	if director == null:
		return
	var stream_a := _dummy_stream()
	var stream_b := _dummy_stream()
	_bind_resolvers(director, {"bgm_title": stream_a, "bgm_explore": stream_b})
	var bgm := _bgm_player(director)

	director.call("play_bgm", "bgm_title", 0.0)
	assert_eq(director.call("current_bgm"), "bgm_title", "current_bgm must report the playing track.")
	assert_eq(bgm.stream, stream_a, "BgmPlayer must carry the resolved stream.")
	assert_true(bgm.playing, "BgmPlayer must be playing after play_bgm.")
	assert_eq(bgm.volume_db, 0.0, "Immediate switch must play at full BGM volume.")
	var expected_first: Array[String] = ["bgm_title"]
	assert_eq(_history(), expected_first, "play_bgm must append the track to bgm_history.")
	assert_eq(_resolver.track_calls, 1, "play_bgm must resolve the stream exactly once.")

	director.call("play_bgm", "bgm_explore", 0.0)
	assert_eq(director.call("current_bgm"), "bgm_explore")
	assert_eq(bgm.stream, stream_b, "A different track must swap the stream.")
	var expected_second: Array[String] = ["bgm_title", "bgm_explore"]
	assert_eq(_history(), expected_second)


func test_play_bgm_same_track_reentry_ignored() -> void:
	var director := _make_director()
	if director == null:
		return
	var stream_a := _dummy_stream()
	_bind_resolvers(director, {"bgm_title": stream_a})
	var bgm := _bgm_player(director)

	director.call("play_bgm", "bgm_title", 0.0)
	var first_stream: AudioStream = bgm.stream
	director.call("play_bgm", "bgm_title", 0.0)
	assert_eq(_resolver.track_calls, 1, "Same-track re-entry must not re-resolve.")
	assert_eq(bgm.stream, first_stream, "Same-track re-entry must not disturb the stream.")
	var expected: Array[String] = ["bgm_title"]
	assert_eq(_history(), expected, "Same-track re-entry must not append history.")
	assert_eq(director.call("current_bgm"), "bgm_title")


func test_play_bgm_switch_fades_out_then_in() -> void:
	var director := _make_director()
	if director == null:
		return
	var stream_a := _dummy_stream()
	var stream_b := _dummy_stream()
	_bind_resolvers(director, {"bgm_title": stream_a, "bgm_explore": stream_b})
	var bgm := _bgm_player(director)
	director.call("play_bgm", "bgm_title", 0.0)

	director.call("play_bgm", "bgm_explore", FADE_TOTAL_SECONDS)
	assert_eq(director.call("current_bgm"), "bgm_explore", "current_bgm must report the new track immediately.")
	assert_eq(bgm.stream, stream_a, "The old stream must keep playing while fading out.")
	var expected: Array[String] = ["bgm_title", "bgm_explore"]
	assert_eq(_history(), expected)

	await get_tree().create_timer(FADE_WAIT_SECONDS).timeout
	assert_eq(bgm.stream, stream_b, "After the crossfade the new stream must be live.")
	assert_eq(bgm.volume_db, 0.0, "Fade-in must settle at full BGM volume.")
	assert_true(bgm.playing, "BGM must still be playing after the crossfade.")
	assert_eq(_resolver.track_calls, 2, "The crossfade must have resolved both tracks.")


func test_bgm_history_keeps_only_last_eight_entries() -> void:
	var director := _make_director()
	if director == null:
		return
	var ids: Array[String] = []
	var streams: Dictionary = {}
	for index: int in 10:
		var track_id := "bgm_track_%02d" % (index + 1)
		ids.append(track_id)
		streams[track_id] = _dummy_stream()
	_bind_resolvers(director, streams)
	for track_id: String in ids:
		director.call("play_bgm", track_id, 0.0)

	var history := _history()
	assert_eq(history.size(), BGM_HISTORY_LIMIT, "bgm_history must cap at eight entries.")
	if history.size() == BGM_HISTORY_LIMIT:
		assert_eq(history[0], "bgm_track_03", "Oldest entries must be evicted first.")
		assert_eq(history[BGM_HISTORY_LIMIT - 1], "bgm_track_10", "Newest entry must be last.")
	assert_eq(director.call("current_bgm"), "bgm_track_10")


# ---------------------------------------------------------------- play_sfx


func test_play_sfx_rotates_pool_round_robin() -> void:
	var director := _make_director()
	if director == null:
		return
	var stream_a := _dummy_stream()
	var stream_b := _dummy_stream()
	_bind_resolvers(director, {}, {"sfx_a": stream_a, "sfx_b": stream_b})

	director.call("play_sfx", "sfx_a")
	director.call("play_sfx", "sfx_b")
	director.call("play_sfx", "sfx_a")
	var slots := _sfx_slots(director)
	assert_eq(slots.size(), SFX_POOL_SIZE)
	assert_eq((slots[0] as AudioStreamPlayer).stream, stream_a, "First play must take slot 0.")
	assert_true((slots[0] as AudioStreamPlayer).playing, "The used slot must be playing.")
	assert_eq((slots[1] as AudioStreamPlayer).stream, stream_b, "Second play must take slot 1.")
	assert_eq((slots[2] as AudioStreamPlayer).stream, stream_a, "Third play must take slot 2.")
	assert_eq((slots[3] as AudioStreamPlayer).stream, null, "Untouched slots must stay idle.")
	assert_false((slots[3] as AudioStreamPlayer).playing)
	assert_eq(director.call("sfx_pool_cursor"), 3, "Cursor must advance once per successful play.")

	for _index: int in 6:
		director.call("play_sfx", "sfx_b")
	assert_eq(director.call("sfx_pool_cursor"), 1, "Nine plays must wrap the cursor back to slot 1.")
	assert_eq((slots[0] as AudioStreamPlayer).stream, stream_b, "The ninth play must reuse slot 0.")


func test_play_sfx_applies_volume_offset() -> void:
	var director := _make_director()
	if director == null:
		return
	_bind_resolvers(director, {}, {"sfx_ui_click": _dummy_stream()})
	director.call("play_sfx", "sfx_ui_click", -6.0)
	var slots := _sfx_slots(director)
	if slots.size() == SFX_POOL_SIZE:
		assert_eq((slots[0] as AudioStreamPlayer).volume_db, -6.0, "volume_offset_db must land on the slot.")
		assert_true((slots[0] as AudioStreamPlayer).playing)
	assert_eq(director.call("sfx_pool_cursor"), 1)


# ---------------------------------------------------------------- 坏路径


func test_missing_or_bad_resolver_warns_and_ignores_without_crashing() -> void:
	var director := _make_director()
	if director == null:
		return
	# 完全未注入 resolver。
	director.call("play_bgm", "bgm_title", 0.0)
	director.call("play_sfx", "sfx_ui_click")
	assert_eq(director.call("current_bgm"), "", "Unresolved bgm must leave current_bgm empty.")
	assert_eq(_history().size(), 0, "Unresolved bgm must not touch history.")
	for slot: Variant in _sfx_slots(director):
		assert_false((slot as AudioStreamPlayer).playing, "Unresolved sfx must not start any slot.")
	assert_eq(director.call("sfx_pool_cursor"), 0, "Unresolved sfx must not advance the cursor.")

	# resolver 返回 null。
	_resolver = StreamResolver.new()
	_resolver.null_result = true
	director.set("track_resolver", Callable(_resolver, "resolve_track"))
	director.set("sfx_resolver", Callable(_resolver, "resolve_sfx"))
	director.call("play_bgm", "bgm_title", 0.0)
	director.call("play_sfx", "sfx_ui_click")
	assert_eq(director.call("current_bgm"), "", "Null resolution must be ignored.")
	assert_true(_resolver.track_calls > 0, "The null resolver must have been consulted.")

	# resolver 返回非 AudioStream。
	_resolver.bogus_result = true
	director.call("play_bgm", "bgm_title", 0.0)
	director.call("play_sfx", "sfx_ui_click")
	assert_eq(director.call("current_bgm"), "", "Non-AudioStream resolution must be ignored.")
	assert_eq(director.call("sfx_pool_cursor"), 0, "Failed sfx plays must not advance the cursor.")
	assert_eq(_history().size(), 0, "All failed plays must keep history untouched.")


# ---------------------------------------------------------------- 静音与停止


func test_set_master_muted_toggles_master_bus_mute() -> void:
	var director := _make_director()
	if director == null:
		return
	assert_false(director.call("is_master_muted"), "Director must start unmuted.")
	assert_false(AudioServer.is_bus_mute(0), "Precondition: Master bus starts unmuted.")

	director.call("set_master_muted", true)
	assert_true(director.call("is_master_muted"), "Mute flag must flip to true.")
	assert_true(AudioServer.is_bus_mute(0), "Master bus must actually be muted on the AudioServer.")

	director.call("set_master_muted", false)
	assert_false(director.call("is_master_muted"), "Mute flag must flip back to false.")
	assert_false(AudioServer.is_bus_mute(0), "Master bus must be unmuted again.")


func test_stop_all_stops_playback_and_resets_bgm_selection() -> void:
	var director := _make_director()
	if director == null:
		return
	_bind_resolvers(director, {"bgm_title": _dummy_stream()}, {"sfx_ui_click": _dummy_stream()})
	director.call("play_bgm", "bgm_title", 0.0)
	director.call("play_sfx", "sfx_ui_click")
	var bgm := _bgm_player(director)
	assert_true(bgm.playing, "Precondition: bgm playing before stop_all.")

	director.call("stop_all")
	assert_false(bgm.playing, "stop_all must stop the bgm player.")
	assert_eq(director.call("current_bgm"), "", "stop_all must reset the bgm selection.")
	for slot: Variant in _sfx_slots(director):
		assert_false((slot as AudioStreamPlayer).playing, "stop_all must stop every sfx slot.")

	director.call("play_bgm", "bgm_title", 0.0)
	assert_eq(director.call("current_bgm"), "bgm_title", "Replay after stop_all must not be treated as re-entry.")
	assert_eq(_history().size(), 2, "Replay must append history again.")
	assert_true(bgm.playing, "Replay after stop_all must start playback again.")
