extends RefCounted
const FORMAT := "fever-save"
const SCHEMA_VERSION := 3
## Disk format only. The engine continues to use complete, validated snapshots.
## Chapter/unit deltas refer to installed content; shared values are lossless
## fallbacks for custom fields and definitions absent from the current chapter.
const Difficulty = preload("res://engine/campaign_difficulty.gd")
const Personal = preload("res://engine/rogue_personals.gd")
const Config = preload("res://engine/personal_skill_config.gd")
const UNIT_STATIC = ["name", "class_name", "portrait", "sprite", "movement_sprite", "source_deployment", "source_stat_offsets", "weapon_rank_source", "ai_provenance", "terrain_bonuses", "movement_costs", "movement_costs_rain"]
var game_id := "fe7"
var rom_digest := ""
var paths: Dictionary = {}
var chapters: Dictionary = {}
var unit_bases: Dictionary = {}
var items: Dictionary = {}
var item_definition_keys: Dictionary = {}
var shared: Array = []
var shared_index: Dictionary = {}
var expanded: Dictionary = {}
var expanded_sizes: Dictionary = {}
var references: Dictionary = {}
var imported_tables: Array = []
var imported_maps: Array = []
var expanded_bytes := 0
var error := ""
var nodes := 0

func configure(pack: Dictionary) -> void:
	game_id = str(pack.get("id", "fe7"))
	rom_digest = str(pack.get("rom_sha256",""))
	paths.clear()
	chapters.clear()
	unit_bases.clear()
	items.clear()
	item_definition_keys.clear()
	Config.ensure_loaded()
	for entry in pack.get("chapters", []): paths[str(entry.id)] = str(entry.path)
	var manifest_path := str(pack.get("item_manifest", "res://content/fe7/item_manifest.json"))
	if FileAccess.file_exists(manifest_path):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest is Dictionary:
			var normalizer = preload("res://engine/battle_state.gd").new()
			for item in manifest.get("items", []):
				if item is Dictionary and item.has("rom_item_id"):
					var definition: Dictionary = normalizer._normalize_item(item)
					items[str(int(item.rom_item_id))] = definition
					for key in definition: item_definition_keys[key] = true

func _chapter(id: String, difficulty: String) -> Dictionary:
	var key := id + ":" + difficulty
	if chapters.has(key): return chapters[key]
	if paths.has(id) and not preload("res://runtime/rom_assets.gd").ensure_resource(paths[id]):
		error = "Cannot prepare the chapter referenced by this save."
		return {}
	if not paths.has(id) or not FileAccess.file_exists(paths[id]):
		error = "Save references an unavailable chapter: " + id
		return {}
	var source = JSON.parse_string(FileAccess.get_file_as_string(paths[id]))
	if not source is Dictionary:
		error = "Cannot read chapter definition: " + id
		return {}
	var result := Difficulty.chapter(source, difficulty)
	_refresh(result)
	# A long campaign must not retain every complete chapter in memory.
	if chapters.size() >= 4:
		var oldest: String = chapters.keys()[0]
		chapters.erase(oldest)
		unit_bases.erase(oldest)
	chapters[key] = result
	var units := {}
	_collect_units(result, units)
	unit_bases[key] = units
	return result

func _collect_units(value: Variant, result: Dictionary) -> void:
	if value is Array:
		for child in value: _collect_units(child, result)
	elif value is Dictionary:
		if value.has("id") and value.has("faction") and value.has("max_hp"):
			# Ambiguous IDs must use a literal fallback, never the wrong spawn.
			var id := str(value.id)
			if not result.has(id): result[id] = value
			elif result[id] != value: result[id] = {}
		for key in value:
			if key != "difficulty_variants": _collect_units(value[key], result)

static func is_compact(document: Dictionary) -> bool:
	return document.get("format", "") == FORMAT

func encode(snapshot: Dictionary) -> Dictionary:
	error = ""
	if not preload("res://runtime/game_identity.gd").accepts(snapshot,game_id,rom_digest):
		error = "Cannot save progress from a different game."
		return {}
	shared = []
	shared_index.clear()
	imported_tables.clear()
	imported_maps.clear()
	var body: Variant = _encode(snapshot, "", "normal")
	imported_tables.clear()
	imported_maps.clear()
	if not error.is_empty(): return {}
	return {"format":FORMAT, "schema_version":SCHEMA_VERSION, "pack_id":game_id, "rom_sha256":rom_digest, "data":body, "shared":shared}

func decode(document: Dictionary, undo_limit: int = -1, defer_undo: bool = false) -> Dictionary:
	error = ""
	if not preload("res://runtime/game_identity.gd").accepts(document, game_id, rom_digest):
		error = "This save belongs to a different game; current progress was preserved."
		return {}
	if not is_compact(document) or document.get("schema_version") != SCHEMA_VERSION or not document.get("shared") is Array:
		error = "Unsupported save format."
		return {}
	shared = document.shared
	if shared.size() > 200000:
		error = "Save contains too many shared records."
		return {}
	expanded.clear()
	expanded_sizes.clear()
	expanded_bytes = 0
	nodes = 0
	var body: Variant = document.get("data")
	var deferred_history: Array = []
	if undo_limit >= 0 or defer_undo:
		body = _unshared(body)
		if body is Dictionary and body.has("undo_history"):
			body = body.duplicate()
			var history: Variant = _unshared(body.undo_history)
			if history is Array:
				if undo_limit >= 0: history = history.slice(-undo_limit) if undo_limit > 0 else []
				body.undo_history = [] if defer_undo else history
				if defer_undo:
					for raw in history:
						var entry: Variant = _unshared(raw)
						if not entry is Dictionary or not entry.get("snapshot") is Dictionary: continue
						deferred_history.append({"action":entry.get("action", ""), "label":entry.get("label", "Previous action"), "snapshot":{"format":FORMAT, "schema_version":SCHEMA_VERSION, "pack_id":game_id, "rom_sha256":rom_digest, "chapter_id":body.get("chapter_id", ""), "data":entry.snapshot, "shared":shared}})
	references.clear()
	_count_references(body, {})
	var result: Variant = _decode(body, 0)
	# Never retain a second expanded save between Continue and the next save.
	expanded.clear()
	expanded_sizes.clear()
	references.clear()
	shared = []
	if not error.is_empty() or not result is Dictionary:
		if error.is_empty(): error = "Invalid save data."
		return {}
	if not preload("res://runtime/game_identity.gd").accepts(result,game_id,rom_digest):
		error = "Save content belongs to a different game."
		return {}
	_refresh(result)
	if defer_undo: result.undo_history = deferred_history
	return result

func _unshared(value: Variant) -> Variant:
	var seen := {}
	while value is Dictionary and value.has("$shared"):
		var raw: Variant = value["$shared"]
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floor(float(raw)) or int(raw) < 0 or int(raw) >= shared.size() or seen.has(int(raw)):
			error = "Invalid shared save reference."
			return null
		seen[int(raw)] = true
		value = shared[int(raw)]
	return value

func _count_references(value: Variant, visited: Dictionary, depth: int = 0) -> void:
	if depth > 128: return # The decoder reports excessive nesting.
	if value is Array:
		for child in value: _count_references(child, visited, depth + 1)
	elif value is Dictionary:
		if value.has("$shared"):
			var raw: Variant = value["$shared"]
			if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floor(float(raw)) or int(raw) < 0 or int(raw) >= shared.size(): return
			var index := int(raw)
			references[index] = int(references.get(index, 0)) + 1
			if not visited.has(index):
				visited[index] = true
				_count_references(shared[index], visited, depth + 1)
		elif value.has("$literal") and value["$literal"] is Dictionary:
			for key in value["$literal"]: _count_references(value["$literal"][key], visited, depth + 1)
		else:
			for key in value: _count_references(value[key], visited, depth + 1)

func _encode(value: Variant, chapter_id: String, difficulty: String) -> Variant:
	if value is Array:
		var list: Array = []
		for child in value: list.append(_encode(child, chapter_id, difficulty))
		return _intern(list)
	if not value is Dictionary: return value
	if is_compact(value) and value.get("schema_version") == SCHEMA_VERSION:
		# Loaded undo checkpoints stay compact in RAM. Rebase their references
		# into the output table instead of expanding a chapter to save it again.
		if not value.get("shared") is Array or str(value.get("pack_id", "fe7")) != game_id:
			error = "Invalid compact checkpoint."; return {}
		var index := -1
		for i in range(imported_tables.size()):
			if is_same(imported_tables[i], value.shared): index = i; break
		if index < 0:
			index = imported_tables.size()
			imported_tables.append(value.shared)
			imported_maps.append({})
		return _import_encoded(value.get("data"), value.shared, imported_maps[index], 0)
	if value.has("chapter_id"):
		chapter_id = str(value.chapter_id)
		if value.get("state") is Dictionary: difficulty = str(value.state.get("chapter", {}).get("difficulty", "normal"))
	var result: Dictionary = {}
	if value.has("rom_item_id") and value.has("uses") and items.has(str(int(value.rom_item_id))):
		var changes := {}
		for key in value:
			# Capacity is mutable (durability modes). Unknown modifiers survive.
			if key in ["uses", "max_uses"] or not item_definition_keys.has(key): changes[key] = _encode(value[key], chapter_id, difficulty)
		result = {"$item":int(value.rom_item_id), "values":changes}
	elif value.has("id") and value.has("events") and value.has("units") and paths.has(str(value.id)):
		var id := str(value.id)
		var mode := str(value.get("difficulty", difficulty))
		result = {"$chapter":id, "difficulty":mode, "patch":_diff(value, _chapter(id, mode), id, mode)}
	elif value.has("id") and value.has("faction") and value.has("max_hp") and paths.has(chapter_id):
		_chapter(chapter_id, difficulty)
		var base: Dictionary = unit_bases.get(chapter_id + ":" + difficulty, {}).get(str(value.id), {})
		if not base.is_empty():
			result = {"$unit":str(value.id), "chapter":chapter_id, "difficulty":difficulty, "patch":_diff(value, base, chapter_id, difficulty, true)}
		else: result = _fields(value, chapter_id, difficulty)
	else: result = _fields(value, chapter_id, difficulty)
	return _intern(result)

func _import_encoded(value: Variant, table: Array, remapped: Dictionary, depth: int) -> Variant:
	if not error.is_empty(): return null
	if depth > 128: error = "Checkpoint exceeds reconstruction limits."; return null
	if value is Array:
		var encoded_array: Array = []
		for child in value: encoded_array.append(_import_encoded(child, table, remapped, depth + 1))
		return _intern(encoded_array)
	if not value is Dictionary: return value
	if value.has("$shared"):
		var raw: Variant = value["$shared"]
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floor(float(raw)) or int(raw) < 0 or int(raw) >= table.size():
			error = "Invalid checkpoint reference."; return null
		var index := int(raw)
		if remapped.has(index):
			if remapped[index] == null: error = "Circular checkpoint reference."
			return remapped[index]
		remapped[index] = null
		remapped[index] = _import_encoded(table[index], table, remapped, depth + 1)
		return remapped[index]
	var result := {}
	for key in value:
		# Structural maps (patch.set, item.values, $literal) are not encoded
		# records themselves: preserve them while rebasing their leaf values.
		if key == "$literal" or (key == "values" and value.has("$item")) or (key == "patch" and (value.has("$chapter") or value.has("$unit"))):
			if not value[key] is Dictionary: error = "Invalid checkpoint record."; return null
			var fields := {}
			for field in value[key]:
				if key == "patch" and field == "set":
					var changes := {}
					for name in value[key][field]: changes[name] = _import_encoded(value[key][field][name], table, remapped, depth + 1)
					fields[field] = changes
				elif key == "patch" and field == "remove": fields[field] = value[key][field]
				else: fields[field] = _import_encoded(value[key][field], table, remapped, depth + 1)
			result[key] = fields
		else: result[key] = _import_encoded(value[key], table, remapped, depth + 1)
	return _intern(result)

func _fields(value: Dictionary, chapter_id: String, difficulty: String) -> Dictionary:
	var result := {}
	for key in value:
		if key == "rogue_personal" and value[key] is Dictionary and Config.defaults.has(str(value[key].get("id", ""))):
			var personal: Dictionary = value[key].duplicate(true)
			personal.erase("name")
			personal.erase("description")
			result[key] = _encode(personal, chapter_id, difficulty)
		else: result[key] = _encode(value[key], chapter_id, difficulty)
	if value.keys().any(func(key): return str(key).begins_with("$")): return {"$literal":result}
	return result

func _diff(value: Dictionary, base: Dictionary, id: String, mode: String, unit: bool = false) -> Dictionary:
	var changes := {}
	var removed: Array = []
	for key in base:
		if not value.has(key): removed.append(key)
	for key in value:
		# All mutable unit fields are explicit, even if equal to today's default.
		if not base.has(key) or value[key] != base[key] or (unit and key not in UNIT_STATIC):
			changes[key] = _encode(value[key], id, mode)
	return {"set":changes, "remove":removed}

func _intern(value: Variant) -> Variant:
	var serialized := JSON.stringify(value)
	if serialized.length() < 96: return value
	var digest := serialized.sha256_text()
	if shared_index.has(digest): return {"$shared":shared_index[digest]}
	var index := shared.size()
	shared.append(value)
	shared_index[digest] = index
	return {"$shared":index}

func _decode(value: Variant, depth: int) -> Variant:
	if not error.is_empty(): return null
	nodes += 1
	# Approximate Variant allocation costs without serializing every subtree.
	expanded_bytes += 64 + value.size() * 48 if value is Dictionary else (32 + value.size() * 24 if value is Array else (24 + value.length() * 4 if value is String else 24))
	if expanded_bytes > 268435456:
		error = "Expanded save is too large."
		return null
	if depth > 128 or nodes > 2000000:
		error = "Save exceeds reconstruction limits."
		return null
	if value is Array:
		var list: Array = []
		for child in value: list.append(_decode(child, depth + 1))
		return list
	if not value is Dictionary: return value
	if value.has("$literal"):
		if not value["$literal"] is Dictionary: error = "Invalid literal save record."; return {}
		var literal := {}
		for key in value["$literal"]: literal[key] = _decode(value["$literal"][key], depth + 1)
		return literal
	if value.has("$shared"):
		var raw: Variant = value["$shared"]
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floor(float(raw)) or int(raw) < 0 or int(raw) >= shared.size():
			error = "Invalid shared save reference."
			return null
		var index := int(raw)
		references[index] = int(references.get(index, 1)) - 1
		if expanded.has(index):
			if expanded[index] == null: error = "Circular save reference."; return null
			var cached: Variant = expanded[index]
			if references[index] <= 0:
				expanded.erase(index)
				expanded_sizes.erase(index)
				return cached
			expanded_bytes += int(expanded_sizes.get(index, 0))
			if expanded_bytes > 268435456: error = "Expanded save is too large."; return null
			return cached.duplicate(true)
		expanded[index] = null
		var before := expanded_bytes
		var decoded: Variant = _decode(shared[index], depth + 1)
		if not error.is_empty(): return null
		if decoded is not Dictionary and decoded is not Array:
			error = "Invalid shared save record."
			return null
		if references[index] <= 0:
			expanded.erase(index)
			return decoded
		var weight := expanded_bytes - before
		expanded[index] = decoded
		expanded_sizes[index] = weight
		expanded_bytes += weight
		if expanded_bytes > 268435456: error = "Expanded save is too large."; return null
		return decoded.duplicate(true)
	if value.has("$item"):
		var raw: Variant = value["$item"]
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) != floor(float(raw)):
			error = "Invalid item reference."; return {}
		var key := str(int(value["$item"]))
		if not items.has(key) or not value.get("values") is Dictionary:
			error = "Save references an unavailable item: " + key
			return {}
		var item: Dictionary = items[key].duplicate(true)
		var changes: Variant = _decode(value["values"], depth + 1)
		if changes is Dictionary: item.merge(changes, true)
		return item
	if value.has("$chapter") or value.has("$unit"):
		var id := str(value.get("$chapter", value.get("chapter", "")))
		var mode := str(value.get("difficulty", "normal"))
		if mode not in Difficulty.MODES: error = "Invalid saved difficulty."; return {}
		var base := _chapter(id, mode)
		if value.has("$unit"): base = unit_bases.get(id + ":" + mode, {}).get(str(value["$unit"]), {})
		if base.is_empty(): error = "Save definition is unavailable: " + id; return {}
		var patch: Variant = value.get("patch")
		if not patch is Dictionary or not patch.get("set") is Dictionary or not patch.get("remove") is Array:
			error = "Invalid save patch."; return {}
		# Avoid copying large default armies/events only to replace them with
		# the saved fields immediately afterward.
		var before_copy := OS.get_static_memory_usage()
		var decoded_map := {}
		for key in base:
			if patch.remove.has(key) or patch.set.has(key): continue
			var field: Variant = base[key]
			decoded_map[key] = field.duplicate(true) if field is Dictionary or field is Array else field
		expanded_bytes += maxi(0, OS.get_static_memory_usage() - before_copy)
		if expanded_bytes > 268435456: error = "Expanded save is too large."; return null
		for key in patch.set: decoded_map[key] = _decode(patch.set[key], depth + 1)
		return decoded_map
	var result := {}
	for key in value: result[key] = _decode(value[key], depth + 1)
	return result

func _refresh(value: Variant) -> void:
	if value is Array:
		for child in value: _refresh(child)
	elif value is Dictionary:
		if value.has("uses") and (value.get("rom_item_id") is float or value.get("rom_item_id") is int):
			var base: Dictionary = items.get(str(int(value.rom_item_id)), {})
			if not base.is_empty():
				for key in item_definition_keys:
					if key not in ["uses", "max_uses"] and not base.has(key): value.erase(key)
			for key in base:
				if key not in ["uses", "max_uses"]: value[key] = base[key].duplicate(true) if base[key] is Dictionary or base[key] is Array else base[key]
		if value.get("rogue_personal") is Dictionary and value.has("id") and value.has("faction"): Personal.initialize(value)
		for key in value: _refresh(value[key])
