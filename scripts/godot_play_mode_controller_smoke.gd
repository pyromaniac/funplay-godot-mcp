extends SceneTree

const PlayModeController = preload("res://addons/funplay_mcp/core/funplay_play_mode_controller.gd")


class FakeEditorSettings:
	extends RefCounted

	var metadata: Dictionary = {}

	func get_project_metadata(section: String, key: String, default = null):
		return metadata.get("%s/%s" % [section, key], default)


class FakeEditor:
	extends RefCounted

	var settings := FakeEditorSettings.new()
	var playing: bool = false
	var playing_scene: String = ""
	var play_main_calls: int = 0
	var play_current_calls: int = 0
	var play_custom_calls: int = 0
	var stop_calls: int = 0

	func get_editor_settings():
		return settings

	func is_playing_scene() -> bool:
		return playing

	func get_playing_scene() -> String:
		return playing_scene

	func get_current_path() -> String:
		return "res://main.tscn"

	func get_open_scenes() -> PackedStringArray:
		return PackedStringArray(["res://main.tscn"])

	func play_main_scene() -> void:
		play_main_calls += 1
		playing = true
		playing_scene = "res://main.tscn"

	func play_current_scene() -> void:
		play_current_calls += 1
		playing = true
		playing_scene = get_current_path()

	func play_custom_scene(scene_path: String) -> void:
		play_custom_calls += 1
		playing = true
		playing_scene = scene_path

	func stop_playing_scene() -> void:
		stop_calls += 1
		playing = false
		playing_scene = ""


class FakePlugin:
	extends RefCounted

	var editor := FakeEditor.new()

	func get_editor_interface():
		return editor


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("application/run/main_scene", "res://main.tscn")
	var plugin := FakePlugin.new()
	plugin.editor.settings.metadata = {
		"debug_options/multiple_instances_enabled": true,
		"debug_options/run_instance_count": 2,
		"debug_options/run_instances_config": [
			{"override_args": true, "arguments": "-- creative"},
			{"override_args": true, "arguments": "-- client"},
		],
	}
	var controller = PlayModeController.new(plugin)

	var refused: Dictionary = controller.request_start("main")
	if not _expect(not bool(refused.get("success", true)), "Unconfirmed multiple-instance start unexpectedly succeeded."):
		return
	if not _expect(str(refused.get("code", "")) == "MULTIPLE_INSTANCES_CONFIRMATION_REQUIRED", "Multiple-instance refusal returned the wrong code."):
		return
	if not _expect(plugin.editor.play_main_calls == 0, "A refused request reached EditorInterface."):
		return

	var scheduled: Dictionary = controller.request_start("main", "", {"allow_multiple_instances": true})
	if not _expect(str(scheduled.get("status", "")) == "scheduled", "Confirmed start was not scheduled."):
		return
	if not _expect(plugin.editor.play_main_calls == 0, "Play started inside the request callback instead of being deferred."):
		return
	var operation_id: String = str(scheduled.get("operation", {}).get("id", ""))

	var duplicate: Dictionary = controller.request_start("main", "", {"allow_multiple_instances": true})
	if not _expect(bool(duplicate.get("deduplicated", false)), "A duplicate scheduled start was not deduplicated."):
		return
	if not _expect(str(duplicate.get("operation", {}).get("id", "")) == operation_id, "A duplicate request created a second operation."):
		return

	controller.poll()
	var running_state: Dictionary = controller.get_state()
	if not _expect(plugin.editor.play_main_calls == 1, "The deferred start did not execute exactly once."):
		return
	if not _expect(bool(running_state.get("is_playing_scene", false)), "The controller did not confirm the running state."):
		return
	if not _expect(running_state.get("pending_operation", {}).is_empty(), "A completed start remained pending."):
		return
	if not _expect(str(running_state.get("last_operation", {}).get("status", "")) == "completed", "The completed start was not recorded."):
		return
	if not _expect(running_state.get("open_scenes", []) is Array, "Open scenes were not normalized to a JSON array."):
		return
	if not _expect(int(running_state.get("run_instances", {}).get("effective_instance_count", 0)) == 2, "The effective instance count was not reported."):
		return
	if not _expect(bool(running_state.get("run_instances", {}).get("has_custom_arguments", false)), "Custom per-instance arguments were not detected."):
		return

	var already_running: Dictionary = controller.request_start("main")
	if not _expect(str(already_running.get("status", "")) == "already_running", "A repeated start was not idempotent."):
		return
	if not _expect(plugin.editor.play_main_calls == 1, "An idempotent start restarted the scene."):
		return

	var restart: Dictionary = controller.request_start("main", "", {
		"allow_multiple_instances": true,
		"restart_if_running": true,
	})
	if not _expect(str(restart.get("status", "")) == "scheduled", "An explicit restart was not scheduled."):
		return
	controller.poll()
	if not _expect(plugin.editor.play_main_calls == 2, "An explicit restart did not execute."):
		return

	var stop: Dictionary = controller.request_stop()
	if not _expect(str(stop.get("status", "")) == "scheduled", "Stop was not scheduled."):
		return
	if not _expect(plugin.editor.stop_calls == 0, "Stop ran inside the request callback instead of being deferred."):
		return
	var duplicate_stop: Dictionary = controller.request_stop()
	if not _expect(bool(duplicate_stop.get("deduplicated", false)), "A duplicate stop was not deduplicated."):
		return
	controller.poll()
	if not _expect(plugin.editor.stop_calls == 1 and not plugin.editor.playing, "The deferred stop did not complete exactly once."):
		return

	var start_to_cancel: Dictionary = controller.request_start("main", "", {"allow_multiple_instances": true})
	if not _expect(str(start_to_cancel.get("status", "")) == "scheduled", "The cancellation test did not schedule a start."):
		return
	var canceled: Dictionary = controller.request_stop()
	if not _expect(str(canceled.get("status", "")) == "canceled_before_start", "Stop did not cancel the queued start."):
		return
	controller.poll()
	if not _expect(plugin.editor.play_main_calls == 2, "A canceled start still reached EditorInterface."):
		return

	plugin.editor.playing = true
	plugin.editor.playing_scene = "res://main.tscn"
	controller.request_stop()
	var conflicting_start: Dictionary = controller.request_start("main", "", {
		"allow_multiple_instances": true,
		"restart_if_running": true,
	})
	if not _expect(str(conflicting_start.get("code", "")) == "PLAY_MODE_TRANSITION_PENDING", "A start bypassed a pending stop transition."):
		return
	controller.poll()
	if not _expect(not plugin.editor.playing, "The final stop transition was not confirmed."):
		return

	var already_stopped: Dictionary = controller.request_stop()
	if not _expect(str(already_stopped.get("status", "")) == "already_stopped", "Stopping an idle editor was not idempotent."):
		return

	controller.teardown()
	print("play mode controller smoke passed")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	printerr(message)
	quit(1)
	return false
