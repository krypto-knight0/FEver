extends RefCounted
## Optional, private Ogg/WAV/MP3 voice packs. No voice media ships in the app.
const ImportArchive = preload("res://runtime/import_archive.gd")
const ACTIONS := ["select", "attack", "crit", "damage", "defeat", "status"]
var root := "user://voices/"
var game_id := "fe7"
var entries: Array = []
var directory := ""
var enabled := true
var volume := 0.8
var cache: Dictionary = {}
var report = preload("res://runtime/import_report.gd").new()

func _init(game: String = "fe7") -> void:
	game_id = game
	if game_id == "fe6": root = "user://fe6/voices/"

func reload() -> void:
	entries.clear(); cache.clear(); directory = ""
	enabled = true; volume = 0.8
	var settings := ConfigFile.new()
	if settings.load(root + "active.cfg") != OK: return
	enabled = bool(settings.get_value("voices", "enabled", true))
	volume = clampf(float(settings.get_value("voices", "volume", 0.8)), 0, 1)
	var id := str(settings.get_value("voices", "pack", ""))
	if id.length() != 64 or not id.is_valid_hex_number(): return
	directory = root + id + "/"
	var data = JSON.parse_string(FileAccess.get_file_as_string(directory + "voices.json"))
	if data is Dictionary and data.get("game_id", "fe7") == game_id and data.get("voices") is Array: entries = data.voices

func delete_all() -> Error:
	# Only this store's private storage; source archives are never removed.
	var failure := _delete_directory(root)
	reload()
	return failure

func _delete_directory(path: String) -> Error:
	if not root.begins_with("user://") or root == "user://" or not root.ends_with("/") or not ImportArchive.safe_path(root.trim_prefix("user://").trim_suffix("/")) or not path.begins_with(root): return ERR_INVALID_PARAMETER
	var folder := DirAccess.open(path)
	if folder == null: return OK if not DirAccess.dir_exists_absolute(path) else ERR_CANT_OPEN
	for file in folder.get_files():
		var failure := DirAccess.remove_absolute(path.path_join(file))
		if failure != OK: return failure
	for child in folder.get_directories():
		var failure := _delete_directory(path.path_join(child))
		if failure != OK: return failure
	return DirAccess.remove_absolute(path)

func save_preferences() -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var settings := ConfigFile.new()
	settings.load(root + "active.cfg")
	settings.set_value("voices", "enabled", enabled)
	settings.set_value("voices", "volume", volume)
	settings.save(root + "active.cfg")

func clips(unit: Dictionary, action: String) -> Array:
	if unit.get("game_id", "fe7") != game_id: return []
	var fallback: Array = []
	for entry in entries:
		if entry.has("character_id"):
			if int(entry.character_id) != int(unit.get("rom_character_id", -1)): continue
		elif str(entry.get("character", "")).to_lower() not in [str(unit.get("name", "")).to_lower(), str(unit.get("id", "")).to_lower()]: continue
		var candidates: Array = entry.actions.get(action, [])
		if entry.has("class_id"):
			if int(entry.class_id) == int(unit.get("rom_class_id", -1)) and not candidates.is_empty(): return candidates
		else: fallback = candidates
	return fallback

func stream(path: String) -> AudioStream:
	if not cache.has(path):
		var audio := decode_clip(FileAccess.get_file_as_bytes(directory + path), path.get_extension())
		if audio == null: return null
		if cache.size() >= 16: cache.erase(cache.keys()[0])
		cache[path] = audio
	return cache[path]

static func decode_clip(bytes: PackedByteArray, extension: String) -> AudioStream:
	var audio: AudioStream
	match extension.to_lower():
		"ogg":
			if bytes.size() < 4 or bytes.slice(0,4).get_string_from_ascii() != "OggS": return null
			audio = AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			if bytes.size() < 12 or bytes.slice(0,4).get_string_from_ascii() != "RIFF" or bytes.slice(8,12).get_string_from_ascii() != "WAVE": return null
			audio = AudioStreamWAV.load_from_buffer(bytes)
		"mp3":
			if bytes.size() < 3 or (bytes.slice(0,3).get_string_from_ascii() != "ID3" and not (bytes[0] == 255 and (bytes[1] & 224) == 224)): return null
			audio = AudioStreamMP3.load_from_buffer(bytes)
	if audio is AudioStreamWAV: audio.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif audio != null: audio.loop = false
	return audio

func _safe(path: String) -> bool:
	return ImportArchive.safe_path(path)

func import_pack(path: String) -> String:
	report = preload("res://runtime/import_report.gd").new()
	var archive := ImportArchive.new()
	var failure := archive.open_archive(path, 512 * 1024 * 1024, 16385,
		8 * 1024 * 1024, 512 * 1024 * 1024, true)
	if not failure.is_empty(): return failure
	var result := _extract(archive, (path + str(Time.get_ticks_usec()) + Crypto.new().generate_random_bytes(16).hex_encode()).sha256_text())
	archive.close()
	return result

func _extract(archive: ImportArchive, id: String) -> String:
	var manifests: Array = archive.sizes.keys().filter(func(entry): return str(entry).get_file().to_lower() == "voices.json")
	if manifests.size() != 1: return "The ZIP needs exactly one voices.json, at its root or inside a folder."
	var manifest := str(manifests[0])
	var prefix := manifest.left(manifest.length() - manifest.get_file().length())
	var raw := archive.read_file(manifest, 2 * 1024 * 1024)
	if not archive.error.is_empty(): return archive.error
	var config = JSON.parse_string(raw.get_string_from_utf8())
	if not config is Dictionary or config.get("schema_version") != 1 or not config.get("voices") is Array: return "Invalid voice configuration."
	if config.get("game_id", "fe7") != game_id: return "This voice pack is for a different game. Load the matching game before importing it."
	if config.voices.is_empty() or config.voices.size() > 512: return "Use 1–512 voice sets."
	var destination := root + id + "/"
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return "Cannot create voice storage."
	var paths := {}
	var selectors := {}
	var normalized: Array = []
	for source in config.voices:
		var failure := _validate_set(source)
		if not failure.is_empty(): report.skip(failure); continue
		var label := str(source.get("character", source.get("character_id", "")))
		var selector := str(source.get("character_id", source.get("character", ""))).to_lower() + ":" + str(source.get("class_id", "default"))
		if selectors.has(selector): report.skip("Duplicate voice set: " + label); continue
		var entry: Dictionary = source.duplicate(true)
		entry.actions = {}
		for action in source.actions:
			if action not in ACTIONS or not source.actions[action] is Array or source.actions[action].size() > 128:
				report.skip("Invalid voice action: %s / %s" % [label, str(action)]); continue
			var action_clips: Array = []
			for clip in source.actions[action]:
				if not clip is String or not _safe(clip) or clip.get_extension().to_lower() not in ["ogg", "wav", "mp3"]:
					report.skip("Invalid clip: %s / %s / %s" % [label, action, str(clip)]); continue
				var resolved := archive.resolve_path(prefix + clip)
				if resolved.is_empty(): report.skip("Missing clip: %s / %s" % [label, clip]); continue
				if not paths.has(resolved):
					if paths.size() >= 8192: return "Use no more than 8192 voice clips."
					var bytes := archive.read_file(resolved, -1, true)
					if not archive.error.is_empty(): report.skip(archive.error); paths[resolved] = ""; continue
					var audio := decode_clip(bytes, resolved.get_extension())
					if audio == null or audio.get_length() <= 0 or audio.get_length() > 60:
						report.skip("Invalid or over-60-second clip: " + clip); paths[resolved] = ""; continue
					var local := resolved.substr(prefix.length())
					if DirAccess.make_dir_recursive_absolute((destination + local).get_base_dir()) != OK: return "Cannot create voice folder."
					var clip_output := FileAccess.open(destination + local, FileAccess.WRITE)
					if clip_output == null: return "Cannot write voice clip."
					clip_output.store_buffer(bytes); clip_output.flush()
					var clip_write_error := clip_output.get_error(); clip_output.close()
					if clip_write_error != OK: return "Cannot save voice clip."
					paths[resolved] = local
					report.accepted += 1
				if not str(paths[resolved]).is_empty() and not action_clips.has(paths[resolved]): action_clips.append(paths[resolved])
			if not action_clips.is_empty(): entry.actions[action] = action_clips
		if entry.actions.is_empty(): report.skip("No valid clips for " + label); continue
		selectors[selector] = true
		normalized.append(entry)
	if normalized.is_empty(): return report.no_valid("voice clips")
	config.voices = normalized
	var output := FileAccess.open(destination + "voices.json", FileAccess.WRITE)
	if output == null: return "Cannot save voice config."
	output.store_string(JSON.stringify(config)); output.flush()
	var write_error := output.get_error(); output.close()
	if write_error != OK: return "Cannot save voice config."
	var settings := ConfigFile.new()
	settings.load(root + "active.cfg")
	settings.set_value("voices", "pack", id)
	if settings.save(root + "active.pending") != OK: return "Cannot save voice selection."
	if DirAccess.rename_absolute(root + "active.pending", root + "active.cfg") != OK: return "Cannot activate voice pack."
	return ""

func _validate_set(entry: Variant) -> String:
	if not entry is Dictionary or not entry.get("actions") is Dictionary: return "Each voice set needs an actions object."
	if entry.has("character_id"):
		if not _integer(entry.character_id, 1, 255): return "Invalid voice character_id: " + str(entry.character_id)
	elif not entry.get("character") is String or entry.character.strip_edges().is_empty(): return "Each voice set needs a character or character_id."
	if entry.has("class_id") and not _integer(entry.class_id, 0, 255): return "Invalid voice class_id: " + str(entry.class_id)
	return ""

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high
