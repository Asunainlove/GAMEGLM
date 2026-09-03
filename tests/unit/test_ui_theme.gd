extends GutTest

## WP11 / visual polish：主题资源契约（Noto Sans SC + StyleBoxTexture UI 皮肤）。

const THEME_PATH: String = "res://themes/starsoil_theme.tres"
const FONT_PATH: String = "res://assets/fonts/NotoSansSC-Regular.subset.otf"
const PANEL_TEX_PATH: String = "res://assets/art/ui/panels/panel_menu.png"
const BTN_NORMAL_PATH: String = "res://assets/art/ui/buttons/btn_normal.png"


func test_theme_resource_exists_and_loads() -> void:
	assert_true(ResourceLoader.exists(THEME_PATH), "themes/starsoil_theme.tres must exist.")
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme, "Theme resource must load as Theme.")


func test_theme_uses_embedded_noto_sans_sc_font() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme, "Theme resource must load as Theme.")
	if theme == null:
		return

	var font: Font = theme.default_font
	assert_not_null(font, "Theme must define a default font.")
	assert_true(font is FontFile, "Default font must be embedded FontFile (Noto Sans SC subset).")
	if font is FontFile:
		var font_file: FontFile = font
		assert_eq(
			font_file.resource_path, FONT_PATH,
			"Default font must point at the approved Noto Sans SC subset."
		)
	assert_true(ResourceLoader.exists(FONT_PATH), "Noto Sans SC subset asset must exist.")


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
	assert_true(panel_style is StyleBoxTexture, "PanelContainer must use StyleBoxTexture (approved panel art).")
	var tex_panel: StyleBoxTexture = panel_style as StyleBoxTexture
	if tex_panel != null:
		assert_not_null(tex_panel.texture, "Panel StyleBoxTexture must carry a texture.")
		if tex_panel.texture != null:
			assert_eq(tex_panel.texture.resource_path, PANEL_TEX_PATH)
		assert_eq(tex_panel.texture_margin_left, 28.0)
		assert_eq(tex_panel.texture_margin_top, 24.0)
		assert_true(tex_panel.content_margin_left >= 14.0, "Panel content margin must stay readable.")

	var plain_panel_style: StyleBox = theme.get_stylebox("panel", "Panel")
	assert_true(plain_panel_style is StyleBoxTexture, "Panel type must use StyleBoxTexture.")

	var button_style: StyleBox = theme.get_stylebox("normal", "Button")
	assert_true(button_style is StyleBoxTexture, "Button normal must use StyleBoxTexture (approved button art).")
	var tex_button: StyleBoxTexture = button_style as StyleBoxTexture
	if tex_button != null:
		assert_not_null(tex_button.texture, "Button StyleBoxTexture must carry a texture.")
		if tex_button.texture != null:
			assert_eq(tex_button.texture.resource_path, BTN_NORMAL_PATH)
		assert_eq(tex_button.texture_margin_left, 10.0)
		assert_true(tex_button.content_margin_left >= 12.0, "Button content margin must stay readable.")

	assert_not_null(theme.get_stylebox("hover", "Button"), "Button hover style must be defined.")
	assert_not_null(theme.get_stylebox("pressed", "Button"), "Button pressed style must be defined.")
	assert_not_null(theme.get_stylebox("disabled", "Button"), "Button disabled style must be defined.")
