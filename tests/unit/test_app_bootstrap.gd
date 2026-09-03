extends GutTest

const APP_SCENE_PATH: String = "res://scenes/app.tscn"


func test_project_uses_locked_runtime_contract() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), APP_SCENE_PATH)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1280)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 720)
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60)
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")


func test_app_exposes_required_session_hosts() -> void:
	var app_scene: PackedScene = load(APP_SCENE_PATH) as PackedScene
	assert_not_null(app_scene, "App scene must exist and load.")
	if app_scene == null:
		return

	var app: Node = app_scene.instantiate()
	add_child_autofree(app)
	assert_eq(app.name, "App")

	var world_host: Node = app.get_node_or_null("WorldHost")
	var modal_layer: Node = app.get_node_or_null("ModalLayer")
	var ui_layer: Node = app.get_node_or_null("UILayer")
	assert_true(world_host is Node2D, "WorldHost must be a Node2D session host.")
	assert_true(modal_layer is CanvasLayer, "ModalLayer must be a CanvasLayer.")
	assert_true(ui_layer is CanvasLayer, "UILayer must be a CanvasLayer.")


func test_app_starts_with_simplified_chinese_greybox_ui() -> void:
	var app_scene: PackedScene = load(APP_SCENE_PATH) as PackedScene
	assert_not_null(app_scene, "App scene must exist and load.")
	if app_scene == null:
		return

	var app: Node = app_scene.instantiate()
	add_child_autofree(app)
	var title: Label = app.get_node_or_null("UILayer/StartupScreen/Layout/Title") as Label
	var status: Label = app.get_node_or_null("UILayer/StartupScreen/Layout/Status") as Label
	assert_not_null(title)
	assert_not_null(status)
	if title != null:
		assert_eq(title.text, "星壤：余辉纪元")
	if status != null:
		assert_eq(status.text, "琉砂海 · 余辉纪元垂直切片")
