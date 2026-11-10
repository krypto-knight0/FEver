extends RefCounted
## Presentation-only, literal word/phrase replacements. Never rewrite game data.
const PATH := "user://translations.json"
const MAX_BYTES := 1024 * 1024
static var loaded := false
static var config := {"schema_version":1, "enabled":true, "replacements":[]}
static var matcher: RegEx
static var ordered: Array = []
static var cache: Dictionary = {}
static var report = preload("res://runtime/import_report.gd").new()

static func ensure_loaded() -> void:
	if loaded: return
	loaded = true
	if FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file and file.get_length() <= MAX_BYTES:
			var value = JSON.parse_string(file.get_as_text())
			if validate(value).is_empty(): activate(value)

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("schema_version") != 1 or not value.get("replacements") is Array: return "Use schema_version 1 and a replacements array."
	if value.has("enabled") and not value.enabled is bool: return "enabled must be true or false."
	if value.replacements.size() > 512: return "Use no more than 512 replacements."
	var seen := {}
	for entry in value.replacements:
		if not entry is Dictionary or not entry.get("from") is String or not entry.get("to") is String: return "Each replacement needs from and to text."
		if entry.from.strip_edges().is_empty() or entry.from.length() > 256 or entry.to.length() > 2048: return "Original text must contain 1–256 characters; replacement text can contain up to 2,048."
		for option in ["case_sensitive", "whole_word"]:
			if entry.has(option) and not entry[option] is bool: return option + " must be true or false."
		var key: String = entry.from if entry.get("case_sensitive", false) else entry.from.to_lower()
		if seen.has(key): return "Duplicate original text: " + str(entry.from)
		seen[key] = true
	return ""

static func _literal(value: String) -> String:
	var result := ""
	for character in value:
		if character in "\\.^$|()[]{}*+?": result += "\\"
		result += character
	return result

static func _compile(value: Dictionary) -> Dictionary:
	var rows: Array = value.replacements.duplicate(true)
	# Match longest phrases first, once against the original string. Replacements
	# never feed back into another rule, even with swaps such as A->B and B->A.
	rows.sort_custom(func(a,b): return a.from.length() > b.from.length())
	var parts: Array[String] = ["(\\[[^\\]\\n]*\\])"] # Preserve BBCode formatting tags.
	for entry in rows:
		var pattern := _literal(entry.from)
		if not entry.get("case_sensitive", false): pattern = "(?i:" + pattern + ")"
		if entry.get("whole_word", true): pattern = "(?<![\\p{L}\\p{N}_])" + pattern + "(?![\\p{L}\\p{N}_])"
		parts.append("(" + pattern + ")")
	var regex := RegEx.new()
	if regex.compile("|".join(parts)) != OK: return {}
	return {"matcher":regex,"rows":rows}

static func activate(value: Dictionary) -> String:
	var compiled := _compile(value)
	if compiled.is_empty(): return "These replacements are too complex. Shorten the original phrases or use fewer entries."
	config = value.duplicate(true)
	config.schema_version = 1
	config.enabled = value.get("enabled", true)
	matcher = compiled.matcher; ordered = compiled.rows
	cache.clear(); loaded = true
	return ""

static func save(value: Dictionary) -> String:
	var failure := validate(value)
	if not failure.is_empty(): return failure
	if _compile(value).is_empty(): return "These replacements are too complex. Shorten the original phrases or use fewer entries."
	var file := FileAccess.open(PATH + ".pending", FileAccess.WRITE)
	if file == null: return "Cannot save translations."
	file.store_string(JSON.stringify(value,"\t")); file.flush()
	var error := file.get_error(); file.close()
	if error != OK or DirAccess.rename_absolute(PATH + ".pending", PATH) != OK: return "Cannot save translations."
	return activate(value)

static func import_file(path: String) -> String:
	report = preload("res://runtime/import_report.gd").new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return "Choose a JSON translation config up to 1 MiB."
	var value = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or not value.get("replacements") is Array: return "Use schema_version 1 and a replacements array."
	var clean: Dictionary = value.duplicate(true)
	clean.replacements = []
	var failure := validate(clean)
	if not failure.is_empty(): return failure
	if value.replacements.size() > 512: return "Use no more than 512 replacements."
	for entry in value.replacements:
		clean.replacements.append(entry)
		failure = validate(clean)
		if not failure.is_empty(): clean.replacements.pop_back(); report.skip(failure)
	if clean.replacements.is_empty() and not value.replacements.is_empty(): return report.no_valid("replacements")
	report.accepted = clean.replacements.size()
	return save(clean)

static func apply(text: String) -> String:
	ensure_loaded()
	if not config.enabled or matcher == null or ordered.is_empty() or text.is_empty(): return text
	if cache.has(text): return cache[text]
	var result := ""
	var cursor := 0
	for found in matcher.search_all(text):
		result += text.substr(cursor, found.get_start() - cursor)
		var replacement: String = found.get_string()
		if found.get_start(1) < 0:
			for index in range(ordered.size()):
				if found.get_start(index + 2) >= 0:
					replacement = ordered[index].to
					break
		result += replacement
		cursor = found.get_end()
	result += text.substr(cursor)
	if cache.size() >= 1024: cache.clear()
	cache[text] = result
	return result

static func matches_search(text: String, query: String) -> bool:
	var needle := query.strip_edges().to_lower()
	return needle.is_empty() or text.to_lower().contains(needle) or apply(text).to_lower().contains(needle)
