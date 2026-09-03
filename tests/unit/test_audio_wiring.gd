extends GutTest

## W003-A10 AudioDirector 接线测试（并行包 A9 交付 src/audio/audio_director.gd，
## class_name AudioDirector：play_bgm/play_sfx/set_master_muted）。
##
## 接线语义：
## - app.gd 以 ResourceLoader.exists 守卫动态装配 AudioDirector（A9 未合入时
##   优雅跳过，合并后自动生效）；测试经注入替身断言调用时序。
## - 标题期请求 "bgm_title"；game_start（继续）切 "bgm_explore"；fresh 路径
##   由重载后的新 App 实例在 boot 分支请求 "bgm_explore"。
## - A10：装配后注入 AudioCatalog track/sfx resolver；并把引用交给 GameSession。

const APP_SCENE_PATH: String = "res://scenes/app.tscn"
const AUDIO_DIRECTOR_PATH: String = "res://src/audio/audio_director.gd"


class SaveProbeSpy extends RefCounted:
	var available: bool = false

	func has_save() -> bool:
		return available


class FreshBootSpy extends RefCounted:
	var calls: int = 0

	func run() -> void:
		calls += 1


## AudioDirector 替身：模拟 A9 类的 play_bgm 签名。
class AudioDirectorSpy extends Node:
	var bgm_calls: Array = []

	func play_bgm(track_id: String) -> void:
		bgm_calls.append(track_id)


var _save_probe_spy: SaveProbeSpy = null
var _fresh_boot_spy: FreshBootSpy = null
var _audio_spy: AudioDirectorSpy = null


func after_each() -> void:
	# 替身 AudioDirector 注入后不进场景树（autofree 够不到），手动释放防 orphan。
	if is_instance_valid(_audio_spy):
		_audio_spy.free()
	_audio_spy = null
	_save_probe_spy = null
	_fresh_boot_spy = null


func _make_app_with_audio_spy() -> Node:
	var packed: PackedScene = load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "res://scenes/app.tscn 必须存在且可加载。")
	if packed == null:
		return null
	var app: Node = packed.instantiate()
	assert_not_null(app)
	if app == null:
		return null
	_audio_spy = AudioDirectorSpy.new()
	app.set("audio_director", _audio_spy)
	return app


func _inject_save_probe(app: Node) -> void:
	var title: Node = app.get_node_or_null("TitleScreen")
	assert_not_null(title, "app.tscn 必须实例化 TitleScreen。")
	if title == null:
		return
	var probe := SaveProbeSpy.new()
	probe.available = true
	_save_probe_spy = probe
	title.set("has_save", Callable(probe, "has_save"))


func test_app_boot_with_title_plays_title_bgm() -> void:
	var app: Node = _make_app_with_audio_spy()
	if app == null:
		return
	add_child_autofree(app)
	var spy: AudioDirectorSpy = _audio_spy
	assert_not_null(spy)
	if spy == null:
		return
	assert_eq(spy.bgm_calls.size(), 1, "标题期必须恰好请求一次 BGM。")
	if spy.bgm_calls.size() == 1:
		assert_eq(str(spy.bgm_calls[0]), "bgm_title", "标题期必须请求标题 BGM。")


func test_app_continue_switches_bgm_to_explore() -> void:
	var app: Node = _make_app_with_audio_spy()
	if app == null:
		return
	_inject_save_probe(app)
	add_child_autofree(app)
	var title: Node = app.get_node_or_null("TitleScreen")
	var spy: AudioDirectorSpy = _audio_spy
	assert_not_null(title)
	assert_not_null(spy)
	if title == null or spy == null:
		return
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	assert_not_null(cont)
	if cont == null:
		return
	cont.pressed.emit()
	assert_eq(spy.bgm_calls.size(), 2, "继续进入游戏必须追加一次 BGM 请求。")
	if spy.bgm_calls.size() == 2:
		assert_eq(str(spy.bgm_calls[1]), "bgm_explore", "进入游戏必须切到探索 BGM。")


func test_app_fresh_start_does_not_switch_bgm_in_pre_reload_instance() -> void:
	var app: Node = _make_app_with_audio_spy()
	if app == null:
		return
	var fresh_spy := FreshBootSpy.new()
	_fresh_boot_spy = fresh_spy
	app.set("fresh_boot_handler", Callable(fresh_spy, "run"))
	add_child_autofree(app)
	var title: Node = app.get_node_or_null("TitleScreen")
	var spy: AudioDirectorSpy = _audio_spy
	assert_not_null(title)
	assert_not_null(spy)
	if title == null or spy == null:
		return
	var new_game: Button = title.get_node_or_null("%NewGameButton") as Button
	assert_not_null(new_game)
	if new_game == null:
		return
	new_game.pressed.emit()
	assert_eq(spy.bgm_calls.size(), 1, "fresh 语义下当前实例将被重载替换，不得在重载前切换 BGM。")
	assert_eq(str(spy.bgm_calls[0]), "bgm_title")


func test_app_audio_guard_assembles_or_skips_by_a9_presence() -> void:
	# A9 缺席：守卫优雅跳过；A9 合入后：守卫动态装配实例。两种未来下本测试都成立。
	var guard_should_create := ResourceLoader.exists(AUDIO_DIRECTOR_PATH)
	var app: Node = (load(APP_SCENE_PATH) as PackedScene).instantiate()
	assert_not_null(app)
	if app == null:
		return
	assert_null(
		app.get("audio_director"),
		"未注入替身且尚未进入场景树时，audio_director 必须为 null。"
	)
	add_child_autofree(app)
	if guard_should_create:
		assert_not_null(app.get("audio_director"), "A9 类在场时守卫必须动态装配 AudioDirector。")
	else:
		assert_null(app.get("audio_director"), "A9 类缺席时守卫必须优雅跳过动态装配。")


func test_audio_catalog_resolvers_return_streams_for_title_and_click() -> void:
	# A10：id→OGG resolver 必须对已入库 P0 资产返回 AudioStream。
	assert_true(
		ResourceLoader.exists("res://src/audio/audio_catalog.gd"),
		"AudioCatalog 脚本必须存在。"
	)
	var track: AudioStream = AudioCatalog.resolve_track("bgm_title")
	assert_not_null(track, "bgm_title 必须解析为 AudioStream。")
	assert_true(track is AudioStream, "bgm_title 返回值必须是 AudioStream。")
	var sfx: AudioStream = AudioCatalog.resolve_sfx("sfx_ui_click")
	assert_not_null(sfx, "sfx_ui_click 必须解析为 AudioStream。")
	assert_true(sfx is AudioStream, "sfx_ui_click 返回值必须是 AudioStream。")
	# 缺失资产返回 null，不崩溃。
	assert_null(AudioCatalog.resolve_track("bgm_does_not_exist"))
	assert_null(AudioCatalog.resolve_sfx("sfx_does_not_exist"))


func test_app_injects_resolvers_on_assembled_audio_director() -> void:
	# 关键缺口：装配 AudioDirector 后必须注入 track_resolver / sfx_resolver。
	if not ResourceLoader.exists(AUDIO_DIRECTOR_PATH):
		pass_test("A9 缺席时跳过 resolver 注入断言。")
		return
	var app: Node = (load(APP_SCENE_PATH) as PackedScene).instantiate()
	assert_not_null(app)
	if app == null:
		return
	add_child_autofree(app)
	var director: Node = app.get("audio_director") as Node
	assert_not_null(director, "A9 在场时 App 必须装配 AudioDirector。")
	if director == null:
		return
	assert_true("track_resolver" in director, "AudioDirector 必须暴露 track_resolver。")
	assert_true("sfx_resolver" in director, "AudioDirector 必须暴露 sfx_resolver。")
	var track_resolver: Callable = director.get("track_resolver")
	var sfx_resolver: Callable = director.get("sfx_resolver")
	assert_true(track_resolver.is_valid(), "track_resolver 必须已注入且可调用。")
	assert_true(sfx_resolver.is_valid(), "sfx_resolver 必须已注入且可调用。")
	var track: Variant = track_resolver.call("bgm_title")
	var sfx: Variant = sfx_resolver.call("sfx_ui_click")
	assert_true(track is AudioStream, "注入后的 track_resolver(bgm_title) 必须返回 AudioStream。")
	assert_true(sfx is AudioStream, "注入后的 sfx_resolver(sfx_ui_click) 必须返回 AudioStream。")


func test_app_binds_audio_director_to_game_session() -> void:
	if not ResourceLoader.exists(AUDIO_DIRECTOR_PATH):
		pass_test("A9 缺席时跳过 GameSession 绑定断言。")
		return
	var app: Node = (load(APP_SCENE_PATH) as PackedScene).instantiate()
	assert_not_null(app)
	if app == null:
		return
	add_child_autofree(app)
	var session: Node = app.get_node_or_null("GameSession")
	assert_not_null(session, "app.tscn 必须含 GameSession。")
	if session == null:
		return
	assert_true("audio_director" in session, "GameSession 必须暴露 audio_director。")
	assert_eq(
		session.get("audio_director"),
		app.get("audio_director"),
		"App 必须把同一 AudioDirector 引用交给 GameSession。"
	)
