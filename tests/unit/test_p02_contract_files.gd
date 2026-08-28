extends GutTest

const REQUIRED_PRODUCTION_FILES: Array[String] = [
	"res://src/core/app_result.gd",
	"res://src/state/state_patch.gd",
	"res://src/state/game_state.gd",
	"res://src/save/save_codec.gd",
	"res://src/save/save_service.gd",
]


func test_p02_production_contract_files_exist() -> void:
	for path: String in REQUIRED_PRODUCTION_FILES:
		assert_true(FileAccess.file_exists(path), "Missing required P02 implementation: %s" % path)


func test_p02_registers_only_game_state_and_save_service_autoloads() -> void:
	var autoload_names: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("autoload/"):
			autoload_names.append(property_name.trim_prefix("autoload/"))
	autoload_names.sort()
	assert_eq(autoload_names, ["GameState", "SaveService"])
	assert_eq(ProjectSettings.get_setting("autoload/GameState"), "*res://src/state/game_state.gd")
	assert_eq(ProjectSettings.get_setting("autoload/SaveService"), "*res://src/save/save_service.gd")
