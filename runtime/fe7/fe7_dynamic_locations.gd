extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## Native FE7 location/talk tables, shared by chapter compilation and auditing.
const Data = preload("res://runtime/rom_data.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Flags = preload("res://engine/native_event_flags.gd")
var compiler: RefCounted
var patches: Array = []

func fail(message: String) -> bool:
	compiler.d.fail("FE7 locations",message)
	return false

func read_patches() -> bool:
	patches = []
	var d: RefCounted = compiler.d
	var chapter: int = compiler.chapter_index
	var record: int = d.ptr(int(d.layout.chapters))+chapter*int(d.layout.chapter_stride)
	var operand: int = d.ptr(int(d.layout.changes))+d.u8(record+11)*4
	if d.u32(operand) == 0: return d.error.is_empty()
	var table: int = d.ptr(operand)
	for index in range(64):
		var at := table+index*12
		if not d.require_range(at,12,"FE7 map changes"): return false
		if d.u8(at) == 255: return true
		patches.append(compiler.data.patch(chapter,d.u8(at)))
		if not d.error.is_empty(): return false
	return fail("Unterminated map-change table.")

func attach_changes(site: Dictionary) -> bool:
	var matches: Array = patches.filter(func(p):return site.x >= p.x and site.y >= p.y and site.x < p.x+p.width and site.y < p.y+p.height)
	if site.type in ["village","chest"]:
		var single: Array = matches.filter(func(p):return int(p.width) == 1 and int(p.height) == 1)
		if single.size() != 1: return fail("Location needs one native closing-tile change.")
		site.map_change = single[0]
		if site.type == "village":
			var destroyed: Array = matches.filter(func(p):return int(p.width) > 1)
			if destroyed.size() == 1: site.destroy_map_change = destroyed[0]
	elif site.type == "door":
		# Native door lookup selects the first containing change. Its rectangle
		# can uncover a whole room; do not reduce this to one floor tile.
		if matches.is_empty(): return fail("Door has no native map change.")
		site.map_change = matches[0]
	return true

func objects(result: Dictionary, rows: Array, map: Dictionary) -> bool:
	var d: RefCounted = compiler.d
	for row in rows:
		var at := int(row.offset)
		var kind := int(row.kind)
		var action: int = d.u8(at+10)
		var flag := int(row.flag)
		if flag == 100: flag = 0
		if flag and not Flags.valid_id(flag,"any","fe7"): return fail("Invalid location completion flag.")
		var site := {"id":"fe7_site_%x" % at,"x":d.u8(at+8),"y":d.u8(at+9)}
		if d.u8(at+11) != 0: return fail("Invalid location parameters.")
		# Native lookup cannot reach records outside the current map.
		if site.x >= map.width or site.y >= map.height: continue
		# The upper village tile is its pillage marker, not another visit.
		if kind == 5 and action == 29 and d.u32(at+4) == 1:
			if not rows.any(func(other):return int(other.kind) == 6 and d.u16(int(other.offset)+2) == int(row.flag) and d.u8(int(other.offset)+8) == site.x and d.u8(int(other.offset)+9) == site.y+1): return fail("Unpaired village pillage marker.")
			continue
		if kind == 10 and action in [19,20,21]:
			site.type = "armory" if action == 19 else "shop"
			site.name = {19:"Armory",20:"Vendor",21:"Secret shop"}[action]; site.stock = []
			if action == 21: site.merge({"member_card_required":true,"hidden":true})
			var stock: Variant = Data.shop_stock(d,at,"fe7")
			if stock == null: return false
			for item in stock: site.stock.append({"item":compiler.data.item(int(item.rom_item_id)),"price":item.price})
		elif kind == 7 and action == 18:
			# Native chest commands also require chest terrain. Some chapters
			# retain unused location records on ordinary floor (Light part two).
			var possible_chest: bool = Data.SYMBOLS.find(map.terrain[site.y][site.x]) == 33
			for patch in patches:
				if site.x >= patch.x and site.y >= patch.y and site.x < patch.x+patch.width and site.y < patch.y+patch.height and Data.SYMBOLS.find(patch.terrain[site.y-patch.y][site.x-patch.x]) == 33: possible_chest = true
			if not possible_chest: continue
			site.type = "chest"; site.requires_key = true
			if not attach_changes(site): return false
			var reward: Variant = Data.chest_reward(d,at,"fe7")
			if reward == null: return false
			if reward.has("rom_item_id"): site.give_item = compiler.data.item(int(reward.rom_item_id))
			else: site.reward = reward
		elif kind == 8 and action == 16:
			site.type = "door"; site.requires_key = true
			if not attach_changes(site): return false
			if d.u32(at+4) != 1:
				site.native_visit_event = true
				var visit: Dictionary = compiler.event(Groups.pointer(d,at+4),"visit",flag)
				visit.x = site.x; visit.y = site.y; result.events.append(visit)
		elif kind in [5,6] and action == 14:
			site.type = "village" if kind == 6 else "house"; site.native_visit_event = true
			if site.type == "village" and not attach_changes(site): return false
			var visit: Dictionary = compiler.event(Groups.pointer(d,at+4),"visit",flag)
			visit.x = site.x; visit.y = site.y; result.events.append(visit)
		elif kind == 5 and action == 15 and d.u32(at+4) == 1:
			var lord: int = {1:3,2:1,3:2}.get(int(result.native_route),3)
			site.type = "seize"; site.unit_id = "fe7_unit_%d" % lord
			var terrain_name: String = d.terrain_name(Data.SYMBOLS.find(map.terrain[site.y][site.x]))
			result.objective = {"type":"native_seize","flag":flag,"unit_id":site.unit_id,"terrain_name":terrain_name,"x":site.x,"y":site.y}
			result.objective_text = "Seize the %s with %s" % [terrain_name,preload("res://runtime/rom_names.gd").character(d,"fe7",lord)]
		else: return fail("Unsupported location kind/action at 0x%x." % at)
		if flag: result.native_flag_bindings.sites.append({"id":site.id,"flag":flag})
		result.interactions.append(site)
		if not d.error.is_empty(): return false
	return true

func talks(result: Dictionary, rows: Array) -> bool:
	var d: RefCounted = compiler.d
	for row in rows:
		var at := int(row.offset)
		if int(row.kind) not in [3,4] or d.u16(at+10) != 0: return fail("Unsupported talk eligibility at 0x%x." % at)
		var conditions := {}
		if int(row.kind) == 4:
			conditions.native_unit_presence = [compiler.Native.predicate(d,d.u32(at+12),compiler.chapter_index)]
			if not d.error.is_empty(): return false
		else:
			var selector: int = d.u16(at+12)
			if selector in [0,1,2]:
				if d.u16(at+14) != 0: return fail("Invalid talk route operand.")
				if selector and selector+1 != int(result.native_route): continue
			elif selector == 3:
				if not Flags.valid_id(d.u16(at+14),"any","fe7"): return fail("Invalid talk eligibility flag.")
				conditions.native_flags_all = [d.u16(at+14)]
			else: return fail("Unknown talk selector.")
		var from_id: int = d.u8(at+8)
		var to_id: int = d.u8(at+9)
		if to_id == 0: return fail("Talk requires a target character ID.")
		var flag := 0 if int(row.flag) == 100 else int(row.flag)
		var target := Groups.pointer(d,at+4)
		var talk := {"id":"fe7_talk_%x" % at,"trigger":"talk","game_id":"fe7","from":"fe7_unit_%d" % from_id,"to":"fe7_unit_%d" % to_id}
		if from_id == 0: talk.from = "*"
		if target == compiler.ending_offset:
			talk.native_program = {"version":1,"completion_flag":flag,"scripts":[[{"op":"fe7_victory"},{"op":"end"}]]}
			result.objective = {"type":"native_event"}
			result.objective_text = "Talk to "+d.text(d.u16(d.ptr(int(d.layout.characters))+(to_id-1)*52))
		else: talk.native_program = compiler.program(target,flag)
		talk.conditions = conditions
		result.talks.append(talk)
		if not d.error.is_empty(): return false
	return true

func structures(result: Dictionary, map: Dictionary) -> bool:
	var d: RefCounted = compiler.d
	if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(d,0x2c078,136,[],"f7b8207dea0b8220154c48e1c8d9a7ce20518e829f3e0a05edb62b60d2153451"):
		return fail("Changed native wall/tree initialization.")
	var record: int = d.ptr(int(d.layout.chapters))+compiler.chapter_index*int(d.layout.chapter_stride)
	result.destructibles = []
	for y in range(int(map.height)):
		for x in range(int(map.width)):
			var id: int = Data.SYMBOLS.find(map.terrain[y][x])
			if id not in [27,51] or (id == 27 and y > 0 and Data.SYMBOLS.find(map.terrain[y-1][x]) == 27): continue
			var changes: Array = patches.filter(func(p):return x >= int(p.x) and x < int(p.x+p.width) and y >= int(p.y) and y < int(p.y+p.height) and p.mask[y-int(p.y)][x-int(p.x)])
			if changes.is_empty(): return fail("Breakable wall/tree has no native map change.")
			var hp: int = d.u8(record+44) if id == 27 else d.u8(Policy.address(d,0x2c0e6))
			if hp <= 0: return fail("Breakable wall/tree has invalid native HP.")
			result.destructibles.append({"id":"fe7_structure_%d_%d" % [x,y],"name":d.terrain_name(id),"x":x,"y":y,"hp":hp,"max_hp":hp,"map_change":changes[0]})
	return d.error.is_empty()
