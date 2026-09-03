extends GutTest

## W003-A10：AudioCatalog resolver + 真实 OGG 经 AudioDirector 播放不崩溃。

const CATALOG_PATH: String = "res://src/audio/audio_catalog.gd"
const DIRECTOR_PATH: String = "res://src/audio/audio_director.gd"

const KNOWN_BGM: Array[String] = [
	"bgm_title", "bgm_explore", "bgm_build", "bgm_battle", "bgm_boss", "bgm_boss_final",
]
const KNOWN_SFX: Array[String] = [
	"sfx_mine_hit", "sfx_mine_depleted", "sfx_build_place", "sfx_build_denied",
	"sfx_ui_click", "sfx_battle_action", "sfx_battle_hit", "sfx_victory",
	"sfx_defeat", "sfx_save_notice", "sfx_ending_bell", "sfx_boss_phase",
]

var _director: Node = null


func after_each() -> void:
	if is_instance_valid(_director):
		_director.free()
	_director = null


func test_resolve_track_returns_audio_stream_for_known_ids() -> void:
	var catalog: Script = load(CATALOG_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return
	assert_eq(catalog.get_global_name(), "AudioCatalog")
	for track_id: String in KNOWN_BGM:
		var stream: Variant = catalog.call("resolve_track", track_id)
		assert_true(
			stream is AudioStream,
			"resolve_track('%s') must return AudioStream, got %s" % [track_id, type_string(typeof(stream))]
		)


func test_resolve_sfx_returns_audio_stream_for_known_ids() -> void:
	var catalog: Script = load(CATALOG_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return
	for sfx_id: String in KNOWN_SFX:
		var stream: Variant = catalog.call("resolve_sfx", sfx_id)
		assert_true(
			stream is AudioStream,
			"resolve_sfx('%s') must return AudioStream, got %s" % [sfx_id, type_string(typeof(stream))]
		)


func test_resolvers_return_null_on_missing_ids() -> void:
	var catalog: Script = load(CATALOG_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return
	assert_eq(catalog.call("resolve_track", "bgm_does_not_exist"), null)
	assert_eq(catalog.call("resolve_sfx", "sfx_does_not_exist"), null)
	assert_eq(catalog.call("resolve_track", ""), null)


func test_play_bgm_and_play_sfx_with_catalog_resolvers_do_not_crash() -> void:
	var director_script: Script = load(DIRECTOR_PATH)
	var catalog: Script = load(CATALOG_PATH)
	assert_not_null(director_script)
	assert_not_null(catalog)
	if director_script == null or catalog == null:
		return
	_director = director_script.new()
	add_child(_director)
	_director.set("track_resolver", Callable(catalog, "resolve_track"))
	_director.set("sfx_resolver", Callable(catalog, "resolve_sfx"))
	_director.call("play_bgm", "bgm_title", 0.0)
	assert_eq(_director.call("current_bgm"), "bgm_title")
	var bgm: AudioStreamPlayer = _director.get_node("BgmPlayer") as AudioStreamPlayer
	assert_not_null(bgm)
	if bgm != null:
		assert_true(bgm.stream is AudioStream, "BGM player must hold a real stream.")
		assert_true(bgm.playing, "BGM must be playing after play_bgm.")
	_director.call("play_sfx", "sfx_ui_click", -3.0)
	_director.call("play_sfx", "sfx_mine_hit")
	assert_eq(_director.call("sfx_pool_cursor"), 2)
	_director.call("play_bgm", "bgm_explore", 0.0)
	assert_eq(_director.call("current_bgm"), "bgm_explore")
	_director.call("stop_all")
	assert_eq(_director.call("current_bgm"), "")
