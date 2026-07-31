extends Node


func _ready() -> void:
	var marker_dir: String = ProjectSettings.globalize_path("res://integration_markers")
	DirAccess.make_dir_recursive_absolute(marker_dir)
	var marker_path: String = marker_dir.path_join("instance_%d.json" % OS.get_process_id())
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(JSON.stringify({
			"pid": OS.get_process_id(),
			"user_args": OS.get_cmdline_user_args(),
		}) + "\n")
