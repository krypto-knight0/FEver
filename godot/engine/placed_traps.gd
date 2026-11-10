extends RefCounted
## Runtime traps are separate from terrain so expiry never overwrites map changes.

static func at(b, cell: Vector2i) -> Dictionary:
	for trap in b.chapter.get("placed_traps", []):
		if Vector2i(trap.x, trap.y) == cell: return trap
	return {}

static func destinations(b, unit: Dictionary, item: Dictionary) -> Array:
	if not b._can_command(unit) or unit.faction != "player" or item.get("kind", "") != "trap" or item.get("trap", "") not in ["mine", "light_rune"] or int(item.get("uses", 0)) <= 0: return []
	var cells: Array = []
	for direction in b.DIRECTIONS:
		var cell: Vector2i = b.position(unit) + direction
		if b.movement_cost(unit, cell) <= 0 or not b.unit_at(cell).is_empty() or b._reserved_origin(cell, str(unit.id)): continue
		if int(b.rules.get("fog_radius", 0)) > 0 and not b.visible_cells().has(cell): continue
		if not at(b, cell).is_empty(): continue
		if b.chapter.get("emplacements", []).any(func(site): return Vector2i(site.x, site.y) == cell): continue
		if b.chapter.get("hazards", []).any(func(site): return Vector2i(site.get("x", -1), site.get("y", -1)) == cell): continue
		cells.append(cell)
	return cells

static func place(b, unit: Dictionary, index: int, cell: Vector2i) -> Dictionary:
	var item: Dictionary = b._inventory_item(unit, index)
	if not destinations(b, unit, item).has(cell): return {"ok": false, "reason": "Choose an empty, visible adjacent tile without another trap."}
	b.commit_move(str(unit.id))
	if unit.acted: return {"ok": false, "reason": "Movement was interrupted."}
	var trap := {"kind": str(item.trap), "x": cell.x, "y": cell.y, "owner": str(unit.faction)}
	if item.trap == "light_rune": trap.turns = 3
	else: trap.item = item.duplicate(true); trap.item.uses = 1
	b.chapter.get_or_add("placed_traps", []).append(trap)
	var name := str(item.get("name", "Trap"))
	b._consume_use(item)
	if int(item.uses) <= 0: unit.inventory.remove_at(index)
	b._finish_noncombat(unit)
	b.events_log.append("%s placed %s." % [unit.name, name])
	return {"ok": true, "placed_trap": trap.kind, "item_name": name}

static func interrupts(unit: Dictionary) -> bool:
	# FE7's moving-unit check exempts fliers, lockpick users and assassins.
	return not (unit.get("flying", false) or unit.get("can_lockpick", false) or unit.get("silencer", false))

static func movement_path(b, unit: Dictionary, path: Array) -> Array:
	if not interrupts(unit): return path
	for index in range(1, path.size()):
		var cell: Vector2i = path[index]
		# A mine underneath a stationary ally is not armed until the tile is empty.
		var occupant: Dictionary = b.unit_at(cell)
		if not occupant.is_empty() and occupant.id != unit.id: continue
		if at(b, cell).get("kind", "") == "mine": return path.slice(0, index + 1)
	return path

static func trigger(b, unit: Dictionary, landing: bool = false) -> Dictionary:
	if not b._on_map(unit): return {}
	if landing and b.chapter.has("fe6_step_traps"):
		var step_result := preload("res://engine/fe6_event_actions.gd").step(b,unit)
		if not step_result.is_empty(): return step_result
	var trap := at(b, b.position(unit))
	if trap.get("kind", "") != "mine": return {}
	if not landing and not interrupts(unit): return {}
	var recovered := false
	if unit.get("silencer", false):
		if unit.inventory.size() + (0 if unit.weapon.is_empty() else 1) >= 5: return {}
		recovered = true
	elif unit.get("can_steal", false): return {}
	b.chapter.placed_traps.erase(trap)
	var previous := int(unit.hp)
	if recovered:
		unit.inventory.append(trap.get("item", {"name": "Mine", "kind": "trap", "trap": "mine", "uses": 1, "max_uses": 1}).duplicate(true))
	else:
		unit.hp = maxi(0, previous - 10)
		if b.Rogue.active(b): b.Rogue.Personal.injured(unit, previous - int(unit.hp))
	unit.acted = true
	unit.moved = true
	unit.canto_active = false
	unit.canto_remaining = 0
	var result := {"unit_id": str(unit.id), "target_id": str(unit.id), "previous_hp": previous, "remaining_hp": int(unit.hp), "damage": previous - int(unit.hp), "recovered": recovered}
	b.last_movement_effect = result
	b.events_log.append("%s recovered a Mine." % unit.name if recovered else "%s triggered a Mine: %d damage. Action ended." % [unit.name, result.damage])
	if int(unit.hp) <= 0:
		if unit.faction == "player": unit.casualty_mode = "permanent" if bool(b.rules.get("permadeath", true)) else "injured"
		var passenger_id := str(unit.get("carrying_id", ""))
		b._release_on_death(unit)
		if not passenger_id.is_empty(): result.released_passenger = passenger_id
		b._run_events("unit_defeated", {"unit_id": str(unit.id)})
	if b.phase != "player" or b.auto_playing: b.phase_actions.append({"type": "trap", "result": result.duplicate(true)})
	else: b.pending_trap_effects.append(result.duplicate(true))
	b._check_objective()
	return result

static func decay(b) -> void:
	for trap in b.chapter.get("placed_traps", []).duplicate():
		if trap.kind != "light_rune": continue
		trap.turns = int(trap.turns) - 1
		if trap.turns <= 0:
			b.chapter.placed_traps.erase(trap)
			b.events_log.append("A Light Rune faded.")

static func valid(traps: Variant, rows: Array) -> bool:
	if not traps is Array: return false
	var occupied: Array = []
	for trap in traps:
		if not trap is Dictionary or trap.get("kind", "") not in ["mine", "light_rune"]: return false
		for axis in ["x", "y"]:
			var value = trap.get(axis)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)): return false
		var cell := Vector2i(trap.x, trap.y)
		if cell.x < 0 or cell.y < 0 or cell.y >= rows.size() or cell.x >= rows[0].length() or occupied.has(cell): return false
		occupied.append(cell)
		if trap.get("owner", "enemy") not in ["player", "enemy", "neutral"]: return false
		if trap.kind == "light_rune":
			var turns = trap.get("turns")
			if not (turns is int or turns is float) or not is_finite(float(turns)) or float(turns) != floor(float(turns)) or int(turns) < 1 or int(turns) > 3: return false
		elif trap.has("item"):
			if not trap.item is Dictionary or trap.item.get("kind", "") != "trap" or trap.item.get("trap", "") != "mine" or trap.item.get("uses", 0) != 1: return false
	return true
