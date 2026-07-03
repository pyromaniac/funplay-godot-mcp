extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bridge_script = load("res://addons/funplay_mcp/runtime/funplay_mcp_runtime_bridge.gd")
	if bridge_script == null:
		_fail("Failed to load runtime bridge script.")
		return

	var scene := Node2D.new()
	scene.name = "SmokeScene"
	var label := Label.new()
	label.name = "ScoreLabel"
	label.text = "42"
	scene.add_child(label)
	root.add_child(scene)
	current_scene = scene

	var bridge = bridge_script.new()
	root.add_child(bridge)
	await process_frame

	if not _run_command(bridge, "query_node", {"node_path": "ScoreLabel", "properties": ["text"]}, "query"):
		return
	if not _run_command(bridge, "send_input", {"type": "key", "key": "space", "mode": "tap"}, "input"):
		return
	if _run_command(bridge, "send_input", {"type": "key", "key": "space", "mode": "invalid"}, "bad_mode", false):
		_fail("Invalid input mode unexpectedly succeeded.")
		return
	if not _run_command(bridge, "get_events", {}, "events"):
		return
	if not _run_capture_headless_check(bridge):
		return

	print("runtime bridge smoke passed")
	quit(0)


func _run_command(bridge: Node, command: String, arguments: Dictionary, label: String, expect_success: bool = true) -> bool:
	var command_id := "%s_%d" % [label, Time.get_ticks_usec()]
	var file := FileAccess.open("user://funplay_mcp_runtime_command.json", FileAccess.WRITE)
	if file == null:
		_fail("Failed to write runtime bridge command.")
		return false
	file.store_string(JSON.stringify({"id": command_id, "command": command, "arguments": arguments}, "\t") + "\n")
	file = null

	bridge._process(0.1)
	var parsed: Dictionary = _read_response(command_id)
	if parsed.is_empty():
		return false

	var succeeded: bool = bool(parsed.get("success", false))
	if succeeded != expect_success:
		_fail("Unexpected command success for %s: %s" % [command, JSON.stringify(parsed)])
		return false
	if not expect_success:
		return false

	if command == "query_node":
		var requested = parsed.get("result", {}).get("requested_properties", {})
		if not (requested is Dictionary) or str(requested.get("text", "")) != "42":
			_fail("query_node did not return the requested Label text.")
			return false
	return true


func _run_capture_headless_check(bridge: Node) -> bool:
	var command_id := "capture_%d" % Time.get_ticks_usec()
	var file := FileAccess.open("user://funplay_mcp_runtime_command.json", FileAccess.WRITE)
	if file == null:
		_fail("Failed to write capture command.")
		return false
	file.store_string(JSON.stringify({
		"id": command_id,
		"command": "capture_view",
		"arguments": {"save_path": "user://funplay_mcp_runtime_screenshots/smoke_capture.png"},
	}, "\t") + "\n")
	file = null

	bridge._process(0.1)
	var parsed: Dictionary = _read_response(command_id)
	if parsed.is_empty():
		return false

	if DisplayServer.get_name().to_lower() == "headless":
		var result = parsed.get("result", {})
		if bool(parsed.get("success", true)) or not (result is Dictionary) or not str(result.get("error", "")).contains("headless"):
			_fail("capture_view should report headless capture as unavailable: %s" % JSON.stringify(parsed))
			return false
		return true

	if not bool(parsed.get("success", false)):
		_fail("capture_view failed outside headless mode: %s" % JSON.stringify(parsed))
		return false
	return true


func _read_response(command_id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string("user://funplay_mcp_runtime_response.json")
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		_fail("Missing runtime bridge response for %s." % command_id)
		return {}
	var parsed: Dictionary = json.data
	if str(parsed.get("id", "")) != command_id:
		_fail("Runtime bridge response id mismatch for %s: %s" % [command_id, JSON.stringify(parsed)])
		return {}
	return parsed


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
