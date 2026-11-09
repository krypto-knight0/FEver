extends RefCounted
## Independent private portrait pack; custom PNGs never enter Art's registry.
const ImportArchive = preload("res://runtime/import_archive.gd")
var root: String
var config_name := "portraits.json"
var array_key := "portraits"
var maximum_dimension := 4096
var maximum_entries := 256
var maximum_config_bytes := 256 * 1024

const NO_VALID := "No valid artwork entries found."
var report = preload("res://runtime/import_report.gd").new()
var game_id := "fe7"

func _init(storage_root: String, backgrounds: bool = false, game: String = "fe7") -> void:
	root = storage_root
	game_id = game
	if game_id == "fe6": maximum_entries = 512
	if backgrounds:
		config_name = "backgrounds.json"
		array_key = "backgrounds"
		maximum_dimension = 4096
var entries: Array = []
var directory := ""
var loaded := false
var enabled := true
var textures: Dictionary = {}
var defaults: Dictionary = {}
var editable_defaults := false

func reload() -> void:
	entries.clear()
	textures.clear()
	defaults.clear()
	directory = ""
	editable_defaults = false
	loaded = true
	enabled = true
	var settings := ConfigFile.new()
	if settings.load(root + "active.cfg") != OK: return
	enabled = bool(settings.get_value("pack", "enabled", true))
	var pack := str(settings.get_value("pack", "id", ""))
	if pack.length() != 64 or not pack.is_valid_hex_number(): return
	directory = root + pack + "/"
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "portraits.json"))
	if value is Dictionary and value.get("portraits") is Array:
		entries = value.portraits
		if int(value.get("schema_version", 1)) >= 2 and value.get("defaults") is Dictionary:
			defaults = value.defaults
			editable_defaults = true

func disable() -> void:
	set_enabled(false)

func set_enabled(value: bool) -> void:
	var settings := ConfigFile.new()
	if settings.load(root + "active.cfg") != OK and array_key != "backgrounds": return
	if DirAccess.make_dir_recursive_absolute(root) != OK: return
	settings.set_value("pack", "enabled", value)
	if settings.save(root + "active.cfg") == OK: reload()

func delete_all() -> Error:
	# Only this store's private import directory is removed, never source ZIPs.
	var error := _delete_directory(root)
	reload()
	return error

func _delete_directory(path: String) -> Error:
	if not path.begins_with(root) or not root.begins_with("user://"): return ERR_INVALID_PARAMETER
	var folder := DirAccess.open(path)
	if folder == null: return OK
	for file in folder.get_files():
		var error := DirAccess.remove_absolute(path.path_join(file))
		if error != OK: return error
	for child in folder.get_directories():
		var error := _delete_directory(path.path_join(child))
		if error != OK: return error
	return DirAccess.remove_absolute(path)

func default_values() -> Dictionary:
	if not loaded: reload()
	var values := {"scale_percent": 100.0, "x_percent": 0.0, "y_percent": 0.0}
	values.merge(defaults, true)
	return values

func save_defaults(scale_percent: float, x_percent: float, y_percent: float, flip: Variant = null) -> String:
	if not loaded: reload()
	if not editable_defaults or directory.is_empty(): return "Reimport your portrait ZIP once to enable editable defaults."
	if not is_finite(scale_percent) or not is_finite(x_percent) or not is_finite(y_percent): return "Enter finite percentage values."
	var updated := defaults.duplicate(true)
	updated.scale_percent = clampf(scale_percent, 1, 400)
	updated.x_percent = clampf(x_percent, -100, 100)
	updated.y_percent = clampf(y_percent, -100, 100)
	if flip is bool: updated.flip_h = flip
	var temporary := directory + "portraits.pending"
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null: return "Cannot save portrait defaults."
	output.store_string(JSON.stringify({"schema_version": 2, "defaults": updated, "portraits": entries}, "\t"))
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK or DirAccess.rename_absolute(temporary, directory + "portraits.json") != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot update portrait defaults."
	defaults = updated
	return ""

func _safe_path(path: String) -> bool:
	return ImportArchive.safe_path(path)

func save_battle_height(index: int, percent: float, inherit: bool = false) -> String:
	if not loaded: reload()
	if array_key != "backgrounds" or directory.is_empty(): return "Load a backgrounds ZIP to adjust battle backgrounds."
	if not is_finite(percent): return "Enter a finite percentage."
	if index < -1 or index >= entries.size(): return "Select an imported battle background."
	if index >= 0 and not str(entries[index].get("character", "")).begins_with("battle_background_"): return "Select an imported battle background."
	var updated_defaults := defaults.duplicate(true)
	var updated_entries := entries.duplicate(true)
	if index == -1: updated_defaults.battle_y_percent = clampf(percent, -100, 100)
	elif inherit: updated_entries[index].erase("battle_y_percent")
	else: updated_entries[index].battle_y_percent = clampf(percent, -100, 100)
	var temporary := directory + "portraits.pending"
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null: return "Cannot save battle background position."
	output.store_string(JSON.stringify({"schema_version":2,"defaults":updated_defaults,"portraits":updated_entries}, "\t"))
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK or DirAccess.rename_absolute(temporary, directory + "portraits.json") != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot update battle background position."
	defaults = updated_defaults; entries = updated_entries; editable_defaults = true
	return ""

func save_entry(index: int, scale_percent: float, x_percent: float, y_percent: float, inherit: bool = false, flip: Variant = null) -> String:
	if not loaded: reload()
	if not editable_defaults or index < 0 or index >= entries.size(): return "Select an imported portrait."
	if not is_finite(scale_percent) or not is_finite(x_percent) or not is_finite(y_percent): return "Enter finite percentage values."
	var updated := entries.duplicate(true)
	if inherit:
		for field in ["scale_percent", "x_percent", "y_percent", "flip_h"]: updated[index].erase(field)
	else:
		updated[index].scale_percent = clampf(scale_percent, 1, 400)
		updated[index].x_percent = clampf(x_percent, -100, 100)
		updated[index].y_percent = clampf(y_percent, -100, 100)
		if flip is bool: updated[index].flip_h = flip
	var output := FileAccess.open(directory + "portraits.pending", FileAccess.WRITE)
	if output == null: return "Cannot save portrait entry."
	output.store_string(JSON.stringify({"schema_version":2,"defaults":defaults,"portraits":updated}, "\t"))
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK or DirAccess.rename_absolute(directory + "portraits.pending", directory + "portraits.json") != OK: return "Cannot update portrait entry."
	entries = updated
	return ""

func import_pack(path: String, refresh: bool = true, image_field: String = "image", activate: bool = true, pack_id: String = "") -> String:
	report = preload("res://runtime/import_report.gd").new()
	var archive := ImportArchive.new()
	var failure := archive.open_archive(path, 1024 * 1024 * 1024, 8192,
		16 * 1024 * 1024, 2 * 1024 * 1024 * 1024, true)
	if not failure.is_empty(): return failure
	var result := _extract(archive, path, refresh, image_field, activate, pack_id)
	archive.close()
	return result

func _extract(archive: ImportArchive, path: String, refresh: bool, image_field: String,
		activate: bool, pack_id: String) -> String:
	var sizes: Dictionary = archive.sizes
	var candidates: Array = sizes.keys().filter(func(name): return str(name).get_file().to_lower() == config_name)
	if candidates.size() != 1: return "Add one " + config_name + " at the ZIP root or inside its artwork folder."
	var config_path := str(candidates[0])
	@warning_ignore("integer_division") # Intentional integer truncation.
	if int(sizes[config_path]) > maximum_config_bytes: return "%s must be no larger than %d KiB." % [config_name, maximum_config_bytes / 1024]
	var archive_prefix := config_path.left(config_path.length() - config_path.get_file().length())
	var config_bytes := archive.read_file(config_path, maximum_config_bytes)
	if not archive.error.is_empty(): return archive.error
	var config: Variant = JSON.parse_string(config_bytes.get_string_from_utf8())
	if not config is Dictionary or not config.get(array_key) is Array or not config.get("defaults", {}) is Dictionary: return "Expected an object with defaults and a " + array_key + " array."
	if str(config.get("game_id", "fe7")) != game_id:
		return "This artwork pack is for %s. Load its matching ROM before importing it." % str(config.get("game_id", "fe7")).to_upper()
	if config[array_key].is_empty() or config[array_key].size() > maximum_entries: return "Add between 1 and %d artwork entries." % maximum_entries
	var defaults_field := "card_defaults" if image_field == "card" else "defaults"
	if not config.get(defaults_field, {}) is Dictionary: return defaults_field + " must be an object."
	var pack_defaults: Dictionary = config.get(defaults_field, {}).duplicate(true)
	for field in ["scale_percent", "x_percent", "y_percent", "battle_y_percent"]:
		if pack_defaults.has(field):
			if not (pack_defaults[field] is float or pack_defaults[field] is int) or not is_finite(float(pack_defaults[field])): return field + " default must be a finite number."
			pack_defaults[field] = clampf(float(pack_defaults[field]), 1 if field == "scale_percent" else -100, 400 if field == "scale_percent" else 100)
	if pack_defaults.has("flip_h") and not pack_defaults.flip_h is bool: return "flip_h default must be true or false."
	var id := (path + str(Time.get_ticks_usec()) + Crypto.new().generate_random_bytes(16).hex_encode()).sha256_text() if pack_id.is_empty() else pack_id
	var destination := root + id + "/"
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return "Cannot create portrait storage."
	var normalized: Array = []
	var identifiers: Dictionary = {}
	for source in config[array_key]:
		if source is Dictionary and not source.has(image_field) and not activate:
			if not source.has("image") and not source.has("card"): report.skip("Artwork entry has neither image nor card.")
			continue
		var proposed := identifiers.duplicate()
		var result := _prepare_entry(source, proposed, pack_defaults, image_field, archive_prefix, archive)
		if result.has("error"):
			report.skip("Entry %d: %s" % [config[array_key].find(source) + 1, result.error]); continue
		var value: Dictionary = result.value
		var local := str(normalized.size()) + ".png"
		var image_output := FileAccess.open(destination + local, FileAccess.WRITE)
		if image_output == null: return "Cannot save portrait images."
		image_output.store_buffer(result.png); image_output.flush()
		var image_write_error := image_output.get_error(); image_output.close()
		if image_write_error != OK: return "Cannot save portrait images."
		value.image = local
		normalized.append(value)
		identifiers = proposed
		report.accepted += 1
	if normalized.is_empty() and activate: return NO_VALID + " " + report.no_valid("artwork")
	var output := FileAccess.open(destination + "portraits.json", FileAccess.WRITE)
	if output == null: return "Cannot save portrait configuration."
	output.store_string(JSON.stringify({"schema_version": 2, "defaults": pack_defaults, "portraits": normalized}, "\t"))
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK: return "Cannot save portrait configuration."
	if activate:
		var failure := activate_pack(id)
		if not failure.is_empty(): return failure
		if refresh: reload()
	return ""

func _prepare_entry(source: Variant, identifiers: Dictionary, pack_defaults: Dictionary,
		image_field: String, archive_prefix: String, archive: ImportArchive) -> Dictionary:
	if not source is Dictionary: return {"error":"Each artwork entry must be an object."}
	var entry: Dictionary = source.duplicate(true)
	var entry_error := validate_entry(entry, identifiers)
	if not entry_error.is_empty(): return {"error": entry_error}
	if array_key == "backgrounds":
		var key := str(entry.get("id", ""))
		if key != "title_" + game_id and not key.begins_with("background_") and not key.begins_with("cg_") and not key.begins_with("battle_background_") and not key.begins_with("battle_platform_"): return {"error": "Use title_%s, background_NNN, cg_NNN, battle_background_NAME or battle_platform_NAME as the id." % game_id}
		if identifiers.has(key): return {"error": "Duplicate background id: " + key}
		identifiers[key] = true
		entry.character = key
	if image_field == "card":
		entry.image = entry.get("card", "")
		# Card transforms are independent: dialogue scale/offsets would not
		# make sense inside a small card frame.
		for field in ["scale_percent", "x_percent", "y_percent", "flip_h"]:
			entry.erase(field)
			if source.has("card_" + field): entry[field] = source["card_" + field]
	entry.erase("card")
	for field in ["scale_percent", "x_percent", "y_percent", "flip_h"]: entry.erase("card_" + field)
	var value: Dictionary = pack_defaults.duplicate(true)
	value.merge(entry, true)
	if str(value.get("character", "")).is_empty() and not value.has("character_id"): return {"error": "Each portrait needs character or character_id."}
	if not value.get("image", "") is String: return {"error": image_field + " must be a PNG path."}
	var image_path := str(value.get("image", ""))
	var archive_path := archive.resolve_path(archive_prefix + image_path)
	if not _safe_path(image_path) or image_path.get_extension().to_lower() != "png" or archive_path.is_empty(): return {"error": "Missing or invalid PNG path: " + image_path}
	for field in ["scale_percent", "x_percent", "y_percent", "battle_y_percent"]:
		if value.has(field) and (not (value[field] is float or value[field] is int) or not is_finite(float(value[field]))): return {"error": field + " must be a finite number."}
	if value.has("flip_h") and not value.flip_h is bool: return {"error": "flip_h must be true or false."}
	value.scale_percent = clampf(float(value.get("scale_percent", 100)), 1, 400)
	value.x_percent = clampf(float(value.get("x_percent", 0)), -100, 100)
	value.y_percent = clampf(float(value.get("y_percent", 0)), -100, 100)
	if value.has("battle_y_percent"): value.battle_y_percent = clampf(float(value.battle_y_percent), -100, 100)
	var png := archive.read_file(archive_path, -1, true)
	if not archive.error.is_empty(): return {"error": archive.error}
	if png.size() != int(archive.sizes[archive_path]) or png.size() < 24 or png.slice(0, 8).hex_encode() != "89504e470d0a1a0a": return {"error": "Invalid PNG: " + image_path}
	var width := _big_endian(png, 16)
	var height := _big_endian(png, 20)
	if width < 1 or height < 1 or width > maximum_dimension or height > maximum_dimension: return {"error": "PNG dimensions must be at most %d × %d." % [maximum_dimension, maximum_dimension]}
	var dimension_error := validate_dimensions(entry, width, height)
	if not dimension_error.is_empty(): return {"error": dimension_error}
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK: return {"error": "Cannot decode PNG: " + image_path}
	value.source_image = image_path
	for field in ["scale_percent", "x_percent", "y_percent", "flip_h", "battle_y_percent"]:
		if not entry.has(field): value.erase(field)
	return {"value":value, "png":png}

func validate_entry(entry: Dictionary, _identifiers: Dictionary) -> String:
	for field in ["character_id", "portrait_id", "class_id"]:
		if entry.has(field):
			var value: Variant = entry[field]
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or value < 0 or value > 65535: return "Invalid artwork " + field
	for field in ["character", "class"]:
		if entry.has(field) and not entry[field] is String: return "Invalid artwork " + field
	return ""

func validate_dimensions(_entry: Dictionary, _width: int, _height: int) -> String:
	return ""

func activate_pack(id: String) -> String:
	var settings := ConfigFile.new()
	settings.set_value("pack", "id", id)
	if settings.save(root + "active.pending") != OK: return "Cannot save portrait selection."
	if DirAccess.rename_absolute(root + "active.pending", root + "active.cfg") != OK: return "Cannot activate portrait pack."
	return ""

func _big_endian(bytes: PackedByteArray, at: int) -> int:
	return (int(bytes[at]) << 24) | (int(bytes[at + 1]) << 16) | (int(bytes[at + 2]) << 8) | int(bytes[at + 3])

func find_portrait(character: String, context: Dictionary = {}) -> Dictionary:
	if context.get("game_id", game_id) != game_id: return {}
	if game_id == "fe7" and int(context.get("portrait_id", -1)) == 160: character = "fe6_unit_3"
	if not loaded: reload()
	if not enabled: return {}
	var best: Dictionary = {}
	var score := -1
	for entry in entries:
		if entry.has("portrait_id"):
			if int(entry.portrait_id) != int(context.get("portrait_id", -1)): continue
		elif entry.has("character_id"):
			if int(entry.character_id) != int(context.get("rom_character_id", -1)): continue
		elif str(entry.get("character", "")).to_lower() != character.to_lower(): continue
		var specific: bool = entry.has("class_id") or entry.has("class")
		if entry.has("class_id") and int(entry.class_id) != int(context.get("rom_class_id", -1)): continue
		if entry.has("class") and str(entry["class"]).to_lower() != str(context.get("class_name", "")).to_lower(): continue
		var priority := int(specific) + (4 if entry.has("portrait_id") else 2 if entry.has("character_id") else 0)
		if priority > score: best = entry; score = priority
	if best.is_empty(): return {}
	var resolved := default_values()
	resolved.merge(best, true)
	return resolved

func texture(entry: Dictionary) -> Texture2D:
	var path := directory + str(entry.get("image", ""))
	if not textures.has(path):
		var image := Image.load_from_file(path)
		if image == null: return null
		while textures.size() >= 4: textures.erase(textures.keys()[0])
		textures[path] = ImageTexture.create_from_image(image)
	return textures[path]
