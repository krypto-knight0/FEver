extends RefCounted
const Patch = preload("res://engine/chapter_patch.gd")
const MODES := ["normal", "hard", "rogue_normal", "rogue_hard"]
const LABELS := ["Classic Normal", "Classic Hard", "Rogue Normal", "Rogue Hard"]
## Difficulty is fixed for a loaded chapter. Campaign choice is applied only
## when a fresh chapter definition is loaded, never to a live suspend state.

static func normalize(value: Variant) -> String:
	return str(value) if value in MODES else "normal"

static func is_rogue(value: Variant) -> bool:
	return normalize(value) in ["rogue_normal", "rogue_hard"]

static func is_hard(value: Variant) -> bool:
	return normalize(value) in ["hard", "rogue_hard"]

static func label(value: Variant) -> String:
	return LABELS[MODES.find(normalize(value))]

static func matches(value: Variant, allowed: Array) -> bool:
	for mode in allowed:
		if mode in ["normal", "hard"]:
			if (mode == "hard") == is_hard(value): return true
		elif normalize(mode) == normalize(value): return true
	return false

static func chapter(source: Dictionary, selected: String) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		if key == "difficulty_variants": continue
		var value: Variant = source[key]
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var difficulty := normalize(selected)
	if is_hard(difficulty):
		var changes: Dictionary = source.get("difficulty_variants", {}).get("hard", {})
		if changes.has("delta"):
			var patched: Variant = _apply_delta(result, changes.delta)
			if not patched is Dictionary: return {}
			result = patched
		for key in changes.get("_remove_keys", []): result.erase(key)
		for key in changes:
			if key in ["_remove_keys", "delta"]: continue
			var value: Variant = changes[key]
			result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	_apply_generated_unit_mode(result, is_hard(difficulty))
	result.difficulty = difficulty
	result.get_or_add("rules", {}).hard_mode = is_hard(difficulty)
	if result.get("dynamic_rom",false) and str(result.get("game_id","")) == "fe7" and is_hard(difficulty):
		# Native Hard skips tutorial lessons; story and gameplay event branches
		# still execute through their normal mode-aware programs.
		result.fe7_tutorials = {"select":[],"destination":[],"action":[]}
		_remove_tutorials(result)
	var subtitle := str(source.get("subtitle", "Campaign"))
	for mode in LABELS: subtitle = subtitle.trim_suffix(" · " + mode)
	result.subtitle = subtitle + " · " + label(difficulty)
	if str(result.get("id", "")).begins_with("fe7_tutorial_"):
		if is_hard(difficulty): _remove_tutorials(result)
	if is_rogue(difficulty):
		preload("res://engine/rogue_enemies.gd").apply(result)
	return result

static func _apply_delta(value: Variant, delta: Dictionary) -> Variant:
	var result := Patch.apply(value, delta)
	if not result.error.is_empty(): push_error("Invalid chapter difficulty patch: " + result.error)
	return result.value

static func _apply_generated_unit_mode(value: Variant, hard: bool) -> void:
	if value is Array:
		for child in value: _apply_generated_unit_mode(child, hard)
	elif value is Dictionary:
		if value.has("rom_hard_mode"):
			var changes: Dictionary = value.rom_hard_mode
			value.erase("rom_hard_mode")
			if hard: value.merge(changes.duplicate(true), true)
		for child in value.values(): _apply_generated_unit_mode(child, hard)

static func _remove_tutorials(value: Variant) -> void:
	if value is Array:
		for index in range(value.size()-1, -1, -1):
			if value[index] is Dictionary and value[index].get("tutorial", false): value.remove_at(index)
			else: _remove_tutorials(value[index])
	elif value is Dictionary:
		for key in value: _remove_tutorials(value[key])

static func preserve_starting_army(previous: RefCounted, fresh: RefCounted) -> void:
	# A difficulty restart uses the original chapter-start roster and resources.
	# Newly recruited units, spent gold, injuries and experience from the aborted
	# attempt cannot leak into the fresh map or duplicate chapter rewards.
	var army = preload("res://engine/army_roster.gd")
	var starting: Dictionary = {}
	for unit in army.all_units(previous):
		if unit.get("faction", "") == "player": starting[str(unit.id)] = unit
	var seen: Array = []
	for index in range(fresh.units.size()):
		var slot: Dictionary = fresh.units[index]
		if slot.faction != "player": continue
		if starting.has(str(slot.id)):
			var unit: Dictionary = starting[str(slot.id)].duplicate(true)
			for key in ["x", "y", "essential"]:
				if slot.has(key): unit[key] = slot[key]
			unit.erase("benched")
			fresh.units[index] = unit
			seen.append(str(slot.id))
		else:
			# Optional native slots are placeholders for the existing army.
			slot["_remove_difficulty_placeholder"] = true
	fresh.units = fresh.units.filter(func(u): return not u.get("_remove_difficulty_placeholder", false))
	fresh.chapter.reserve_units = []
	for id in starting:
		if seen.has(id): continue
		var unit: Dictionary = starting[id].duplicate(true)
		unit.benched = true
		fresh.chapter.reserve_units.append(unit)
	for key in ["campaign_roster", "unavailable_recruits"]:
		if previous.chapter.has(key): fresh.chapter[key] = previous.chapter[key].duplicate(true)
	fresh.gold = previous.gold
	fresh.inventory = previous.inventory.duplicate(true)
	fresh.support_points = previous.support_points.duplicate(true)
	fresh.support_ranks = previous.support_ranks.duplicate(true)
	fresh.chapter_repairs_applied = previous.chapter_repairs_applied
