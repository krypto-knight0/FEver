extends RefCounted
## Follow chapter and event references without executing the event interpreter.
## Turn schedules and chapter adapters own occurrence identity and spawn policy.
const LAYOUTS := {
	"fe7":[0x31580, 152, 67, 120, 0x315d4, 0xd72c],
	"fe6":[0x2bb20, 68, 45, 58, 0x2bbcc, 0xe038],
}
const TABLES := {
	"fe7":{"enemies_enm":6, "enemies_ehm":7, "enemies_hnm":8, "enemies_hhm":9,
		"players_enm":10, "players_ehm":11, "players_hnm":12, "players_hhm":13},
	"fe6":{"units":4,"players":5},
}
const CONDITIONS := ["turn", "talk", "objects", "always"]
const MAX_UNITS := 256
const MAX_COMMANDS := 2048

static func integer(value: Variant, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= high and value == int(value)

static func fail(decoder: RefCounted, reason: String) -> int:
	decoder.fail("ROM deployment group", reason)
	return -1

static func pointer(decoder: RefCounted, at: int) -> int:
	var target: int = decoder.ptr(at)
	if target < 0 or target % 4 != 0 or not decoder.require_range(target, 4, "Deployment pointer"):
		decoder.fail("ROM deployment group", "Invalid deployment or event pointer.", at)
		return -1
	return target

static func chapter_events(decoder: RefCounted, game: String, chapter: int) -> int:
	var layout: Array = decoder.layout.get("deployment_layout",LAYOUTS[game])
	var table := pointer(decoder, layout[0])
	if table < 0: return -1
	var record := table + chapter * int(layout[1])
	if not decoder.require_range(record, layout[1]): return -1
	var event_id: int = decoder.u8(record + int(layout[3]))
	if event_id == 0: return fail(decoder, "Chapter has no event group.")
	var events := pointer(decoder, layout[4])
	return pointer(decoder, events + event_id * 4) if events >= 0 else -1

static func script_root(decoder: RefCounted, events: int, spec: Dictionary, game: String) -> int:
	var event: String = str(spec.get("event", ""))
	if event == "ending" or (event == "opening" and game == "fe7"):
		if spec.has("condition"): return fail(decoder, "Direct events cannot select a condition.")
		return pointer(decoder, events + (24 if game == "fe6" else (56 if event == "opening" else 60)))
	if event not in CONDITIONS or not integer(spec.get("condition"), 127):
		return fail(decoder, "Invalid chapter event selector.")
	var at := pointer(decoder, events + CONDITIONS.find(event) * 4)
	if at < 0: return -1
	for row in range(int(spec.condition) + 1):
		var kind: int = decoder.u16(at)
		if not decoder.error.is_empty(): return -1
		if kind == 0: return fail(decoder, "Chapter event condition is missing.")
		var size := 16 if game == "fe7" and (event == "talk" or (event == "turn" and kind != 1)) else 12
		if not decoder.require_range(at, size): return -1
		if row == int(spec.condition):
			if event == "objects" and decoder.u8(at + 10) in [19, 20, 21]:
				return fail(decoder, "Shop data is not an event script.")
			return pointer(decoder, at + 4)
		at += size
	return -1

static func command(decoder: RefCounted, start: int, index: int, game: String) -> Dictionary:
	var dispatch := pointer(decoder, decoder.layout.get("deployment_layout",LAYOUTS[game])[5])
	if dispatch < 0: return {}
	var at := start
	for i in range(index + 1):
		var opcode: int = decoder.u16(at)
		if opcode > 255:
			fail(decoder, "Unknown event opcode while locating a deployment.")
			return {}
		var words: int = decoder.u32(dispatch + opcode * 8 + 4)
		if words < 1 or words > 16:
			fail(decoder, "Invalid event command width.")
			return {}
		# The filtered FE7 load has an extended route/difficulty form.
		if game == "fe7" and opcode in decoder.layout.get("filtered_loads",[0x34,0x37]) and decoder.u32(at + 4) in [2, 3, 0x10002, 0x10003]: words = 3
		if not decoder.require_range(at, words * 4): return {}
		if i == index: return {"offset":at, "opcode":opcode, "words":words}
		if opcode in ([10, 11] if game == "fe7" else [6]):
			fail(decoder, "Deployment command lies beyond the event terminator.")
			return {}
		at += words * 4
	return {}

static func group_start(decoder: RefCounted, spec: Dictionary, game: String) -> int:
	var events := chapter_events(decoder, game, int(spec.chapter))
	if events < 0: return -1
	if spec.has("table"):
		if spec.size() != 2 or not TABLES[game].has(spec.table): return fail(decoder, "Invalid native deployment table selector.")
		return pointer(decoder, events + int(TABLES[game][spec.table]) * 4)
	if decoder.layout.get("event_variant","") == "fe7j":
		return fail(decoder,"Japanese FE7 script-selected groups require the dynamic event adapter.")
	var script := script_root(decoder, events, spec, game)
	if script < 0: return -1
	var visited := {script:true}
	for index in spec.get("calls", []):
		var event_call := command(decoder, script, int(index), game)
		if event_call.is_empty(): return -1
		if game != "fe7" or event_call.opcode not in [0x58, 0xcb] or event_call.words != 2: return fail(decoder, "Expected a direct event call.")
		script = pointer(decoder, int(event_call.offset) + 4)
		if script < 0: return -1
		if visited.has(script): return fail(decoder, "Cyclic deployment event path.")
		visited[script] = true
	var load_command := command(decoder, script, int(spec.command), game)
	if load_command.is_empty(): return -1
	var at := int(load_command.offset)
	if game == "fe7" and load_command.opcode == 0x35:
		if load_command.words != 5 or not integer(spec.get("slot"), 3): return fail(decoder, "Invalid route deployment selector.")
		return pointer(decoder, at + (int(spec.slot) + 1) * 4)
	if spec.has("slot"): return fail(decoder, "Only route loads accept a slot selector.")
	if load_command.opcode not in ([0x32, 0x33, 0x34, 0x36, 0x37] if game == "fe7" else [0x12, 0x13]):
		return fail(decoder, "Expected a unit-load command.")
	if load_command.words not in ([2, 3] if game == "fe7" else [2]): return fail(decoder, "Invalid unit-load width.")
	return pointer(decoder, at + (int(load_command.words) - 1) * 4)

static func group(decoder: RefCounted, spec: Variant, game: String) -> Array:
	if not decoder.error.is_empty(): return []
	if not LAYOUTS.has(game) or not spec is Dictionary or not integer(spec.get("chapter"), int(LAYOUTS[game][2]) - 1):
		fail(decoder, "Invalid deployment chapter selector.")
		return []
	for key in spec:
		if key not in ["chapter", "table", "event", "condition", "calls", "command", "slot"]:
			fail(decoder, "Unknown deployment group selector.")
			return []
	if not spec.has("table"):
		if not integer(spec.get("command"), MAX_COMMANDS - 1) or not spec.get("calls", []) is Array or spec.get("calls", []).size() > 16:
			fail(decoder, "Invalid deployment command selector.")
			return []
		for index in spec.get("calls", []):
			if not integer(index, MAX_COMMANDS - 1):
				fail(decoder, "Invalid deployment call selector.")
				return []
	# Memoization belongs to this decoder/ROM load only, never to disk. Returning
	# copies prevents one adapter from changing another adapter's group members.
	var memo: Dictionary = decoder.get_meta("deployment_groups", {})
	var key := game + JSON.stringify(spec)
	if memo.has(key): return memo[key].duplicate()
	var at := group_start(decoder, spec, game)
	if at < 0: return []
	var result: Array = []
	for i in range(MAX_UNITS):
		var record := at + i * 16
		if not decoder.require_range(record, 16, "Deployment group member"): return []
		if decoder.u8(record) == 0:
			if memo.size() < 2048:
				memo[key] = result.duplicate()
				decoder.set_meta("deployment_groups", memo)
			return result
		if (decoder.u8(record + 3) >> 1) & 3 == 3:
			fail(decoder, "Invalid deployment faction.")
			return []
		result.append(record)
	fail(decoder, "Deployment group has no bounded terminator.")
	return []

static func address(decoder: RefCounted, spec: Variant, game: String) -> int:
	if not spec is Dictionary or not integer(spec.get("index"), MAX_UNITS - 1): return fail(decoder, "Invalid deployment member selector.")
	var selector: Dictionary = spec.duplicate()
	selector.erase("index")
	var members := group(decoder, selector, game)
	if not decoder.error.is_empty(): return -1
	if int(spec.index) >= members.size(): return fail(decoder, "Required deployment member is missing from its ROM group.")
	return int(members[int(spec.index)])
