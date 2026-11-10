extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## Bounded regional FE7 event compiler. Tutorial input locks are relaxed; native
## event combat, dialogue and progression remain cartridge-driven.
const Groups = preload("res://runtime/rom_deployments.gd")
const Runner = preload("res://engine/native_event_runner.gd")
const Native = preload("res://runtime/fe7/fe7_dynamic_native.gd")
const Scene = preload("res://runtime/rom_story_scene.gd")
const Difficulty = preload("res://runtime/fe7/fe7_dynamic_difficulty.gd")
const MAX_SCRIPTS := 128
const WIDTHS := {1:1,2:1,4:1,5:1,9:1,10:1,11:1,12:1,13:2,0x11:2,0x14:1,0x17:3,0x1c:1,0x24:3,0x26:3,0x30:2,0x34:2,0x37:3,0x39:1,0x3b:1,0x3c:2,0x40:2,0x42:2,0x43:2,0x4f:2,0x52:2,0x64:2,0x69:2,0x6d:2,0x74:1,0x75:1,0x76:1,0x79:2,0x7a:1,0x7f:1,0x87:1,0x88:1,0x8c:1,0x8d:1,0x90:1,0x91:1,0x9f:2,0xa0:2,0xa1:1,0xa2:2,0xa3:2,0xa5:3,0xa8:1,0xa9:2,0xd2:3,0xd6:1,0xd8:1,0xd9:1}
var d: RefCounted
var data: RefCounted
var names := {}
var destinations := {}
var chapter_index := 0
var native_route := 1
var presentation := false
var ending_offset := -1
var requests_victory := false
var compiled_scripts: Array = []
var script_ids := {}

func fail(reason: String) -> void:
	d.fail("FE7 dynamic events",reason)

static func effect(key: String, value: Variant) -> Dictionary:
	return {"op":"effect","effect":{key:value}}

func text(id: int, state: Dictionary, tutorial: bool) -> Array:
	if state.get("ambiguous",false) or state.has("route_yes") or state.has("branch_test"): fail("Continued dialogue 0x%x requires one retained portrait state." % id); return []
	var reader := preload("res://runtime/rom_dialogue_controls.gd").new()
	var pages := reader.read(d,"fe7",names,id,"Tactician",state)
	var choice := false
	var argument := false
	for token in preload("res://runtime/rom_dialogue_controls.gd").tokenize(d,"fe7",id):
		if choice and not (token[1] and int(token[0]) in [0,1,2]): fail("Native choice must end its dialogue."); return []
		if argument: argument = false; continue
		if token[1] and int(token[0]) in [16,128]: argument = true; continue
		if token[1] and int(token[0]) in [24,25]: choice = true
	state.clear(); state.merge({"slot":reader.slot,"faces":reader.faces})
	for page in pages:
		page.tutorial = tutorial
		page.skip_group = "fe7_text_%d" % id
		for key in ["portrait","left_portrait","right_portrait"]:
			if not str(page.get(key,"")).is_empty():
				page[key] = str(page[key]).replace("res://content/fe7/",data.prefix)
				data.assets[page[key]] = {"kind":"portrait","id":int(str(page[key]).get_file().get_basename())}
	if choice:
		if pages.is_empty(): fail("Native choice has no prompt."); return []
		pages[-1].native_choice = true
		pages[-1].tutorial = false
		pages[-1].skip_stop = true
	return pages

func continued_text(id: int, state: Dictionary, tutorial: bool) -> Dictionary:
	if state.has("branch_test"):
		var test: Dictionary = state.branch_test
		var yes_state: Dictionary = state.branch_yes.duplicate(true)
		var no_state: Dictionary = state.branch_no.duplicate(true)
		var command := {"op":"conditional_dialogue","test":test,"yes":text(id,yes_state,tutorial),"no":text(id,no_state,tutorial)}
		state.clear()
		state.merge(yes_state if yes_state == no_state else {"branch_test":test,"branch_yes":yes_state,"branch_no":no_state})
		return command
	if state.has("route_yes"): return route_text(id,id,state,tutorial,false)
	return effect("dialogue",text(id,state,tutorial))

func route_text(eli: int, hec: int, state: Dictionary, tutorial: bool, reset: bool) -> Dictionary:
	var yes_state: Dictionary = {} if reset else state.get("route_yes",state).duplicate(true)
	var no_state: Dictionary = {} if reset else state.get("route_no",state).duplicate(true)
	var command := {"op":"conditional_dialogue","test":{"kind":"route","value":2},"yes":text(eli,yes_state,tutorial),"no":text(hec,no_state,tutorial)}
	state.clear()
	state.merge(yes_state if yes_state == no_state else {"route_yes":yes_state,"route_no":no_state})
	return command

func background(id: int, cg: bool) -> Dictionary:
	var path := "res://content/fe7/rom/scenes/%s_%03d.png" % ["cg" if cg else "background",id]
	var recipe: Variant = Scene.asset(d,path)
	path = path.replace("res://content/fe7/",data.prefix)
	if recipe != null: data.assets[path] = recipe
	return effect("dialogue",[{"text":"","native_control":true,"background":path,"scene_type":"cg" if cg else "dialogue"}])

func program(start: int, completion: int = 0, lesson: bool = false, scene: bool = false) -> Dictionary:
	presentation = scene
	compiled_scripts = []; script_ids = {}
	compile_script(start,lesson,chapter_index)
	if not d.error.is_empty(): return {}
	var result := {"version":1,"completion_flag":completion,"scripts":compiled_scripts}
	var error := Runner.validate(result,"fe7")
	if not error.is_empty(): fail(error); return {}
	return result

func compile_script(start: int, lesson: bool, scene_chapter: int) -> int:
	var key := "%x:%d:%s" % [start,scene_chapter,lesson]
	if script_ids.has(key): return script_ids[key]
	if compiled_scripts.size() >= 64: fail("Too many called scripts."); return 0
	var identity := compiled_scripts.size()
	script_ids[key] = identity; compiled_scripts.append([])
	compiled_scripts[identity] = compile_commands(start,lesson,scene_chapter)
	return identity

func compile_commands(start: int, lesson: bool, scene_chapter: int) -> Array:
	if start+80 <= d.rom.size() and Native.Pure.actual_signature(d,start,80,[],"f0a15670b18b9ea9a160323510d61631861d91d0b520f4c8f747f6a888cacaad"):
		return [{"op":"defeat"},{"op":"end"}]
	var body := script(d,start)
	var command_widths := widths()
	var labels := {}
	var native_positions := {}
	var commands: Array = []
	var state := {}
	var tutorial := lesson
	var last_patch := -1
	for entry in body:
		var op := int(entry.opcode)
		var at := int(entry.offset)
		native_positions[at] = commands.size()
		var filtered: bool = op in [0x32,0x35] and entry.words in [2,3]
		if not command_widths.has(op) or (entry.words != command_widths[op] and not filtered): fail("Unsupported command/width 0x%x at 0x%x." % [op,at]); return []
		var a := int(entry.operands[1]) if entry.words > 1 else 0
		var b := int(entry.operands[2]) if entry.words > 2 else 0
		var high := int(entry.operands[0])>>16
		var c := {"op":"nop"}
		match op:
			10,11:
				if op == 11 and presentation:
					var record: int = d.ptr(int(d.layout.chapters))+chapter_index*int(d.layout.chapter_stride)
					var header := Groups.chapter_events(d,"fe7",chapter_index)
					if start == Groups.pointer(d,header+56) and d.u8(record+13) != 0:
						var normal := {"op":"fe7_prepare","players":data.group(Groups.pointer(d,header+Difficulty.bank(native_route,true))),"enemies":data.group(Groups.pointer(d,header+Difficulty.bank(native_route,false)),false,true)}
						var hard := {"op":"fe7_prepare","players":data.group(Groups.pointer(d,header+Difficulty.bank(native_route,true,true))),"enemies":data.group(Groups.pointer(d,header+Difficulty.bank(native_route,false,true)),false,true)}
						append_modes(commands,normal,hard)
				c = {"op":"end"}
			5: c = background(high,false)
			9:
				state.clear()
				c = effect("dialogue",[{"text":"","native_control":true,"background":"","scene_type":"dialogue"}])
			13,0xe,0x11,0x17,0x18,0xd2,0xd3,0xd4:
				if op not in [0x11,0x18,0xd4]: state.clear()
				# There is no player tactician-gender setting; use the first native
				# variant, as the original importer does for its default tactician.
				c = continued_text(a,state,tutorial)
			0xa5,0xa6:
				# System/tutorial bubbles create their own text context.
				state.clear(); c = effect("dialogue",text(b,state,true))
			0x16,0x101:
				# Native tactics-rating advice has three variants. The port has no
				# campaign ranking ledger; use its middle evaluation for this house.
				if high > 4: fail("Unsupported rating dialogue selector."); return []
				var table := Groups.pointer(d,at+4)
				if not d.require_range(table,12,"FE7 rating dialogue"): return []
				for index in range(3):
					if d.u32(table+index*4) <= 0 or d.u32(table+index*4) > 65535: fail("Invalid rating dialogue text."); return []
				if op == 0x16: state.clear()
				c = effect("dialogue",text(d.u32(table+4),state,tutorial))
			0x15:
				var table := Groups.pointer(d,at+4)
				var characters: int = d.ptr(int(d.layout.record_layout[0]))
				var selectors := {}
				c = {"op":"visitor_dialogue","pages":{}}
				for index in range(253):
					var record := characters+index*52
					if not d.require_range(record,52,"FE7 switch visitor"): return []
					if d.u8(record+4) != index+1 or d.u16(record) == 0: continue
					var selector: int = d.u8(record+48)
					if not d.require_range(table+selector*4,4,"FE7 visitor speech"): return []
					if not selectors.has(selector): selectors[selector] = text(d.u32(table+selector*4),{},tutorial)
					c.pages[str(index+1)] = selectors[selector]
				state.clear()
			0xd6: c = background(high,true)
			0xdc,0xdd: c = background(a,op == 0xdd)
			0xde:
				if not presentation or a&0xffff0000: fail("Unsupported CG-to-map transition."); return []
				c = effect("dialogue",[{"text":"","native_control":true,"background":"","scene_type":"map","scene_actions":[{"type":"focus","x":a&255,"y":(a>>8)&255}]}])
			0xcd,0xce:
				# Warp animation only. The adjacent LOAD/MOVE/REMOVE commands own
				# unit state, including timed retreats and cutaway scenes.
				if high != 0 or b not in [0,1]: fail("Unsupported warp presentation."); return []
				c = {"op":"focus","character":a} if op == 0xce else effect("dialogue",[{"text":"","native_control":true,"scene_actions":[{"type":"focus","x":signed16(a),"y":signed16(a>>16)}]}])
			0xcc: c = {"op":"call","script":compile_script(Groups.pointer(d,at+4),tutorial,scene_chapter)}
			0x56:
				var target := Groups.pointer(d,at+4)
				if target == ending_offset and not presentation:
					requests_victory = true
					commands.append({"op":"fe7_victory"})
					c = {"op":"end"}
				else: c = {"op":"tail","script":compile_script(target,tutorial,scene_chapter)}
			0x57,0x58:
				# Native proc+0x56 is a count of following commands to skip, not
				# an ASM return register or label. Resolve after IR expansion.
				var destination: int = body.find(entry)+high+1
				if destination >= body.size(): fail("Conditional skip exceeds the script."); return []
				c = {"op":"branch","target":int(body[destination].offset),"native_target":true,"when":op == 0x57,"test":Native.predicate(d,a,chapter_index,tutorial)}
			0x1f: c = {"op":"focus","character":{1:3,2:1,3:2}.get(native_route,3)}
			0x1e: c = {"op":"focus","character":high}
			0x1d,0x20: c = effect("dialogue",[{"text":"","native_control":true,"scene_actions":[{"type":"focus","x":high&255,"y":high>>8}]}])
			0x65: c = {"op":"focus","character":a}
			0x7d: c = effect("dialogue",[{"text":"","native_control":true,"rom_sound":high}])
			0x77: c = effect("dialogue",[{"text":"","native_control":true,"save_music":true,"music":"song_%03x" % high}])
			0x78: c = effect("dialogue",[{"text":"","native_control":true,"restore_music":true}])
			8: c = effect("dialogue",[{"text":"","native_control":true,"music":"song_02c"}])
			0x76,0x79: c = effect("dialogue",[{"text":"","native_control":true,"music":"song_%03x" % high}])
			0x7a: c = effect("dialogue",[{"text":"","native_control":true,"music":""}])
			0x30,0x31,0x34:
				# Both deploy native slots. LOU2 is also used for existing party
				# members of scripted arrivals, not just visual actors.
				c = deployment(Groups.pointer(d,at+4),scene_chapter)
				# Some departure scenes LOAD a single actor moving off the map,
				# immediately wait, then erase it. Keep that bounded pattern visual;
				# ordinary reinforcement bounds remain strict.
				var spawned: Array = c.get("effect",{}).get("spawns",[])
				var following := body.find(entry)+1
				while following < body.size() and int(body[following].opcode) in [2,0x39]: following += 1
				if spawned.size() == 1 and (int(spawned[0].x) == 255 or int(spawned[0].y) == 255) and following < body.size() and int(body[following].opcode) == 0x69 and int(body[following].operands[1]) == int(spawned[0].rom_character_id):
					var actor: Dictionary = spawned[0]
					if int(actor.x) == 255: actor.x = -1
					if int(actor.y) == 255: actor.y = -1
					c = effect("dialogue",[{"text":"","native_control":true,"fe6_scene_units":[actor]}])
				if op == 0x31:
					for unit in c.get("effect",{}).get("spawns",[]): unit.native_skip_dead = true
			0x32,0x35:
				if high != 0 or (entry.words == 3 and a not in [2,3,0x10002,0x10003]): fail("Unsupported deployment filter."); return []
				c = deployment(Groups.pointer(d,at+4*(int(entry.words)-1)),scene_chapter)
				if entry.words != 3: fail("Filtered deployment requires a route operand."); return []
				# Native 0x32/0x35 compare the low byte with the story route.
				# Only 0x32 also gates a nonzero high halfword on Hard mode.
				commands.append({"op":"branch","target":commands.size()+2,"absolute":true,"when":false,"test":{"kind":"route","value":a&255}})
				if op == 0x32 and a>>16: c.mode = "hard"
			0x33,0x36:
				# Four native banks: route 2 normal/hard, route 3 normal/hard.
				# Branch targets are IR positions, distinct from native labels.
				for bank in range(4):
					if d.u32(at+4+bank*4) == 0: continue
					commands.append({"op":"branch","target":commands.size()+2,"absolute":true,"when":false,"test":{"kind":"route","value":2 if bank < 2 else 3}})
					var spawn := deployment(Groups.pointer(d,at+4+bank*4),scene_chapter)
					spawn.mode = "normal" if bank%2 == 0 else "hard"
					commands.append(spawn)
			0x2e:
				# Store a scene actor position in native scratch RAM. No supported
				# command reads that RAM; the subsequent moves have explicit targets.
				if not presentation or a < 1 or a > 255 or b > 63: fail("Unsupported scene-position store."); return []
			0x27: c = {"op":"scene_unit","action":"move_next","character":a,"target":b}
			0x21,0x22,0x2c: c = {"op":"scene_unit","action":"move_at","from_x":signed16(a),"from_y":signed16(a>>16),"x":signed16(b),"y":signed16(b>>16)}
			0x24,0x25,0x2d: c = {"op":"scene_unit","action":"move","character":a,"x":signed16(b),"y":signed16(b>>16)}
			0x2a:
				var base := commands.size()
				commands.append({"op":"branch","target":base+3,"absolute":true,"when":false,"test":{"kind":"presence","character":a,"factions":["player"]}})
				commands.append({"op":"scene_unit","action":"move_path","character":a,"steps":movement_steps(d.ptr(at+8))})
				commands.append({"op":"jump","target":base+4,"absolute":true})
				c = {"op":"scene_unit","action":"move_path","character":a,"steps":movement_steps(d.ptr(at+12))}
			0x23,0x26,0x29:
				var ptr: int = d.ptr(at+(12 if op == 0x29 else 8))
				var steps := movement_steps(ptr)
				c = {"op":"scene_unit","action":"move_path","character":a&65535,"steps":steps}
				if op == 0x23: c = {"op":"scene_unit","action":"move_path_at","from_x":signed16(a),"from_y":signed16(a>>16),"steps":steps}
				if op == 0x29:
					# Native 0x29 animates from the current position and then stores
					# its explicit destination. The coordinates are not a path origin.
					commands.append(c)
					c = {"op":"scene_unit","action":"move","character":a&65535,"x":signed16(b),"y":signed16(b>>16)}
			0x37:
				# LOEV is a temporary visual actor; it never acquires inventory or
				# joins the playable army. Stage its native class sprite directly.
				var class_id := (a>>16)&255
				var class_at: int = d.ptr(int(d.layout.record_layout[3]))+class_id*84
				if not d.require_range(class_at,84,"FE7 scene actor"): return []
				var sprite: String = data.prefix+"rom/scene_actor_%d.png" % class_id
				data.assets[sprite] = {"kind":"sprite","id":d.u8(class_at+6),"faction":0}
				c = effect("dialogue",[{"text":"","native_control":true,"fe6_scene_units":[{"id":"scene_%d" % (a&255),"rom_character_id":a&255,"sprite":sprite,"faction":"player","x":b&65535,"y":b>>16}]}])
			0x69,0x6b,0x6d: c = {"op":"scene_unit","action":"withdraw" if op == 0x6d else "remove","character":a}
			0x6a: c = {"op":"scene_unit","action":"remove_at","from_x":signed16(a),"from_y":signed16(a>>16)}
			0x6c:
				if not presentation: fail("Scene withdrawal outside a story scene."); return []
				c = {"op":"scene_unit","action":"remove_at","from_x":signed16(a),"from_y":signed16(a>>16)}
			0x68:
				c = {"op":"scene_unit","action":"remove_at","from_x":signed16(a),"from_y":signed16(a>>16)}
			0x70,0x71:
				if b == 1 and presentation:
					c = {"op":"scene_unit","action":"visibility","character":a,"hidden":op == 0x70}
				elif b == 0x10000 and op == 0x71:
					c = {"op":"scene_unit","action":"return","character":a} # Clear escaped state.
				elif b == 4 and op == 0x70: c = {"op":"fe7_casualty","character":a}
				elif b == 2 and op == 0x71: c = {"op":"scene_unit","action":"refresh","character":a}
				elif b in [2,0x10000] and op == 0x70: c = {"op":"fe7_unit_state","character":a,"field":"acted" if b == 2 else "escaped","value":true}
				elif b == 0x400000 and op == 0x71 and presentation:
					# Retain a recruited actor even when the opening uses a cutaway map.
					var header := Groups.chapter_events(d,"fe7",chapter_index)
					c = {"op":"fe7_retain_actor","character":a,"fallback":data.group(Groups.pointer(d,header+(48 if native_route == 3 else 40)))}
				elif b == 0x800 and op == 0x70: c = {"op":"fe7_ballista","character":a}
				else: fail("Unsupported unit-state mask."); return []
			0x8b,0xe3,0xe5,0xe6,0xe7,0xea,0xeb,0x94:
				# RGB palette scaling, palette cycling and mosaic fades; native
				# dialogue/CG/map commands continue to own the visible scene.
				if not presentation or high != 0: fail("Display effect outside a story scene."); return []
				if op == 0x94 and b not in [0,1,2]: fail("Unsupported mosaic effect."); return []
			0x80:
				if not preload("res://runtime/fe7/fe7_dynamic_finale.gd").valid_opcode(d,op): return []
				if chapter_index != 47 or not presentation: fail("Campaign ending outside the final chapter."); return []
				for root in preload("res://runtime/fe7/fe7_dynamic_finale.gd").ending_scripts(self):
					commands.append({"op":"call","script":compile_script(root,false,scene_chapter)})
				commands.append({"op":"campaign_end"})
				c = {"op":"end"}
			0x8a,0xdf,0xe0,0xe4:
				if not preload("res://runtime/fe7/fe7_dynamic_finale.gd").valid_opcode(d,op): return []
				if not presentation: fail("Final scene effect outside presentation."); return []
			0xe2:
				if not presentation or high != 0 or not (Native.Pure.signature(d,0x11afc,52,[],"193b1102383ff706a3ace5dabb0443bb2450a52aff233fa3c1b7de23f8af3050") and Native.Pure.signature(d,0xc013c8,40,[],"d84452ec155a5cab7e89329047fcb80521f82cd3b2f2aa2aec4068c0a9dc47a9") and Native.Pure.signature(d,0x11a24,216,[],"578c04a9c123a7c364953066687cbc02661a36f525a3538f808fb9c20b5a442b")):
					fail("Changed scene sprite effect."); return []
			0xe8:
				# Native AP sprite effect; no unit/gameplay state.
				var descriptor := Groups.pointer(d,at+4)
				if not presentation or high != 0 or not d.require_range(descriptor,20,"FE7 scene effect"): fail("Unsupported scene effect."); return []
				for offset in [0,4,8]:
					if d.u32(descriptor+offset) != 0: Groups.pointer(d,descriptor+offset)
			0xe9:
				if not presentation or high != 0: fail("Unsupported scene effect cleanup."); return []
			0x95:
				var mode := int(entry.operands[4])
				if mode not in [0,0x10000,0x1000000,124,125,126,127]: fail("Unsupported scripted combat mode."); return []
				var rounds: Array = []
				if mode != 0x1000000:
					var pointer := Groups.pointer(d,at+12)
					var ended := false
					for index in range(65):
						if not d.require_range(pointer+index*4,4,"FE7 scripted combat"): return []
						var flags: int = d.u16(pointer+index*4)
						var side: int = d.u8(pointer+index*4+2)
						var damage: int = d.u8(pointer+index*4+3)
						if side == 128: ended = true; break
						# Bits 2/3 describe follow-up/retaliation strikes. The supplied
						# damage is final, including critical damage, not a multiplier.
						if flags&~0x80f or side not in [0,1,8,9,10] or damage > 127 or index == 64:
							fail("Unsupported scripted combat hit."); return []
						rounds.append({"counter":bool(side&8),"miss":bool(flags&2),"critical":bool(flags&1),"damage":damage})
						if flags&0x800: rounds[-1].silencer = true
					if not ended: fail("Unterminated scripted combat."); return []
				c = {"op":"scripted_battle","attacker":a,"defender":b,"automatic":mode == 0x1000000,"rounds":rounds}
				if mode == 0x10000: c.ballista = true
				if mode in [124,125,126,127]:
					c.ring = data.item(mode)
					if not c.ring.has("ring_bonuses"): fail("Changed scripted ring effect."); return []
				if scene_chapter != chapter_index: c.scene_only = true
			0x3c,0x3d,0x40:
				c = Native.callback(d,a)
				if c.get("op") == "fe7_finale":
					for command in preload("res://runtime/fe7/fe7_dynamic_finale.gd").commands(self,int(c.address),scene_chapter): append_command(commands,command)
					continue
				if c.get("op") == "fe7_promote": c.character = native_route-1
				if c.get("op") == "fe7_bonus":
					for index in range(1,4): c.items[index] = data.item(int(c.items[index]))
					if c.has("default_without_lyn"): c.default_without_lyn = data.item(int(c.default_without_lyn))
				elif c.get("op") == "fe7_grants":
					for gift in c.gifts: gift.item = data.item(int(gift.item))
			0x43,0x46,0x47,0x4a,0x4b,0x4c,0x4d,0x4e,0x4f,0x50,0x51,0x52,0x53,0x54,0x55:
				if op == 0x43: c = {"op":"jump","target":a}
				elif op in [0x50,0x51]: c = {"op":"branch","target":a,"when":false,"test":{"kind":"choice"}}
				elif op == 0x54: c = {"op":"branch","target":a,"when":true,"test":{"kind":"turn_at_least","value":high}}
				elif op in [0x4d,0x4e]:
					if high != 0: fail("Unsupported route branch variant."); return []
					c = {"op":"branch","target":a,"when":true,"test":{"kind":"route","value":2 if op == 0x4d else 3}}
				elif op == 0x55:
					if high not in [0,1]: fail("Unsupported fielded-unit branch variant."); return []
					c = {"op":"branch","target":a,"when":high == 1,"test":{"kind":"fielded","character":b}}
				elif op == 0x4f: c = {"op":"branch","target":a,"when":high != 0,"test":{"kind":"hard"}}
				elif op == 0x52: c = {"op":"branch","target":a,"when":true,"test":{"kind":"hard"}}
				elif op in [0x46,0x47]:
					c = {"op":"branch","target":a,"when":op == 0x46,"test":Native.predicate(d,b,chapter_index,tutorial)}
				elif op == 0x4c:
					if high not in [0,1]: fail("Invalid active-unit branch."); return []
					if tutorial:
						if high == 1: c = {"op":"jump","target":a} # Skip wrong-unit rejection.
					else: c = {"op":"branch","target":a,"when":high == 1,"test":{"kind":"active","character":b}}
				elif op in [0x4a,0x4b]: c = {"op":"branch","target":a,"when":op == 0x4a,"test":{"kind":"flag","flag":b}}
				elif op == 0x53:
					commands.append({"op":"branch","target":a,"when":false,"test":{"kind":"casualty","character":b}})
					c = {"op":"set","flag":int(entry.operands[3])}
				# Tutorial path always compiles. QoL skips pages, never game effects.
			0x42:
				if labels.has(a): fail("Duplicate native label."); return []
				labels[a] = commands.size()
			0x74,0x75: c = {"op":"set" if op == 0x74 else "clear","flag":high}
			0x5a: c = effect("give_items",[{"unit_id":"fe7_unit_%d" % a,"item":data.item(b)}])
			0x5b:
				if high != 0 or a <= 0 or a > 255: fail("Unsupported party item reward."); return []
				c = effect("give_items",[{"unit_id":"fe7_unit_%d" % {1:3,2:1,3:2}[native_route],"item":data.item(a)}])
			0x59: c = effect("give_item_to_actor",data.item(a))
			0x5c:
				# Zero amount reads a native event register; that variant needs a
				# register model. Nonzero amounts distinguish visitor vs party gold.
				if a <= 0 or high not in [0,1]: fail("Unsupported native gold source."); return []
				c = {"op":"gold","mode":"active" if high == 0 else "party","amount":a}
			0x5f:
				if high > 15: fail("Unsupported fog radius source."); return []
				c = effect("fog_radius",high)
			0x0f,0x12: c = route_text(a,b,state,tutorial,op == 0x0f)
			0x63:
				if b not in [0,0x40,0x80]: fail("Unsupported native affiliation."); return []
				c = {"op":"faction","character":a,"faction":{0:"player",0x40:"neutral",0x80:"enemy"}[b]}
			0x72,0x73:
				if b>>16: fail("Unsupported AI change parameters."); return []
				var unit := {"source_deployment":{"ai":[b&255,(b>>8)&255,0,0],"offset":"0x%x" % at},"faction":"enemy","ai":"","ai_no_attack":false,"ai_waypoint":[],"ai_waypoint_region":[],"ai_waypoint_reached":false,"ai_excluded_character_ids":[],"npc_talk_target":""}
				if not preload("res://runtime/rom_unit_factory.gd")._ai(d,"fe7",unit): return []
				unit.erase("source_deployment"); unit.erase("faction")
				c = {"op":"scene_unit","action":"ai","character":a,"settings":unit}
				if op == 0x73:
					if a&0xff00ff00: fail("Unsupported coordinate AI selector."); return []
					c = {"op":"scene_unit","action":"ai_at","from_x":a&255,"from_y":(a>>16)&255,"settings":unit}
			0x19,0x100:
				if op == 0x100: state.clear()
				var yes_state := state.duplicate(true)
				var no_state := state.duplicate(true)
				c = {"op":"conditional_dialogue","test":{"kind":"flag","flag":a},"yes":text(b,yes_state,tutorial),"no":text(int(entry.operands[3]),no_state,tutorial)}
				# A later MORETEXT requires one unambiguous face state.
				state = yes_state if yes_state == no_state else {"branch_test":c.test,"branch_yes":yes_state,"branch_no":no_state}
			0x1a,0x1b:
				if op == 0x1a: state.clear()
				var test := Native.predicate(d,a,chapter_index,tutorial)
				if not d.error.is_empty(): return []
				if test.kind == "constant": c = effect("dialogue",text(b if test.value else int(entry.operands[3]),state,tutorial))
				else:
					var yes_state := state.duplicate(true)
					var no_state := state.duplicate(true)
					c = {"op":"conditional_dialogue","test":test,"yes":text(b,yes_state,tutorial),"no":text(int(entry.operands[3]),no_state,tutorial)}
					state = yes_state if yes_state == no_state else {"branch_test":c.test,"branch_yes":yes_state,"branch_no":no_state}
			0x99,0x9a: c = effect("weather",high)
			0x9b,0x9c:
				if high > 15: fail("Unsupported fog radius."); return []
				c = effect("fog_radius",high)
			0x5d:
				if high == 0x8000:
					if last_patch < 0: fail("Map restoration without a preceding patch."); return []
					c = effect("map_change",data.patch(chapter_index,last_patch,true))
				else:
					last_patch = high
					c = effect("map_change",data.patch(chapter_index,high))
			0x60,0x62:
				if high == 0xffff: fail("Map change requires a preceding coordinate lookup."); return []
				# Both commands apply the indexed patch. Bit 15 updates the native
				# persistence list; the port persists the resulting terrain directly.
				c = effect("map_change",data.patch(chapter_index,high&0x7fff))
			0x61:
				if high not in [0,1]: fail("Unsupported map refresh mode."); return []
			0x5e:
				var locations := preload("res://runtime/fe7/fe7_dynamic_locations.gd").new(); locations.compiler = self
				if not locations.read_patches(): return []
				var matches: Array = locations.patches.filter(func(p):return (high&255) >= p.x and (high&255) < p.x+p.width and (high>>8) >= p.y and (high>>8) < p.y+p.height)
				if matches.is_empty(): fail("No native map change at command coordinates."); return []
				# GetMapChangeIdAt scans the complete table, retaining the last hit.
				c = effect("map_change",matches[-1])
			0x93:
				# Native palette fade process (speed, mode, wait). Scene transitions
				# handle the port's fade; this command has no persistent map effects.
				if not presentation or b not in [0,1,2]: fail("Unsupported palette fade."); return []
			0x82,0x83:
				if not presentation: fail("Map cutaway outside a story scene."); return []
				# Ending cutaway maps are presentation only; MNCH selects the actual
				# campaign destination. Never replace the playable battle's map.
				var map_id := a if op == 0x82 else high
				scene_chapter = map_id
				var path: String = data.prefix+"maps/scene_%d.png" % map_id
				data.assets[path] = {"kind":"map","chapter":map_id}
				c = effect("dialogue",[{"text":"","native_control":true,"background":path,"scene_type":"dialogue"}])
				var scene_map: Variant = preload("res://runtime/rom_data.gd").map_fields(d,{"chapter":map_id,"fields":["width","height","terrain"]},"fe7")
				if scene_map == null: return []
				var scene_terrain := {}
				for row in scene_map.terrain:
					for symbol in row: scene_terrain[symbol] = {"id":preload("res://runtime/rom_data.gd").SYMBOLS.find(symbol)}
				scene_map.native_battle_terrain = data.terrain_art(map_id,scene_terrain)
				c.effect.dialogue[0].fe7_scene_map = scene_map
			0xda: c = effect("dialogue",[{"text":d.text(a),"source_text_id":a}])
			0x7f:
				if not destinations.has(high): fail("Unsupported next chapter %d." % high); return []
				c = {"op":"destination","path":destinations[high]}
			0x81:
				# Native game-control mode 3 exits the tutorial campaign. The main-story
				# reset/roster handoff is selected through the chapter route choices.
				if not presentation or chapter_index != 11 or high != 0: fail("Unsupported campaign-segment handoff."); return []
				c = {"op":"destination","path":""}
			0x88: tutorial = true
			0x97:
				if not presentation or a != 0x08000001+Policy.address(d,0x4110): fail("Unsupported ending display process."); return []
			0x3a: pass # Camera-follow toggle; scene motion owns the port's camera.
			0x85: pass # Native skip lock; the port always allows skipping presentation.
			0x48,0x49: pass # Native event-skip branch/flag; effects compile before presentation is skipped.
			0xa0:
				# Prescribed battle outcomes are intentionally disabled in free
				# control mode. Still bound and validate this native data stream.
				var ptr := Groups.pointer(d,at+4)
				var ended := false
				for round_index in range(64):
					if not d.require_range(ptr+round_index*4,4,"FE7 tutorial battle"): return []
					if d.u32(ptr+round_index*4)&0x800000: ended = true; break
				if not ended: fail("Unterminated tutorial battle data."); return []
			# Timers, fades, volume ducking, camera cursors and map display,
			# plus deliberately relaxed tutorial input locks.
			1,2,4,12,0x14,0x1c,0x39,0x3b,0x64,0x87,0x8c,0x8d,0x90,0x91,0x9f,0xa1,0xa2,0xa3,0xa8,0xa9,0xab,0xac,0xd8,0xd9,0x7b,0x7c,0x92,0x98,0x84,0x8e,0x8f,0xdb: pass
			_: fail("Unadapted native event command."); return []
		if scene_chapter != chapter_index and c.get("op") == "scene_unit":
			c = effect("dialogue",[{"text":"","native_control":true,"fe6_scene_command":c}])
		if not d.error.is_empty(): return []
		if c.get("effect",{}).get("dialogue",[]).any(func(page):return page.get("native_choice",false)):
			for page in c.effect.dialogue:
				if page.get("native_choice",false): commands.append({"op":"choice","page":page})
				else: commands.append(effect("dialogue",[page]))
			continue
		append_command(commands,c)
	for command in commands:
		if command.op in ["jump","branch"]:
			if command.get("native_target",false):
				command.erase("native_target"); command.target = native_positions[command.target]; continue
			if command.get("absolute",false): command.erase("absolute"); continue
			if not labels.has(command.target): fail("Missing native branch label."); return []
			command.target = labels[command.target]
	return commands

func append_modes(commands: Array, normal: Dictionary, hard: Dictionary) -> void:
	if normal == hard: commands.append(normal); return
	var start := commands.size()
	commands.append({"op":"branch","target":start+3,"when":true,"absolute":true,"test":{"kind":"hard"}})
	commands.append(normal)
	commands.append({"op":"jump","target":start+4,"absolute":true})
	commands.append(hard)

func append_command(commands: Array, command: Dictionary) -> void:
	if command.get("op") not in ["fe7_retain_actor","fe7_final_formation"]:
		commands.append(command); return
	var header := Groups.chapter_events(d,"fe7",chapter_index)
	var hard := command.duplicate(true)
	hard.fallback = data.group(Groups.pointer(d,header+Difficulty.bank(native_route,true,true)))
	append_modes(commands,command,hard)

func deployment(pointer: int, scene_chapter: int) -> Dictionary:
	var units: Array = data.group(pointer,scene_chapter != chapter_index)
	if scene_chapter == chapter_index: return effect("spawns",units)
	# Units on a cutaway map are actors, not deployments on the battle map.
	# In particular they must not acquire new items or withdraw the carried party.
	var map: Variant = preload("res://runtime/rom_data.gd").map_fields(d,{"chapter":scene_chapter,"fields":["width","height"]},"fe7")
	if map == null: return {"op":"nop"}
	# Native cutaways reuse groups from larger maps, then reposition their
	# actors. Offscreen starting coordinates are valid for these visual actors.
	return effect("dialogue",[{"text":"","native_control":true,"fe6_scene_units":units}])

static func signed16(value: int) -> int:
	value &= 65535
	return value-65536 if value >= 32768 else value

func movement_steps(pointer: int) -> Array:
	var result: Array = []
	for count in range(512):
		var step: int = d.u8(pointer); pointer += 1
		if step == 4: return result
		if step in [0,1,2,3]: result.append([[-1,0],[1,0],[0,1],[0,-1]][step])
		elif step in [9,12]: pointer += 1
		elif step != 10: fail("Unsupported movement bytecode."); return []
	fail("Unterminated movement path."); return []

static func widths() -> Dictionary:
	var result := WIDTHS.duplicate()
	result.merge({0x8b:1,0x6c:2,0xe3:5,0xe:2,0xe5:4,0xe6:1,0xe7:1,0xea:4,0xeb:1,0x94:4,0x2e:3,0xcd:3,0xce:3,0xde:2,0x5b:2,0x48:2,8:1,0x46:3,0x47:3,0x4a:3,0x4c:3,0xa6:4,0x4b:3,0x53:4,0x65:2,0x78:1,0x7b:1,0x7c:1,0x7d:1,0x92:1,0x98:1,0xcc:2,0xdc:3,0xdd:3,0xd4:3,0x25:4,0x29:4,0x2d:3,0x5a:3,0x5d:1,0x82:4,0x83:1,0x84:1,0x8e:1,0x8f:1,0xda:3,0xdb:1})
	result.merge({0x18:3,0x19:4,0x1a:4,0x1b:4,0x1d:1,0x1e:1,0x21:3,0x22:4,0x23:3,0x2c:3,0x32:2,0x35:2,0x36:5,0x4d:2,0x4e:2,0x55:3,0x56:2,0x59:2,0x63:3,0x99:1,0x9a:1})
	result.merge({0x0f:3,0x3a:1,0x3d:2,0x5c:2,0x72:3,0x77:1})
	result.merge({0x60:1,0x61:1,0x62:1})
	result[0x85] = 1
	result.merge({0x2a:4,0x57:2,0x58:2})
	result.merge({0x95:5,0x71:3,0xe2:3,0x6b:2,0x15:2,0x6a:2,0x31:2,0x54:2,0x50:2,0x51:2,0x5f:1,0x70:3})
	result.merge({0x49:2,0x9b:1,0x9c:1,0x81:1,0x73:3,0xe8:3,0xe9:1,0x16:2,0x12:3,0x33:5,0x20:1,0x27:3})
	result.merge({0x68:2,0x5e:1,0x93:4,0x1f:1,0x80:1,0x8a:1,0xdf:2,0xe4:3})
	result.merge({0xe0:2,0x101:2,0x100:4,0x97:2,0xd3:4,0xab:1,0xac:2})
	return result

func event(start: int, trigger: String, flag: int = 0, lesson: bool = false) -> Dictionary:
	return {"id":"fe7_event_%x_%s" % [start,trigger],"trigger":trigger,"native_program":program(start,flag,lesson,trigger in ["chapter_start","victory"])}

func turn_event(row: Dictionary, lesson: bool = false) -> Dictionary:
	var at := int(row.offset)
	if int(row.kind) == 1:
		# Flag checks in the turn table run on the next phase boundary.
		var flagged := event(Groups.pointer(d,at+4),"turn",int(row.flag),lesson)
		flagged.each_turn = true
		flagged.conditions = {"native_flags_all":[d.u16(at+8)]}
		return flagged
	if int(row.kind) != 2 or d.u32(at+12) > 5 or d.u8(at+10) not in [0,0x80,0x40] or d.u8(at+11) != 0: fail("Unsupported native turn condition."); return {}
	var target := Groups.pointer(d,at+4)
	var first_turn_scene: bool = target != ending_offset and d.u8(at+8) == 1 and d.u8(at+9) == 0 and d.u8(at+10) == 0 and script(d,target).any(func(c):return c.opcode in [0x82,0x83])
	var result: Dictionary
	if first_turn_scene:
		var record: int = d.ptr(int(d.layout.chapters))+chapter_index*int(d.layout.chapter_stride)
		# This scene runs after the player selects their army, so speeches and
		# cutaway formations observe the deployed party rather than the default.
		result = {"id":"fe7_event_%x_turn" % target,"trigger":"preparations" if d.u8(record+13) != 0 else "turn","native_scene":true,"native_program":program(target,int(row.flag),lesson,true)}
	else: result = event(target,"victory" if target == ending_offset else "turn",int(row.flag),lesson)
	result.turn = d.u8(at+8)
	result.phase = {0:"player",0x80:"enemy",0x40:"npc"}[d.u8(at+10)]
	result.conditions = {}
	if d.u8(at+9):
		if d.u8(at+9) < d.u8(at+8): fail("Invalid native turn range."); return {}
		result.erase("turn"); result.each_turn = true; result.native_repeat = true
		result.conditions.merge({"turn_min":d.u8(at+8),"turn_max":d.u8(at+9)})
	var selection: int = d.u32(at+12)
	if selection in [1,2,3,4]: result.conditions.native_unit_presence = [{"kind":"route","value":2 if selection in [1,3] else 3}]
	if selection in [3,4,5]: result.conditions.difficulty = ["hard"]
	return result

func tutorials(chapter: int, events: Array) -> Dictionary:
	var result := {"select":[],"destination":[],"action":[]}
	# Native tutorial directory contains only the twelve tutorial chapter records.
	if chapter >= 12: return result
	var table: int = d.ptr(int(d.layout.tutorials))+chapter*16
	for group in range(4):
		var at := Groups.pointer(d,table+group*4)
		var ended := false
		for index in range(128):
			var kind: int = d.u16(at)
			if kind == 0: ended = true; break
			var size := 16 if group in [1,3] else 12
			if not d.require_range(at,size,"FE7 tutorial condition"): return {}
			var flag: int = d.u16(at+2)
			if group == 3:
				events.append(turn_event({"offset":at,"kind":kind,"flag":flag},true))
			elif group == 1:
				if kind not in [15,16]: fail("Unsupported tutorial destination condition."); return {}
				# Any legal destination satisfies this stage. No rejection dialog,
				# forced cursor, controller mask or command restrictions.
				result.destination.append({"flag":flag,"requires":d.u16(at+12)})
			else:
				if kind != 1: fail("Unsupported tutorial flag condition."); return {}
				var entry := event(Groups.pointer(d,at+4),"tutorial",flag,true)
				entry.requires = d.u16(at+8)
				result["select" if group == 0 else "action"].append(entry)
			at += size
		if not ended: fail("Unterminated tutorial condition table."); return {}
	return result

func quotes(chapter: int, units: Array, events: Array) -> void:
	var progress = preload("res://runtime/rom_chapter_progress.gd")
	var seen := {}
	for unit in units:
		if seen.has(unit.id): continue
		seen[unit.id] = true
		var scripted_death := false
		for kind in ["battle","defeat_script","death"]:
			if kind == "death" and scripted_death: continue
			var quote: Variant = progress.quote(d,kind,chapter,int(unit.rom_character_id),true,native_route)
			if quote == null: return
			if quote.is_empty(): continue
			var compiled := {}
			if quote.has("script"):
				compiled = program(int(quote.script))
				if native_route > 1:
					scripted_death = true
					if int(quote.flag):
						# The native death dispatcher sets this flag after the event.
						# A wrapper preserves that order even for tail transfers.
						compiled = compiled.duplicate(true)
						for script_commands in compiled.scripts:
							for command in script_commands:
								if command.op in ["call","tail"]: command.script = int(command.script)+1
						compiled.scripts.push_front([{"op":"call","script":1},{"op":"set","flag":int(quote.flag)},{"op":"end"}])
			else:
				var pages: Array = []
				for part in quote.parts: pages.append_array(text(int(part.text.id),{},false))
				var commands: Array = [effect("dialogue",pages)]
				if kind == "death" and int(quote.flag): commands.append({"op":"set","flag":int(quote.flag)})
				commands.append({"op":"end"})
				compiled = {"version":1,"scripts":[commands],"completion_flag":int(quote.flag) if kind == "battle" else 0}
			var entry := {"id":"fe7_quote_%s_%s" % [unit.id,kind],"trigger":"battle" if kind == "battle" else "unit_defeated","unit_id":unit.id,"native_program":compiled}
			var error := Runner.validate_event(entry,"fe7")
			if not error.is_empty(): fail(error); return
			events.append(entry)

@warning_ignore("shadowed_variable")
static func script(d: RefCounted, start: int) -> Array:
	var result: Array = []
	var at := start
	for index in range(Groups.MAX_COMMANDS):
		var command := Groups.command(d,at,0,"fe7")
		if command.is_empty(): return []
		command.native_opcode = command.opcode
		if Policy.us(d): command.opcode = preload("res://runtime/fe7/fe7_dynamic_us_profile.gd").opcode(command.opcode)
		command.operands = []
		for word in range(int(command.words)): command.operands.append(d.u32(at+word*4))
		result.append(command)
		if command.opcode in [10,11]: return result
		at += int(command.words)*4
	d.fail("FE7 events","Unterminated event script.",start)
	return []

@warning_ignore("shadowed_variable")
static func inspect(d: RefCounted, chapter: int) -> Dictionary:
	var header := Groups.chapter_events(d,"fe7",chapter)
	if header < 0: return {}
	var roots := {"opening":Groups.pointer(d,header+56),"ending":Groups.pointer(d,header+60)}
	var conditions := {}
	for kind in Groups.CONDITIONS:
		var at := Groups.pointer(d,header+Groups.CONDITIONS.find(kind)*4)
		var rows: Array = []
		var ended := false
		for index in range(128):
			var opcode: int = d.u16(at)
			if opcode == 0: ended = true; break
			var size := 16 if kind == "talk" or (kind == "turn" and opcode != 1) else 12
			if not d.require_range(at,size,"FE7 event condition"): return {}
			var row := {"offset":at,"kind":opcode,"flag":d.u16(at+2),"data":[]}
			for word in range(0,size,4): row.data.append(d.u32(at+word))
			rows.append(row)
			# Object rows can contain item IDs/shop lists, not scripts. Retain
			# their raw operands until the corresponding semantic adapter exists.
			if kind != "objects":
				var target: int = d.u32(at+4)
				if target >= 0x08000000 and target < 0x0a000000:
					roots["%s_%d" % [kind,index]] = Groups.pointer(d,at+4)
			at += size
		if not ended: d.fail("FE7 events","Unterminated condition table."); return {}
		conditions[kind] = rows
	var scripts := {}
	for name in roots:
		var at := int(roots[name])
		if at < 0 or not d.error.is_empty(): return {}
		if scripts.has(str(at)): continue
		if scripts.size() >= MAX_SCRIPTS: d.fail("FE7 events","Too many script roots."); return {}
		scripts[str(at)] = script(d,at)
		if not d.error.is_empty(): return {}
	return {"chapter":chapter,"header":header,"roots":roots,"conditions":conditions,"scripts":scripts,"execution_supported":false}
