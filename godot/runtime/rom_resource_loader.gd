extends ResourceFormatLoader

func _get_recognized_extensions() -> PackedStringArray: return PackedStringArray(["png","wav"])
func _handles_type(type: StringName) -> bool: return type in [&"Texture2D",&"ImageTexture",&"AudioStream",&"AudioStreamWAV",&"Resource"]
func _get_resource_type(path: String) -> String:
	if not _exists(path): return ""
	return "AudioStreamWAV" if path.ends_with(".wav") else "ImageTexture"
func _exists(path: String) -> bool: return preload("res://runtime/rom_assets.gd").assets.has(path)
func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	var result: Resource = preload("res://runtime/rom_assets.gd").resource(path)
	if result: return result
	return ERR_FILE_NOT_FOUND
