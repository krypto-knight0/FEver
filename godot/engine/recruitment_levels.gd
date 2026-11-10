extends RefCounted
## Fresh recruits use original starting classes, requested join levels and ROM WEXP.
## Saved games and earned campaign carryover are never passed through this adapter.
static var profiles: Dictionary = {}

static func target(unit: Dictionary, chapter: Dictionary) -> Dictionary:
	var chapter_id := str(chapter.get("id", ""))
	if not chapter_id.begins_with("fe7_tutorial_") and not chapter_id.begins_with("fe7_eli_") and not chapter_id.begins_with("fe7_hec_"): return {}
	var id := str(unit.get("id", ""))
	if profiles.is_empty():
		profiles = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/recruitment_profiles.json")).characters
	return profiles.get(id, {}).duplicate(true)

static func apply_chapter(state: RefCounted) -> void:
	for key in ["units", "events", "talks", "interactions"]:
		_apply(state.chapter.get(key, []), state)

static func _apply(value: Variant, state: RefCounted) -> void:
	if value is Array:
		for child in value: _apply(child, state)
	elif value is Dictionary:
		if value.has("growths") and value.has("rom_character_id") and value.has("level"):
			var requested := target(value, state.chapter)
			if requested.is_empty(): return
			if int(requested.rom_class_id) != int(value.get("rom_class_id", -1)):
				if state.rules.get("promotion_catalog", {}).get("promotions", []).is_empty():
					state.rules.promotion_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://content/fe7/promotion_manifest.json"))
				var definition: Dictionary = state._class_definition(int(requested.rom_class_id)).duplicate(true)
				if value.get("promoted", false) and not requested.promoted:
					var old: Dictionary = state._class_definition(int(value.rom_class_id))
					definition.promotion_gains = {}
					for stat in old.get("promotion_gains", {}): definition.promotion_gains[stat] = -int(old.promotion_gains[stat])
				var unit: Dictionary = state._normalize_unit(value)
				state._apply_class_change(unit, definition)
				value.merge(unit, true)
			value.level = int(requested.level)
			value.exp = 0
			value.weapon_exp = requested.weapon_exp.duplicate(true)
			value.promoted = bool(requested.promoted)
		else:
			for key in ["units", "spawns", "events", "talks", "interactions"]:
				if value.has(key): _apply(value[key], state)
