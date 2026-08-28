class_name AppResult
extends RefCounted

var is_ok: bool
var code: String
var message: String
var value: Variant
var details: Dictionary


func _init(
		result_is_ok: bool,
		result_code: String,
		result_message: String = "",
		result_value: Variant = null,
		result_details: Dictionary = {}
) -> void:
	is_ok = result_is_ok
	code = result_code
	message = result_message
	value = result_value
	details = result_details.duplicate(true)


static func success(
		result_value: Variant = null,
		result_code: String = "ok",
		result_details: Dictionary = {}
) -> AppResult:
	return AppResult.new(true, result_code, "", result_value, result_details)


static func failure(result_code: String, result_message: String) -> AppResult:
	return AppResult.new(false, result_code, result_message)
