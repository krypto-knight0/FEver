extends RefCounted
## Bounded FE7 event selection. ASM predicates are never executed or guessed.
const Data = preload("res://runtime/rom_data.gd")
const Deployments = preload("res://runtime/rom_deployments.gd")
const Predicates = preload("res://runtime/rom_event_predicates.gd")
const CONTROL_WIDTHS := {0x44:2,0x45:2,0x48:3,0x49:3,0x4a:2,0x4b:2,0x4c:3,0x4d:3,0x4e:3,0x4f:2,0x50:2,0x51:2,0x58:2,0xcb:2,0x76:1,0x77:1}
var decoder: RefCounted
var context := {}
var flags := {}
var stack: Array = []
var result: Array = []
var budget := 0
var started := false
var stopped := false
var selection := {}
var occurrences := {}

func fail(reason: String) -> Variant:
	decoder.fail("ROM event flow",reason)
	return null

func pointer(at: int) -> int:
	var value: int = decoder.ptr(at)
	if value < 0 or value%4 or not decoder.require_range(value,4,"Event pointer"):
		fail("Invalid event pointer.")
		return -1
	return value

func root(source: Variant) -> int:
	if not source is Dictionary:
		fail("Invalid event source.")
		return -1
	if source.size() == 1 and Data.integer(source.get("address")) and int(source.address)%4 == 0: return int(source.address)
	if not Data.integer(source.get("chapter"),0,66) or source.get("event") not in ["opening","ending","worldmap","turn","talk","objects","always"]:
		fail("Invalid chapter event source.")
		return -1
	var conditional: bool = source.event in ["turn","talk","objects","always"]
	if source.size() != (3 if conditional else 2) or (conditional and not Data.integer(source.get("condition"),0,127)):
		fail("Invalid event condition selector.")
		return -1
	if source.event == "worldmap":
		var chapters := pointer(0x31580)
		var table := pointer(0xb561c)
		if chapters < 0 or table < 0: return -1
		var at := chapters+int(source.chapter)*152
		if not decoder.require_range(at,152,"World-map chapter"): return -1
		return pointer(table+decoder.u8(at+121)*4)
	var events := Deployments.chapter_events(decoder,"fe7",int(source.chapter))
	return Deployments.script_root(decoder,events,source,"fe7") if events >= 0 else -1

func script(at: int) -> Variant:
	var dispatch := pointer(0xd72c)
	if dispatch < 0: return null
	var code: Array = []
	var labels := {}
	for i in range(2048):
		if not decoder.require_range(at,4,"Event command"): return null
		var op: int = decoder.u16(at)
		if op > 255: return fail("Unknown event opcode.")
		var width: int = decoder.u32(dispatch+op*8+4)
		if width < 1 or width > 16: return fail("Invalid native event command width.")
		if op in [0x34,0x37] and decoder.u32(at+4) in [2,3,0x10002,0x10003]: width = 3
		if width < int(CONTROL_WIDTHS.get(op,1)) or not decoder.require_range(at,width*4,"Event operands"): return fail("Truncated event control command.")
		var words: Array = []
		for word in range(width): words.append(decoder.u32(at+word*4))
		code.append({"offset":at,"opcode":op,"words":words})
		if op == 0x44:
			if width != 2 or labels.has(words[1]): return fail("Duplicate or invalid event label.")
			labels[words[1]] = code.size()-1
		if op in [0,10,11]: return {"code":code,"labels":labels}
		at += width*4
	return fail("Event terminator not found within the command limit.")

func read(source: RefCounted, spec: Variant, game: String) -> Variant:
	decoder = source
	if game != "fe7" or not spec is Dictionary or not spec.get("source") is Dictionary: return fail("Invalid event-flow recipe.")
	for key in spec:
		if key not in ["source","context","start","stop","after","before"]: return fail("Unknown event-flow field.")
	var supplied: Variant = spec.get("context",{})
	if not supplied is Dictionary: return fail("Invalid event context.")
	context = supplied
	for key in context:
		if key not in ["route","hard","active","flags","scene_skip","conversation_skip","units","unit_groups"]: return fail("Unknown event context field.")
	if not Data.integer(context.get("route",1),1,3) or not context.get("hard",false) is bool or not Data.integer(context.get("active",0),0,255) or not context.get("flags",[]) is Array or context.get("flags",[]).size() > 1024: return fail("Invalid event context values.")
	if not context.get("scene_skip",false) is bool or not context.get("conversation_skip",false) is bool: return fail("Invalid event skip context.")
	if (context.has("units") or context.has("unit_groups")) and Predicates.snapshot(decoder,context) == null: return null
	flags = {}
	for flag in context.get("flags",[]):
		if not Data.integer(flag,0,65535): return fail("Invalid initial event flag.")
		flags[int(flag)] = true
	for key in ["start","stop"]:
		if spec.has(key) and (not Data.integer(spec[key]) or int(spec[key])%4): return fail("Invalid event range anchor.")
	# Occurrences count executed commands, including calls, on this context's branch.
	# Exclusive boundaries let scene ranges follow relocated native scripts without
	# storing the cinematic commands' addresses or preventing additions inside them.
	if (spec.has("start") and spec.has("after")) or (spec.has("stop") and spec.has("before")): return fail("Conflicting event range boundaries.")
	for key in ["after","before"]:
		if not spec.has(key): continue
		var marker: Variant = spec[key]
		if not marker is Dictionary or marker.size() != 2 or not Data.integer(marker.get("opcode"),0,255) or not Data.integer(marker.get("occurrence"),1,8192): return fail("Invalid event command boundary.")
	selection = spec
	started = not spec.has("start") and not spec.has("after")
	stopped = false
	occurrences = {}
	stack = []
	result = []
	budget = 0
	var at := root(spec.source)
	if at < 0 or not decoder.error.is_empty(): return null
	if not execute(at): return null
	if not started or ((spec.has("stop") or spec.has("before")) and not stopped): return fail("Event range anchor was not reached on the selected branch.")
	return result

func boundary_matches(key: String, opcode: int) -> bool:
	if not selection.has(key): return false
	var marker: Dictionary = selection[key]
	return int(marker.opcode) == opcode and int(marker.occurrence) == int(occurrences[opcode])

func execute(at: int) -> bool:
	if stack.has(at) or stack.size() >= 16:
		fail("Cyclic or excessive event call depth.")
		return false
	stack.append(at)
	var program: Variant = script(at)
	if program == null: return false
	var index := 0
	while index < program.code.size() and not stopped:
		var entry: Dictionary = program.code[index]
		index += 1
		budget += 1
		if budget > 8192:
			fail("Event execution limit exceeded.")
			return false
		var op: int = entry.opcode
		var w: Array = entry.words
		occurrences[op] = int(occurrences.get(op,0))+1
		if boundary_matches("before",op):
			stopped = true
			break
		if entry.offset == selection.get("start",-1): started = true
		if started: result.append(entry)
		if boundary_matches("after",op): started = true
		if entry.offset == selection.get("stop",-1):
			stopped = true
			break
		if op in [0,10,11]: break
		var jump := false
		match op:
			0x45: jump = true
			0x46,0x47:
				fail("Opaque event predicate requires an explicit engine adapter (opcode 0x%x at 0x%x)." % [op,entry.offset])
				return false
			0x48,0x49:
				var answer: Variant = Predicates.evaluate(decoder,int(w[2]),context)
				if answer == null: return false
				jump = answer if op == 0x48 else not answer
			# Native FE7U handlers test event-state bits 0x06 and 0x02 respectively.
			# Import normally uses an unskipped scene; UI skipping remains live engine logic.
			0x4a: jump = context.get("scene_skip",false) or context.get("conversation_skip",false)
			0x4b: jump = context.get("conversation_skip",false)
			0x4c: jump = flags.has(w[2])
			0x4d: jump = not flags.has(w[2])
			0x4e: jump = int(context.get("active",0)) != w[2] if int(w[0])>>16 else int(context.get("active",0)) == w[2]
			0x4f: jump = int(context.get("route",1)) == 2
			0x50: jump = int(context.get("route",1)) == 3
			0x51: jump = bool(int(w[0])>>16) == context.get("hard",false)
			0x76: flags[int(w[0])>>16] = true
			0x77: flags.erase(int(w[0])>>16)
			0x58,0xcb:
				var target := pointer(int(entry.offset)+4)
				if target < 0 or not execute(target): return false
		if jump:
			if not program.labels.has(w[1]):
				fail("Missing event branch label.")
				return false
			index = int(program.labels[w[1]])+1
	stack.pop_back()
	return decoder.error.is_empty()
