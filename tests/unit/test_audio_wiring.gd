extends GutTest

## W003-A10 AudioDirector 接线测试（并行包 A9 交付 src/audio/audio_director.gd，
## class_name AudioDirector：play_bgm/play_sfx/set_master_muted）。
##
## 接线语义：
## - app.gd 以 ResourceLoader.exists 守卫动态装配 AudioDirector（A9 未合入时
##   优雅跳过，合并后自动生效）；测试经注入替身断言调用时序。
## - 标题期请求 "bgm_title"；game_start（继续）切 "bgm_explore"；fresh 路径
##   由重载后的新 App 实例在 boot 分支请求 "bgm_explore"。
## - resolver 未注入时 play_bgm 静默跳过是 A9 类自身语义，app 层只负责调用。

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
	# A9 缺席（当前 worktree 状态）：守卫必须优雅跳过、audio_director 保持
	# null 且 boot 全程不崩溃；A9 合入后：守卫必须动态装配实例。
	# 两种未来下本测试都成立。
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
