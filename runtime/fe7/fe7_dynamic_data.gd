extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## FE7 item-use and unit policy around the shared live table readers.
const Data = preload("res://runtime/rom_data.gd")
const Factory = preload("res://runtime/rom_unit_factory.gd")
var d: RefCounted
var prefix := ""
var chapter_index := 0
var native_route := 1
var support_characters: Array = []
var enemy_records := {}
var campaign := {}
var items := {}
var assets := {}
var unit_offsets := {}
var battles := {"game_id":"fe7","animations":{},"fps":60,"supported":true}
var movement := {"schema_version":1,"movement":{}}
var item_policy_checked := false
var discount_item := 0

func item(id: int, required: bool = true) -> Dictionary:
	if not item_policy_checked:
		if not validate_item_policy(): return {}
		item_policy_checked = true
	if items.has(id):
		if required and items[id].has("compatibility_unsupported"):
			d.fail("FE7 item",items[id].compatibility_unsupported); return {}
		return items[id].duplicate(true)
	var at := Data.item_record(d,id,"fe7")
	if at < 0: return {}
	var flags: int = d.u32(at+8)
	var fields := ["rom_item_id","source_offset","name","description","icon","uses","max_uses","cost_per_use","unsellable","stealable","required_rank","unrepairable"]
	if flags&1: fields.append_array(["type","might","hit","weight","crit","min_range","max_range","brave","cannot_counter","triangle_reverse","ignore_defense","effective_class_ids","weapon_exp"])
	var value: Variant = Data.item_record_fields(d,{"id":id,"fields":fields},"fe7")
	if value == null: return {}
	var result: Dictionary = value
	result.game_id = "fe7"
	result.negate_critical = bool(flags&0x8000)
	result.negate_flying_effectiveness = bool(flags&0x4000)
	if flags&8: result.merge({"unbreakable":true,"uses":maxi(1,int(result.uses)),"max_uses":maxi(1,int(result.max_uses))},true)
	result.native_asset_once = bool(flags&8)
	result.icon = str(result.icon).replace("res://content/fe7/",prefix)
	assets[result.icon] = {"kind":"icon","id":d.u8(at+29)}
	if flags&1:
		# Native eligibility checks the combined character/class flags. This
		# preserves edited weapon locks and characters without name/ID guesses.
		var locks: int = Data.fe7_weapon_locks(flags)
		if locks: result.required_unit_flags = locks
		result.flying_effectiveness = d.u32(at+16) != 0 and d.u32(at+16) == d.u32(Policy.address(d,0x16d00))
		result.effectiveness_multiplier = 2 if Policy.us(d) else 3
		if d.u32(at+12):
			result.stat_bonuses = Data.item_stat_bonuses(d,at)
		var weapon_effects := {1:"poison",2:"drain",3:"halve_hp",4:"devil"}
		if weapon_effects.has(d.u8(at+31)): result.weapon_effect = weapon_effects[d.u8(at+31)]
		var runesword: bool = id == 17 and bool(flags&0x40)
		if runesword:
			var pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
			if not (pure.signature(d,0x28c08,480,[],"b971aa2952d7f8b481873820fabc05dbdee74da92d59126381d030a6098e6b54") and pure.signature(d,0x2939c,152,[],"1ba5d4d7087385e7ed345ae2c6240c260376baca0112d6d878ed9f7fe1e9a80d")):
				d.fail("FE7 magic sword","Changed native Runesword combat policy."); return {}
			# Native attack subtracts floor(Str/2), leaving ceil(Str/2).
			result.merge({"magic_damage":true,"half_strength":true,"round_half_strength_up":true,"no_critical":true,"no_weapon_exp":true,"triangle_type":"dark"},true)
		var dragon: bool = result.type == "dragon" and id == 143
		if dragon:
			if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(d,0x2939c,152,[],"1ba5d4d7087385e7ed345ae2c6240c260376baca0112d6d878ed9f7fe1e9a80d"):
				d.fail("FE7 dragon","Changed native defense-negation policy."); return {}
			if flags&0x400:
				if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(d,0x1674a,48,[],"b4c0e07cbce8198ebb20abda5135c8d53cf63c0ab10bec41f572d1a3251e818f"):
					d.fail("FE7 dragon","Changed native dragon weapon lock."); return {}
				result.required_unit_flags = locks | 0x40000
				result.required_rank = 0 # Native dragon lock returns before ordinary ranks.
			result.native_dragon_breath = true
		if (flags&0x0f004400 and not (dragon and flags&0x0f004400 == 0x400)) or (d.u8(at+31) != 0 and not weapon_effects.has(d.u8(at+31))) or (flags&0x40 and d.u8(at+31) != 0 and not runesword) or (result.type == "dragon" and not dragon):
			result.compatibility_unsupported = "Weapon %d needs its native special-effect adapter." % id
	elif flags&4:
		staff(result,at)
	else:
		result.merge({"type":"item","kind":"treasure"})
		# Effect selectors, not English names or fixed item IDs. Engine behavior
		# remains an explicit compatibility assumption, as in the FE6 importer.
		match d.u8(at+30):
			0x19,0x1a,0x1b,0x1c,0x1d,0x2e,0x30,0x31,0x32:
				if preload("res://runtime/fe7/fe7_dynamic_promotions.gd").accepts(id,d.u8(at+30)): result.merge({"kind":"promotion","promotion":true},true)
				else: result.compatibility_unsupported = "Item %d is outside the native promotion eligibility switch." % id
			0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18:
				result.merge({"type":"consumable","kind":"consumable","stat_boosts":{}},true)
				var bonuses: int = d.ptr(at+12)
				if not d.require_range(bonuses,9,"FE7 stat booster"): return {}
				for index in range(9):
					var bonus: int = d.u8(bonuses+index)
					if bonus: result.stat_boosts[(Data.STATS+["mov","con"])[index]] = bonus
			0x1e,0x1f,0x20,0x26:
				var use: int = d.u8(at+30)
				result.merge({"kind":"key","opens":["door","chest"] if use == 0x20 else ["door" if use == 0x1f else "chest"],"requires_lockpick_skill":use == 0x20},true)
			0x21: result.merge({"type":"consumable","kind":"consumable","healing":10},true)
			0x22: result.merge({"type":"consumable","kind":"consumable","healing_full":true},true)
			0x23: result.merge({"type":"consumable","kind":"consumable","temporary_bonuses":{"res":7}},true)
			0x24: result.merge({"type":"consumable","kind":"consumable","cure_status":"poison"},true)
			0x25: result.merge({"type":"consumable","kind":"consumable","vision_bonus":4},true)
			0x2a,0x2b,0x2c,0x2d:
				result.merge({"type":"item","kind":"ring","ring_bonuses":{0x2a:{"attack":10},0x2b:{"def":10,"res":10},0x2c:{"crit":10},0x2d:{"avoid":10}}[d.u8(at+30)]},true)
			0x2f:
				var pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
				if not pure.signature(d,0x273bc,24,[],"8007988aa935f89021eb128e6dadcf48c69e9e4462c222f0bb6f8d7197c92349") or not pure.signature(d,0x2ae44,508,[],"c9630148521a1baf38cbcad8f3a19d8a758ae04a94a2b5c90fd8109b96cf251a"):
					d.fail("FE7 growth item","Changed native growth boost or eligibility."); return {}
				result.merge({"type":"consumable","kind":"consumable","growth_boost":d.u8(Policy.address(d,0x2ae84))},true)
			0x27: result.merge({"kind":"trap","trap":"mine"},true)
			0x28: result.merge({"kind":"trap","trap":"light_rune"},true)
			0x29: result.kind = "accessory" # Iron Rune: carried critical protection, no active use.
			0: pass
			_: result.compatibility_unsupported = "Item %d needs its native use adapter." % id
		if flags&0xc000: result.kind = "accessory"
		if id == discount_item: result.merge({"kind":"accessory","shop_discount":0.5},true)
	items[id] = result
	if required and result.has("compatibility_unsupported"):
		d.fail("FE7 item",result.compatibility_unsupported); return {}
	return result.duplicate(true)

func validate_item_policy() -> bool:
	# Reviewed CanUnitUseWeapon and shop-price routines in both regional ABIs.
	# Only table pointers and the live discount-item operand are masked.
	var shared = preload("res://runtime/rom_event_predicates.gd")
	var us := Policy.us(d)
	var lock_at := 0x161a4 if us else 0x16620
	var shop_at := 0xb1d40 if us else 0xb2b64
	if not shared.signature(d,lock_at,476,[348,349,350,351,424,425,426,427],"38f030034320ecfc9839fa39b005c32a0a1517c0d1bd2cbad9d2010aec1bae39" if us else "f032396e98b491cf36e5873d5643e419fd7b48a947c7bb294431955a1031bf27"):
		d.fail("FE7 item eligibility","Changed native weapon permission policy.",lock_at); return false
	if not shared.signature(d,shop_at,80,[22],"1b12e4b4e972e621b2bbb821bd33d893253356f9b9dfe24f30ffbc74ea50ea82" if us else "c6798beeef40759150f6547a73e499ea20dee16c5d8ee997004eccda69ab35d2"):
		d.fail("FE7 shop price","Changed native discount policy.",shop_at); return false
	if d.u32(lock_at+348) != d.u32(int(d.layout.items)) or d.u32(lock_at+424) != d.u32(int(d.layout.items)):
		d.fail("FE7 item eligibility","Weapon permission table disagrees with item table.",lock_at); return false
	discount_item = d.u8(shop_at+22)
	return true

func staff(result: Dictionary, at: int) -> void:
	# FE7's native use-selector ABI. Names, ranks, ranges, price, experience
	# and durability come from the inserted cartridge, not stock item IDs.
	result.merge({"type":"staff","kind":"staff","healing":0,"min_range":d.u8(at+25)>>4,"max_range":maxi(1,d.u8(at+25)&15),"weapon_exp":d.u8(at+32),"experience":int(d.u16(at+26)/20.0)+10},true)
	if d.u8(at+25)&15 == 0: result.merge({"range_magic_half":true,"magic_range_min":5})
	match d.u8(at+30):
		1,2,4: result.healing = 20 if d.u8(at+30) == 2 else 10
		3: result.healing_full = true
		5: result.merge({"healing":10,"heal_all":true},true)
		6: result.staff_effect = "restore"
		7,8,9: result.merge({"inflict_status":{7:"silence",8:"sleep",9:"berserk"}[d.u8(at+30)],"status_duration":5,"hit":d.u8(at+22)})
		10: result.merge({"staff_effect":"warp","destination_magic_half":true,"magic_range_min":5})
		11: result.staff_effect = "rescue"
		12: result.merge({"staff_effect":"torch","vision_bonus":8})
		13: result.staff_effect = "repair"
		14: result.merge({"staff_effect":"unlock","opens":["door"],"requires_staves":true})
		15: result.temporary_bonuses = {"res":7}
		_: result.compatibility_unsupported = "Staff %d needs its native use adapter." % int(result.rom_item_id)

func group(at: int, visual_only: bool = false, preparation: bool = false) -> Array:
	if campaign.is_empty(): campaign = preload("res://runtime/fe7/fe7_dynamic_native.gd").campaign(d)
	if not d.error.is_empty(): return []
	var result: Array = []
	var identities := {}
	for index in range(256):
		var record := at+index*16
		if not d.require_range(record,16,"FE7 deployment"): return []
		var character: int = d.u8(record)
		if character == 0: return result
		var inventory := {"weapon":{},"inventory":[]}
		for slot in range(4):
			var id: int = d.u8(record+8+slot)
			if id == 0: continue
			var carried := item(id,not visual_only)
			# An unarmed cutaway actor needs its appearance, not a playable
			# adapter for an unused weapon carried only by a scene actor.
			if visual_only and carried.has("compatibility_unsupported"): continue
			if not d.error.is_empty(): return []
			if inventory.weapon.is_empty() and carried.has("might"): inventory.weapon = carried
			else: inventory.inventory.append(carried)
		var identity := "fe7_unit_%d" % character
		if identities.has(identity): identity = "fe7_dynamic_unit_%x" % record
		identities[identity] = true
		var value: Variant = Factory.create(d,"fe7",record,identity,{"symbols":Array(Data.SYMBOLS.split("",false)),"promoted_bonus":0,"enemy_bonus":0},inventory)
		if value == null: return []
		var unit: Dictionary = value
		# Closed rooms already contain their native army. Visibility and AI
		# become active when a roof patch reveals the unit's current tile.
		unit.concealed_by_roof = true
		for character_record in support_characters:
			if character in character_record.rom_character_ids:
				unit.support_id = character_record.id; unit.affinity = character_record.affinity; break
		# Generic character records can occur in multiple LOAD groups on one map.
		# Bind each generic enemy slot once. Named units keep their identity
		# across alternate route/scene groups so talks and recruitment still match.
		if unit.faction == "enemy" and not unit.has("portrait"):
			if not enemy_records.has(character): enemy_records[character] = record
			unit.id = "fe7_unit_%d" % character if int(enemy_records[character]) == record else "fe7_dynamic_unit_%x" % record
		preload("res://runtime/fe7/fe7_dynamic_difficulty.gd").apply(d,unit,chapter_index,native_route,preparation)
		if not d.error.is_empty(): return []
		if unit.faction != "player" and unit.get("ai_mode","") in ["loot","escape"]:
			unit.ai_escape_points = escape_points(str(unit.faction))
			if not d.error.is_empty(): return []
		# The shared factory's FE7U routine addresses are provenance only; they
		# are not valid references in a Japanese cartridge.
		unit.weapon_rank_source.erase("initialization")
		unit.weapon_rank_source.erase("autolevel")
		if campaign.aliases.has(character) and int(campaign.aliases[character]) != character: unit.campaign_return_from = "fe7_unit_%d" % int(campaign.aliases[character])
		unit.essential = unit.faction == "player" and (character in [1,2,3] or int(campaign.aliases.get(character,0)) == 3)
		unit.lord = unit.essential
		unit.sprite = str(unit.sprite).replace("res://content/fe7/",prefix)
		var class_at: int = d.ptr(int(d.layout.record_layout[3]))+int(unit.rom_class_id)*84
		unit.native_tracks_experience = character <= 69 and d.u8(d.ptr(int(d.layout.characters))+(character-1)*52+9) != 0
		unit.native_class_con = d.u8(class_at+17)
		unit.native_class_mov = d.u8(class_at+18)
		unit.native_unit_flags = d.u32(class_at+40) | d.u32(d.ptr(int(d.layout.characters))+(character-1)*52+40)
		# Native IsPosMagicSealed scans enemy slots and attribute bit 26.
		if unit.native_unit_flags&0x04000000 and unit.faction == "enemy":
			if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(d,0x18b0c,112,[],"986250e21f8272802a7ac1c8e43449e852187ea845cb208bef301ff27ce98bdc"):
				d.fail("FE7 magic seal","Changed native seal radius/query."); return []
			unit.magic_seal_radius = d.u8(Policy.address(d,0x18b56))
			unit.magic_seal_enemy_only = true
			unit.blockable_spawn = false
		var faction := "npc" if unit.faction == "neutral" else str(unit.faction)
		for team in ["player","enemy","npc"]:
			var path := str(unit.sprite).replace("_"+faction+".png","_"+team+".png")
			assets[path] = {"kind":"sprite","id":d.u8(class_at+6),"faction":["player","enemy","npc"].find(team)}
			assets[path.trim_suffix(".png")+"_idle.png"] = assets[path].duplicate()
			assets[path.trim_suffix(".png")+"_idle.png"].idle = true
		if unit.has("portrait"):
			unit.portrait = str(unit.portrait).replace("res://content/fe7/",prefix)
			assets[unit.portrait] = {"kind":"portrait","id":str(unit.portrait).get_file().get_basename().to_int()}
		result.append(unit)
		unit_offsets["%d_%d_%s" % [int(unit.rom_character_id),int(unit.rom_class_id),unit.faction]] = unit
	d.fail("FE7 deployment","Unterminated unit group.",at)
	return []

func prepare_art(promotions: Dictionary) -> void:
	for source in unit_offsets.values():
		for route in promotions.get("promotions",[]):
			if int(route.from_class) != int(source.rom_class_id): continue
			var u: Dictionary = source.duplicate()
			u.rom_class_id = int(route.to_class)
			u.promoted = bool(d.u32(d.ptr(int(d.layout.record_layout[3]))+int(u.rom_class_id)*84+40)&0x100)
			unit_offsets["promoted_%d_%d_%s" % [int(u.rom_character_id),int(u.rom_class_id),u.faction]] = u
	art()

func art() -> void:
	var animations = preload("res://runtime/rom_animation_data.gd")
	var reader = preload("res://runtime/rom_battle_data.gd")
	for u in unit_offsets.values():
		var cid := int(u.rom_class_id)
		if not movement.movement.has(str(cid)):
			var at: int = d.ptr(int(d.layout.movement))+(cid-1)*8
			var motion := animations.movement(d,d.ptr(at+4))
			if not d.error.is_empty(): return
			motion.erase("frames")
			motion.merge({"class_id":cid,"frame_size":[64,64],"anchor":[32,56],"paths":{}})
			for team in ["player","enemy","npc"]:
				var path := prefix+"movement/%03d_%s.png" % [cid,team]
				motion.paths[team] = path
				assets[path] = {"kind":"movement","id":cid,"faction":["player","enemy","npc"].find(team)}
			movement.movement[str(cid)] = motion
		var cl: int = d.ptr(int(d.layout.record_layout[3]))+cid*84
		if d.u32(cl+52) == 0: continue
		var mapping: int = d.ptr(cl+52)
		var character: int = d.ptr(int(d.layout.characters))+(int(u.rom_character_id)-1)*52
		var palette: int = d.u8(character+(36 if u.get("promoted",false) else 35)) if int(u.rom_character_id)>0 else 0
		var ended := false
		for index in range(64):
			var at := mapping+index*4
			if not d.require_range(at,4,"FE7 animation mapping"): return
			if d.u32(at) == 0: ended = true; break
			var key: int = d.u8(at)
			var is_item: bool = d.u8(at+1) == 0
			var weapon: String = item(key,false).get("type","other") if is_item else (Data.WEAPONS[key] if key<8 else ("unarmed" if key==9 else "other"))
			var identity := "%d_%s_%d_%d_%s" % [cid,weapon,key if is_item else 0,palette,u.faction]
			if battles.animations.has(identity):
				if not battles.animations[identity].characters.has(u.rom_character_id): battles.animations[identity].characters.append(u.rom_character_id)
				continue
			var selector := {"class_id":cid,"weapon_type":d.u8(d.ptr(int(d.layout.items))+key*36+7) if is_item else key,"item_ids":[key] if is_item else [],"palette_id":palette,"bank":["player","enemy","neutral"].find(str(u.faction))}
			var profile := reader.profile(d,"fe7",selector)
			if not d.error.is_empty(): return
			profile.merge({"class_id":cid,"weapon":weapon,"characters":[u.rom_character_id],"item_ids":selector.item_ids,"faction":u.faction,"atlas":{},"frame_size":[288,160],"columns":8,"anchor":[148,88]})
			for side in ["left","right"]:
				var path: String = prefix+"battle/"+identity+"_"+side+".png"
				profile.atlas[side] = path
				assets[path] = {"kind":"battle_rom","game":"fe7","selector":selector,"side":side}
			battles.animations[identity] = profile
		if not ended: d.fail("FE7 animations","Unterminated class mapping."); return
	battles.background = battle_background(3)
	battles.platform = battle_platform(1)

func battle_background(id: int) -> String:
	var path := prefix+"battle/background_%d.png" % id
	var at: int = d.ptr(Policy.address(d,0x6b790))+(id-1)*12
	assets[path] = {"kind":"scene","graphics":[[d.ptr(at)]],"tsa":d.ptr(at+4),"palette":d.ptr(at+8),"tsa_lz":true,"palette_lz":true,"width":240,"height":160,"header":false}
	return path

func battle_platform(id: int) -> String:
	var path := prefix+"battle/platform_%d.png" % id
	assets[path] = {"kind":"platform","id":id}
	return path

func terrain_art(chapter: int, terrain: Dictionary) -> Dictionary:
	# Native chapter environment selects two terrain-ID lookup tables. This
	# stays correct with Japanese/translated terrain names and repointed art.
	var environments := [[0x532ec,0x53214],[0x53274,0x53198],[0x5327c,0x531a0],[0x53284,0x531a8],[0x5328c,0x531b0],[0x53294,0x531b8],[0x5329c,0x531c0],[0x532a4,0x531c8],[0x532ac,0x531d0],[0x532b4,0x531d8],[0x532bc,0x531e0],[0x532c4,0x531e8],[0x532cc,0x531f0],[0x532d4,0x531f8],[0x532dc,0x53200]]
	var environment: int = d.u8(d.ptr(int(d.layout.chapters))+chapter*int(d.layout.chapter_stride)+19)
	if environment >= environments.size(): d.fail("FE7 battle terrain","Unsupported environment lookup."); return {}
	var bg: int = d.ptr(Policy.address(d,environments[environment][0]))
	var floor_at: int = d.ptr(Policy.address(d,environments[environment][1]))
	var result := {}
	for tile in terrain.values():
		var background_id: int = d.u8(bg+int(tile.id))
		var platform_id: int = d.u8(floor_at+int(tile.id))
		if background_id == 0 or background_id > 64 or platform_id == 0 or platform_id > 128:
			d.fail("FE7 battle terrain","Unsupported native background/platform ID."); return {}
		result[str(int(tile.id))] = {"background":battle_background(background_id),"platform":battle_platform(platform_id)}
	return result

func patch(chapter: int, id: int, restore: bool = false) -> Dictionary:
	var result: Variant = Data.map_fields(d,{"chapter":chapter,"change":id,"fields":["x","y","width","height","terrain","mask"]},"fe7")
	if result == null: return {}
	if restore:
		# Restore only this change's cells, preserving other doors and bridges.
		var changed: Dictionary = result
		result = Data.map_fields(d,{"chapter":chapter,"fields":["x","y","width","height","terrain","mask"]},"fe7")
		if result == null: return {}
		for y in range(int(result.height)):
			for x in range(int(result.width)):
				result.mask[y][x] = y >= int(changed.y) and y < int(changed.y+changed.height) and x >= int(changed.x) and x < int(changed.x+changed.width) and changed.mask[y-int(changed.y)][x-int(changed.x)]
	result.id = "restore_%d" % id if restore else str(id)
	result.image = prefix+"maps/%d_change_%d%s.png" % [chapter,id,"_restore" if restore else ""]
	assets[result.image] = {"kind":"map","chapter":chapter}
	if not restore: assets[result.image].change = id
	return result

func escape_points(faction: String) -> Array:
	# Native nearest-reachable escape list, indexed by chapter and faction.
	# The pointers can relocate; preserve the getter's bounded record ABI.
	if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(d,0x39df0,136,[52,53,54,55,128,129,130,131],"1cba0d32d5fea698966fa9fd8cade3fe0e13b7d1be4bb847160ef10b6fcc6db1"):
		d.fail("FE7 escape AI","Changed escape-list reader."); return []
	var table: int = d.ptr(Policy.address(d,0x39e24 if faction == "enemy" else 0x39e70))
	var at: int = d.ptr(table+chapter_index*4)
	var points: Array = []
	for index in range(65):
		if not d.require_range(at+index*4,4,"FE7 escape points"): return []
		if d.u8(at+index*4) == 255: return points
		if index == 64: break
		points.append([d.u8(at+index*4),d.u8(at+index*4+1)])
	d.fail("FE7 escape AI","Unterminated escape-point list.",at)
	return []
