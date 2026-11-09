extends RefCounted
## Optional lessons without GBA input locks. Native flags still connect the
## selection, destination and action lessons. Progress lives in chapter state
## so saves/Undo preserve it, independently of the UI's tutorial-skip setting.
const Flags = preload("res://engine/native_event_flags.gd")
const Runner = preload("res://engine/native_event_runner.gd")

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not Runner.keys(value,["select","destination","action"]): return false
	for kind in value:
		if not value[kind] is Array or value[kind].size() > 128: return false
		for row in value[kind]:
			if not row is Dictionary or not Flags.valid_id(row.get("requires"),"any","fe7"): return false
			if kind == "destination":
				if not Runner.keys(row,["flag","requires"]) or not Flags.valid_id(row.flag,"chapter","fe7"): return false
			elif not Runner.keys(row,["id","trigger","native_program","requires"]) or row.trigger != "tutorial" or not Runner.validate_event(row,"fe7").is_empty(): return false
	return true

static func notify(b, kind: String, unit_id: String) -> bool:
	if not b.chapter.get("dynamic_rom",false) or not b.chapter.has("fe7_tutorials") or not b.native_events_ready: return false
	var unit: Dictionary = b.get_unit(unit_id)
	if b.phase != "player" or not b.outcome.is_empty() or unit.get("faction") != "player" or unit.get("acted",false): return false
	var lessons: Dictionary = b.chapter.fe7_tutorials
	var before: int = b.dialogue_queue.size()
	if kind == "select":
		# Reselecting/cancelling must not consume the next turn's lesson chain.
		if int(b.chapter.get("fe7_lesson_selection_turn",0)) == b.turn: return false
		if dispatch(b,lessons.select,unit_id): b.chapter.fe7_lesson_selection_turn = b.turn
	elif kind == "action":
		for row in lessons.destination:
			if Flags.has_flag(b.native_event_state,int(row.requires)) and not Flags.has_flag(b.native_event_state,int(row.flag)):
				Flags.set_flag(b.native_event_state,int(row.flag))
				break
		dispatch(b,lessons.action,unit_id)
	return b.dialogue_queue.size() > before

static func dispatch(b, rows: Array, unit_id: String) -> bool:
	for row in rows:
		if not Flags.has_flag(b.native_event_state,int(row.requires)) or Flags.has_flag(b.native_event_state,int(row.native_program.completion_flag)): continue
		var applied := Runner.execute(b,row,{"unit_id":unit_id})
		if applied: b._run_events("native_flag",{"unit_id":unit_id})
		return applied
	return false
