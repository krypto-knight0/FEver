extends RefCounted
## Bind victory to the cartridge's ending-event conditions, not map order.
const Groups = preload("res://runtime/rom_deployments.gd")
var compiler: RefCounted

func conditions(result: Dictionary, report: Dictionary) -> bool:
	var d: RefCounted = compiler.d
	var ending := int(report.roots.ending)
	result.objective = {"type":"event","event_id":"unbound_native_objective"}
	for row in report.conditions.turn:
		var target := Groups.pointer(d,int(row.offset)+4)
		if target == int(report.roots.opening): continue
		var entry: Dictionary = compiler.turn_event(row)
		if target == ending:
			if not entry.has("turn") or entry.phase != "player" or not entry.conditions.is_empty() or int(entry.turn) < 2:
				d.fail("FE7 progression","Unsupported timed ending condition."); return false
			result.objective = {"type":"survive","turns":int(entry.turn)-1}
			result.objective_text = "Survive %d turns" % (int(entry.turn)-1)
		else: result.events.append(entry)
	for row in report.conditions.always:
		var at := int(row.offset)
		var target := Groups.pointer(d,at+4)
		var required: int = d.u16(at+8)
		if int(row.kind) == 11:
			var area: Dictionary = compiler.event(target,"enter_region",int(row.flag))
			area.search_on_wait = true
			area.native_repeat = true # A false phase check must not consume an unflagged area.
			area.actor_faction = "any" # Native rectangle scripts decide which phase/actor qualifies.
			if area.native_program.get("scripts",[]).any(func(commands):return commands.any(func(c):return c.get("test",{}).get("kind") in ["desert_find","active_dead"])):
				# Treasure searches and fort captures resolve after the actor finishes.
				area.native_action_search = true
				area.actor_faction = "player"
				result.native_search_events = true
			area.region = [d.u8(at+8),d.u8(at+9),d.u8(at+10),d.u8(at+11)]
			if area.region[0] > area.region[2] or area.region[1] > area.region[3]:
				d.fail("FE7 progression","Invalid native region.",at); return false
			result.events.append(area)
			continue
		if int(row.kind) == 14 and target != ending:
			var conditional: Dictionary = compiler.event(target,"native_flag",int(row.flag))
			conditional.conditions = {"native_unit_presence":[compiler.Native.predicate(d,d.u32(at+8),compiler.chapter_index)]}
			result.events.append(conditional)
			continue
		if int(row.kind) == 14 and target == ending:
			if not compiler.Native.rout(d,d.u32(at+8)): return false
			result.objective = {"type":"rout"}
			continue
		if int(row.kind) != 1:
			d.fail("FE7 progression","Unsupported always condition.",at); return false
		if required == 101:
			if not compiler.Native.game_over(d,target): return false
		if target == ending:
			if result.objective.type == "survive":
				result.objective.alternative_native_flag = required
				var record: int = d.ptr(int(d.layout.chapters))+compiler.chapter_index*int(d.layout.chapter_stride)
				result.objective_text = d.text(d.u16(record+int(d.layout.get("chapter_objective",138))))
			else: result.objective = {"type":"native_flag","flag":required}
			continue
		# Tutorials tag themselves with the native tutorial command. Failure and
		# story events must remain visible when the player skips lessons.
		var entry: Dictionary = compiler.event(target,"native_flag",int(row.flag))
		entry.conditions = {"native_flags_all":[required]}
		result.events.append(entry)
	if compiler.requests_victory:
		result.objective = {"type":"native_event"}
		var record: int = d.ptr(int(d.layout.chapters))+compiler.chapter_index*int(d.layout.chapter_stride)
		result.objective_text = d.text(d.u16(record+int(d.layout.get("chapter_objective",138))))
	return d.error.is_empty()
