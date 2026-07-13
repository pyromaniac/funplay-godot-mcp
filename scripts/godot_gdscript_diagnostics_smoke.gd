extends SceneTree

const CoreTools = preload("res://addons/funplay_mcp/core/funplay_core_tools.gd")
const ToolRegistry = preload("res://addons/funplay_mcp/core/funplay_tool_registry.gd")
const INVALID_SCRIPT = "res://tests/fixtures/gdscript_diagnostics/invalid_too_many_args.gd"
const EXPECTED_LINE = 9

class FakeSettings:
	extends RefCounted
	var tool_profile: String = "core"


func _init() -> void:
	var tools = CoreTools.new(null, null)
	var valid: Dictionary = _parse_result(tools.validate_gdscript_file({
		"path": "res://addons/funplay_mcp/runtime/funplay_mcp_runtime_bridge.gd",
	}))
	if not bool(valid.get("ok", false)) or int(valid.get("diagnostic_count", -1)) != 0:
		_fail("Valid GDScript unexpectedly failed diagnostics: %s" % JSON.stringify(valid))
		return

	var invalid: Dictionary = _parse_result(tools.validate_gdscript_file({"path": INVALID_SCRIPT}))
	if bool(invalid.get("ok", true)):
		_fail("Invalid GDScript unexpectedly passed validation.")
		return
	if not _assert_diagnostic(invalid, "validate_gdscript_file"):
		return

	var registry = ToolRegistry.new(null, FakeSettings.new())
	var scan: Dictionary = _parse_result(registry.call_tool("get_script_errors", {
		"path": "res://tests/fixtures/gdscript_diagnostics",
		"language": "gdscript",
		"max_files": 10,
	}))
	if int(scan.get("error_count", 0)) != 1:
		_fail("get_script_errors did not return exactly one invalid fixture: %s" % JSON.stringify(scan))
		return
	var errors = scan.get("errors", [])
	if not (errors is Array) or errors.is_empty() or not (errors[0] is Dictionary):
		_fail("get_script_errors returned an invalid errors payload: %s" % JSON.stringify(scan))
		return
	if not _assert_diagnostic(errors[0], "get_script_errors"):
		return
	registry.teardown()

	print("gdscript diagnostics smoke passed")
	quit(0)


func _assert_diagnostic(result: Dictionary, source_name: String) -> bool:
	if int(result.get("line", -1)) != EXPECTED_LINE:
		_fail("%s did not return line %d: %s" % [source_name, EXPECTED_LINE, JSON.stringify(result)])
		return false
	var diagnostics = result.get("diagnostics", [])
	if not (diagnostics is Array) or diagnostics.is_empty() or not (diagnostics[0] is Dictionary):
		_fail("%s returned no structured diagnostics: %s" % [source_name, JSON.stringify(result)])
		return false
	var diagnostic: Dictionary = diagnostics[0]
	if str(diagnostic.get("path", "")) != INVALID_SCRIPT:
		_fail("%s returned the wrong diagnostic path: %s" % [source_name, JSON.stringify(diagnostic)])
		return false
	if int(diagnostic.get("line", -1)) != EXPECTED_LINE:
		_fail("%s returned the wrong diagnostic line: %s" % [source_name, JSON.stringify(diagnostic)])
		return false
	if not str(diagnostic.get("message", "")).contains("Too many arguments"):
		_fail("%s returned an incomplete diagnostic message: %s" % [source_name, JSON.stringify(diagnostic)])
		return false
	if not str(diagnostic.get("snippet", "")).contains("select_player_action"):
		_fail("%s returned no source snippet: %s" % [source_name, JSON.stringify(diagnostic)])
		return false
	return true


func _parse_result(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
