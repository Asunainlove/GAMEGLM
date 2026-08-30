extends Node

## W001-P05 启动屏淡出：boot（_ready 装配）完成后把 UILayer/StartupScreen 的
## modulate:a 从 1 补间到 0（2 秒），随后隐藏节点。节点与其文案**保留**
## （test_app_bootstrap 断言锁定，不可删）；StartupScreen 及其 Layout 的
## mouse_filter 均为 IGNORE，淡出期间不阻塞输入。淡出完成入口
## finish_startup_fade 公开，测试可手动调用完成（跳过真实补间等待）。

const STARTUP_FADE_SECONDS: float = 2.0

@onready var world_host: Node2D = %WorldHost
@onready var modal_layer: CanvasLayer = %ModalLayer
@onready var ui_layer: CanvasLayer = %UILayer
@onready var startup_screen: ColorRect = %StartupScreen

var _startup_fade_tween: Tween = null


func _ready() -> void:
	assert(world_host != null)
	assert(modal_layer != null)
	assert(ui_layer != null)
	_begin_startup_fade()


func _begin_startup_fade() -> void:
	if startup_screen == null or not startup_screen.visible:
		return
	_startup_fade_tween = create_tween()
	_startup_fade_tween.tween_property(startup_screen, "modulate:a", 0.0, STARTUP_FADE_SECONDS)
	_startup_fade_tween.finished.connect(finish_startup_fade)


## 淡出完成：停止补间（若仍在运行）、隐藏启动屏并复位 modulate 供复用。
## 节点本身保留在场景树中。
func finish_startup_fade() -> void:
	if _startup_fade_tween != null and _startup_fade_tween.is_valid():
		_startup_fade_tween.kill()
	_startup_fade_tween = null
	if startup_screen == null or not startup_screen.visible:
		return
	startup_screen.visible = false
	startup_screen.modulate.a = 1.0
