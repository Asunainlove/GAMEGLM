extends Node

## W001-P05 启动屏淡出 + W003-A10 标题/主菜单流程（缺口报告 E2）。
##
## W003-A10 时序（详见 ops/evidence/W003-A10.md）：
## 1. boot（_ready）：标题层 TitleScreen 可见并遮住游戏画面；GameSession/
##    WorldHost/Hud 置 process_mode DISABLED——**读档时序说明**：GameSession._ready
##    （子节点先于父节点就绪）已把 auto 档 restore 进 store，此后玩家在标题上
##    做选择；标题期间游戏不 tick，存档不会被覆盖（autosave 只在 patch 后触发，
##    而 tick/请求链全部冻结）。
## 2. 继续（game_start(false)）：解锁 process_mode（恢复各自原值，Hud 为
##    ALWAYS）→ 请求 "bgm_explore" → 标题淡出（0.8s）→ 标题 fade_out_finished
##    接续**既有启动屏文案淡出流程**（_begin_startup_fade，2s）→ 游戏。
## 3. 新游戏（game_start(true)）：fresh 引导 = reset_to_initial + 删除
##    auto/manual 档 + 置 static 标志 + reload_current_scene；重载后的新 App
##    _ready 消费标志（static 变量存活于脚本资源，不随场景重载丢失）：跳过
##    标题、直接解锁、请求 "bgm_explore"、接续既有启动屏淡出。先 reset+删档
##    再重载，与 GameSession._on_restart_requested（W001-P06）语义一致，且
##    保证重载后的读档必然失败（无档）→ 干净的初始状态与 PlayerSpawn 出生点。
##
## W001-P05 既有契约（test_app_bootstrap / test_integration 锁定，未改动）：
## StartupScreen 节点与其文案**保留**（保留为标题背景层，标题在其上层 30），
## mouse_filter 均 IGNORE 不阻塞输入；淡出完成入口 finish_startup_fade 公开，
## 测试可手动调用完成（跳过真实补间等待）。
##
## A9 AudioDirector 接线：以 ResourceLoader.exists 守卫动态装配
## res://src/audio/audio_director.gd（class_name AudioDirector：play_bgm/
## play_sfx/set_master_muted）；A9 未合入时优雅跳过，合并后自动生效。测试可
## 预先注入 audio_director 替身。play_bgm 的 resolver 未注入静默跳过是 A9
## 类自身语义，app 层只负责调用。

const STARTUP_FADE_SECONDS: float = 2.0
const TITLE_FADE_SECONDS: float = 0.8
const DEFAULT_SAVE_SLOT: String = "auto"
const MANUAL_SAVE_SLOT: String = "manual"
const AUDIO_DIRECTOR_SCRIPT_PATH: String = "res://src/audio/audio_director.gd"
const TITLE_BGM_ID: String = "bgm_title"
const EXPLORE_BGM_ID: String = "bgm_explore"

## W003-A10 fresh 引导跨重载标志：仅由缺省 fresh 引导置位、下一次 App._ready
## 消费并复位；测试注入 fresh_boot_handler 替身时永不置位。
static var _fresh_boot_pending: bool = false

@onready var world_host: Node2D = %WorldHost
@onready var modal_layer: CanvasLayer = %ModalLayer
@onready var ui_layer: CanvasLayer = %UILayer
@onready var startup_screen: ColorRect = %StartupScreen
@onready var title_screen: TitleScreen = %TitleScreen
@onready var game_session: Node = get_node_or_null("GameSession")

var _startup_fade_tween: Tween = null

## 标题期间被锁 process_mode 的节点 → 原值（解锁恢复用；Hud 原为 ALWAYS）。
var _locked_process_modes: Dictionary = {}

## 注入点：新游戏 fresh 引导；缺省 reset+删档+标记+重载场景。测试注入替身
## （直接重载会杀掉 GUT 测试场景）。
var fresh_boot_handler: Callable = Callable()

## 注入点：AudioDirector（A9）。非 null 时跳过守卫式动态装配。
var audio_director: Node = null


func _ready() -> void:
	assert(world_host != null)
	assert(modal_layer != null)
	assert(ui_layer != null)
	assert(title_screen != null)
	_configure_title_screen()
	_resolve_audio_director()
	if _fresh_boot_pending:
		_fresh_boot_pending = false
		_enter_game_after_fresh_reload()
	elif title_screen.visible:
		_lock_game_input()
		_play_bgm(TITLE_BGM_ID)
	else:
		_begin_startup_fade()


# ---------------------------------------------------------------- 标题编排（W003-A10）


## 注入标题的存档探测（已有注入时保留替身）、接线信号并刷新继续按钮状态。
func _configure_title_screen() -> void:
	if title_screen == null:
		return
	if not title_screen.has_save.is_valid():
		title_screen.has_save = _probe_auto_save
	if not title_screen.game_start.is_connected(_on_title_game_start):
		title_screen.game_start.connect(_on_title_game_start)
	if not title_screen.quit_requested.is_connected(_on_title_quit_requested):
		title_screen.quit_requested.connect(_on_title_quit_requested)
	title_screen.refresh_continue_state()


## 缺省 auto 档探测：SaveService.load_slot("auto") 完整读档成功即可续玩。
## （GameSession._ready 已把可读档 restore 进 store；此处仅作可用性判定。）
func _probe_auto_save() -> bool:
	return SaveService.load_slot(DEFAULT_SAVE_SLOT).is_ok


## 标题期输入锁：GameSession（停 tick/建造热键）、WorldHost（停玩家物理与
## 输入，防键盘泄漏进游戏）、Hud（停菜单/背包快捷键）。记录原 process_mode
## 便于按原值恢复（Hud 在 ui_hud.tscn 中为 PROCESS_MODE_ALWAYS）。
func _lock_game_input() -> void:
	_locked_process_modes.clear()
	for node: Node in _lockable_nodes():
		_locked_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _unlock_game_input() -> void:
	for node_value: Variant in _locked_process_modes:
		var node := node_value as Node
		if node != null and is_instance_valid(node):
			node.process_mode = int(_locked_process_modes[node_value])
	_locked_process_modes.clear()


func _lockable_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	if game_session != null:
		nodes.append(game_session)
	if world_host != null:
		nodes.append(world_host)
	var hud := get_node_or_null("UILayer/Hud")
	if hud != null:
		nodes.append(hud)
	return nodes


## game_start 路由：fresh=true 走新游戏引导；false 走继续（读档已在 boot 时
## restore，直接解锁进入游戏循环）。
func _on_title_game_start(fresh: bool) -> void:
	if fresh:
		_begin_fresh_boot()
		return
	_unlock_game_input()
	_play_bgm(EXPLORE_BGM_ID)
	_begin_title_fade_out()


## 退出：标题层只发 quit_requested，真正的 get_tree().quit() 在 app 层执行。
func _on_title_quit_requested() -> void:
	if get_tree() != null:
		get_tree().quit()


## fresh 引导：注入替身优先；缺省重置持久态 → 删除 auto/manual 槽全部候选
## 文件 → 置跨重载标志 → 重载当前场景。重载后的新 App._ready 消费标志。
func _begin_fresh_boot() -> void:
	if fresh_boot_handler.is_valid():
		fresh_boot_handler.call()
		return
	GameState.reset_to_initial()
	SaveService.delete_slot(DEFAULT_SAVE_SLOT)
	SaveService.delete_slot(MANUAL_SAVE_SLOT)
	_fresh_boot_pending = true
	if get_tree() != null:
		get_tree().reload_current_scene()


## fresh 重载后的进入分支（App._ready 消费 _fresh_boot_pending 时调用）：
## 跳过标题、解锁游戏输入、请求探索 BGM，并启动既有启动屏文案淡出流程。
func _enter_game_after_fresh_reload() -> void:
	if title_screen != null:
		title_screen.visible = false
	_unlock_game_input()
	_play_bgm(EXPLORE_BGM_ID)
	_begin_startup_fade()


## 标题淡出：完成后接续既有启动屏淡出流程（_begin_startup_fade）。标题缺席
## 或已隐藏（fade_out 幂等返回 false）时直接回退到启动屏淡出。
func _begin_title_fade_out() -> void:
	if title_screen == null or not title_screen.visible:
		_begin_startup_fade()
		return
	if not title_screen.fade_out_finished.is_connected(_begin_startup_fade):
		title_screen.fade_out_finished.connect(_begin_startup_fade)
	if not title_screen.fade_out(TITLE_FADE_SECONDS):
		_begin_startup_fade()


# ---------------------------------------------------------------- 启动屏淡出（W001-P05，未改动）


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


# ---------------------------------------------------------------- AudioDirector 接线（A9）


## A9 守卫式装配：脚本缺席时优雅跳过（并行合并后无需改动即自动生效）；
## 已注入替身（测试）时跳过。
func _resolve_audio_director() -> void:
	if audio_director != null:
		return
	if not ResourceLoader.exists(AUDIO_DIRECTOR_SCRIPT_PATH):
		return
	var script: Variant = load(AUDIO_DIRECTOR_SCRIPT_PATH)
	if script is Script:
		var candidate: Variant = (script as Script).new()
		if candidate is Node:
			audio_director = candidate
			audio_director.name = "AudioDirector"
			add_child(audio_director)


## 请求 BGM（"bgm_title" → "bgm_explore"）。AudioDirector 缺席、无 play_bgm
## 方法，或（A9 自身语义）resolver 未注入时静默跳过。
func _play_bgm(track_id: String) -> void:
	if audio_director == null or not audio_director.has_method("play_bgm"):
		return
	audio_director.call("play_bgm", track_id)
