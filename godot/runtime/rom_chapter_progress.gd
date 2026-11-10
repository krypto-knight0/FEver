extends RefCounted
## Bind simple chapter completion and quotes to the player's cartridge tables.
## Resource paths and unit/event IDs remain engine identities, not ROM payloads.
const Groups = preload("res://runtime/rom_deployments.gd")
const Flow = preload("res://runtime/rom_event_flow.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const QUOTES := {"battle":[0x79454,12],"death":[0x79550,16],"defeat_script":[0x7955c,12]}

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("ROM chapter progress",reason)
	return null

static func flag(d: RefCounted, value: int) -> int:
	if value in [0,100]: return 0
	if Flags.valid_id(value): return value
	fail(d,"Unsupported chapter completion flag.")
	return -1

static func quote(d: RefCounted, kind: String, chapter: int, character: int, live_script: bool = false, story_route: int = 1) -> Variant:
	var main_script: bool = kind == "defeat_script" and story_route > 1 and d.layout.has("defeat_script_main")
	var layout: Array = d.layout.defeat_script_main if main_script else d.layout.get("quote_layouts",QUOTES)[kind]
	var at := Groups.pointer(d,int(layout[0]))
	if at < 0: return null
	var found: Dictionary = {}
	for row in range(512):
		if not d.require_range(at,int(layout[1]),"Chapter quote"): return null
		if d.u8(at) == 0: return found
		var scope: int = d.u8(at+1)
		# 0x43 is the native all-chapters sentinel, including the main campaigns.
		if d.u8(at) == character and scope in [chapter,int(d.layout.get("quote_all_chapters",67)),255]:
			# The Japanese dispatcher returns the first eligible row, allowing
			# chapter-specific quotes to precede the all-chapters fallback.
			if live_script and d.layout.get("event_variant","") in ["fe7j","fe7u"] and not found.is_empty(): return found
			if not found.is_empty() or d.u16(at+2) != 0: return fail(d,"Quote has ambiguous or conditional eligibility.")
			var completion: int = 0
			var parts: Array = []
			if kind == "defeat_script":
				# The tutorial defeat table owns a script, even though its dialogue
				# is essential in free control. Do not enable tutorial input control.
				var script := Groups.pointer(d,at+4)
				if script < 0: return null
				if live_script:
					if flag(d,d.u32(at+8)) < 0: return null
					found = {"script":script,"flag":flag(d,d.u32(at+8)) if main_script else 0,"offset":at}
					# The native main-campaign lookup takes the first eligible row:
					# a chapter-specific defeat overrides the following generic one.
					if main_script: return found
					at += int(layout[1])
					continue
				var flow := Flow.new(); flow.decoder = d
				var program: Variant = flow.script(script)
				if program == null: return null
				var clear_faces := false
				for entry in program.code:
					if entry.opcode not in [0xd,9,10] or entry.words.size() != (2 if entry.opcode == 0xd else 1):
						return fail(d,"Defeat quote script has unsupported gameplay effects.")
					if entry.opcode == 9: clear_faces = true
					if entry.opcode == 0xd:
						var part := {"text":{"event":entry.offset,"opcode":0xd,"word":1}}
						if clear_faces: part.reset = true
						parts.append(part); clear_faces = false
				# This field controls the native tutorial event; it is not asserted
				# by the free-control death quotation adapter.
				if flag(d,d.u32(at+8)) < 0: return null
			else:
				if kind == "death" and live_script and d.layout.get("event_variant","") in ["fe7j","fe7u"] and d.u32(at+8) != 0:
					if d.u16(at+4) != 0 or d.u16(at+6) != 0 or d.u16(at+14) != 0: return fail(d,"Unsupported combined death text and event.")
					var script := Groups.pointer(d,at+8)
					completion = flag(d,d.u16(at+12))
					if script < 0 or completion < 0: return null
					return {"script":script,"flag":completion,"offset":at}
				if d.u16(at+6) != 0 or (kind == "death" and d.u32(at+8) != 0) or d.u16(at+int(layout[1])-2) != 0:
					return fail(d,"Quote has an unsupported attached event.")
				completion = flag(d,d.u16(at+(8 if kind == "battle" else 12)))
				if completion < 0: return null
				if d.u16(at+4) != 0: parts.append({"text":{"id":d.u16(at+4)}})
			found = {"parts":parts,"flag":completion,"offset":at}
		at += int(layout[1])
	return fail(d,"Quote table has no bounded terminator.")

