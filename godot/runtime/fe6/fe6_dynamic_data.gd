extends RefCounted
## Construct engine definitions from FE6 records, without stock chapter templates.
const Data = preload("res://runtime/rom_data.gd")
const Factory = preload("res://runtime/rom_unit_factory.gd")
const Animations = preload("res://runtime/rom_animation_data.gd")
const BattleArt = preload("res://runtime/rom_battle_data.gd")
var d: RefCounted
var prefix := ""
var items: Dictionary = {}
var assets: Dictionary = {}
var battles := {"game_id":"fe6","animations":{},"fps":60}
var movement := {"schema_version":1,"movement":{}}
var unit_offsets := {}
var chapter_index := 0
var formations := {}
var support_characters: Array = []
var terrain: Array = []

func fail(message: String) -> Variant:
	d.fail("FE6 compatibility",message)
	return null

func item(id: int, required: bool = true) -> Dictionary:
	if items.has(id):
		if required and items[id].has("compatibility_unsupported"): fail(items[id].compatibility_unsupported); return {}
		return items[id].duplicate(true)
	var at := Data.item_record(d,id,"fe6")
	if at < 0: return {}
	var flags: int = d.u32(at+8)
	var fields := ["rom_item_id","source_offset","name","description","icon","uses","max_uses","cost_per_use","unsellable","stealable","required_rank","unrepairable","negate_flying_effectiveness"]
	if flags&1: fields.append_array(["type","might","hit","weight","crit","min_range","max_range","brave","cannot_counter","triangle_reverse","ignore_defense","effective_class_ids","flying_effectiveness","weapon_effect"])
	var result: Variant = Data.item_record_fields(d,{"id":id,"fields":fields},"fe6")
	if result == null: return {}
	result.game_id = "fe6"
	result.icon = str(result.icon).replace("res://content/fe6/",prefix)
	assets[result.icon] = {"kind":"icon","id":d.u8(at+29)}
	if flags&1:
		result.weapon_exp = 1
		if flags&0x100: result.triangle_multiplier = 1
		result.effectiveness_multiplier = 3
		if d.u32(at+12):
			result.stat_bonuses = {}
			var stats: Array = Data.STATS+["mov","con"]
			for i in range(stats.size()):
				var value: int = d.u8(d.ptr(at+12)+i)
				if value: result.stat_bonuses[stats[i]] = value
		if d.u8(at+7) == 11: result.merge({"unbreakable":true,"weapon_exp":0,"uses":1,"max_uses":1},true)
		if id == 8: result.ranged_fixed_damage = 10
		var locks := 0
		for bits in [[0x400,0x40000],[0x800,0x10000],[0x1000,0x20000],[0x2000,0x80000]]:
			if flags&int(bits[0]): locks |= int(bits[1])
		if locks: result.required_unit_flags = locks
	elif flags&4:
		result.merge({"type":"staff","kind":"staff","min_range":1,"max_range":maxi(1,d.u8(at+25)&15),"weapon_exp":1,"experience":d.u16(at+26)/20+10})
		match id:
			67,68,70,118: result.healing = 20 if id == 68 else (15 if id == 118 else 10)
			69: result.healing_full = true
			71: result.merge({"healing":10,"heal_all":true})
			72: result.merge({"staff_effect":"warp","destination_range_unlimited":true})
			73: result.staff_effect = "rescue"
			74: result.staff_effect = "restore"
			75,76,80: result.merge({"inflict_status":{75:"silence",76:"sleep",80:"berserk"}[id],"status_turns":5,"hit":d.u8(at+22),"healing":0})
			77: result.merge({"vision_bonus":4,"min_range":0,"max_range":0},true)
			78: result.staff_effect = "repair"
			81: result.merge({"staff_effect":"unlock","opens":["door"],"requires_staves":true})
			82: result.temporary_bonuses = {"res":7}
			119: result.merge({"healing_full":true,"staff_effect":"saint","heal_all":true,"min_range":0,"max_range":255},true)
			_:
				result.compatibility_unsupported = "Staff %d needs an adapter for its native use routine." % id
				if required: fail(result.compatibility_unsupported); return {}
		if id in [70,71,73,75,76,80]: result.merge({"range_magic_half":true,"magic_range_bonus":5,"magic_range_min":0})
	else:
		result.merge({"type":"item","kind":"treasure"})
		match id:
			86,87,88,89,90,91,92,93,94:
				result.merge({"type":"consumable","kind":"consumable","stat_boosts":{}},true)
				for i in range(9):
					var value: int = d.u8(d.ptr(at+12)+i)
					if value: result.stat_boosts[(Data.STATS+["mov","con"])[i]] = value
			95,96,97,98,99: result.merge({"kind":"promotion","promotion":true},true)
			100,101,103: result.merge({"kind":"key","opens":["door","chest"] if id == 103 else ["door" if id == 101 else "chest"],"requires_lockpick_skill":id == 103},true)
			104,105,106,107,108:
				result.merge({"type":"consumable","kind":"consumable"},true)
				if id == 104: result.healing = 10
				elif id == 105: result.healing_full = true
				elif id == 106: result.temporary_bonuses = {"res":7}
				elif id == 107: result.vision_bonus = 4
				else: result.cure_status = "poison"
			109: result.merge({"kind":"key_item","member_card":true},true)
			110: result.merge({"kind":"key_item","shop_discount":0.5},true)
			124: result.kind = "key_item"
			_:
				# A native use routine is gameplay, even for an unknown item ID.
				if d.u8(at+30) != 0:
					result.compatibility_unsupported = "Item %d needs an adapter for its native use routine." % id
					if required: fail(result.compatibility_unsupported); return {}
	items[id] = result
	return result.duplicate(true)

func inventory(at: int) -> Dictionary:
	var result := {"weapon":{},"inventory":[]}
	for i in range(4):
		var id: int = d.u8(at+8+i)
		if id == 0: continue
		var value := item(id)
		if value.is_empty(): return result
		if result.weapon.is_empty() and value.has("might"): result.weapon = value
		else: result.inventory.append(value)
	return result

func group(at: int) -> Array:
	var result: Array = []
	var seen := {}
	formations[at] = []
	if at < 0: fail("Invalid unit-list pointer."); return result
	for index in range(256):
		var record := at+index*16
		if not d.require_range(record,16,"FE6 compatible unit list"): return []
		var character: int = d.u8(record)
		if character == 0: return result
		var member := unit(record)
		if not d.error.is_empty(): return []
		if member.faction == "player":
			formations[at].append({"unit_id":"" if seen.has(member.id) else member.id,"x":member.x,"y":member.y})
			if seen.has(member.id): continue
		elif seen.has(member.id): member.id = "fe6_dynamic_unit_%x" % record
		seen[member.id] = true
		result.append(member)
	fail("Unterminated unit list.")
	return []

func unit(at: int) -> Dictionary:
	if unit_offsets.has(at): return unit_offsets[at].duplicate(true)
	var fields: Array = Factory.FIELDS.duplicate()
	fields.erase("name")
	fields.append_array(["experience_bonus","experience_defeat_bonus"])
	var value: Variant = Data.unit_record_fields(d,{"offset":at,"fields":fields,"terrain_keys":Array(Data.SYMBOLS.split("",false))},"fe6")
	if value == null: return {}
	var u: Dictionary = value
	var character := int(u.rom_character_id)
	var ca: int = d.ptr(0x17680)+character*48
	var cl: int = d.ptr(0x176e0)+int(u.rom_class_id)*72
	# Alternate records provide deployment bases; native LOAD then switches the
	# personal identity/growths to the preceding record for alternate-route units.
	if d.u32(ca+40)&0x800000:
		if character < 2: fail("Invalid alternate character record."); return {}
		character -= 1; ca -= 48; u.rom_character_id = character
		for i in range(Data.STATS.size()): u.growths[Data.STATS[i]] = d.u8(ca+28+i)
		var portrait: int = d.u16(ca+6)
		if portrait == 0: portrait = d.u16(cl+8)
		u.portrait = "res://content/fe6/rom/portraits/%03d.png" % portrait
	u.name = d.text(d.u16(ca))
	u.sprite = str(u.sprite).replace("res://content/fe6/",prefix)
	u.portrait = str(u.portrait).replace("res://content/fe6/",prefix)
	var flags: int = d.u32(ca+40)|d.u32(cl+36)
	u.id = "fe6_unit_%d" % character if u.faction != "enemy" or flags&0x8000 or d.u16(ca+6) != 0 else "fe6_dynamic_enemy_%x" % at
	u.merge({"game_id":"fe6","exp":0,"multiple_s_ranks":true,"essential":character == 1,"lord":character == 1,"can_use_staves":int(u.weapon_exp.get("staff",0)) > 0,"can_steal":bool(flags&4),"can_lockpick":bool(flags&8),"weapon_types":[]})
	u.merge(inventory(at))
	if int(u.y) >= 0 and int(u.y) < terrain.size() and int(u.x) >= 0 and int(u.x) < str(terrain[int(u.y)]).length() and str(terrain[int(u.y)])[int(u.x)] == "H":
		u.concealed_by_roof = true
	for kind in u.weapon_exp:
		if int(u.weapon_exp[kind]) > 0: u.weapon_types.append(kind)
	if u.weapon.get("type") == "other": u.weapon_types.append("other")
	preload("res://engine/fe6_unit_traits.gd").apply(u,d.u32(cl+36),d.u32(ca+40))
	for support_character in support_characters:
		if support_character.rom_character_ids.has(character):
			u.support_id = support_character.id; u.affinity = support_character.affinity; break
	if u.faction != "player" and not base_ai(u): return {}
	if u.source_deployment.autolevel:
		for carried in [u.weapon]+u.inventory:
			var kind := str(carried.get("type",""))
			if int(u.weapon_exp.get(kind,0)) > 0: u.weapon_exp[kind] = maxi(int(u.weapon_exp[kind]),int(carried.get("required_rank",0)))
	if flags&0x08000000:
		var last_item := 0
		for i in range(4):
			if d.u8(at+8+i): last_item = d.u8(at+8+i)
		if last_item: u.drop_item = item(last_item)
	if flags&1: u.mounted = true
	var sprite: int = d.u8(cl+6)
	var faction := "npc" if u.faction == "neutral" else str(u.faction)
	for team in ["player","enemy","npc"]:
		var path: String = str(u.sprite).replace("_"+faction+".png","_"+team+".png")
		assets[path] = {"kind":"sprite","id":sprite,"faction":["player","enemy","npc"].find(team)}
		assets[path.trim_suffix(".png")+"_idle.png"] = {"kind":"sprite","id":sprite,"faction":["player","enemy","npc"].find(team),"idle":true}
	assets[u.portrait] = {"kind":"portrait","id":int(str(u.portrait).get_file().get_basename())}
	unit_offsets[at] = u
	return u.duplicate(true)

func base_ai(u: Dictionary) -> bool:
	# FE6's standard AI selectors use the same tactical approximations as the
	# existing port. Custom AI bytecode/ASM is outside this compatibility ABI.
	var primary := int(u.source_deployment.ai[0])
	var secondary := int(u.source_deployment.ai[1])
	var modes := {0:"pursue",1:"pursue",2:"pursue",3:"attack_in_range",4:"raid",5:"loot",6:"pursue",7:"pursue",9:"pursue",11:"pursue",12:"escape",15:"pursue",17:"attack_in_range",18:"attack_in_range",19:"pursue",20:"pursue",21:"pursue",22:"pursue",23:"pursue",24:"pursue"}
	if primary not in [0,1,3,6,7,8,9,11,12,13,14] or not modes.has(secondary): fail("Unsupported FE6 AI selectors %d/%d." % [primary,secondary]); return false
	u.merge({"ai":"","ai_excluded_character_ids":[],"ai_waypoint":[],"ai_waypoint_reached":false,"ai_approach_character":0,"ai_approach_complete":false,"ai_escape_points":[],"ai_escape_if_missing_character":0,"npc_escape":[],"npc_talk_target":""},true)
	u.ai_mode = "stationary" if primary == 3 else modes[secondary]
	u.ai_no_attack = primary == 6 or secondary in [5,12]
	u.ai_random_move = secondary == 9
	if secondary == 9 and d.u8(d.ptr(d.ptr(0x5c97ec)+secondary*4)) != 0x16: fail("Random movement AI changed."); return false
	if secondary in [19,20,21,22,23]:
		var script: int = d.ptr(d.ptr(0x5c97ec)+secondary*4)
		if d.u8(script+32) != 0xc: fail("Castle waypoint AI changed."); return false
		u.ai_waypoint = [d.u8(script+33),d.u8(script+35)]
		u.ai_after_waypoint = "attack_in_range"
	if primary == 3: u.ai = "stationary"
	if primary == 6: u.ai_no_attack = true
	if primary in [7,8,9]:
		var script: int = d.ptr(d.ptr(0x5c97f8)+primary*4)
		if d.u8(script) != 5: fail("Selective-attack AI changed format."); return false
		var list: int = d.ptr(script+8)
		u.ai_excluded_character_ids = []
		var ended := false
		for i in range(256):
			var value: int = d.u16(list+i*2)
			if value == 0: ended = true; break
			if value > 255: fail("Invalid AI character list."); return false
			u.ai_excluded_character_ids.append(value)
		if not ended: fail("Unterminated AI character list."); return false
	if secondary in [11,15]:
		var script: int = d.ptr(d.ptr(0x5c97ec)+secondary*4)
		if d.u8(script) != 13: fail("Approach AI changed format."); return false
		var target: int = d.u32(script+4)
		if target < 1 or target > 255: fail("Invalid AI approach target."); return false
		u.ai_approach_character = target
		if u.faction == "neutral": u.npc_talk_target = "fe6_unit_%d" % target
		if secondary == 15: u.ai_escape_if_missing_character = target
	if secondary in [5,12,15]:
		var points: Variant = preload("res://runtime/fe6/rom_fe6_unit_29.gd").escape_points(d,chapter_index,u.faction == "neutral",true)
		if points == null: return false
		u.ai_escape_points = points
		if not points.is_empty(): u.npc_escape = points[0]
		if secondary == 12: u.ai_no_attack = true
	return d.error.is_empty()

func promotion_catalog() -> Dictionary:
	var result := {"schema_version":1,"classes":{},"promotions":[]}
	var eligible := {}
	for entry in [[95,0x237b0],[96,0x237b8],[97,0x237c0],[98,0x237c8],[99,0x237f0]]:
		var pointer: int = d.ptr(entry[1])
		var ended := false
		for index in range(64):
			var cid: int = d.u8(pointer+index)
			if cid == 0: ended = true; break
			eligible.get_or_add(cid,[]).append(entry[0])
		if not ended: fail("Unterminated promotion eligibility."); return {}
	eligible[1] = [] # FE6's lord promotes through its event routine.
	for cid in eligible:
		var cl: int = d.ptr(0x176e0)+int(cid)*72
		var target: int = d.u8(cl+5)
		result.promotions.append({"from_class":cid,"to_class":target,"items":eligible[cid],"minimum_level":1 if int(cid) == 1 else 10})
		for class_id in [int(cid),target]:
			if result.classes.has(str(class_id)): continue
			var definition := class_definition(class_id)
			if not d.error.is_empty(): return {}
			result.classes[str(class_id)] = definition
	return result

func class_definition(cid: int) -> Dictionary:
	var at: int = d.ptr(0x176e0)+cid*72
	if cid < 1 or not d.require_range(at,72,"Promotion class") or d.u8(at+4) != cid: fail("Invalid promotion class identity."); return {}
	var flags: int = d.u32(at+36)
	var result := {"rom_class_id":cid,"class_name":d.text(d.u16(at)),"stat_caps":{"luck":30,"con":d.u8(at+25),"mov":15},"weapon_exp":{},"weapon_types":[],"movement_costs":{},"terrain_bonuses":{},"base_stats":{"con":d.u8(at+17),"mov":d.u8(at+18)},"promotion_base_difference":true,
		"canto":bool(flags&2),"flying":bool(flags&0x1800),"mounted":bool(flags&1),"can_lockpick":bool(flags&8),"critical_bonus":30 if flags&0x40 else 0,"multiple_s_ranks":true,"sprites":{}}
	result.fe6_class_flags = flags
	var experience: Variant = Data.class_experience(d,cid,"fe6")
	if experience == null: return {}
	result.merge(experience)
	for i in range(6): result.base_stats[Data.STATS[i]] = d.u8(at+11+i); result.stat_caps[Data.STATS[i]] = d.u8(at+19+i)
	for i in range(8):
		var rank: int = d.u8(at+40+i)
		result.weapon_exp[Data.WEAPONS[i]] = rank
		if rank: result.weapon_types.append(Data.WEAPONS[i])
	result.can_use_staves = result.weapon_exp.staff > 0
	if flags&1: result.aid_base = 20 if flags&0x4000 else 25
	for tid in range(Data.SYMBOLS.length()):
		var cost: int = d.u8(d.ptr(at+52)+tid)
		result.movement_costs[Data.SYMBOLS[tid]] = cost-256 if cost >= 128 else cost
		result.terrain_bonuses[Data.SYMBOLS[tid]] = {"avoid":d.u8(d.ptr(at+56)+tid),"defense":d.u8(d.ptr(at+60)+tid),"resistance":d.u8(d.ptr(at+64)+tid)}
	for faction in ["player","enemy","npc"]:
		var path := prefix+"rom/sprites/%03d_%s.png" % [d.u8(at+6),faction]
		result.sprites[faction] = path
		assets[path] = {"kind":"sprite","id":d.u8(at+6),"faction":["player","enemy","npc"].find(faction)}
		assets[path.trim_suffix(".png")+"_idle.png"] = assets[path].merged({"idle":true})
	return result

func prepare_art(promotions: Dictionary) -> void:
	for source in unit_offsets.values():
		var classes: Array = [int(source.rom_class_id)]
		for route in promotions.get("promotions",[]):
			if int(route.from_class) == int(source.rom_class_id) and not classes.has(int(route.to_class)): classes.append(int(route.to_class))
		for cid in classes:
			for faction in ["player","enemy","neutral"]:
				var u: Dictionary = source.duplicate()
				u.rom_class_id = cid; u.faction = faction
				u.promoted = bool(d.u32(d.ptr(0x176e0)+cid*72+36)&0x100)
				unit_offsets["art_%d_%d_%s" % [int(source.rom_character_id),cid,faction]] = u
	art()

func art() -> void:
	for u in unit_offsets.values():
		var cid := int(u.rom_class_id)
		if not movement.movement.has(str(cid)):
			var at: int = d.ptr(0x60ed8)+(cid-1)*8
			var data := Animations.movement(d,d.ptr(at+4))
			data.erase("frames")
			data.merge({"class_id":cid,"frame_size":[64,64],"anchor":[32,56],"paths":{}})
			for faction in ["player","enemy","npc"]:
				var path := prefix+"movement/%03d_%s.png" % [cid,faction]
				data.paths[faction] = path
				assets[path] = {"kind":"movement","id":cid,"faction":["player","enemy","npc"].find(faction)}
			movement.movement[str(cid)] = data
		var cl: int = d.ptr(0x176e0)+cid*72
		if d.u32(cl+48) == 0: continue
		var mapping: int = d.ptr(cl+48)
		var ca: int = d.ptr(0x17680)+int(u.rom_character_id)*48
		var palette: int = d.u8(ca+(36 if u.promoted else 35))
		var ended := false
		for index in range(64):
			var at := mapping+index*4
			if not d.require_range(at,4,"FE6 compatible animation mapping"): return
			if d.u32(at) == 0: ended = true; break
			var is_item: bool = d.u8(at+1) == 0
			var key: int = d.u8(at)
			var weapon: String = item(key).get("type","other") if is_item else (Data.WEAPONS[key] if key < 8 else ("unarmed" if key == 9 else "other"))
			var identity := "%d_%s_%d_%d_%s" % [cid,weapon,key if is_item else 0,palette,u.faction]
			if battles.animations.has(identity):
				if not battles.animations[identity].characters.has(u.rom_character_id): battles.animations[identity].characters.append(u.rom_character_id)
				continue
			var bank := ["player","enemy","neutral"].find(str(u.faction))
			var selector := {"class_id":cid,"weapon_type":d.u8(d.ptr(0x16410)+key*32+7) if is_item else key,"item_ids":[key] if is_item else [],"palette_id":palette,"bank":bank}
			var data := BattleArt.profile(d,"fe6",selector)
			if not d.error.is_empty(): return
			data.merge({"class_id":cid,"weapon":weapon,"characters":[u.rom_character_id],"item_ids":selector.item_ids,"faction":u.faction,"atlas":{},"frame_size":[288,160],"columns":8,"anchor":[148,88]})
			for side in ["left","right"]:
				var path: String = prefix+"battle/"+identity+"_"+side+".png"
				data.atlas[side] = path
				assets[path] = {"kind":"battle_rom","game":"fe6","selector":selector,"side":side}
			battles.animations[identity] = data
		if not ended: fail("Unterminated class animation mapping."); return

func patch(chapter: int, id: int) -> Dictionary:
	var result: Variant = Data.map_fields(d,{"chapter":chapter,"change":id,"fields":["x","y","width","height","terrain","mask"]},"fe6")
	if result == null: return {}
	result.id = id; result.image = prefix+"maps/%d_change_%d.png" % [chapter,id]
	assets[result.image] = {"kind":"map","chapter":chapter,"change":id}
	return result
