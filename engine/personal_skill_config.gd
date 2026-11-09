extends RefCounted
## Data only: imports select known effects; they never load scripts or resources.
const DEFAULT_PATH := "res://config/personal_skills.json"
const USER_PATH := "user://personal_skills.json"
static var defaults: Dictionary = {}
static var overrides: Dictionary = {}
static var loaded := false
static var resolved: Dictionary = {}
static var report = preload("res://runtime/import_report.gd").new()

static func ensure_loaded() -> void:
	if loaded: return
	loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	if data is Dictionary: defaults = data.get("characters", {})
	if FileAccess.file_exists(USER_PATH):
		var custom = JSON.parse_string(FileAccess.get_file_as_string(USER_PATH))
		if validate(custom).is_empty(): overrides = custom.characters.duplicate(true)

static func definition(id: String) -> Dictionary:
	ensure_loaded()
	if resolved.has(id): return resolved[id]
	var result: Dictionary = defaults.get(id, {}).duplicate(true)
	result.merge(overrides.get(id, {}), true)
	# Changing only effect_id inherits that effect's tuning, not the old effect's.
	var effect := str(result.get("effect_id", id))
	for field in ["parameters", "stats"]:
		if not result.has(field): continue
		var tuning: Dictionary = defaults.get(effect, {}).get(field, {}).duplicate(true)
		if defaults.get(id, {}).get("effect_id", id) == effect:
			tuning.merge(defaults.get(id, {}).get(field, {}), true)
		tuning.merge(overrides.get(id, {}).get(field, {}), true)
		result[field] = tuning
	# Internal cartridge references are not part of editable/exported tuning.
	result.erase("rom_character_id")
	result.erase("description_names")
	resolved[id] = result
	return result

static func validate(data: Variant) -> String:
	ensure_loaded()
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("characters") is Dictionary:
		return "Expected schema_version 1 and a characters object."
	for source_id in data.characters:
		var id := str(source_id)
		var entry = data.characters[source_id]
		if not defaults.has(id) or not entry is Dictionary: return "Unknown character or invalid entry: " + str(id)
		for key in entry:
			if key not in ["name", "description", "effect_id", "parameters", "stats"]: return "Unknown field: " + str(key)
		for key in ["name", "description", "effect_id"]:
			if entry.has(key) and (not entry[key] is String or entry[key].length() > (2000 if key == "description" else 100)): return "Invalid " + key + " for " + str(id)
		var effect := str(entry.get("effect_id", defaults[id].get("effect_id", id)))
		if not defaults.has(effect) and effect not in ["stat_bonus", "combat_bonus", "none"]: return "Unknown effect_id: " + effect
		for field in ["parameters", "stats"]:
			if not entry.get(field, {}) is Dictionary: return field + " must be an object."
			for key in entry.get(field, {}):
				var value = entry[field][key]
				var permitted: bool = key in ["str", "magic", "skill", "speed", "luck", "def", "res", "con", "mov", "hit", "avoid", "crit", "atk"] if field == "stats" else defaults.get(effect, {}).get("parameters", {}).has(key)
				if not permitted: return "Unknown " + field + " entry: " + str(key)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value) or absf(float(value)) > 100: return "Stats and parameters must be whole numbers between -100 and 100."
				if field == "parameters" and value < 0: return "Parameters cannot be negative."
	return ""

static func display_name(id: String, fallback: String = "Character") -> String:
	ensure_loaded()
	# User-authored overrides remain authoritative. Default names are never
	# cached in the skill configuration or inferred by capitalizing engine IDs.
	if overrides.get(id,{}).has("name"): return str(overrides[id].name)
	var character := int(defaults.get(id,{}).get("rom_character_id",0))
	var assets = load("res://runtime/rom_assets.gd")
	var game := "fe6" if id.begins_with("fe6_unit_") else "fe7"
	if character > 0 and assets.initialized() and assets.game_id == game:
		return preload("res://runtime/rom_names.gd").character(assets.decoder,game,character)
	return fallback

static func description(id: String) -> String:
	var text := str(definition(id).get("description",""))
	if overrides.get(id,{}).has("description"): return text
	var names := {}
	var assets = load("res://runtime/rom_assets.gd")
	if assets.dynamic_content != null and str(definition(id).get("effect_id",id)) in ["fe6_unit_1","fe6_unit_38"]:
		text = text.replace("female support partners","support partners").replace("male support partners","support partners")
	var game := "fe6" if id.begins_with("fe6_unit_") else "fe7"
	for key in defaults.get(id,{}).get("description_names",{}):
		var character := int(defaults[id].description_names[key])
		names[key] = preload("res://runtime/rom_names.gd").character(assets.decoder,game,character) if assets.initialized() and assets.game_id == game else "the paired ally"
	return text.format(names)

static func import_file(path: String) -> String:
	report = preload("res://runtime/import_report.gd").new()
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > 262144: return "Could not read config (maximum 256 KB)."
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("characters") is Dictionary: return "Expected schema_version 1 and a characters object."
	var accepted := {}
	for id in data.characters:
		var error := validate({"schema_version":1,"characters":{id:data.characters[id]}})
		if not error.is_empty(): report.skip(str(id) + ": " + error); continue
		accepted[id] = data.characters[id]
	if accepted.is_empty() and not data.characters.is_empty(): return report.no_valid("personal skills")
	data.characters = accepted
	report.accepted = accepted.size()
	var output := FileAccess.open(USER_PATH + ".tmp", FileAccess.WRITE)
	if not output: return "Could not save the config."
	output.store_string(JSON.stringify(data, "\t"))
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK or DirAccess.rename_absolute(USER_PATH + ".tmp", USER_PATH) != OK: return "Could not save the config."
	overrides = data.characters.duplicate(true)
	resolved.clear()
	return ""

static func reset() -> void:
	overrides.clear()
	resolved.clear()
	if FileAccess.file_exists(USER_PATH): DirAccess.remove_absolute(USER_PATH)
