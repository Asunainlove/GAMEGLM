class_name TitleScreen
extends CanvasLayer

## W003-A10 独立标题/主菜单界面（缺口报告 E2：启动屏纯过场不可点）。
##
## 场景契约（tests/unit/test_title_screen.gd 锁定）：
## - 根为 CanvasLayer，layer 30：位于 UILayer(20) 之上、ModalLayer(50) 之下，
##   全屏 Root 控件 mouse_filter STOP 拦截鼠标，遮住游戏画面。
## - 原创中文大字标"星壤：余辉纪元" + 副题"琉砂海 · 垂直切片"。
## - 按钮列：新游戏 / 继续 / 说明 / 退出。继续按钮由注入的 has_save Callable
##   判定可用态（auto 槽存在可读档才可用），禁用态显示"无存档"。
## - 退出只发 quit_requested 交 app 层 get_tree().quit()（本层不得自杀退出，
##   测试套件才能存活）。
## - 说明面板复用既有 HUD 操作说明灰盒文案（原文照搬，不改写）。
##
## 表现层约束：本节点不触碰持久状态，只发信号；fresh/continue 的落账与重载
## 由 app.gd 编排（_begin_fresh_boot / _unlock_game_input）。淡出入口
## fade_out(seconds) / finish_fade_out 公开，测试可手动完成淡出（跳过真实补间）。

signal game_start(fresh: bool)
signal quit_requested
signal fade_out_finished

const DEFAULT_FADE_SECONDS: float = 0.8
const CONTINUE_TEXT: String = "继续"
const NO_SAVE_TEXT: String = "无存档"

## 注入点：() -> bool，auto 槽是否存在可读档。缺省无效时按"无存档"处理
## （继续禁用）——app.gd 在 _configure_title_screen 注入 SaveService 探测。
var has_save: Callable = Callable()

var _fade_tween: Tween = null

## P2-B art probes (ui-assets §7): drop-in under assets/art/ui/title/.
## Missing → visible graybox structure; never invent approved art files.
const LOGO_ASSET_ID: String = "uia_ttl_logo"
const BTNRAIL_ASSET_ID: String = "uia_ttl_btnrail"
const DEFAULT_ASSET_BASE_DIR: String = "res://assets/art"
const LOGO_GRAYBOX := Color(0.094, 0.133, 0.184, 0.85)
const BTNRAIL_GRAYBOX := Color(0.043, 0.067, 0.110, 0.70)

## Injectable for tests (user://).
var asset_base_dir: String = DEFAULT_ASSET_BASE_DIR

@onready var _root: Control = %Root
@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _help_button: Button = %HelpButton
@onready var _quit_button: Button = %QuitButton
@onready var _help_panel: PanelContainer = %HelpPanel
@onready var _title_label: Label = %TitleLabel
@onready var _logo: TextureRect = %Logo
@onready var _logo_graybox: ColorRect = %LogoGraybox
@onready var _btnrail: TextureRect = %ButtonRailScrim
@onready var _btnrail_graybox: ColorRect = %ButtonRailGraybox


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_help_button.pressed.connect(_on_help_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_help_panel.visible = false
	refresh_continue_state()
	apply_p2_art_hooks()


## Probe UIA-TTL-LOGO + UIA-TTL-BTNRAIL; swap graybox → real texture on drop-in.
func apply_p2_art_hooks() -> void:
	_apply_logo_probe()
	_apply_btnrail_probe()


func _apply_logo_probe() -> void:
	if _logo == null or _logo_graybox == null:
		return
	var texture := AssetAdapter.texture(LOGO_ASSET_ID, asset_base_dir)
	if texture != null:
		_logo.texture = texture
		_logo.visible = true
		_logo_graybox.visible = false
		# Real wordmark replaces 64px Label as sole identity; keep node for a11y tests.
		if _title_label != null:
			_title_label.visible = false
		_root.set_meta("logo_graybox", false)
	else:
		_logo.texture = null
		_logo.visible = false
		_logo_graybox.visible = true
		_logo_graybox.color = LOGO_GRAYBOX
		if _title_label != null:
			_title_label.visible = true
		_root.set_meta("logo_graybox", true)


func _apply_btnrail_probe() -> void:
	if _btnrail == null or _btnrail_graybox == null:
		return
	var texture := AssetAdapter.texture(BTNRAIL_ASSET_ID, asset_base_dir)
	if texture != null:
		_btnrail.texture = texture
		_btnrail.visible = true
		_btnrail_graybox.visible = false
		_root.set_meta("btnrail_graybox", false)
	else:
		_btnrail.texture = null
		_btnrail.visible = false
		_btnrail_graybox.visible = true
		_btnrail_graybox.color = BTNRAIL_GRAYBOX
		_root.set_meta("btnrail_graybox", true)


## auto 槽是否存在可读档；has_save 未注入（无效）时按无存档处理。
func has_valid_save() -> bool:
	if has_save.is_valid():
		return bool(has_save.call())
	return false


## 重算继续按钮可用态与文案；has_save 注入变化后由 app（或测试）调用。
func refresh_continue_state() -> void:
	var can_continue := has_valid_save()
	_continue_button.disabled = not can_continue
	_continue_button.text = CONTINUE_TEXT if can_continue else NO_SAVE_TEXT


## 淡出并隐藏标题层（进入游戏）。seconds <= 0 立即完成；标题已隐藏时返回
## false（幂等，app 层据此回退到直接启动既有启动屏淡出）。
func fade_out(seconds: float = DEFAULT_FADE_SECONDS) -> bool:
	if not visible:
		return false
	if seconds <= 0.0:
		finish_fade_out()
		return true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, seconds)
	_fade_tween.finished.connect(finish_fade_out)
	return true


## 完成/中止淡出：停止补间（若仍在运行）、隐藏层并复位 Root modulate 供复用。
## 节点本身保留在场景树中。
func finish_fade_out() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	visible = false
	_root.modulate.a = 1.0
	fade_out_finished.emit()


func _on_new_game_pressed() -> void:
	game_start.emit(true)


func _on_continue_pressed() -> void:
	if _continue_button.disabled:
		return
	game_start.emit(false)


func _on_help_pressed() -> void:
	_help_panel.visible = not _help_panel.visible


func _on_quit_pressed() -> void:
	quit_requested.emit()
