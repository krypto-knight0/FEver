extends RefCounted
## Export exact save bytes without loading a cartridge or decoding progress.
static func files() -> Dictionary:
	var result := {}
	for game in ["fe6", "fe7"]:
		var path := preload("res://runtime/game_identity.gd").save_path(game)
		# Only the current format's save locations belong in a new export.
		if FileAccess.file_exists(path): result[game + "/suspend.json"] = path
	# Modified cartridges have separate identities and must be included in backup.
	var identity = preload("res://runtime/game_identity.gd")
	for folder in DirAccess.get_directories_at("user://saves"):
		if not folder.begins_with("fe6-"): continue
		var digest := folder.trim_prefix("fe6-")
		if digest.is_empty() or not identity.valid_digest(digest): continue
		var path: String = identity.save_path("fe6",digest)
		if FileAccess.file_exists(path): result[folder+"/suspend.json"] = path
	return result

static func export_to(path: String) -> String:
	var saves := files()
	if saves.is_empty(): return "No saves on this device yet."
	var archive := ZIPPacker.new()
	if archive.open(path) != OK: return "Cannot write saves to this location."
	for name in saves:
		var source := FileAccess.open(saves[name], FileAccess.READ)
		if source == null:
			archive.close()
			return "Cannot read the save for " + str(name).get_base_dir() + "."
		var error := archive.start_file(name)
		while error == OK and source.get_position() < source.get_length():
			var chunk := source.get_buffer(65536)
			if chunk.is_empty(): error = ERR_FILE_CANT_READ
			else: error = archive.write_file(chunk)
		if error == OK: error = archive.close_file()
		if error != OK:
			archive.close()
			return "Could not finish the save archive."
	return "Exported %d save(s)." % saves.size() if archive.close() == OK else "Could not finish the save archive."

static func show_export(parent: Node) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.use_native_dialog = true
	picker.filters = PackedStringArray(["*.zip ; All game saves"])
	picker.current_file = "fever-saves.zip"
	parent.add_child(picker)
	picker.file_selected.connect(func(path):
		var notice := AcceptDialog.new()
		notice.dialog_text = export_to(path)
		parent.add_child(notice)
		notice.confirmed.connect(notice.queue_free)
		notice.canceled.connect(notice.queue_free)
		notice.popup_centered(Vector2i(360, 160))
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)
