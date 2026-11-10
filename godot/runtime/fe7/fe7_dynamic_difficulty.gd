extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## FE7 native difficulty operands. Reuse the shared deterministic stat roller;
## retain both results in one chapter and select only when starting a fresh map.
const Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Levels = preload("res://runtime/fe7/rom_fe7_autolevel.gd")

static func validate(d: RefCounted) -> bool:
	for spec in [
		[0x34d44,24,[12,20],"3ea64be67911ea71835ee9300c57011171818db6a169ef680d4dd1eab52a9816"],
		[0xa614,248,[],"532041139288843126cdb2f58629debea901a0bdad2468cf1bd5e6b3ff745c4b"],
		[0x17f70,64,[],"a5819f397ffa1cff6a9986530d968402cd0c41f3ee39ff2bdf7d54cb1a6deb15"],
		[0x17f3c,52,[],"17c95797525fb67fb6a8a8929b3597671ab511133e7ac718f1c1a4a3e9a7244f"],
		[0x7a160,56,[12,13,14,15],"6aaee81f493285d32c796c271c83a5523782f5a3825bdad073422e442a743028"],
		[0x7a198,76,[],"6cdd33193b1f4655bdc741e95423f2537510722968932306995c4a9c399c02c4"],
		[0xd6c0,68,[],"24901d4fe42d340c101a0ea30f29949fc04fe9c014e42025d68eb8dd35579ba0"],
		[0xd744,48,[],"ef53d19fb4836199d31c94d91b5d306924da79e6eca84b34c8b3678e5e063ccf"]]:
		if not Pure.signature(d,spec[0],spec[1],spec[2],spec[3]):
			d.fail("FE7 difficulty","Changed native difficulty policy.",spec[0]); return false
	return true

static func apply(d: RefCounted, unit: Dictionary, chapter: int, route: int, preparation: bool = false) -> void:
	var extra := Levels.chapter_bonus(d,chapter,route)
	# Preparation's all-enemy pass consults optional character overrides.
	# Scripted arrivals use the chapter byte directly. Stock FE7J's list is empty.
	if preparation and route == 3:
		var table: int = d.ptr(Policy.address(d,0x7a16c))
		for index in range(256):
			var row := table+index*8
			if not d.require_range(row,8,"FE7 Hard bonus overrides"): return
			if d.u8(row) == 0: break
			if d.u8(row) == int(unit.rom_character_id): extra = d.u32(row+4); break
			if index == 255: d.fail("FE7 difficulty","Unterminated Hard bonus override table."); return
	if extra > 255: d.fail("FE7 difficulty","Invalid Hard bonus level count."); return
	var normal := Levels.generate(d,unit,Levels.promoted_bonus(d,false),0,true)
	var hard := Levels.generate(d,unit,Levels.promoted_bonus(d,true),extra,true)
	if not d.error.is_empty(): return
	var changes := {}
	for key in hard:
		if hard[key] != normal[key]: changes[key] = hard[key]
	unit.merge(normal,true)
	if not changes.is_empty(): unit.rom_hard_mode = changes

static func bank(route: int, players: bool, hard: bool = false) -> int:
	return (48 if route == 3 else 40) + (0 if players else -16) + (4 if hard else 0)
