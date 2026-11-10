extends RefCounted
## Targeting and effects shared by map commands, inventory commands and AI.

static func repair_slots(state, target: Dictionary) -> Array:
	var result: Array = []
	for entry in state.inventory_slots(str(target.id)):
		var item: Dictionary = entry.item
		if item.get("kind", "") not in ["weapon", "staff"] or item.get("unbreakable", false) or item.get("unrepairable", false) or item.get("staff_effect", "") == "repair": continue
		if int(item.get("uses", 0)) < int(item.get("max_uses", 0)): result.append(entry)
	return result

static func destinations(state, unit: Dictionary, item: Dictionary, target: Dictionary) -> Array:
	var result: Array = []
	var effect := str(item.get("staff_effect", ""))
	var origin: Vector2i = state.position(unit)
	var limits: Vector2i = state.item_range(unit, item)
	if effect == "unlock":
		for site in state.interactions:
			var cell := Vector2i(site.x, site.y)
			var distance: int = state._distance(origin, cell)
			if site.get("used", false) or not state._ordinary_lock(site) or site.get("type", "") not in (["door", "chest"] if state.rules.get("unlock_staff_chests", false) else ["door"]): continue
			if distance >= limits.x and distance <= limits.y: result.append(cell)
		return result
	@warning_ignore("integer_division") # Intentional integer truncation.
	var radius := maxi(int(item.get("magic_range_min", 1)), int(unit.get("magic", unit.get("str", 0))) / 2) if effect == "warp" else (1 if effect == "rescue" else limits.y)
	if effect == "warp" and item.get("destination_range_unlimited", false): radius = state.width + state.height
	for y in range(maxi(0, origin.y - radius), mini(state.height, origin.y + radius + 1)):
		for x in range(maxi(0, origin.x - radius), mini(state.width, origin.x + radius + 1)):
			var cell := Vector2i(x, y)
			var distance: int = state._distance(origin, cell)
			if distance > radius: continue
			if effect == "torch":
				if distance >= limits.x and int(state.rules.get("fog_radius", 0)) > 0: result.append(cell)
			elif not target.is_empty() and state.unit_at(cell).is_empty() and state.movement_cost(target, cell) > 0:
				result.append(cell)
	return result

static func execute(state, unit: Dictionary, index: int, target: Dictionary, destination: Vector2i, repair_slot: int) -> Dictionary:
	var item: Dictionary = unit.inventory[index]
	var effect := str(item.staff_effect)
	if not state.can_use_staff(unit, item): return {"ok": false, "reason": "This unit cannot use that staff."}
	if effect not in ["torch", "unlock"] and not state.helpful_targets(str(unit.id), index).has(str(target.get("id", ""))):
		return {"ok": false, "reason": "Choose an eligible ally within staff range."}
	if effect in ["warp", "rescue", "torch", "unlock"] and not destinations(state, unit, item, target).has(destination):
		return {"ok": false, "reason": "Choose a valid highlighted destination."}
	var repaired: Dictionary = {}
	if effect == "repair":
		for entry in repair_slots(state, target):
			if int(entry.slot) == repair_slot: repaired = state._slot_item(target, repair_slot)
		if repaired.is_empty(): return {"ok": false, "reason": "Choose a damaged weapon or staff to repair."}
	state.commit_move(str(unit.id))
	if unit.acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	var result := {"ok": true, "item_name": str(item.name), "target_id": str(target.get("id", unit.id))}
	if effect in ["warp", "rescue"]:
		result.from = [target.x, target.y]
		target.x = destination.x; target.y = destination.y
		state._sync_carried(target)
		result.destination = [destination.x, destination.y]
		result.relocated = true
	elif effect == "repair":
		repaired.uses = int(repaired.max_uses)
		result.repaired = str(repaired.name)
	elif effect == "torch":
		if not state.chapter.has("torch_lights"): state.chapter.torch_lights = []
		state.chapter.torch_lights.append({"x": destination.x, "y": destination.y, "radius": int(item.get("vision_bonus", 8))})
		result.illuminated = true
	elif effect == "unlock":
		for site in state.interactions:
			if Vector2i(site.x, site.y) != destination or site.get("used", false) or site.get("type", "") not in (["door", "chest"] if state.rules.get("unlock_staff_chests", false) else ["door"]): continue
			site.used = true
			state.NativeFlags.site(state,site)
			if site.get("type", "") == "chest":
				state._award_reward(site.get("reward", {}))
				if site.has("give_item"): result.item_delivery = state._give_item(str(unit.id), site.give_item)
			if site.has("map_change"): state._apply_map_change(site)
			if site.get("native_visit_event",false):
				state._run_events("visit", {"unit_id":str(unit.id),"x":int(site.x),"y":int(site.y)})
			state._run_events("interact", {"unit_id": str(unit.id), "interaction_id": str(site.get("id", ""))})
			result.unlocked = true
			result.target_id = str(unit.id)
			break
	state._consume_use(item, unit)
	result.merge(state._staff_rewards(unit, item), true)
	if int(item.uses) <= 0: unit.inventory.remove_at(index)
	state._finish_noncombat(unit)
	state.Rogue.after_action(state, unit, "assist")
	if effect in ["warp", "rescue"]: state.Traps.trigger(state, target, true)
	state.events_log.append("%s used %s." % [unit.name, result.item_name])
	return result

static func best_plan(state, unit: Dictionary, cells: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	if str(unit.get("status", "")) == "berserk": return best
	for index in range(unit.inventory.size()):
		var item: Dictionary = unit.inventory[index]
		if item.get("kind", "") != "staff": continue
		if item.has("inflict_status") and unit.get("ai_no_attack", false): continue
		if item.get("staff_effect", "") in ["warp", "rescue", "repair", "torch", "unlock"]: continue
		for cell in cells:
			var planning := unit.duplicate()
			planning.x = cell.x; planning.y = cell.y
			if not state.can_use_staff(planning, item): continue
			var limits: Vector2i = state.item_range(planning, item)
			for target in state.units:
				var distance: int = state._distance(cell, state.position(target))
				if distance < limits.x or distance > limits.y or not state._staff_benefits(planning, target, item): continue
				var score := 0.0
				if item.has("inflict_status"):
					score = 45.0 * state.status_staff_accuracy(planning, target) / 100.0
					if item.inflict_status == "silence" and not state.rules.magic_types.has(target.weapon.get("type", "")) and not target.get("can_use_staves", false): continue
				elif item.get("staff_effect", "") == "restore": score = 65.0
				elif item.has("temporary_bonuses"): score = 12.0
				else:
					var healing := int(target.max_hp) if item.get("healing_full", false) else int(item.get("healing", 0)) + int(unit.get("magic", unit.str))
					score = 3.0 * mini(int(target.max_hp) - int(target.hp), healing)
					if int(target.hp) * 2 < int(target.max_hp): score += 20.0
				score -= float(cells[cell]) * 0.01
				if best.is_empty() or score > float(best.score): best = {"index": index, "target_id": str(target.id), "cell": cell, "score": score}
	return best
