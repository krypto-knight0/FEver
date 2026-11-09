extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## FE7 promotion eligibility follows the native item-ID switch. Class lists,
## destinations, gains, ranks and terrain tables are read from the cartridge.
const Data = preload("res://runtime/rom_data.gd")
const ITEMS := {99:[0x19,0x2798c],100:[0x1a,0x27994],101:[0x1b,0x2799c],102:[0x1c,0x279a4],103:[0x1d,0x279ac],135:[0x2e,0x279b4],137:[0x30,0x279cc,0x279d0],139:[0x31,0x279d8],150:[0x32,0x27a00]}

static func accepts(id: int, selector: int) -> bool:
	return ITEMS.has(id) and ITEMS[id][0] == selector

static func catalog(d: RefCounted, prefix: String, assets: Dictionary) -> Dictionary:
	var result := {"schema_version":1,"classes":{},"promotions":[]}
	if d.u16(Policy.address(d,0x27896))&0xff00 != 0x2800:
		d.fail("FE7 promotion","Changed minimum-level comparison."); return {}
	var eligible := {}
	for id in ITEMS:
		var item: int = d.ptr(int(d.layout.items))+int(id)*36
		if d.u8(item+6) != id or not accepts(id,d.u8(item+30)): continue
		for operand in ITEMS[id].slice(1):
			var pointer: int = d.ptr(Policy.address(d,operand))
			var ended := false
			for index in range(256):
				if not d.require_range(pointer+index,1,"FE7 promotion list"): return {}
				var cid: int = d.u8(pointer+index)
				if cid == 0: ended = true; break
				var allowed: Array = eligible.get_or_add(cid,[])
				if not allowed.has(id): allowed.append(id)
			if not ended: d.fail("FE7 promotion","Unterminated eligibility list.",pointer); return {}
	for cid in eligible:
		var source := definition(d,int(cid),prefix,assets)
		if not d.error.is_empty(): return {}
		if source.promoted: continue
		var at: int = d.ptr(int(d.layout.record_layout[3]))+int(cid)*84
		var target: int = d.u8(at+5)
		var promoted := definition(d,target,prefix,assets)
		if not d.error.is_empty(): return {}
		result.classes[str(cid)] = source; result.classes[str(target)] = promoted
		result.promotions.append({"from_class":cid,"to_class":target,"items":eligible[cid],"minimum_level":d.u8(Policy.address(d,0x27896))+1})
	return result

static func definition(d: RefCounted, cid: int, prefix: String, assets: Dictionary) -> Dictionary:
	var at: int = d.ptr(int(d.layout.record_layout[3]))+cid*84
	if cid < 1 or not d.require_range(at,84,"FE7 promotion class") or d.u8(at+4) != cid:
		d.fail("FE7 promotion","Invalid class identity.",at); return {}
	var flags: int = d.u32(at+40)
	var result := {"rom_class_id":cid,"class_name":d.text(d.u16(at)),"promoted":bool(flags&0x100),
		"stat_caps":{"luck":30,"con":d.u8(at+25),"mov":15},"base_stats":{"con":d.u8(at+17),"mov":d.u8(at+18)},
		"promotion_rank_difference":true,"promotion_gains":{},"weapon_exp":{},"weapon_types":[],"movement_costs":{},"movement_costs_rain":{},"terrain_bonuses":{},"sprites":{},
		"experience_power":d.u8(at+26),"experience_bonus":(40 if cid in [31,45,62] else 60) if flags&0x100 else 0,"experience_defeat_bonus":20 if cid in [60,61,62] else 0,
		"canto":bool(flags&2),"flying":bool(flags&0x1000),"mounted":bool(flags&1),"can_lockpick":bool(flags&8),"can_steal":bool(flags&4) or cid in [62,63],
		"critical_bonus":15 if flags&0x40 else 0,"silencer":bool(flags&0x2000000),"multiple_s_ranks":cid in [66,69]}
	for index in range(6):
		result.stat_caps[Data.STATS[index]] = d.u8(at+19+index)
		var gain: int = d.u8(at+34+index)
		result.promotion_gains[Data.STATS[index]] = gain-256 if gain >= 128 else gain
	for index in range(8):
		var rank: int = d.u8(at+44+index)
		result.weapon_exp[Data.WEAPONS[index]] = rank
		if rank: result.weapon_types.append(Data.WEAPONS[index])
	result.can_use_staves = result.weapon_exp.staff > 0
	if flags&1: result.aid_base = 20 if flags&0x4000 else 25
	var pointers: Array = [d.ptr(at+56),d.ptr(at+60),d.ptr(at+68),d.ptr(at+72),d.ptr(at+76)]
	for tid in range(Data.SYMBOLS.length()):
		var symbol: String = Data.SYMBOLS[tid]
		for index in range(2):
			var cost: int = d.u8(pointers[index]+tid)
			result["movement_costs" if index == 0 else "movement_costs_rain"][symbol] = cost-256 if cost >= 128 else cost
		result.terrain_bonuses[symbol] = {"avoid":d.u8(pointers[2]+tid),"defense":d.u8(pointers[3]+tid),"resistance":d.u8(pointers[4]+tid)}
	for faction in ["player","enemy","npc"]:
		var path := prefix+"rom/sprites/%03d_%s.png" % [d.u8(at+6),faction]
		result.sprites[faction] = path
		assets[path] = {"kind":"sprite","id":d.u8(at+6),"faction":["player","enemy","npc"].find(faction)}
		assets[path.trim_suffix(".png")+"_idle.png"] = assets[path].merged({"idle":true})
	return result
