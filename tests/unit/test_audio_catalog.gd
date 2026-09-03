extends GutTest

## AudioCatalog：id → res://assets/audio/{bgm,sfx}/<id>.ogg

const KNOWN_BGM: Array[String] = [
	"bgm_title", "bgm_explore", "bgm_build", "bgm_battle", "bgm_boss", "bgm_boss_final",
]
const KNOWN_SFX_SAMPLE: Array[String] = [
	"sfx_ui_click", "sfx_mine_hit", "sfx_victory",
]


func test_resolve_track_loads_shipped_ogg() -> void:
	for track_id: String in KNOWN_BGM:
		var stream: AudioStream = AudioCatalog.resolve_track(track_id)
		assert_not_null(stream, "BGM '%s' must resolve after batch4 drop-in." % track_id)
		if stream != null:
			assert_true(stream is AudioStream)


func test_resolve_sfx_loads_shipped_ogg() -> void:
	for sfx_id: String in KNOWN_SFX_SAMPLE:
		var stream: AudioStream = AudioCatalog.resolve_sfx(sfx_id)
		assert_not_null(stream, "SFX '%s' must resolve after batch4 drop-in." % sfx_id)


func test_resolve_missing_ids_return_null() -> void:
	assert_null(AudioCatalog.resolve_track(""))
	assert_null(AudioCatalog.resolve_track("bgm_does_not_exist"))
	assert_null(AudioCatalog.resolve_sfx(""))
	assert_null(AudioCatalog.resolve_sfx("sfx_does_not_exist"))


func test_app_binds_catalog_resolvers_on_real_director() -> void:
	var packed: PackedScene = load("res://scenes/app.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var app: Node = packed.instantiate()
	assert_not_null(app)
	if app == null:
		return
	add_child_autofree(app)
	var director: Node = app.get("audio_director") as Node
	assert_not_null(director, "App must assemble AudioDirector when script exists.")
	if director == null:
		return
	var track_resolver: Callable = director.get("track_resolver")
	var sfx_resolver: Callable = director.get("sfx_resolver")
	assert_true(track_resolver.is_valid(), "track_resolver must be injected.")
	assert_true(sfx_resolver.is_valid(), "sfx_resolver must be injected.")
	var title_stream: Variant = track_resolver.call("bgm_title")
	assert_true(title_stream is AudioStream, "Injected track_resolver must load bgm_title.")
