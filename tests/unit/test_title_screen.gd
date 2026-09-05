extends GutTest

## W003-A10 标题/主菜单界面：场景契约 + app 标题流程冒烟（TDD RED 先行）。
##
## 约定：不 preload、不以全局类名引用尚未存在的 TitleScreen 脚本（Parse Error
## 会级联打断整套件的收集，见 W002-GAP4 evidence 的 RED 教训），一律运行时
## load() 后按鸭子类型断言。
##
## 锁定语义（缺口报告 E2）：
## - 标题为独立 CanvasLayer（layer 30，位于 UILayer 20 之上、ModalLayer 50 之下），
##   全屏 Root 拦截鼠标，遮住游戏画面。
## - 按钮列：新游戏 / 继续 / 说明 / 退出；继续按钮由注入的 has_save Callable
##   判定可用态，禁用态显示"无存档"。
## - 既有 StartupScreen 节点与其文案全部保留（test_app_bootstrap 锁定），作为
##   标题背景层；其淡出时机延后到 game_start 之后接续（既有断言不涉及时机）。

const TITLE_SCENE_PATH: String = "res://scenes/title_screen.tscn"
const APP_SCENE_PATH: String = "res://scenes/app.tscn"

const TITLE_TEXT: String = "星壤：余辉纪元"
const SUBTITLE_TEXT: String = "琉砂海 · 垂直切片"
const NEW_GAME_TEXT: String = "新游戏"
const CONTINUE_TEXT: String = "继续"
const NO_SAVE_TEXT: String = "无存档"
const HELP_TEXT: String = "说明"
const QUIT_TEXT: String = "退出"

## has_save 替身宿主（Callable 只持 ObjectID，测试实例字段保活）。
class SaveProbeSpy extends RefCounted:
	var available: bool = false

	func has_save() -> bool:
		return available


## app.fresh_boot_handler 替身：fresh 路径不得真实 reload 测试场景。
class FreshBootSpy extends RefCounted:
	var calls: int = 0

	func run() -> void:
		calls += 1


var _save_probe_spy: SaveProbeSpy = null
var _fresh_boot_spy: FreshBootSpy = null


func _load_title() -> Node:
	var packed: PackedScene = load(TITLE_SCENE_PATH) as PackedScene
	assert_not_null(packed, "res://scenes/title_screen.tscn 必须存在且可加载。")
	if packed == null:
		return null
	var title: Node = packed.instantiate()
	assert_not_null(title, "title_screen.tscn 必须可实例化。")
	return title


func _load_app() -> Node:
	var packed: PackedScene = load(APP_SCENE_PATH) as PackedScene
	assert_not_null(packed, "res://scenes/app.tscn 必须存在且可加载。")
	if packed == null:
		return null
	var app: Node = packed.instantiate()
	assert_not_null(app, "app.tscn 必须可实例化。")
	return app


func _inject_save_probe(title: Node, available: bool) -> void:
	var probe := SaveProbeSpy.new()
	probe.available = available
	_save_probe_spy = probe
	title.set("has_save", Callable(probe, "has_save"))


# ---------------------------------------------------------------- 场景契约


func test_title_scene_contract_layer_root_and_texts() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	assert_true(title is CanvasLayer, "TitleScreen 根必须是 CanvasLayer。")
	assert_eq(title.name, "TitleScreen")
	assert_eq(title.layer, 30, "标题层必须位于 UILayer(20) 之上、ModalLayer(50) 之下。")
	var root: Control = title.get_node_or_null("%Root") as Control
	assert_not_null(root, "标题必须提供全屏 Root 控件。")
	if root != null:
		assert_eq(
			root.mouse_filter, Control.MOUSE_FILTER_STOP,
			"Root 必须拦截鼠标，避免标题期间误触世界。"
		)
	var label: Label = title.get_node_or_null("%TitleLabel") as Label
	assert_not_null(label, "标题必须有大字标节点。")
	if label != null:
		assert_eq(label.text, TITLE_TEXT)
	var subtitle: Label = title.get_node_or_null("%Subtitle") as Label
	assert_not_null(subtitle, "标题必须有副题节点。")
	if subtitle != null:
		assert_eq(subtitle.text, SUBTITLE_TEXT)
	var backdrop: Node = title.get_node_or_null("Root/Backdrop")
	assert_true(backdrop is TextureRect, "Title Backdrop must be TextureRect wired to bg_title.")
	if backdrop is TextureRect:
		var tex: Texture2D = (backdrop as TextureRect).texture
		assert_not_null(tex, "Title Backdrop must reference bg_title.png.")
		if tex != null:
			assert_eq(tex.resource_path, "res://assets/art/ui/title/bg_title.png")


func test_title_buttons_and_default_no_save_state() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	var new_game: Button = title.get_node_or_null("%NewGameButton") as Button
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	var help: Button = title.get_node_or_null("%HelpButton") as Button
	var quit: Button = title.get_node_or_null("%QuitButton") as Button
	assert_not_null(new_game)
	assert_not_null(cont)
	assert_not_null(help)
	assert_not_null(quit)
	if new_game != null:
		assert_eq(new_game.text, NEW_GAME_TEXT)
		assert_false(new_game.disabled, "新游戏始终可用（无档也允许开新局）。")
	if cont != null:
		assert_true(cont.disabled, "缺省（未注入 has_save）按无存档处理，继续必须禁用。")
		assert_eq(cont.text, NO_SAVE_TEXT, "继续按钮禁用态必须显示'无存档'。")
	if help != null:
		assert_eq(help.text, HELP_TEXT)
	if quit != null:
		assert_eq(quit.text, QUIT_TEXT)


func test_title_continue_enabled_when_save_available() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	_inject_save_probe(title, true)
	title.call("refresh_continue_state")
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	assert_not_null(cont)
	if cont != null:
		assert_false(cont.disabled, "有 auto 档时继续必须可用。")
		assert_eq(cont.text, CONTINUE_TEXT)


# ---------------------------------------------------------------- 信号语义


func test_title_new_game_emits_game_start_fresh() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	watch_signals(title)
	var new_game: Button = title.get_node_or_null("%NewGameButton") as Button
	assert_not_null(new_game)
	if new_game == null:
		return
	new_game.pressed.emit()
	assert_signal_emitted_with_parameters(title, "game_start", [true])


func test_title_continue_emits_game_start_not_fresh() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	_inject_save_probe(title, true)
	title.call("refresh_continue_state")
	watch_signals(title)
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	assert_not_null(cont)
	if cont == null:
		return
	cont.pressed.emit()
	assert_signal_emitted_with_parameters(title, "game_start", [false])


func test_title_continue_guarded_when_disabled() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	watch_signals(title)
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	assert_not_null(cont)
	if cont == null:
		return
	cont.pressed.emit()
	assert_signal_not_emitted(title, "game_start", "无存档时继续不得发出 game_start。")


func test_title_quit_requests_quit_without_self_quitting() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	watch_signals(title)
	var quit: Button = title.get_node_or_null("%QuitButton") as Button
	assert_not_null(quit)
	if quit == null:
		return
	quit.pressed.emit()
	assert_signal_emitted(title, "quit_requested", "退出必须经 quit_requested 交 app 处理，标题层不得直接自杀退出。")


func test_title_help_panel_toggles() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	var panel: Control = title.get_node_or_null("%HelpPanel") as Control
	var help: Button = title.get_node_or_null("%HelpButton") as Button
	assert_not_null(panel)
	assert_not_null(help)
	if panel == null or help == null:
		return
	assert_false(panel.visible, "说明面板默认隐藏。")
	help.pressed.emit()
	assert_true(panel.visible, "按说明必须展开操作说明面板。")
	help.pressed.emit()
	assert_false(panel.visible, "再次按说明必须收起面板。")


func test_title_help_text_reuses_greybox_operations_copy() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	var panel: Control = title.get_node_or_null("%HelpPanel") as Control
	assert_not_null(panel)
	if panel == null:
		return
	var joined := ""
	for child: Node in panel.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null:
			joined += label.text
	assert_true(joined.contains("操作说明"), "说明面板必须复用既有操作说明文案。")
	assert_true(joined.contains("移动：WASD 或方向键"))
	assert_true(joined.contains("菜单：Esc 键"))


func test_title_fade_out_hides_layer_and_is_idempotent() -> void:
	var title: Node = _load_title()
	if title == null:
		return
	add_child_autofree(title)
	assert_true(title.visible, "标题初始必须可见。")
	assert_true(title.call("fade_out", 0.0), "fade_out(0) 必须立即完成并返回 true。")
	assert_false(title.visible, "fade_out 完成后标题必须隐藏。")
	assert_true(title.is_inside_tree(), "fade_out 后节点必须保留在场景树。")
	assert_false(title.call("fade_out", 0.5), "已隐藏后再次 fade_out 必须返回 false。")


# ---------------------------------------------------------------- app 流程冒烟


func test_app_shows_title_and_locks_game_input_on_boot() -> void:
	var app: Node = _load_app()
	if app == null:
		return
	var title: Node = app.get_node_or_null("TitleScreen")
	assert_not_null(title, "app.tscn 必须实例化 TitleScreen。")
	if title == null:
		return
	_inject_save_probe(title, true)
	add_child_autofree(app)
	assert_true(title.visible, "启动后标题必须可见（遮住游戏画面）。")
	var session: Node = app.get_node_or_null("GameSession")
	assert_not_null(session)
	if session != null:
		assert_eq(
			session.process_mode, Node.PROCESS_MODE_DISABLED,
			"标题期间 GameSession 必须停止 tick（存档已在 _ready 读入，等待玩家选择）。"
		)
	var world_host: Node = app.get_node_or_null("WorldHost")
	assert_not_null(world_host)
	if world_host != null:
		assert_eq(
			world_host.process_mode, Node.PROCESS_MODE_DISABLED,
			"标题期间世界/玩家必须停止处理（防键盘输入泄漏进游戏）。"
		)
	var hud: Node = app.get_node_or_null("UILayer/Hud")
	assert_not_null(hud)
	if hud != null:
		assert_eq(hud.process_mode, Node.PROCESS_MODE_DISABLED, "标题期间 HUD 快捷键必须停用。")
	var startup: Control = app.get_node_or_null("UILayer/StartupScreen") as Control
	assert_not_null(startup, "既有 StartupScreen 必须保留。")
	if startup != null:
		assert_true(startup.visible, "启动屏保留为标题背景层，节点与文案不删除。")
	if title != null:
		assert_true(
			(title.get("has_save") as Callable).is_valid(),
			"app 必须为标题注入存档探测 Callable。"
		)


func test_app_continue_unlocks_game_and_chains_startup_fade() -> void:
	var app: Node = _load_app()
	if app == null:
		return
	var title: Node = app.get_node_or_null("TitleScreen")
	assert_not_null(title)
	if title == null:
		return
	_inject_save_probe(title, true)
	add_child_autofree(app)
	var session: Node = app.get_node_or_null("GameSession")
	var hud: Node = app.get_node_or_null("UILayer/Hud")
	var startup: Control = app.get_node_or_null("UILayer/StartupScreen") as Control
	assert_not_null(session)
	assert_not_null(startup)
	watch_signals(title)
	var cont: Button = title.get_node_or_null("%ContinueButton") as Button
	assert_not_null(cont)
	if cont == null:
		return
	cont.pressed.emit()
	assert_signal_emitted_with_parameters(title, "game_start", [false])
	if session != null:
		assert_eq(
			session.process_mode, Node.PROCESS_MODE_INHERIT,
			"game_start 后必须解锁 GameSession。"
		)
	if hud != null:
		assert_eq(
			hud.process_mode, Node.PROCESS_MODE_ALWAYS,
			"解锁后 HUD 必须恢复场景原 process_mode（暂停菜单语义）。"
		)
	assert_true(title.visible, "标题在淡出完成前保持可见。")
	title.call("finish_fade_out")
	assert_false(title.visible)
	assert_true(title.is_inside_tree(), "标题淡出后节点保留在场景树。")
	if startup != null:
		assert_true(startup.visible, "标题淡出完成后既有启动屏文案淡出流程必须已接续启动。")
	assert_not_null(
		app.get("_startup_fade_tween") as Tween,
		"标题淡出链必须触发既有 _begin_startup_fade（启动屏补间已创建）。"
	)
	app.call("finish_startup_fade")
	if startup != null:
		assert_false(startup.visible, "启动屏淡出经既有 finish_startup_fade 手动完成后隐藏。")


func test_app_fresh_game_start_uses_injected_handler_without_scene_reload() -> void:
	var app: Node = _load_app()
	if app == null:
		return
	var title: Node = app.get_node_or_null("TitleScreen")
	assert_not_null(title)
	if title == null:
		return
	var fresh_spy := FreshBootSpy.new()
	_fresh_boot_spy = fresh_spy
	app.set("fresh_boot_handler", Callable(fresh_spy, "run"))
	add_child_autofree(app)
	var new_game: Button = title.get_node_or_null("%NewGameButton") as Button
	assert_not_null(new_game)
	if new_game == null:
		return
	new_game.pressed.emit()
	assert_eq(fresh_spy.calls, 1, "fresh 路径必须调用注入的 fresh_boot_handler（替身，不真实重载）。")
	assert_true(title.visible, "fresh 路径走场景重载语义，当前实例不做标题淡出。")


func test_app_after_fresh_reload_unlocks_game_and_skips_title() -> void:
	var app: Node = _load_app()
	if app == null:
		return
	add_child_autofree(app)
	var session: Node = app.get_node_or_null("GameSession")
	var title: Node = app.get_node_or_null("TitleScreen")
	var startup: Control = app.get_node_or_null("UILayer/StartupScreen") as Control
	assert_not_null(session)
	assert_not_null(title)
	assert_not_null(startup)
	if session == null or title == null or startup == null:
		return
	app.call("_enter_game_after_fresh_reload")
	assert_eq(session.process_mode, Node.PROCESS_MODE_INHERIT, "fresh 重载后必须直接解锁游戏。")
	assert_false(title.visible, "fresh 重载后的新 App 必须跳过标题。")
	assert_true(startup.visible, "fresh 重载后既有启动屏文案淡出流程正常接续。")
	app.call("finish_startup_fade")
	assert_false(startup.visible)
