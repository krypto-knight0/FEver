extends RefCounted
## ArenaGenOpposingJid / ArenaGenBaseWeapons literal-pool references.
## Lists, character bases, class growths/caps and weapon definitions stay in ROM.
const Data = preload("res://runtime/rom_data.gd")
const FIELDS := ["hp", "strength", "skill", "speed", "defense", "resistance", "luck"]

static func read(d: RefCounted, items: Dictionary, game: String = "fe6") -> Dictionary:
	if game not in ["fe6", "fe7"]: d.fail("Arena", "Unknown cartridge profile."); return {}
	var result := {"game_id":game, "lists":{}, "basic":[], "rankup":[], "classes":{}, "weapons":{}}
	var layout: Array = d.layout.get("arena_layout",[0x2eb58,0x2eb64,0x2ebb4,0x2f1c0,0x2eddc,0x178f0] if game == "fe7" else [0x299fc,0x29a08,0x29a58,0x29c44,0x29c64,0x176e0])
	var lists := [["melee",layout[0]],["bow",layout[1]],["magic",layout[2]]]
	for entry in lists:
		var at: int = d.ptr(entry[1])
		var list: Array = []
		for i in range(128):
			var id: int = d.u8(at+i)
			if id == 0: break
			if id > (99 if game == "fe7" else 75): d.fail("Arena", "Invalid opponent class.", at+i); return {}
			list.append(id)
		if list.is_empty() or list.size() == 128: d.fail("Arena", "Invalid opponent list.", at); return {}
		result.lists[entry[0]] = list
		for id in list:
			if result.classes.has(str(id)): continue
			var cls := class_record(d, int(id), game)
			if cls.is_empty(): return {}
			result.classes[str(id)] = cls
	var basic: int = d.ptr(int(layout[3]))
	for i in range(8): result.basic.append(d.u8(basic+i))
	var upgrades: int = d.ptr(int(layout[4]))
	for i in range(128):
		var id: int = d.u8(upgrades+i)
		result.rankup.append(id)
		if id == 255: break
	if result.rankup[-1] != 255: d.fail("Arena", "Unterminated weapon upgrades.", upgrades); return {}
	for id in result.basic + result.rankup:
		if id in [0,255]: continue
		if not items.has(int(id)): d.fail("Arena", "Arena weapon is missing from the ROM item catalog.", upgrades); return {}
		result.weapons[str(int(id))] = items[int(id)].duplicate(true)
	return result if d.error.is_empty() else {}

static func class_record(d: RefCounted, id: int, game: String = "fe6") -> Dictionary:
	if game == "fe7": return fe7_class_record(d, id)
	var at: int = d.ptr(0x176e0) + id*72
	var character: int = d.ptr(0x17680) + 0xe1*48
	if not d.require_range(at,72) or not d.require_range(character,48): return {}
	if d.u8(at+4) != id: d.fail("Arena", "Class identity mismatch.", at); return {}
	var cls := {"name":d.text(d.u16(at)), "attributes":"0x%x" % d.u32(at+36), "constitution":d.u8(at+17), "movement":d.u8(at+18), "bases":{}, "growths":{}, "caps":{}, "weapon_ranks":{}}
	var experience: Variant = Data.class_experience(d, id, game)
	if experience == null: return {}
	cls.experience = experience
	for i in range(FIELDS.size()):
		var personal: int = d.u8(character+12+i)
		if personal >= 128: personal -= 256
		cls.bases[FIELDS[i]] = maxi(0, personal+(d.u8(at+11+i) if i<6 else 0))
		cls.growths[FIELDS[i]] = d.u8(at+27+i)
		cls.caps[FIELDS[i]] = 80 if i == 0 else (30 if i == 6 else d.u8(at+19+i))
	for i in range(Data.WEAPONS.size()):
		var personal: int = d.u8(character+20+i)
		cls.weapon_ranks[Data.WEAPONS[i]] = personal if personal else d.u8(at+40+i)
	return cls

static func fe7_class_record(d: RefCounted, id: int) -> Dictionary:
	if id < 1 or id > 99: d.fail("Arena", "Invalid class identifier."); return {}
	var at: int = d.ptr(int(d.layout.get("arena_layout",[0,0,0,0,0,0x178f0])[5])) + id*84
	if not d.require_range(at,84,"Arena class"): return {}
	if d.u8(at+4) != id: d.fail("Arena", "Class identity mismatch.", at); return {}
	var cls := {"name":d.text(d.u16(at)), "attributes":"0x%x" % d.u32(at+40), "constitution":d.u8(at+17), "movement":d.u8(at+18), "bases":{}, "growths":{}, "caps":{}, "weapon_ranks":{}}
	for i in range(FIELDS.size()):
		var base: int = d.u8(at+11+i) if i < 6 else 0
		cls.bases[FIELDS[i]] = base-256 if base >= 128 else base
		cls.growths[FIELDS[i]] = d.u8(at+27+i)
		cls.caps[FIELDS[i]] = d.u8(at+19+i) if i < 6 else 30
	for i in range(Data.WEAPONS.size()): cls.weapon_ranks[Data.WEAPONS[i]] = d.u8(at+44+i)
	return cls if d.error.is_empty() else {}
