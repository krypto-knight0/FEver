extends RefCounted
## Campaign roster and preparations. Benched and recovering units are saved
## with the chapter, outside the active battlefield and its turn/objective loops.

static func all_units(state: RefCounted) -> Array:
	return state.units + state.chapter.get("reserve_units", [])

static func eligible(unit: Dictionary) -> bool:
	return unit.get("faction", "") == "player" and int(unit.get("hp", 0)) > 0 and int(unit.get("recovery_chapters", 0)) == 0 and not unit.get("escaped", false)

static func forced_ids(state: RefCounted) -> Array:
	var result: Array = state.chapter.get("deployment", {}).get("forced", []).duplicate()
	if state.rules.get("optional_convoy_merchant", false): result.erase("convoy_merchant")
	if state.chapter.get("explicit_forced_deployment", false): return result
	for unit in all_units(state):
		if state.rules.get("optional_convoy_merchant", false) and str(unit.get("id", "")) == "convoy_merchant": continue
		if unit.get("faction", "") == "player" and (unit.get("essential", false) or unit.get("supply_provider", false)) and not result.has(str(unit.id)):
			result.append(str(unit.id))
	return result

static func default_selection(state: RefCounted) -> Array:
	var result: Array = []
	var forced := forced_ids(state)
	var slots: Array = state.chapter.get("deployment", {}).get("slots", [])
	for id in forced:
		var unit: Dictionary = state.get_unit(str(id))
		if eligible(unit): result.append(str(id))
	if state.Rogue.active(state):
		var candidates := all_units(state).filter(func(unit): return eligible(unit) and not result.has(str(unit.id)))
		# Stable sorting preserves the chapter's native formation for ties and
		# for a new army that has no deployment history yet.
		var native_order := {}
		for slot in slots: native_order[str(slot.get("unit_id", ""))] = native_order.size()
		for unit in candidates:
			if not native_order.has(str(unit.id)): native_order[str(unit.id)] = native_order.size()
		candidates.sort_custom(func(a, b):
			var recent_a := int(a.get("last_deployed", -1))
			var recent_b := int(b.get("last_deployed", -1))
			return recent_a > recent_b if recent_a != recent_b else int(native_order[str(a.id)]) < int(native_order[str(b.id)]))
		for unit in candidates:
			if result.size() >= slots.size(): break
			result.append(str(unit.id))
		return result
	for slot in slots:
		var id := str(slot.get("unit_id", ""))
		if eligible(state.get_unit(id)) and not result.has(id) and result.size() < slots.size(): result.append(id)
	for unit in all_units(state):
		if eligible(unit) and not result.has(str(unit.id)) and result.size() < slots.size(): result.append(str(unit.id))
	return result

static func deploy(state: RefCounted, selected: Array, placements: Dictionary = {}) -> Dictionary:
	var slots: Array = state.chapter.get("deployment", {}).get("slots", [])
	if state.chapter.get("deployment_complete", false) or state.turn != 1 or state.phase != "player" or not state.pending_moves.is_empty(): return {"ok": false, "reason": "Preparations are over."}
	if selected.is_empty() or selected.size() > slots.size(): return {"ok": false, "reason": "Choose between one and %d units." % slots.size()}
	var unique: Array = []
	for id in selected:
		if unique.has(str(id)) or not eligible(state.get_unit(str(id))): return {"ok": false, "reason": "An unavailable unit was selected."}
		unique.append(str(id))
	for id in forced_ids(state):
		if eligible(state.get_unit(str(id))) and not unique.has(str(id)): return {"ok": false, "reason": "Required units must deploy."}
	# Preserve each selected unit's native slot, then place replacements in the
	# freed slots. Validate every destination before committing any changes.
	var assignments: Dictionary = {}
	var free: Array = slots.duplicate(true)
	for slot in slots:
		var id := str(slot.get("unit_id", ""))
		if unique.has(id):
			assignments[id] = Vector2i(int(slot.x), int(slot.y))
			free.erase(slot)
	for id in unique:
		if assignments.has(id): continue
		# Explicit placements are validated below; a greedy temporary formation
		# must not reject a valid drag-and-drop formation first.
		if placements.has(id):
			assignments[id] = placements[id]
			continue
		var unit: Dictionary = state.get_unit(id)
		var chosen := -1
		for index in range(free.size()):
			if state.movement_cost(unit, Vector2i(int(free[index].x), int(free[index].y))) > 0:
				chosen = index
				break
		if chosen < 0: return {"ok": false, "reason": "No suitable starting tile for %s." % unit.name}
		assignments[id] = Vector2i(int(free[chosen].x), int(free[chosen].y))
		free.remove_at(chosen)
	if not placements.is_empty():
		if placements.size() != assignments.size(): return {"ok": false, "reason": "The formation no longer matches the roster."}
		var occupied: Array = []
		for id in assignments:
			if not placements.has(id): return {"ok": false, "reason": "A unit has no starting tile."}
			var cell: Vector2i = placements[id]
			if forced_ids(state).has(id) and cell != assignments[id]: return {"ok": false, "reason": "Required units cannot change position."}
			if occupied.has(cell) or not slots.any(func(slot): return cell == Vector2i(int(slot.x), int(slot.y))) or state.movement_cost(state.get_unit(id), cell) <= 0:
				return {"ok": false, "reason": "Choose an unoccupied, suitable deployment tile."}
			occupied.append(cell)
		assignments = placements.duplicate()
	var active: Array = []
	var reserve: Array = []
	for unit in all_units(state):
		if unit.get("faction", "") != "player":
			active.append(unit)
		elif assignments.has(str(unit.id)):
			unit.erase("benched")
			unit.last_deployed = int(state.chapter.get("rogue", {}).get("completed", state.chapter.get("chapter_number", 0)))
			unit.x = assignments[str(unit.id)].x
			unit.y = assignments[str(unit.id)].y
			active.append(unit)
		else:
			unit.benched = true
			reserve.append(unit)
	state.units = active
	state.chapter.reserve_units = reserve
	state.chapter.deployment_complete = true
	if state.Rogue.active(state):
		for unit in state.units:
			if unit.faction == "player": state.Rogue.start_phase(state, unit)
	return {"ok": true}

static func transfer(previous: RefCounted, next: RefCounted, permadeath: bool) -> void:
	preload("res://engine/native_event_flags.gd").carry(previous,next)
	next.chapter.story_flags = previous.chapter.get("story_flags", {}).duplicate(true)
	if not next.chapter.get("campaign_reset",false):
		for key in ["fe7_rank_records","fe7_rank_deaths"]:
			if previous.chapter.has(key): next.chapter[key] = previous.chapter[key].duplicate(true)
	if previous.chapter.has("fe7_experience"): next.chapter.fe7_experience = previous.chapter.fe7_experience.duplicate(true)
	if str(next.chapter.get("id", "")).begins_with("fe6_"):
		next.chapter.fe6_experience = previous.chapter.get("fe6_experience",{}).duplicate(true)
		if previous.get_unit("fe6_unit_43").get("faction", "") == "player": next.chapter.story_flags.fe6_unit_43_recruited = true
		var route_performer: Dictionary = previous.get_unit("fe6_unit_52")
		if not route_performer.is_empty() and int(route_performer.hp) <= 0: next.chapter.story_flags.fe6_unit_52_defeated = true
	if str(next.chapter.get("id", "")) in ["fe7_eli_chapter23", "fe7_eli_chapter23b", "fe7_hec_chapter24", "fe7_hec_chapter24b"]:
		var fe7_unit_34: Dictionary = previous.get_unit("fe7_unit_34")
		next.chapter.story_flags.heaven_seal_eligible = not fe7_unit_34.is_empty() and fe7_unit_34.get("faction", "") == "player" and _campaign_survivor(fe7_unit_34)

	next.chapter.unavailable_recruits = previous.chapter.get("unavailable_recruits", []).duplicate()
	for id in previous.chapter.get("future_recruits", []):
		var recruit: Dictionary = previous.get_unit(str(id))
		if not recruit.is_empty() and int(recruit.hp) <= 0 and not next.chapter.unavailable_recruits.has(id): next.chapter.unavailable_recruits.append(id)
	next.chapter.campaign_roster = previous.chapter.get("campaign_roster", {}).duplicate(true)
	if next.chapter.get("campaign_reset", false):
		# fe7_unit_3's army disperses. Preserve progression separately from the new army,
		# including benched allies; new chapter definitions supply all equipment.
		if next.chapter.has("lyn_handoff") and previous.chapter.get("native_route",0) == 1: preload("res://engine/fe7_preparation.gd").lyn_assets(previous,next)
		next.chapter.campaign_roster = {}
		next.chapter.unavailable_recruits = []
		for unit in all_units(previous):
			if unit.get("faction", "") == "player" and _campaign_survivor(unit):
				next.chapter.campaign_roster[str(unit.id)] = unit.duplicate(true)
		for unit in next.units: restore_campaign_unit(next, unit)
		return
	var old_roster: Dictionary = {}
	for unit in all_units(previous):
		if unit.get("faction", "") == "player": old_roster[str(unit.id)] = unit
	for id in next.chapter.get("exclude_carryover_units", []):
		if old_roster.has(id):
			next.chapter.campaign_roster[id] = old_roster[id].duplicate(true)
			old_roster.erase(id)
	# The two Light battles share the selected army; there is no new preparation.
	if next.chapter.get("native_continue_formation",false):
		for unit in previous.units:
			if unit.faction == "player" and not unit.get("benched",false): next.units.append(unit.duplicate(true))
	var fresh: Array = []
	var seen: Array = []
	for candidate in next.units:
		var id := str(candidate.id)
		if candidate.faction != "player":
			fresh.append(candidate)
			continue
		if next.chapter.unavailable_recruits.has(id): continue
		if next.chapter.get("carryover_units", []).has(id) and not old_roster.has(id): continue
		if old_roster.has(id): candidate = _carry_unit(old_roster[id], candidate, permadeath)
		fresh.append(candidate)
		seen.append(id)
	# A reserve missing from the next map's native formation is still in the army.
	for id in old_roster:
		if seen.has(id): continue
		var unit := _carry_unit(old_roster[id], {}, permadeath)
		unit.x = 0
		unit.y = 0
		unit.benched = true
		fresh.append(unit)
	next.units = []
	next.chapter.reserve_units = []
	for unit in fresh:
		if unit.get("faction", "") == "player" and (unit.get("benched", false) or not eligible(unit)):
			unit.benched = true
			unit.x = 0
			unit.y = 0
			next.chapter.reserve_units.append(unit)
		else: next.units.append(unit)
	for unit in next.units: restore_campaign_unit(next, unit)

static func _campaign_survivor(unit: Dictionary) -> bool:
	# Recovering casual-mode allies are alive; permanent casualties restart
	# from their recruitment profile if they return in the next storyline.
	return int(unit.get("hp", 1)) > 0 or unit.get("casualty_mode", "") == "injured"

static func restore_campaign_unit(state: RefCounted, unit: Dictionary) -> void:
	if unit.get("campaign_restored", false) or unit.get("faction", "") == "enemy": return
	var old: Dictionary = state.chapter.get("campaign_roster", {}).get(str(unit.get("campaign_return_from", unit.get("campaign_progression_from", unit.get("id", "")))), {})
	if old.is_empty() or not _campaign_survivor(old): return
	# Never copy weapons, inventory, positions, faction or deployment flags.
	for key in ["rogue_skills", "rogue_learned_types", "rogue_native_types", "rogue_personal", "rogue_growth_gains", "rogue_level_count", "magic", "level", "exp", "max_hp", "str", "skill", "speed", "def", "res", "luck", "con", "mov", "growths", "weapon_exp", "promoted", "rom_class_id", "class_name", "stat_caps", "weapon_types", "movement_costs", "movement_costs_rain", "terrain_bonuses", "canto", "flying", "aid", "aid_base", "can_use_staves", "can_steal", "can_lockpick", "critical_bonus", "experience_power", "experience_bonus", "experience_defeat_bonus", "sprite", "movement_sprite"]:
		if unit.has("campaign_progression_from") and key not in ["rogue_skills", "rogue_learned_types", "rogue_native_types", "rogue_personal", "rogue_growth_gains", "rogue_level_count", "magic", "level", "exp", "max_hp", "str", "skill", "speed", "def", "res", "luck"]: continue
		if unit.has("campaign_progression_from") and key == "rogue_personal": continue
		if old.has(key): unit[key] = old[key].duplicate(true) if old[key] is Dictionary or old[key] is Array else old[key]
	unit.hp = int(unit.max_hp)
	if old.has("silencer") and not unit.has("campaign_progression_from"): unit.silencer = bool(old.silencer)
	if old.has("fe6_class_flags") and not unit.has("campaign_progression_from"):
		preload("res://engine/fe6_unit_traits.gd").apply(unit,int(old.fe6_class_flags),int(old.get("fe6_personal_flags",0)))
	unit.campaign_restored = true
	var native := preload("res://engine/recruitment_levels.gd").target(unit, state.chapter)
	if bool(unit.get("promoted", false)) == bool(native.get("promoted", false)):
		unit.level = maxi(int(unit.level), int(native.get("level", 1)))

static func _carry_unit(old: Dictionary, template: Dictionary, permadeath: bool) -> Dictionary:
	var unit := old.duplicate(true)
	if unit.get("supply_provider", false): unit.essential = bool(template.get("essential", false))
	unit.erase("manual_weapon_turn")
	unit.status = ""
	unit.status_turns = 0
	for key in ["x", "y", "essential"]:
		if template.has(key): unit[key] = template[key]
	unit.erase("benched")
	for key in ["acted", "moved", "traded", "canto_active"]: unit[key] = false
	for key in ["move_spent", "canto_remaining"]: unit[key] = 0
	unit.carrying_id = ""
	unit.rescued_by = ""
	if unit.has("rogue_skills"):
		unit.rogue_personal_state = {}
		unit.rogue_tiles_moved = 0
		unit.rogue_effects = []
		unit.rogue_used = {}
		unit.rogue_action_taken = false
		unit.erase("rogue_fury")
	unit.temporary_bonuses = {}
	unit.ring_bonuses = {}
	unit.vision_bonus = 0
	unit.recovery_chapters = maxi(0, int(old.get("recovery_chapters", 0)) - 1)
	if int(old.hp) <= 0:
		var permanent := str(old.get("casualty_mode", "permanent" if permadeath else "injured")) == "permanent"
		if permanent: unit.hp = 0
		else:
			unit.hp = int(unit.max_hp)
			unit.recovery_chapters = 1
	else: unit.hp = int(unit.max_hp)
	return unit
