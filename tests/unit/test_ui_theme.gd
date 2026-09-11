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


func test_theme_font_ladder_variations() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	assert_eq(theme.get_font_size("font_size", "Label"), 14, "Body Label font size must be 14.")
	assert_eq(theme.get_font_size("font_size", "LabelPanelTitle"), 18, "Panel title ladder must be 18.")
	assert_eq(theme.get_font_size("font_size", "LabelScreenTitle"), 20, "Screen title ladder must be 20.")
	assert_eq(theme.get_font_size("font_size", "LabelBanner"), 22, "Banner ladder must be 22.")
	assert_eq(theme.get_type_variation_base("LabelPanelTitle"), "Label")
	assert_eq(theme.get_type_variation_base("LabelScreenTitle"), "Label")
	assert_eq(theme.get_type_variation_base("LabelBanner"), "Label")


func test_theme_shared_panel_variants() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	for type_name in ["PanelDialog", "PanelInventory", "PanelMenu", "PanelHelp", "PanelDimOverlay"]:
		assert_true(theme.get_stylebox_list(type_name).has("panel"), "%s must define panel style." % type_name)
	var dialog: StyleBox = theme.get_stylebox("panel", "PanelDialog")
	assert_true(dialog is StyleBoxTexture, "PanelDialog must use StyleBoxTexture.")
	var dialog_tex: StyleBoxTexture = dialog as StyleBoxTexture
	if dialog_tex != null and dialog_tex.texture != null:
		assert_eq(dialog_tex.texture.resource_path, "res://assets/art/ui/panels/panel_dialog.png")
	var inv: StyleBox = theme.get_stylebox("panel", "PanelInventory")
	assert_true(inv is StyleBoxTexture)
	var inv_tex: StyleBoxTexture = inv as StyleBoxTexture
	if inv_tex != null and inv_tex.texture != null:
		assert_eq(inv_tex.texture.resource_path, "res://assets/art/ui/panels/panel_inventory.png")
	var help: StyleBox = theme.get_stylebox("panel", "PanelHelp")
	assert_true(help is StyleBoxTexture)
	var help_tex: StyleBoxTexture = help as StyleBoxTexture
	if help_tex != null and help_tex.texture != null:
		assert_eq(help_tex.texture.resource_path, "res://assets/art/ui/panels/panel_help.png")
	var dim: StyleBox = theme.get_stylebox("panel", "PanelDimOverlay")
	assert_true(dim is StyleBoxFlat, "FinishBanner dim overlay must be tokenised StyleBoxFlat.")


func test_theme_gold_focus_ring() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	var focus: StyleBox = theme.get_stylebox("focus", "Button")
	assert_true(focus is StyleBoxFlat, "Button focus must be a gold ring StyleBoxFlat.")
	var flat: StyleBoxFlat = focus as StyleBoxFlat
	if flat == null:
		return
	assert_eq(flat.border_width_left, 2)
	assert_eq(flat.border_width_top, 2)
	assert_eq(flat.border_width_right, 2)
	assert_eq(flat.border_width_bottom, 2)
	# gold.main #E8C878 → Color(0.910, 0.784, 0.471) ±2/255
	assert_true(abs(flat.border_color.r - StarsoilTokens.GOLD_MAIN.r) <= 2.0 / 255.0)
	assert_true(abs(flat.border_color.g - StarsoilTokens.GOLD_MAIN.g) <= 2.0 / 255.0)
	assert_true(abs(flat.border_color.b - StarsoilTokens.GOLD_MAIN.b) <= 2.0 / 255.0)


func test_starsoil_tokens_match_ui_assets_section_0_1() -> void:
	# Spot-check contract hex → Color (±2/255 already baked into StarsoilTokens).
	assert_true(abs(StarsoilTokens.GOLD_MAIN.r - 232.0 / 255.0) <= 2.0 / 255.0)
	assert_true(abs(StarsoilTokens.SEMANTIC_TEAL.r - 107.0 / 255.0) <= 2.0 / 255.0)
	assert_true(abs(StarsoilTokens.TEXT_PRIMARY.r - 219.0 / 255.0) <= 2.0 / 255.0)
	assert_true(abs(StarsoilTokens.BG_DEEP.r - 11.0 / 255.0) <= 2.0 / 255.0)


func test_scenes_use_theme_panel_variations_not_local_stylebox_forks() -> void:
	var hud: PackedScene = load("res://scenes/ui_hud.tscn") as PackedScene
	var dialogue: PackedScene = load("res://scenes/dialogue_box.tscn") as PackedScene
	var title: PackedScene = load("res://scenes/title_screen.tscn") as PackedScene
	var battle: PackedScene = load("res://scenes/battle.tscn") as PackedScene
	assert_not_null(hud)
	assert_not_null(dialogue)
	assert_not_null(title)
	assert_not_null(battle)
	var hud_root: Node = hud.instantiate()
	var inv: PanelContainer = hud_root.get_node("InventoryPanel") as PanelContainer
	assert_eq(str(inv.theme_type_variation), "PanelInventory")
	assert_false(inv.has_theme_stylebox_override("panel"), "InventoryPanel must not fork StyleBox locally.")
	var menu: PanelContainer = hud_root.get_node("MenuPanel") as PanelContainer
	assert_eq(str(menu.theme_type_variation), "PanelMenu")
	var help: PanelContainer = hud_root.get_node("MenuPanel/Content/HelpPanel") as PanelContainer
	assert_eq(str(help.theme_type_variation), "PanelHelp")
	hud_root.free()

	var dlg_root: Node = dialogue.instantiate()
	var panel: Panel = dlg_root.get_node("Panel") as Panel
	assert_eq(str(panel.theme_type_variation), "PanelDialog")
	assert_false(panel.has_theme_stylebox_override("panel"))
	dlg_root.free()

	var title_root: Node = title.instantiate()
	var subtitle: Label = title_root.get_node("%Subtitle") as Label
	assert_not_null(subtitle)
	# Decorative teal banned: subtitle must not use semantic.teal.
	var sub_color: Color = subtitle.get_theme_color("font_color")
	if subtitle.has_theme_color_override("font_color"):
		sub_color = subtitle.get("theme_override_colors/font_color")
	assert_false(
		abs(sub_color.r - 0.42) < 0.02 and abs(sub_color.g - 0.79) < 0.02 and abs(sub_color.b - 0.72) < 0.02,
		"Title subtitle must not use decorative teal."
	)
	var title_help: PanelContainer = title_root.get_node("%HelpPanel") as PanelContainer
	assert_eq(str(title_help.theme_type_variation), "PanelHelp")
	title_root.free()

	var battle_root: Node = battle.instantiate()
	var finish: PanelContainer = battle_root.get_node("UI/FinishBanner") as PanelContainer
	assert_eq(str(finish.theme_type_variation), "PanelDimOverlay")
	assert_false(finish.has_theme_stylebox_override("panel"), "FinishBanner must use theme PanelDimOverlay, not local StyleBoxFlat.")
	battle_root.free()
