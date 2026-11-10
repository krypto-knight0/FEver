extends RefCounted
## Compile bounded FE6 event scripts. No stock chapter/command-index bindings.
const Groups = preload("res://runtime/rom_deployments.gd")
const Reader = preload("res://runtime/fe6/rom_fe6_events.gd")
const Routes = preload("res://runtime/fe6/rom_fe6_routes.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Dialogue = preload("res://runtime/rom_dialogue_controls.gd")
const Scene = preload("res://runtime/rom_story_scene.gd")
const Runner = preload("res://engine/native_event_runner.gd")
const Data = preload("res://runtime/rom_data.gd")
const Native = preload("res://runtime/fe6/fe6_dynamic_native.gd")
const TalkPredicates = preload("res://runtime/fe6/rom_fe6_talk_predicates.gd")
# Only presentation commands with known widths may be discarded.
const VISUAL := {1:1,2:2,10:1,11:2,20:1,21:1,22:1,0x2c:2,0x2d:2,0x2e:2,0x2f:1,0x39:2,0x3a:1,0x3b:1,0x40:1,0x41:1,0x43:2,0x44:2,0x45:2,0x46:2,0x47:1,0x48:1}
var d: RefCounted
var data: RefCounted
var chapter := 0
var destinations := {}
var names := {}
var patches: Array = []
var scripts: Array = []
var addresses := {}
var hard_bonus := false
var opening_start := -1
var chapter_fields := {}
var ending_program := false

func fail(message: String) -> Variant:
	d.fail("FE6 dynamic chapter %d" % chapter,message)
	return null

func text(id: int, state: Dictionary = {}) -> Array:
	var controls := Dialogue.new()
	var pages := controls.read(d,"fe6",names,id,"",state)
	state.clear(); state.merge({"slot":controls.slot,"faces":controls.faces})
	for page in pages:
		page.skip_group = "fe6_text_%d" % id
		register_art(page)
		for key in ["portrait","left_portrait","right_portrait"]:
			if page.has(key) and not str(page[key]).is_empty(): page[key] = str(page[key]).replace("res://content/fe6/",data.prefix)
	return rebase(pages)

func rebase(value: Variant) -> Variant:
	if value is String: return value.replace("res://content/fe6/rom/",data.prefix+"rom/")
	if value is Array: return value.map(rebase)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = rebase(value[key])
		return result
	return value

func register_art(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): register_art(child)
	elif value is Array:
		for child in value: register_art(child)
	elif value is String and value.begins_with("res://content/fe6/rom/portraits/"):
		data.assets[value.replace("res://content/fe6/",data.prefix)] = {"kind":"portrait","id":int(value.get_file().get_basename())}

func program(start: int, completion: int = 0, ending: bool = false) -> Dictionary:
	ending_program = ending
	scripts = []; addresses = {}
	compile_script(start)
	var result := {"version":1,"scripts":scripts,"completion_flag":completion}
	if d.error.is_empty():
		var error := Runner.validate(result,"fe6")
		if not error.is_empty(): fail(error+" Script 0x%x." % start)
	return result

func compile_script(start: int) -> int:
	if addresses.has(start): return addresses[start]
	if scripts.size() >= 64: fail("Too many event subroutines."); return 0
	var index := scripts.size()
	addresses[start] = index; scripts.append([])
	var body := Reader.commands(d,start)
	var labels := {}
	for i in range(body.size()):
		if body[i].opcode == 0x1b:
			var label: int = d.u32(int(body[i].offset)+4)
			if labels.has(label): fail("Duplicate event label."); return index
			labels[label] = i
	var state := {}
	var scene_only := false
	for entry in body:
		if not d.error.is_empty(): return index
		var at := int(entry.offset)
		var op := int(entry.opcode)
		var a: int = d.u32(at+4) if entry.words > 1 else 0
		var b: int = d.u32(at+8) if entry.words > 2 else 0
		var c: Variant = {"op":"nop"}
		var widths := Routes.WIDTHS.merged({0xc:2,0xd:3,0xf:3,0x10:3,0x11:3,0x21:2,0x25:2,0x31:2,0x3f:4,0x49:5})
		if widths.has(op) and entry.words != widths[op]: fail("Changed width for opcode 0x%x at 0x%x." % [op,at]); return index
		match op:
			6: c = {"op":"end"}
			3,4:
				var path := "res://content/fe6/rom/backgrounds/%03d.png" % a
				var recipe: Variant = Scene.asset(d,path)
				path = path.replace("res://content/fe6/",data.prefix)
				data.assets[path] = recipe
				c = effect("dialogue",[{"text":"","native_control":true,"background":path}])
			5: state.clear(); c = effect("dialogue",[{"text":"","native_control":true,"background":""}])
			7,8:
				if op == 7: state.clear()
				c = effect("dialogue",text(a,state))
			0xc: c = {"op":"focus","character":a}
			0xd: c = {"op":"fe6","action":"move_at","from_x":signed_coord(a&65535),"from_y":signed_coord(a>>16),"x":signed_coord(b&65535),"y":signed_coord(b>>16)}
			0xf: c = {"op":"fe6","action":"move","character":a,"x":signed_coord(b&65535),"y":signed_coord(b>>16)}
			0x11: c = {"op":"fe6","action":"move_next","character":a,"target":b}
			0x10:
				var pointer: int = d.ptr(at+8) # Movement bytecode need not be word aligned.
				var steps: Array = []
				var ended := false
				for count in range(512):
					var step: int = d.u8(pointer); pointer += 1
					if step == 4: ended = true; break
					if step in [9,12]: pointer += 1
					elif step == 10: pass
					elif step in [0,1,2,3]: steps.append([[-1,0],[1,0],[0,1],[0,-1]][step])
					else: fail("Unsupported scripted movement command."); return index
				if not ended: fail("Unterminated scripted movement."); return index
				c = {"op":"fe6","action":"move_path","character":a,"steps":steps}
			0x12,0x13: c = effect("spawns",data.group(Groups.pointer(d,at+4)))
			0x17: c = callback(a,at)
			0x19:
				if a != 0x0806d1fd or not Routes.Finale.verify(d,0x6d1fc): fail("Unsupported repeating native callback."); return index
				c = final_speeches()
			0x21: pass # Presentation skip marker; play the scene in full.
			0x1b: pass
			0x1c,0x1f,0x20,0x22,0x23,0x24:
				if not labels.has(a): fail("Missing branch label at 0x%x." % at); return index
				if op == 0x1c: c = {"op":"jump","target":labels[a]}
				else:
					var test: Variant = {"kind":"flag","flag":b} if op in [0x22,0x23] else ({"kind":"active","character":b} if op == 0x24 else query(b))
					c = {"op":"branch","target":labels[a],"test":test,"when":op in [0x1f,0x22,0x24]}
			0x25: c = {"op":"tail","script":compile_script(Groups.pointer(d,at+4))}
			0x26: c = effect("give_item_to_actor",data.item(a))
			0x27: c = effect("give_items",[{"unit_id":"fe6_unit_%d" % a,"item":data.item(b)}])
			0x28: c = {"op":"gold","amount":a,"mode":"party"}
			0x29,0x2a:
				var selected: Array = patches.filter(func(p):return int(p.id) == a) if op == 0x29 else patches.filter(func(p):return a&255 >= p.x and a&255 < p.x+p.width and (a>>8)&255 >= p.y and (a>>8)&255 < p.y+p.height)
				if op == 0x2a:
					var exact := selected.filter(func(p):return int(p.x) == (a&255) and int(p.y) == ((a>>8)&255))
					if exact.size() == 1: selected = exact
				if selected.size() != 1: fail("Missing or ambiguous map change at 0x%x." % at); return index
				c = effect("map_change",selected[0])
			0x2b:
				if b not in [0,64,128]: fail("Invalid faction."); return index
				c = {"op":"faction","character":a,"faction":{0:"player",64:"neutral",128:"enemy"}[b]}
			0x30: c = {"op":"fe6","action":"remove","character":a}
			0x31: c = {"op":"fe6","action":"kill","character":a}
			0x32:
				var u := {"faction":"neutral" if b == 0xc06 else "enemy","source_deployment":{"ai":[b&255,(b>>8)&255]}}
				if not data.base_ai(u): return index
				u.erase("faction"); u.erase("source_deployment")
				c = {"op":"fe6","action":"ai","character":a,"settings":u}
			0x33:
				if b != 0: fail("Unsupported coordinate AI at 0x%x." % at); return index
				c = effect("ai_changes",[{"x":a&65535,"y":a>>16,"ai_mode":"pursue"}])
			0x34,0x35:
				if a not in [0,100]: c = {"op":"set" if op == 0x34 else "clear","flag":a}
			0x36,0x37,0x38:
				c = effect("dialogue",[{"text":"","native_control":true,"music":"player_phase" if op == 0x38 else ("" if a == 0 else "song_%03x" % a)}])
			0x3c: c = effect("rom_sound",a)
			0x3d:
				if not destinations.has(a): fail("Chapter destination %d has no valid chapter record." % a); return index
				c = {"op":"destination","path":destinations[a]}
			0x3e: c = {"op":"fe6","action":"game_end"}
			0x3f:
				if not ending_program: fail("Gameplay map replacement requires a dedicated adapter."); return index
				var map: Variant = Data.map_fields(d,{"chapter":a,"fields":["width","height"]},"fe6")
				if map == null: return index
				var path: String = data.prefix+"maps/scene_%d.png" % a
				data.assets[path] = {"kind":"map","chapter":a}
				c = effect("dialogue",[{"text":"","native_control":true,"scene_type":"map","scene_actions":[{"type":"begin","hide_units":true},{"type":"map_patch","x":0,"y":0,"width":map.width,"height":map.height,"image":path},{"type":"focus","x":b,"y":d.u32(at+12)}]}])
				scene_only = true
			0x4c: c = effect("weather",a)
			0x49:
				if d.u32(at+16) != 0: fail("Unsupported scripted-battle mode."); return index
				var pointer: int = d.ptr(at+12)
				var rounds: Array = []
				var ended := false
				for i in range(64):
					var flags: int = d.u16(pointer+i*4)
					var side: int = d.u8(pointer+i*4+2)
					if side&128: ended = true; break
					if flags&~3 or side not in [0,1,8,9,10]: fail("Unsupported scripted-battle hit."); return index
					rounds.append({"counter":bool(side&8),"miss":bool(flags&2),"critical":bool(flags&1),"damage":d.u8(pointer+i*4+3)})
				if not ended: fail("Unterminated scripted battle."); return index
				c = {"op":"fe6","action":"scripted_battle","attacker":a,"defender":b,"rounds":rounds}
			_:
				if not VISUAL.has(op) or entry.words != VISUAL[op]: fail("Unsupported event opcode 0x%x at 0x%x." % [op,at]); return index
		if c == null: return index
		if scene_only:
			if op in [0x12,0x13]: c = effect("dialogue",[{"text":"","native_control":true,"fe6_scene_units":c.effect.spawns}])
			elif op in [0xd,0xf,0x10,0x30]: c = effect("dialogue",[{"text":"","native_control":true,"fe6_scene_command":c}])
		scripts[index].append(c)
	return index

static func effect(key: String, value: Variant) -> Dictionary:
	return {"op":"effect","effect":{key:value}}

static func signed_coord(value: int) -> int:
	return value-65536 if value >= 32768 else value

func query(address: int) -> Variant:
	return Native.query(d,address) if Native.SIGNATURES.has((address-0x08000000)&~1) else Routes.query(d,address)

func final_speeches() -> Dictionary:
	var pages := {}
	var at: int = d.ptr(0x6b7fc)
	for index in range(256):
		var character: int = d.u8(at+index*16)
		if character in [0,255]: return {"op":"fe6","action":"speeches","pages":pages}
		var id: int = d.u16(at+index*16+12)
		if character != 1 and id and not pages.has(str(character)): pages[str(character)] = text(id)
	fail("Unterminated final speeches.")
	return {}

func callback(address: int, command_at: int) -> Variant:
	if address < 0x08000001 or address&1 == 0: return fail("Invalid Thumb callback pointer.")
	var at := (address-0x08000000)&~1
	if Native.SIGNATURES.has(at):
		if not Native.verify(d,at): return null
		match at:
			0x6ced8: return {"op":"nop"} # Reveal unit; the port renders loaded units immediately.
			0x6cf88: return {"op":"fe6","action":"trap_uses","x":d.u8(at+2),"y":d.u8(at+4),"uses":d.u8(at+16)}
			0x28e28: return {"op":"nop"} # Suspend terrain animation during the opening.
			0x6d55c:
				if d.u8(at+2) != chapter: return fail("Native chapter-state assignment disagrees with the chapter.")
				return {"op":"nop"}
			0x6cfd0: return effect("dialogue",[{"text":"","native_control":true,"music":"song_02a"}])
			0x6d000: chapter_fields.get_or_add("rules",{}).weather_effect = "sandstorm"; return effect("rom_sound",0xc4)
			0x6d01c: return {"op":"nop"} # Stop looping ambience; scene sound is one-shot in the port.
			0x6bfc0: return effect("weather",d.u8(at+2))
			0x6ddd4: return effect("fog_radius",d.u8(at+2))
	if at == 0x6d17c:
		if not Routes.Finale.verify(d,at): return null
		var found := patches.filter(func(p):return d.u8(at+2) >= p.x and d.u8(at+2) < p.x+p.width and d.u8(at+4) >= p.y and d.u8(at+4) < p.y+p.height)
		if found.is_empty(): return fail("Village repair has no map change.")
		return effect("map_change",found[-1])
	if at in [0x6d41c,0x6d568,0x6d648]:
		var traps: Variant = preload("res://runtime/fe6/rom_fe6_traps.gd").read(d,command_at,{0x6d41c:"fire",0x6d568:"poison_gas",0x6d648:"light_arrow"}[at])
		if traps == null: return null
		chapter_fields.hazards = traps
		return {"op":"nop"}
	if command_at == opening_start and at == 0x6d620:
		var cycles: Variant = preload("res://runtime/fe6/rom_fe6_map_cycles.gd").read(d,chapter,command_at)
		if cycles == null: return null
		chapter_fields.map_cycles = cycles
		chapter_fields.initial_map_changes = []
		for cycle in cycles:
			for side in ["on","off"]:
				var patch: Dictionary = cycle[side]
				patch.image = data.patch(chapter,int(patch.id)).image
			chapter_fields.initial_map_changes.append(cycle.off)
		return {"op":"nop"}
	# FE6's initial gold helper: verify instructions, permit the literal to change.
	if at == 0x6bfcc:
		if d.raw(at,20).hex_encode() != "00b5b4f743fd03494018b4f745fd01bc00470000": return fail("Initial gold callback changed.")
		return {"op":"gold","mode":"party","amount":d.u32(at+20)}
	if at == 0x6baf0:
		# Difficulty.parameters validates this routine before bonus prepares variants.
		hard_bonus = true
		return {"op":"nop"}
	return Routes.callback_command(d,address)

func prepare(result: Dictionary, header: int) -> bool:
	opening_start = Groups.pointer(d,Groups.pointer(d,header)+4)
	var seize_rows: Array = []
	for table in range(4):
		var start := Groups.pointer(d,header+table*4)
		var ended := false
		for i in range(128):
			var at := start+i*12
			if not d.require_range(at,12,"FE6 dynamic condition"): return false
			var kind: int = d.u16(at)
			if kind == 0: ended = true; break
			var completion: int = d.u16(at+2)
			var entry := {"id":"fe6_dynamic_%d_%d_%d" % [chapter,table,i]}
			if table == 3 and kind == 1:
				# FE6 defeat conditions call native code, rather than an event script.
				if d.u32(at+8) == 101: continue
				entry.merge({"trigger":"native_flag","native_repeat":true,"conditions":{"native_flags_all":[d.u32(at+8)]}})
				entry.native_program = program(Groups.pointer(d,at+4),completion)
				result.events.append(entry)
				if not d.error.is_empty(): return false
				continue
			if table == 2:
				var action: int = d.u8(at+10)
				var site := {"id":entry.id,"x":d.u8(at+8),"y":d.u8(at+9)}
				# The second village tile is the native pillage target, not a script.
				if action == 29 and kind == 5 and d.u32(at+4) == 1: continue
				if action in [19,20,21]:
					site.type = "armory" if action == 19 else "shop"; site.name = {19:"Armory",20:"Vendor",21:"Secret shop"}[action]; site.stock = []
					if action == 21: site.merge({"member_card_required":true,"hidden":true})
					var stock: Variant = Data.shop_stock(d,at,"fe6")
					if stock == null: return false
					for row in stock: site.stock.append({"item":data.item(int(row.rom_item_id)),"price":row.price})
					result.interactions.append(site); continue
				if action == 18 and kind == 7:
					site.type = "chest"; site.requires_key = true
					attach_changes(site)
					var reward: Variant = Data.chest_reward(d,at,"fe6")
					if reward == null: return false
					if reward.has("rom_item_id"): site.give_item = data.item(int(reward.rom_item_id))
					else: site.reward = reward
					result.interactions.append(site); continue
				if kind == 8:
					site.type = "door"; site.requires_key = true; attach_changes(site); result.interactions.append(site); continue
				if action not in [14,15,16,18] or kind not in [5,6]: fail("Unsupported location event at 0x%x." % at); return false
				entry.merge({"trigger":"visit","x":site.x,"y":site.y})
				if action == 15:
					site.type = "seize"; site.unit_id = "fe6_unit_1"; entry.unit_id = site.unit_id
					seize_rows.append({"x":site.x,"y":site.y,"flag":completion,"terminal":d.u32(at+4) == 1,"event_id":entry.id})
				else:
					site.type = "door" if action == 16 else ("village" if kind == 6 else "house")
					if action == 16: site.requires_key = true
				# This script owns its completion flag. Marking it from the used
				# tile before dispatch would suppress the dialogue and reward.
				site.native_visit_event = true
				attach_changes(site)
				result.interactions.append(site)
				if d.u32(at+4) == 1 and action == 15:
					if completion: entry.native_program = {"version":1,"completion_flag":completion,"scripts":[[{"op":"end"}]]}; result.events.append(entry)
					continue
			elif table == 0:
				if i == 0: entry.trigger = "chapter_start"
				elif kind in [2,3]:
					entry.merge({"trigger":"turn","phase":Reader.PHASES.get(d.u8(at+10),""),"each_turn":true,"native_repeat":true,"conditions":{"turn_min":d.u8(at+8),"turn_max":maxi(d.u8(at+8),d.u8(at+9))}})
					if kind == 3: entry.conditions.merge({"difficulty":["hard"],"native_flags_not":[2]})
				elif kind == 1: entry.merge({"trigger":"native_flag","native_repeat":true,"conditions":{"native_flags_all":[d.u32(at+8)]}})
				elif kind == 13:
					var test: Variant = query(d.u32(at+8))
					if test == null: return false
					entry.merge({"trigger":"turn","phase":"any","each_turn":true,"native_repeat":true,"conditions":{"native_unit_presence":[test]}})
				else: fail("Unsupported turn condition at 0x%x." % at); return false
			elif table == 1:
				if kind == 4: entry.merge({"from":"fe6_unit_%d" % d.u8(at+8),"to":"fe6_unit_%d" % d.u8(at+9)})
				elif kind == 13:
					var callback_at: int = (d.u32(at+8)-0x08000000)&~1
					var two_way := Pure.signature(d,callback_at,58,[4,5,6,7,16,18,20,21,22,23,32,34,36,37,38,39],TalkPredicates.TWO_WAY)
					var described: Variant = TalkPredicates.two_way(d,d.u32(at+8),false) if two_way else TalkPredicates.describe(d,d.u32(at+8))
					if described == null: return false
					entry.merge(described)
					if two_way:
						var reverse := entry.duplicate(true); reverse.id += "_reverse"
						reverse.merge(TalkPredicates.two_way(d,d.u32(at+8),true),true)
						reverse.native_program = program(Groups.pointer(d,at+4),completion)
						result.talks.append(reverse)
				else: fail("Unsupported talk condition."); return false
				var body := Reader.commands(d,Groups.pointer(d,at+4))
				if body.any(func(c):return c.opcode == 0x17 and d.u32(int(c.offset)+4) == 0x0806d065):
					if not paid_recruitment(entry,body,i,completion): return false
					result.talks.append(entry)
					continue
			else:
				if kind == 11: entry.merge({"trigger":"enter_region","native_repeat":true,"search_on_wait":true,"region":[d.u8(at+8),d.u8(at+9),d.u8(at+10),d.u8(at+11)]})
				elif kind == 13:
					entry.merge({"trigger":"native_flag","native_repeat":true,"conditions":{"native_unit_presence":[query(d.u32(at+8))]}})
				else: fail("Unsupported global condition."); return false
			entry.native_program = program(Groups.pointer(d,at+4),completion)
			if table == 2:
				for site in result.interactions:
					if site.id != entry.id or site.type != "house": continue
					# Conditional recruitment houses stay open until their script
					# closes the map tile. Ordinary information houses are one-use.
					if entry.native_program.scripts.any(func(body):return body.any(func(c):return c.get("effect",{}).has("map_change"))):
						site.native_revisitable = true; entry.native_repeat = true
			if table == 1: result.talks.append(entry)
			else: result.events.append(entry)
			if not d.error.is_empty(): return false
		if not ended: fail("Unterminated condition table."); return false
	if not objective(result,seize_rows): return false
	result.events.append({"id":"fe6_dynamic_ending","trigger":"victory","native_program":program(Groups.pointer(d,header+24),0,true)})
	result.native_flag_bindings = preload("res://runtime/fe6/rom_fe6_flags.gd").bindings(d,chapter,result.interactions)
	if chapter_fields.has("rules"): result.rules.merge(chapter_fields.rules,true); chapter_fields.erase("rules")
	result.merge(chapter_fields)
	var party: int = Groups.pointer(d,header+20)
	result.dynamic_party_ids = data.formations.get(party,[]).map(func(s):return str(s.unit_id)).filter(func(id):return not id.is_empty())
	result.dynamic_extra_slots = data.formations.get(party,[]).filter(func(s):return str(s.unit_id).is_empty())
	return d.error.is_empty()

func paid_recruitment(entry: Dictionary, body: Array, condition: int, completion: int) -> bool:
	var input := {"talks":[entry]}
	if not preload("res://runtime/fe6/rom_fe6_capital.gd").fe6_unit_39(d,input,chapter,{"event":"talk","condition":condition}): return false
	var recruit: int = d.u32(int(body[48].offset)+4)
	entry.change_faction = [{"unit_id":"fe6_unit_%d" % recruit,"faction":"player"}]
	if completion:
		entry.get_or_add("conditions",{}).native_flags_not = [completion]
		entry.native_flags_set = [completion]
	for key in ["dialogue","decline_dialogue","insufficient_dialogue"]: entry[key] = resolve_story(entry[key],body)
	for offer in entry.recruitment_offers: offer.dialogue = resolve_story(offer.dialogue,body)
	return d.error.is_empty()

func resolve_story(recipe: Dictionary, body: Array) -> Array:
	var pages: Array = []
	for part in recipe["$rom_fe6_story"].parts:
		pages.append_array(text(d.u32(int(body[int(part.source.command)].offset)+4)))
	return pages

func objective(result: Dictionary, rows: Array) -> bool:
	if rows.size() == 1 and rows[0].terminal:
		result.objective = {"type":"seize","unit_id":"fe6_unit_1","x":rows[0].x,"y":rows[0].y}
	elif not rows.is_empty():
		var terminals := rows.filter(func(r):return r.terminal)
		var victory_flag := 0
		if terminals.size() == 1: victory_flag = int(terminals[0].flag)
		elif terminals.is_empty():
			var common: Array = []
			for row in rows:
				var flags: Array = []
				for event in result.events:
					if event.id != row.event_id: continue
					for script in event.native_program.scripts:
						for c in script:
							if c.op == "set" and not flags.has(c.flag): flags.append(c.flag)
				common = flags if row == rows[0] else common.filter(func(f):return flags.has(f))
			if common.size() == 1: victory_flag = int(common[0])
		if victory_flag == 0: fail("Seize events have no unique victory flag."); return false
		result.objective = {"type":"native_seize","unit_id":"fe6_unit_1","flag":victory_flag,"multiple":terminals.size() == 1,"x":rows[-1].x,"y":rows[-1].y}
	else:
		var bosses := {}
		var enemies := {}
		var arrivals := {}
		for event in [{"spawns":result.units}]+result.events:
			if event.get("trigger","chapter_start") != "chapter_start": continue
			for u in Runner.spawn_templates(event):
				if u.faction == "enemy": enemies[u.id] = u
				if u.faction == "enemy" and event.get("trigger") == "chapter_start": arrivals[u.id] = u
				if u.faction == "enemy" and u.get("boss",false): bosses[u.id] = u
		if bosses.is_empty() and enemies.size() == 1: bosses = enemies
		if bosses.is_empty() and arrivals.size() == 1: bosses = arrivals
		if bosses.size() != 1: fail("Chapter without seize points requires a unique boss objective."); return false
		var boss: Dictionary = bosses.values()[0]
		result.objective = {"type":"defeat_boss","unit_id":boss.id,"x":boss.x,"y":boss.y}
	return true

func attach_changes(site: Dictionary) -> void:
	for patch in patches:
		if site.x < patch.x or site.y < patch.y or site.x >= patch.x+patch.width or site.y >= patch.y+patch.height: continue
		if site.type == "village" and patch.width > 1: site.destroy_map_change = patch
		elif site.type in ["village","door","chest"]: site.map_change = patch

func quotes(result: Dictionary) -> bool:
	for entry in [[0x6b744,"battle"],[0x6b7fc,"unit_defeated"]]:
		var pointer: int = d.ptr(entry[0])
		var seen := {}
		var ended := false
		for index in range(256):
			var at := pointer+index*16
			if not d.require_range(at,16,"FE6 quotes"): return false
			var character: int = d.u8(at)
			if character in [0,255]: ended = true; break
			if d.u8(at+1) not in [chapter,45] or seen.has(character): continue
			seen[character] = true
			var text_id: int = d.u16(at+4)
			if text_id == 0: continue
			var matches: Array = data.unit_offsets.values().filter(func(u):return int(u.rom_character_id) == character)
			if matches.is_empty(): continue
			var unit: Dictionary = matches[0]
			var pages := text(text_id)
			for page in pages:
				if str(page.get("portrait","")).is_empty(): page.merge({"speaker":unit.name,"portrait":unit.portrait,"left_portrait":unit.portrait,"right_portrait":"","speaker_side":"left"},true)
			result.events.append({"id":"fe6_dynamic_quote_%s_%d" % [entry[1],character],"trigger":entry[1],"unit_id":unit.id,"dialogue":pages})
		if not ended: fail("Unterminated battle/death quotes."); return false
	return d.error.is_empty()
