extends RefCounted
## Alternating terrain patches use the battle turn as their clock. The caller's
## persisted hazard guard prevents a resumed phase from advancing twice.
static func advance(b) -> void:
	for cycle in b.chapter.get("map_cycles",[]):
		var first := int(cycle.first_turn)
		var period := int(cycle.period)
		if b.turn < first or (b.turn-first) % period != 0: continue
		var enabled: bool = int((b.turn-first)/period) % 2 == 0
		b._apply_map_change({"id":cycle.id,"map_change":cycle.on if enabled else cycle.off})
		b.phase_actions.append({"type":"map_change","id":cycle.id})

static func valid(cycles: Variant, rows: Array) -> bool:
	if not cycles is Array or cycles.size() > 32: return false
	var ids := {}
	for cycle in cycles:
		if not cycle is Dictionary or not cycle.get("id") is String or cycle.id.is_empty() or ids.has(cycle.id): return false
		ids[cycle.id] = true
		for key in ["first_turn","period"]:
			if not preload("res://engine/native_event_flags.gd").integer(cycle.get(key),1,255): return false
		for side in ["off","on"]:
			var patch: Variant = cycle.get(side)
			if not patch is Dictionary or patch.get("cycle_id") != cycle.id or not patch.get("image") is String: return false
			for key in ["x","y","width","height"]:
				if not preload("res://engine/native_event_flags.gd").integer(patch.get(key),0,255): return false
			if patch.width < 1 or patch.height < 1 or patch.y+patch.height > rows.size() or patch.x+patch.width > rows[0].length(): return false
			if not patch.get("terrain") is Array or patch.terrain.size() != int(patch.height) or not patch.get("mask") is Array or patch.mask.size() != int(patch.height): return false
			for y in range(int(patch.height)):
				if not patch.terrain[y] is String or patch.terrain[y].length() != int(patch.width) or not patch.mask[y] is Array or patch.mask[y].size() != int(patch.width): return false
				if not patch.mask[y].all(func(v):return v is bool): return false
	return true
