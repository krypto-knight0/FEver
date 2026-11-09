extends RefCounted
## Settings chapter jump: approximate prior progression without changing saves.
static func prepare(state: RefCounted, previous_chapters: Array) -> void:
	var number := chapter_level(state.chapter)
	var level := mini(15, number if number <= 15 else number - 15)
	var promoted := number >= 16
	state.rng.randomize()
	_level_units(state, state.units, level, [], promoted)
	_level_units(state, state.chapter.get("reserve_units", []), level, [], promoted)
	var recruits_by_id: Dictionary = {}
	var seen_units: Dictionary = {}
	var rewards: Array = []
	var gold := 0
	if not previous_chapters.is_empty(): gold = int(previous_chapters[0].get("gold", 0))
	for chapter in previous_chapters:
		if chapter.get("campaign_reset", false):
			seen_units.clear()
			recruits_by_id.clear()
			rewards.clear()
			gold = int(chapter.get("gold", 0))
		var previous_recruits := _recruits(chapter)
		var candidates: Array = []
		for key in ["units", "reserve_units", "events", "talks", "interactions"]:
			_recruit_candidates(chapter.get(key, []), previous_recruits, candidates)
		for candidate in candidates:
			if not recruits_by_id.has(str(candidate.id)): recruits_by_id[str(candidate.id)] = candidate.duplicate(true)
		for source in chapter.get("units", []):
			var unit: Dictionary = source.duplicate(true)
			if previous_recruits.has(str(unit.get("id", ""))): unit.faction = "player"
			_collect(unit, seen_units, rewards)
		_collect(chapter.get("events", []), seen_units, rewards)
		_collect(chapter.get("interactions", []), seen_units, rewards)
		var seen_talks: Dictionary = {}
		for talk in chapter.get("talks", []):
			if seen_talks.has(str(talk.get("id", ""))): continue
			seen_talks[str(talk.get("id", ""))] = true
			_collect(talk, seen_units, rewards)
		rewards.append_array(chapter.get("inventory", []).duplicate(true))
	if state.chapter.get("campaign_reset", false):
		rewards.clear()
		gold = int(state.chapter.get("gold", 0))
	if not state.chapter.get("campaign_reset", false):
		for id in recruits_by_id:
			if not state.get_unit(id).is_empty() or state.chapter.get("exclude_carryover_units", []).has(id): continue
			var recruit: Dictionary = state._normalize_unit(recruits_by_id[id])
			recruit.faction = "player"
			recruit.benched = true
			recruit.x = 0
			recruit.y = 0
			_level_units(state, recruit, level, [], promoted)
			state.chapter.get_or_add("reserve_units", []).append(recruit)
	for reward in rewards:
		if reward.has("gold"): gold += int(reward.gold)
		elif reward.has("uses"): state.inventory.append(state._normalize_item(reward))
	state.gold = gold
	state.chapter.earned_experience = 0
	state.events_log.append("Chapter preview: allies advanced to level %d%s, preserving native join levels; prior rewards and equipment added to Supply." % [level, " promoted where eligible" if promoted else ""])

static func _recruits(chapter: Dictionary) -> Array:
	var ids: Array = []
	var characters: Array = []
	var candidates: Array = chapter.get("units", []).duplicate()
	for event in chapter.get("talks", []) + chapter.get("events", []) + chapter.get("interactions", []):
		_recruit_effects(event, ids, characters)
		candidates.append_array(preload("res://engine/native_event_runner.gd").spawn_templates(event))
	for unit in candidates:
		if int(unit.get("rom_character_id", -1)) in characters and not ids.has(str(unit.id)): ids.append(str(unit.id))
	# fe6_unit_53's third conversation cannot happen before chapter 12. Chapter jumps
	# approximate that recruitment only after completing chapter 12.
	if chapter_level(chapter) < 12: ids.erase("fe6_unit_53")
	return ids

static func _recruit_effects(value: Variant, ids: Array, characters: Array) -> void:
	if value is Array:
		for child in value: _recruit_effects(child, ids, characters)
	elif value is Dictionary:
		for change in value.get("change_faction", []):
			if change.get("faction", "") == "player" and not ids.has(str(change.unit_id)): ids.append(str(change.unit_id))
		if value.get("op", "") == "faction" and value.get("faction", "") == "player": characters.append(int(value.character))
		for key in ["native_program", "scripts", "effect"]:
			if value.has(key): _recruit_effects(value[key], ids, characters)

static func chapter_level(chapter: Dictionary) -> int:
	if chapter.has("chapter_number"): return maxi(1, int(chapter.chapter_number))
	var title := str(chapter.get("title", ""))
	var matcher := RegEx.new()
	matcher.compile("(?i)chapter\\s+(\\d+)")
	var found := matcher.search(title)
	return maxi(1, int(found.get_string(1))) if found else 1

static func recruitment_baseline(chapters: Array) -> Dictionary:
	var seen: Dictionary = {}
	var latest: Dictionary = {}
	for chapter in chapters:
		if chapter.get("campaign_reset", false): seen.clear()
		var recruits := _recruits(chapter)
		var candidates: Array = []
		_recruit_candidates(chapter.get("units", []), recruits, candidates)
		_recruit_candidates(chapter.get("events", []), recruits, candidates)
		_recruit_candidates(chapter.get("talks", []), recruits, candidates)
		_recruit_candidates(chapter.get("interactions", []), recruits, candidates)
		for unit in candidates:
			var id := str(unit.get("id", ""))
			if id.is_empty() or seen.has(id): continue
			seen[id] = true
			latest = unit.duplicate(true)
			latest.merge(preload("res://engine/recruitment_levels.gd").target(unit, chapter), true)
	return latest

static func _recruit_candidates(value: Variant, recruits: Array, out: Array) -> void:
	if value is Array:
		for child in value: _recruit_candidates(child, recruits, out)
	elif value is Dictionary:
		if value.has("growths") and value.has("level") and (value.get("faction", "") == "player" or recruits.has(str(value.get("id", "")))):
			out.append(value)
		else:
			for key in ["spawns", "events", "interactions", "native_program", "scripts", "effect"]:
				if value.has(key): _recruit_candidates(value[key], recruits, out)

static func _level_units(state: RefCounted, value: Variant, level: int, recruits: Array, promoted: bool) -> void:
	if value is Array:
		for child in value: _level_units(state, child, level, recruits, promoted)
	elif value is Dictionary:
		if (value.get("faction", "") == "player" or recruits.has(str(value.get("id", "")))) and value.has("growths") and value.has("level"):
			var target := clampi(level, 1, 20)
			var native := preload("res://engine/recruitment_levels.gd").target(value, state.chapter)
			if promoted and not bool(value.get("promoted", false)):
				for route in state.rules.get("promotion_catalog", {}).get("promotions", []):
					var source := int(route.from_class if promoted else route.to_class)
					if source != int(value.get("rom_class_id", -1)): continue
					var definition: Dictionary = state._class_definition(int(route.to_class if promoted else route.from_class)).duplicate(true)
					if promoted and int(value.level) < 20:
						state._award_experience(value, (20 - int(value.level)) * int(state.rules.experience_per_level) - int(value.get("exp", 0)))
					elif not promoted:
						var old: Dictionary = state._class_definition(source)
						definition.promotion_gains = {}
						for stat in old.get("promotion_gains", {}): definition.promotion_gains[stat] = -int(old.promotion_gains[stat])
						definition.weapon_exp = {}
					state._apply_class_change(value, definition)
					break
			if promoted and not value.get("promoted", false): target = mini(15, chapter_level(state.chapter))
			if bool(value.get("promoted", false)) == bool(native.get("promoted", false)):
				target = maxi(target, int(native.get("level", 1)))
			target = maxi(target, int(value.level))
			if int(value.level) < target:
				state._award_experience(value, (target - int(value.level)) * int(state.rules.experience_per_level) - int(value.get("exp", 0)))
			value.level = target
			value.exp = 0
			value.hp = int(value.max_hp)
		else:
			for key in value:
				if key not in ["source", "source_deployment", "dialogue"]: _level_units(state, value[key], level, recruits, promoted)

static func _collect(value: Variant, seen_units: Dictionary, rewards: Array) -> void:
	if value is Array:
		for child in value: _collect(child, seen_units, rewards)
	elif value is Dictionary:
		if value.get("faction", "") == "player" and value.has("weapon"):
			var id := str(value.get("id", ""))
			if not seen_units.has(id):
				seen_units[id] = true
				if not value.weapon.is_empty(): rewards.append(value.weapon.duplicate(true))
				rewards.append_array(value.get("inventory", []).duplicate(true))
			return
		for key in ["give_item", "drop_item"]:
			if value.has(key): rewards.append(value[key].duplicate(true))
		if value.has("give_items"):
			for gift in value.give_items:
				if gift.has("item"): rewards.append(gift.item.duplicate(true))
		if value.get("reward", {}) is Dictionary:
			var reward: Dictionary = value.get("reward", {})
			if reward.has("gold"): rewards.append({"gold": reward.gold})
			if reward.has("item"): rewards.append(reward.item.duplicate(true))
		for key in ["spawns", "events", "interactions", "native_program", "scripts", "effect"]:
			if value.has(key): _collect(value[key], seen_units, rewards)
