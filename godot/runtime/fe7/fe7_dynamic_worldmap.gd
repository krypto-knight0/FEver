extends RefCounted
## Compile bounded native world-map paths. Route is fixed by the chapter;
## campaign-flag branches remain live in the shared atomic event interpreter.
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Dialogue = preload("res://runtime/rom_dialogue_controls.gd")
const WIDTHS := {0:1,2:1,0x14:1,0x40:2,0x42:2,0x43:2,0x4a:3,0x4b:3,0x4d:2,0x4e:2,0x7a:1,0x85:1,0x87:1,0x97:2,0xad:4,0xae:1,0xaf:1,0xb2:5,0xb3:4,0xb4:2,0xb5:1,0xb6:1,0xb7:1,0xb8:5,0xb9:3,0xba:4,0xbd:2,0xbe:5,0xbf:2,0xc2:4,0xc3:3,0xc4:3,0xc5:3,0xc9:4,0xca:2,0xcb:1}
const HELPERS := [[0xb6dcc,32,"fc99325d737550c4b01f69b5f8e53ce332695c7c4652afe1221a05a37ae20e35"],[0xb6450,20,"bc94377e0bdcfe40db9d13eda30bc29fd5393f9e45241f60717f4c1ba6b2eaec"],[0xb3dd4,16,"991982a4034aa149368452763a1a16308968e75ca165be720cc6e5fb7a0948c4"]]
var compiler: RefCounted
var code: Array = []
var labels := {}
var flags: Array = []
var root := 0

func fail(reason: String) -> void:
	compiler.d.fail("FE7 world map",reason,root)

static func known_helper(d: RefCounted, pointer: int) -> bool:
	for helper in HELPERS:
		if Policy.identity(d,(pointer-0x08000000)&~1) == helper[0] and pointer&1: return Policy.signature(d,helper[0],helper[1],[],helper[2])
	return false

func attach(opening: Dictionary) -> void:
	var d: RefCounted = compiler.d
	var record: int = d.ptr(int(d.layout.chapters))+compiler.chapter_index*int(d.layout.chapter_stride)
	var id: int = d.u8(record+int(d.layout.deployment_layout[3])+1)
	if id == 0: return
	for helper in HELPERS:
		if not compiler.Native.Pure.signature(d,helper[0],helper[1],[],helper[2]): fail("Changed world-map helper."); return
	root = d.ptr(d.ptr(int(d.layout.world_events))+id*4)
	var at := root
	var ended := false
	for index in range(512):
		var command := Groups.command(d,at,0,"fe7")
		if command.is_empty(): return
		var op: int = preload("res://runtime/fe7/fe7_dynamic_us_profile.gd").opcode(command.opcode) if Policy.us(d) else command.opcode
		if not WIDTHS.has(op) or command.words != WIDTHS[op]: fail("Unsupported command 0x%x." % op); return
		var words: Array = []
		for word in range(int(command.words)): words.append(d.u32(at+word*4))
		words[0] = (int(words[0])&0xffff0000)|op
		if op == 0x42:
			if labels.has(words[1]): fail("Duplicate branch label."); return
			labels[words[1]] = code.size()
		if op in [0x4a,0x4b] and not flags.has(words[2]): flags.append(words[2])
		code.append(words)
		at += int(command.words)*4
		if op == 0: ended = true; break
	if not ended or flags.size() > 3: fail("Unbounded world-map program."); return
	var scripts: Array = []
	decision(scripts,0,[])
	if not d.error.is_empty(): return
	# Root wrapper, existing opening scripts, then world-map decision tree.
	var program: Dictionary = opening.native_program
	var base: int = program.scripts.size()+1
	for commands in program.scripts:
		for command in commands:
			if command.op in ["call","tail"]: command.script = int(command.script)+1
	for commands in scripts:
		for command in commands:
			if command.op in ["call","tail"]: command.script = int(command.script)+base
	program.scripts.push_front([{"op":"call","script":base},{"op":"effect","effect":{"dialogue":[{"text":"","native_control":true,"background":"","scene_type":"map","worldmap":{},"clear_portraits":true}]}},{"op":"call","script":1},{"op":"end"}])
	program.scripts.append_array(scripts)
	var error: String = compiler.Runner.validate(program,"fe7")
	if not error.is_empty(): fail(error)

func decision(scripts: Array, depth: int, active: Array) -> int:
	var index := scripts.size()
	scripts.append([])
	if depth == flags.size():
		var pages := presentation(active)
		scripts[index] = [{"op":"effect","effect":{"dialogue":pages}},{"op":"end"}]
	else:
		var yes := active.duplicate(); yes.append(flags[depth])
		var yes_id := decision(scripts,depth+1,yes)
		var no_id := decision(scripts,depth+1,active)
		scripts[index] = [{"op":"branch","target":2,"when":true,"test":{"kind":"flag","flag":flags[depth]}},{"op":"tail","script":no_id},{"op":"tail","script":yes_id}]
	return index

func presentation(active: Array) -> Array:
	var path: Array = []
	var pc := 0
	for step in range(1024):
		if pc < 0 or pc >= code.size(): fail("Invalid branch destination."); return []
		var words: Array = code[pc]; pc += 1
		var op := int(words[0])&65535
		if op == 0: break
		if op in [0x43,0x4a,0x4b,0x4d,0x4e]:
			if not labels.has(words[1]): fail("Missing branch label."); return []
			var jump: bool = op == 0x43 or (op == 0x4d and compiler.native_route == 2) or (op == 0x4e and compiler.native_route == 3)
			if op in [0x4a,0x4b]: jump = active.has(words[2]) == (op == 0x4a)
			if jump: pc = labels[words[1]]
		else: path.append(words)
		if step == 1023: fail("World-map branch cycle."); return []
	var pages: Array = []
	var pending: Array = []
	var actors := {}
	var faces := {}
	var dots := {}
	var view := [0,0,240,160]
	var mode := 0
	var text_id := 0
	var generations := {}
	for words in path:
		var op := int(words[0])&65535
		match op:
			0x97,0x40:
				if not known_helper(compiler.d,int(words[1])): fail("Unknown world-map helper."); return []
			0xad:
				mode = int(words[1]); view = [int(words[2])&65535,int(words[2])>>16,240,160]
				if mode not in [0,1,2]: fail("Unsupported map display mode."); return []
			0xc9:
				mode = int(words[2])&65535
				if mode not in [0,1,2]: fail("Unsupported map expansion mode."); return []
				view = [int(words[1])&65535,int(words[1])>>16,240,160]
			0xc2:
				view = [int(words[1])&65535,int(words[1])>>16,240,160]
			0xb2: faces[int(words[1])] = int(words[2])
			0xb3: faces.erase(int(words[1]))
			0xbe: dots[str(words[1])] = {"point":[int(words[2])&65535,int(words[2])>>16],"palette":int(words[3])}
			0xbf: dots.erase(str(words[1]))
			0xb8:
				var slot := str(words[1]); var cl := int(words[3])&255
				if cl:
					var previous := slot+"_"+str(generations.get(slot,0))
					if actors.has(previous): actors[previous].end_page = pages.size()
					generations[slot] = int(generations.get(slot,0))+1
					var created := slot+"_"+str(generations[slot])
					actors[created] = actor(cl,int(words[3]),created,pages.size())
				var key := slot+"_"+str(generations.get(slot,0))
				if not actors.has(key): fail("World-map actor moved before creation."); return []
				actors[key].source_route.append([int(words[2])&65535,int(words[2])>>16])
				actors[key].waypoint_pages.append(pages.size())
			0xb9:
				var slot := str(words[1]); var key := slot+"_"+str(generations.get(slot,0))
				if actors.has(key): actors[key].end_page = pages.size()
			0xb4:
				while not pending.is_empty(): emit_fragment(pages,pending.pop_front(),text_id,mode,view,faces,dots)
				text_id = int(words[1]); pending = fragments(text_id)
			0x14:
				if not pending.is_empty(): emit_fragment(pages,pending.pop_front(),text_id,mode,view,faces,dots)
			0xcb:
				while not pending.is_empty(): emit_fragment(pages,pending.pop_front(),text_id,mode,view,faces,dots)
			# Fades, delays, region highlights and silhouettes are presentation
			# embellishments. Narration cues, portraits, camera and journeys survive.
			_: pass
	while not pending.is_empty(): emit_fragment(pages,pending.pop_front(),text_id,mode,view,faces,dots)
	for index in range(pages.size()):
		pages[index].worldmap.merge({"journey_id":"%x_%s_%d" % [root,str(active),compiler.native_route],"actors":actors.values(),"animation_manifest":compiler.data.prefix+"movement.json","page_index":index,"page_count":pages.size()})
	if not pages.is_empty(): pages[0].music = "worldmap"
	return pages

func fragments(id: int) -> Array:
	var tokens := Dialogue.tokenize(compiler.d,"fe7",id)
	var result: Array = []; var fragment: Array = []; var index := 0
	while index < tokens.size():
		if tokens[index] == [128,true] and index+1 < tokens.size() and int(tokens[index+1][0]) == 4:
			result.append(fragment); fragment = []; index += 2
		else: fragment.append(tokens[index]); index += 1
	if not fragment.is_empty(): result.append(fragment)
	return result

func emit_fragment(pages: Array, tokens: Array, id: int, mode: int, view: Array, faces: Dictionary, dots: Dictionary) -> void:
	var d: RefCounted = compiler.d
	var prefix: String = compiler.data.prefix
	# Native camera update (0xb4100) clamps the requested origin.
	view = [clampi(int(view[0]),0,784),clampi(int(view[1]),0,528),240,160]
	var background := prefix+"worldmap/%d_%d_%d.png" % [mode,int(view[0]),int(view[1])]
	if mode in [0,2]:
		compiler.data.assets[background] = {"kind":"scene","graphics":[[d.ptr((0xb5e20 if mode == 0 else 0xb5e64) if Policy.us(d) else (0xb6c2c if mode == 0 else 0xb6c70))]],"palette":d.ptr((0xb5e1c if mode == 0 else 0xb5e60) if Policy.us(d) else (0xb6c28 if mode == 0 else 0xb6c6c)),"tsa":d.ptr((0xb5e2c if mode == 0 else 0xb5e70) if Policy.us(d) else (0xb6c38 if mode == 0 else 0xb6c7c)),"crop":[0,0,240,160]}
	else:
		if int(view[0]) < 0 or int(view[1]) < 0 or int(view[0])+240 > 1024 or int(view[1])+160 > 688: fail("Camera outside world-map bounds."); return
		compiler.data.assets[background] = {"kind":"worldmap","crop":view.duplicate()}
	var reader := Dialogue.new()
	var decoded := reader.read(d,"fe7",{},id,"Narrator",{},tokens)
	for page in decoded:
		page.merge({"background":background,"scene_type":"worldmap","skip_group":"fe7_world_%x" % root,"source_event_offset":"0x%x" % root,"speaker":"Narrator","clear_portraits":true,"worldmap":{"viewport":view.duplicate(),"dots":dots.values().duplicate(true)}})
		page.erase("rom_portrait_slots")
		for side in ["left","right"]:
			var slot := 0 if side == "left" else 1
			page[side+"_portrait"] = ""
			if faces.has(slot):
				var portrait := prefix+"rom/portraits/%03d.png" % int(faces[slot])
				compiler.data.assets[portrait] = {"kind":"portrait","id":int(faces[slot])}
				page[side+"_portrait"] = portrait
		page.worldmap_portraits = true
		pages.append(page)

func actor(cl: int, bits: int, key: String, first: int) -> Dictionary:
	var d: RefCounted = compiler.d
	var at: int = d.ptr(int(d.layout.record_layout[3]))+cl*84
	if not d.require_range(at,84,"World-map class") or d.u8(at+4) != cl: fail("Invalid world-map class.")
	var faction := "npc" if bits&0x4000 else ("enemy" if bits&0x2000 else "player")
	var sprite: String = compiler.data.prefix+"rom/sprites/%03d_%s" % [d.u8(at+6),faction]
	compiler.data.assets[sprite+".png"] = {"kind":"sprite","id":d.u8(at+6),"faction":["player","enemy","npc"].find(faction)}
	compiler.data.assets[sprite+"_idle.png"] = {"kind":"sprite","id":d.u8(at+6),"faction":["player","enemy","npc"].find(faction),"idle":true}
	return {"id":key,"rom_class_id":cl,"faction":faction,"style":(bits>>16)&255,"sprite":sprite+".png","sprite_idle":sprite+"_idle.png","source_route":[],"waypoint_pages":[],"start_page":first}
