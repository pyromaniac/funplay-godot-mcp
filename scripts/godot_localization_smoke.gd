extends SceneTree

const FunplayClientConfigWriter = preload("res://addons/funplay_mcp/core/funplay_client_config_writer.gd")
const FunplayLocalization = preload("res://addons/funplay_mcp/core/funplay_localization.gd")
const FunplayMcpDock = preload("res://addons/funplay_mcp/ui/funplay_mcp_dock.gd")
const FunplayMcpSettings = preload("res://addons/funplay_mcp/core/funplay_mcp_settings.gd")

var _errors: Array[String] = []
var _test_settings_path: String = "user://funplay_mcp_localization_smoke_%d.cfg" % OS.get_process_id()


class FakeServer:
	extends RefCounted

	func is_running() -> bool:
		return false

	func is_attached_to_existing() -> bool:
		return false

	func get_endpoint() -> String:
		return "http://127.0.0.1:8765/"

	func get_interaction_log() -> Array:
		return []

	func start() -> Dictionary:
		return {"ok": true}

	func stop() -> void:
		pass

	func restart() -> Dictionary:
		return {"ok": true}


class FakeToolRegistry:
	extends RefCounted

	func get_exposure_summary(profile: String) -> Dictionary:
		return {
			"profile": profile,
			"language_mode": "gdscript",
			"exposed": 1,
			"total_in_profile": 2,
			"tools": [
				{
					"name": "ping",
					"description": "Ping the server.",
					"exposed": true,
					"disabled": false,
					"language_allowed": true,
				},
				{
					"name": "create_csharp_script",
					"description": "Create a C# script.",
					"exposed": false,
					"disabled": false,
					"language_allowed": false,
				},
			],
		}

	func call_tool(tool_name: String, _arguments: Dictionary) -> String:
		if tool_name == "get_release_readiness":
			return "{}"
		return "{}"


func _initialize() -> void:
	_cleanup_settings()
	_validate_catalogs()
	_validate_language_normalization()
	_validate_legacy_settings_migration()
	_validate_settings_persistence()
	_validate_dock_switching()
	_cleanup_settings()

	if not _errors.is_empty():
		for message in _errors:
			push_error(message)
		quit(1)
		return

	print("localization smoke passed")
	quit(0)


func _validate_catalogs() -> void:
	for error in FunplayLocalization.validate_catalogs():
		_errors.append(error)
	var dock_source: String = FileAccess.get_file_as_string("res://addons/funplay_mcp/ui/funplay_mcp_dock.gd")
	var key_pattern = RegEx.new()
	_expect(key_pattern.compile("_t\\(\"([^\"]+)\"") == OK, "Failed to compile the localization key scan.")
	for key_match in key_pattern.search_all(dock_source):
		var key: String = key_match.get_string(1)
		_expect(FunplayLocalization.has_key(key), "The Dock references an unknown localization key: %s" % key)
	_expect(
		FunplayLocalization.translate("tool_exposure_summary", FunplayLocalization.ENGLISH, [2, 3]) == "Tool Exposure: 2/3 exposed",
		"English format placeholders were not rendered correctly."
	)
	_expect(
		FunplayLocalization.translate("tool_exposure_summary", FunplayLocalization.SIMPLIFIED_CHINESE, [2, 3]) == "工具开放范围：已开放 2/3",
		"Chinese format placeholders were not rendered correctly."
	)


func _validate_language_normalization() -> void:
	_expect(FunplayLocalization.normalize_language("zh-CN") == FunplayLocalization.SIMPLIFIED_CHINESE, "zh-CN should normalize to zh_CN.")
	_expect(FunplayLocalization.normalize_language("zh_Hant") == FunplayLocalization.SIMPLIFIED_CHINESE, "Chinese locale variants should use the Chinese catalog.")
	_expect(FunplayLocalization.normalize_language("en-US") == FunplayLocalization.ENGLISH, "English locale variants should use the English catalog.")
	_expect(FunplayLocalization.normalize_language("fr") == FunplayLocalization.ENGLISH, "Unsupported locales should fall back to English.")


func _validate_settings_persistence() -> void:
	var settings = FunplayMcpSettings.new(_test_settings_path)
	settings.update_ui_language("zh-CN")
	var reloaded = FunplayMcpSettings.new(_test_settings_path)
	_expect(reloaded.ui_language == FunplayLocalization.SIMPLIFIED_CHINESE, "The selected UI language was not persisted.")
	reloaded.update_ui_language("unsupported")
	var fallback = FunplayMcpSettings.new(_test_settings_path)
	_expect(fallback.ui_language == FunplayLocalization.ENGLISH, "Unsupported persisted languages should fall back to English.")


func _validate_legacy_settings_migration() -> void:
	var legacy = ConfigFile.new()
	legacy.set_value("server", "enabled", false)
	legacy.set_value("server", "port", 9123)
	legacy.set_value("server", "auth_token", "localization-smoke-token")
	legacy.set_value("tools", "disabled", ["ping"])
	_expect(legacy.save(_test_settings_path) == OK, "Failed to create the legacy settings fixture.")

	var migrated = FunplayMcpSettings.new(_test_settings_path)
	_expect(not migrated.server_enabled, "Legacy server settings changed during language migration.")
	_expect(migrated.server_port == 9123, "Legacy port settings changed during language migration.")
	_expect(migrated.disabled_tools == ["ping"], "Legacy tool exposure settings changed during language migration.")
	var saved = ConfigFile.new()
	_expect(saved.load(_test_settings_path) == OK, "Migrated settings could not be reloaded.")
	_expect(saved.has_section_key("ui", "language"), "The language migration was not written back to settings.")


func _validate_dock_switching() -> void:
	var settings = FunplayMcpSettings.new(_test_settings_path)
	settings.update_ui_language(FunplayLocalization.ENGLISH)
	var dock = FunplayMcpDock.new()
	get_root().add_child(dock)
	dock.setup(FakeServer.new(), settings, FunplayClientConfigWriter.new(), FakeToolRegistry.new())
	dock._refresh_update_state()
	dock._refresh_tool_exposure(true)
	_expect(_tree_has_text(dock, "Check Updates"), "The Dock did not render the English catalog.")
	_expect(_tree_has_text(dock, "Updates: Not checked"), "The Dock did not localize the English update status.")
	_expect(dock._server_status_text() == "Stopped", "The Dock did not localize the English server status.")
	_expect(dock._localized_result({"code": "config_written", "path": "/tmp/mcp.json"}) == "Configuration written to /tmp/mcp.json", "The Dock did not localize an English operation result.")
	_expect(_count_http_requests(dock) == 1, "The Dock should own one update-check HTTPRequest before switching languages.")

	dock._on_language_selected(1)
	dock._refresh_update_state()
	dock._refresh_tool_exposure(true)
	_expect(settings.ui_language == FunplayLocalization.SIMPLIFIED_CHINESE, "The language selector did not update settings.")
	_expect(_tree_has_text(dock, "检查更新"), "The Dock did not rebuild with the Chinese catalog.")
	_expect(_tree_has_text(dock, "更新：尚未检查"), "The Dock did not localize the Chinese update status.")
	_expect(dock._server_status_text() == "已停止", "The Dock did not localize the Chinese server status.")
	_expect(dock._localized_result({"code": "config_written", "path": "/tmp/mcp.json"}) == "配置已写入 /tmp/mcp.json", "The Dock did not localize a Chinese operation result.")
	_expect(_tree_has_text(dock, "语言不适用"), "Dynamic tool badges were not localized.")
	_expect(_count_http_requests(dock) == 1, "Switching languages replaced or duplicated the update-check HTTPRequest.")

	get_root().remove_child(dock)
	dock.free()


func _tree_has_text(node: Node, expected: String) -> bool:
	if (node is Label or node is Button) and str(node.get("text")) == expected:
		return true
	for child in node.get_children():
		if _tree_has_text(child, expected):
			return true
	return false


func _count_http_requests(node: Node) -> int:
	var count: int = 1 if node is HTTPRequest else 0
	for child in node.get_children():
		count += _count_http_requests(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _cleanup_settings() -> void:
	if FileAccess.file_exists(_test_settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_settings_path))
