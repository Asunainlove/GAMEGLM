extends GutTest

## WP11：主题资源契约测试（先于实现编写，RED → GREEN）。

const THEME_PATH: String = "res://themes/starsoil_theme.tres"


func test_theme_resource_exists_and_loads() -> void:
	assert_true(ResourceLoader.exists(THEME_PATH), "themes/starsoil_theme.tres must exist.")
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme, "Theme resource must load as Theme.")


func test_theme_uses_windows_cjk_system_font() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme, "Theme resource must load as Theme.")
	if theme == null:
		return

	var font: Font = theme.default_font
	assert_not_null(font, "Theme must define a default font.")
	assert_true(font is SystemFont, "Default font must be a SystemFont for offline Windows CJK.")
	if font is SystemFont:
		var system_font: SystemFont = font
		assert_true(system_font.font_names.has("Microsoft YaHei UI"), "Font name list must include Microsoft YaHei UI.")
		assert_true(system_font.font_names.has("Microsoft YaHei"), "Font name list must include Microsoft YaHei.")
		assert_true(system_font.font_names.has("SimHei"), "Font name list must include SimHei.")


func test_theme_base_font_size_is_14() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	assert_eq(theme.default_font_size, 14, "Base font size must be 14.")


func test_theme_defines_minimal_panel_and_button_styles() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return

	var panel_style: StyleBox = theme.get_stylebox("panel", "PanelContainer")
	assert_true(panel_style is StyleBoxFlat, "PanelContainer must use a StyleBoxFlat.")
	var flat_panel: StyleBoxFlat = panel_style as StyleBoxFlat
	if flat_panel != null:
		assert_eq(flat_panel.border_width_left, 1, "Panel border must be thin (1px).")
		assert_eq(flat_panel.border_width_top, 1, "Panel border must be thin (1px).")
		assert_true(flat_panel.bg_color.r < 0.5, "Panel background must be dark.")
		assert_true(flat_panel.bg_color.g < 0.5, "Panel background must be dark.")
		assert_true(flat_panel.bg_color.b < 0.5, "Panel background must be dark.")

	var plain_panel_style: StyleBox = theme.get_stylebox("panel", "Panel")
	assert_true(plain_panel_style is StyleBoxFlat, "Panel type must use a StyleBoxFlat.")

	var button_style: StyleBox = theme.get_stylebox("normal", "Button")
	assert_true(button_style is StyleBoxFlat, "Button normal must use a StyleBoxFlat.")
	var flat_button: StyleBoxFlat = button_style as StyleBoxFlat
	if flat_button != null:
		assert_eq(flat_button.border_width_left, 1, "Button border must be thin (1px).")
		assert_true(flat_button.bg_color.r < 0.5, "Button background must be dark greybox.")
		assert_true(flat_button.bg_color.g < 0.5, "Button background must be dark greybox.")
		assert_true(flat_button.bg_color.b < 0.5, "Button background must be dark greybox.")

	assert_not_null(theme.get_stylebox("hover", "Button"), "Button hover style must be defined.")
	assert_not_null(theme.get_stylebox("pressed", "Button"), "Button pressed style must be defined.")
