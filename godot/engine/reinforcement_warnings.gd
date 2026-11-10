extends RefCounted
## Forecast only phase dispatch on a disposable battle. No RNG, flags, rewards,
## positions or fired-event records in the live battle are changed by warnings.
static func cells(state: RefCounted) -> Array[Vector2i]:
	if not state.rules.get("warn_enemy_reinforcements", false) or state.phase != "player" or not state.outcome.is_empty(): return []
	# Selection and terrain inspection do not change event inputs. Reuse the
	# forecast until the live state changes; never cache across battle objects.
	var key := hash([state.turn, state.phase, state.outcome, state.gold, state.units, state.chapter, state.rules, state.pending_moves, state.fired_events, state.native_event_state, state.native_event_turns, state.native_events_ready, state.interactions, state.destructibles, state.terrain, state.rng.state])
	if state.has_meta("reinforcement_warning_key") and state.get_meta("reinforcement_warning_key") == key:
		return state.get_meta("reinforcement_warning_cells")
	var result := _forecast(state)
	state.set_meta("reinforcement_warning_key", key)
	state.set_meta("reinforcement_warning_cells", result)
	return result

static func _forecast(state: RefCounted) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not state.rules.get("warn_enemy_reinforcements", false) or state.phase != "player" or not state.outcome.is_empty(): return result
	var preview = state.get_script().new()
	if not preview.restore(state.serialize()): return result
	for id in preview.pending_moves.keys(): preview.cancel_move(id)
	var existing := {}
	for unit in preview.units: existing[str(unit.id)] = true
	for phase in ["enemy", "npc", "player"]:
		preview.phase = phase
		if phase == "player": preview.turn += 1
		preview._run_events("turn")
		for unit in preview.units:
			if unit.faction != "enemy" or existing.has(str(unit.id)) or not preview._on_map(unit): continue
			var cell: Vector2i = preview.position(unit)
			if not result.has(cell): result.append(cell)
	# Region/defeat/flag-triggered arrivals can activate during the player's
	# next action. Mark their possible entrances before that action commits.
	var runner = preload("res://engine/native_event_runner.gd")
	var flags = preload("res://engine/native_event_flags.gd")
	for event in state.chapter.get("events", []):
		if event.get("trigger", "turn") not in ["enter_region","wait_region","position","wait","unit_defeated","native_flag"]: continue
		if state.fired_events.has(str(event.get("id", ""))) and not event.get("native_repeat", false): continue
		if not state._event_conditions(event): continue
		if flags.has_flag(state.native_event_state,int(event.get("native_program",{}).get("completion_flag",0))): continue
		for unit in runner.spawn_templates(event):
			if unit.get("faction", "") != "enemy" or not state.get_unit(str(unit.id)).is_empty(): continue
			var cell := Vector2i(int(unit.x), int(unit.y))
			if unit.has("spawn_near_unit"):
				var anchor: Dictionary = state.get_unit(str(unit.spawn_near_unit))
				if state._on_map(anchor): cell = state.position(anchor)
			if state.in_bounds(cell) and not result.has(cell): result.append(cell)
	return result
