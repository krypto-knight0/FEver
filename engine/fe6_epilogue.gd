extends RefCounted
## Read native ending conversations and the PID-indexed character summaries.
## Map choreography, rendered monologue graphics and scrolling credits are not
## emulated here. No ending prose or character outcomes are shipped as text.
const Groups = preload("res://runtime/rom_deployments.gd")
const Reader = preload("res://runtime/fe6/rom_fe6_events.gd")
const Routes = preload("res://runtime/fe6/rom_fe6_routes.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Runner = preload("res://engine/native_event_runner.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const Army = preload("res://engine/army_roster.gd")

static func story(b, d) -> Array:
	var result: Array = []
	if d == null or not d.error.is_empty(): return result
	var parts: Array = []
	var presentation := {"scene_type":"dialogue", "background":""}
	var table := Groups.pointer(d,0x6e328)
	if table < 0: return result
	var ending := clampi(int(b.chapter.get("fe6_ending",2)),0,2)
	var root := Groups.pointer(d,table+ending*4)
	var visited := {}
	for chain in range(8):
		if root < 0 or visited.has(root): d.fail("FE6 epilogue","Invalid ending script chain."); return []
		visited[root] = true
		var code := Reader.commands(d,root)
		var labels := {}
		for i in range(code.size()):
			if code[i].opcode == 0x1b: labels[d.u32(int(code[i].offset)+4)] = i
		var pc := 0; var next := -1
		for step in range(4096):
			if pc >= code.size(): break
			var entry: Dictionary = code[pc]; pc += 1
			var at := int(entry.offset); var op := int(entry.opcode)
			var a: int = d.u32(at+4) if entry.words > 1 else 0
			if op == 6: break
			if op in [7,8]:
				parts.append({"text":{"id":a},"set":presentation.duplicate(true)})
			elif op in [3,4]: presentation.background = "res://content/fe6/rom/backgrounds/%03d.png" % a
			elif op == 5: presentation.background = ""
			elif op in [0x36,0x37]: presentation["music"] = "" if a == 0 else "song_%03x" % a
			elif op == 0x25: next = Groups.pointer(d,at+4); break
			elif op in [0x1c,0x1f,0x20,0x22,0x23]:
				if not labels.has(a): d.fail("FE6 epilogue","Missing branch label."); return []
				var take := op == 0x1c
				if not take:
					var operand: int = d.u32(at+8)
					var value: bool
					if op in [0x22,0x23]: value = Flags.has_flag(b.native_event_state,operand)
					elif operand == 0x0806dec5:
						if not Pure.signature(d,0x6dec4,52,[],"584530ac3f6ab9d154181531b250787b1baa22255ec17f3c3d055a6ad05b5eaf"): d.fail("FE6 epilogue","Marriage callback changed."); return []
						var pair: Array = ["fe6_unit_%d" % d.u8(0x6decc),"fe6_unit_%d" % d.u8(0x6ded4)]; pair.sort()
						value = int(b.support_ranks.get("|".join(pair),0)) > d.u8(0x6dee2)
					else:
						var query: Variant = Routes.query(d,operand)
						if query == null: return []
						value = Runner.test_value(b,b.native_event_state,query,{})
					take = value == (op in [0x1f,0x22])
				if take: pc = labels[a]
		if not d.error.is_empty(): return []
		if next < 0: break
		root = next
	var reader := preload("res://runtime/rom_story_data.gd").new()
	if not reader.configure(d,"fe6"): return []
	var dialogue: Variant = reader.read({"game":"fe6","parts":parts},func(value):return value)
	return dialogue if dialogue is Array and d.error.is_empty() else []

static func pages(b, d) -> Array:
	var result: Array = []
	if d == null or not d.error.is_empty(): return result
	# The table lookup is the same PID-indexed layout used by the native getter.
	var people := Groups.pointer(d,0x9187c)
	if people < 0: return []
	var seen := {}
	var candidates: Array = Army.all_units(b).duplicate()
	candidates.append_array(b.chapter.get("campaign_roster",{}).values())
	var roster: Array = []
	for unit in candidates:
		var pid := int(unit.get("rom_character_id",0))
		# The native table has 0x42 records, including the unused PID-zero row.
		# PID 0x42 is already outside it (e.g. a preview-only story character).
		if unit.get("faction") != "player" or pid < 1 or pid >= 0x42 or seen.has(pid): continue
		seen[pid] = true
		roster.append(unit)
	roster.sort_custom(func(a,z):return int(a.rom_character_id) < int(z.rom_character_id))
	for unit in roster:
		var pid := int(unit.rom_character_id)
		var at := people+pid*8
		if not d.require_range(at,8,"Character ending record"): return []
		var pair: Array = ["fe6_unit_1",str(unit.id)]; pair.sort()
		var alive: bool = int(unit.hp) > 0 or not b.rules.get("permadeath",true) or unit.get("casualty_mode","") == "injured"
		# +4 is the short ending for an undeployed survivor, not a death record.
		var offset := 4 if unit.get("benched",false) else 0
		if int(b.support_ranks.get("|".join(pair),0)) >= 3 and d.u16(at+2) != 0: offset = 2
		var tid: int = d.u16(at+offset)
		if tid == 0: tid = d.u16(at)
		if tid == 0: continue
		var text: String = d.text(tid).replace("\n"," ").strip_edges() if alive else "%s did not survive the campaign." % str(unit.name)
		var title: String = d.text(d.u16(at+6)).strip_edges() if d.u16(at+6) != 0 else str(unit.name)
		if not text.is_empty(): result.append({"title":title,"text":text,"units":[unit]})
	return result if d.error.is_empty() else []
