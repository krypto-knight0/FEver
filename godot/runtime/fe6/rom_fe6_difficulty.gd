extends RefCounted
## Native FE6 difficulty operands and missing early hard-only deployments.
## Bonuses are prepared at import, then selected only for a fresh chapter.
const Groups = preload("res://runtime/rom_deployments.gd")
const Reader = preload("res://runtime/fe6/rom_fe6_events.gd")
const Data = preload("res://runtime/rom_data.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Runner = preload("res://engine/native_event_runner.gd")

static func fail(d: RefCounted, message: String) -> bool:
	d.fail("FE6 difficulty", message)
	return false

static func parameters(d: RefCounted, chapter: int) -> Variant:
	# GetHardModeBonusLevelsByPid: the override pointer can relocate; the
	# remaining instructions establish entry size and chapter field offset.
	if not Pure.signature(d,0x6bab8,56,[12,13,14,15],"718cd9905e5978cb0b2734aa488ae15ae94b94fb23c36be7d9f0aa6ac1c40184") or not Pure.signature(d,0x6baf0,68,[],"1b1b3558018085db1acd3264e6f241d5a796e72c5a6f9f053b02313e4b69c886") or not Pure.signature(d,0xccf0,168,[],"c53bacffbc46b5094a8f2100bd11a9b832668772bdaee8b5d9c586e69918dfbb"):
		fail(d,"Unrecognized hard bonus routine."); return null
	var table := Groups.pointer(d,0x2bb20)
	var overrides := Groups.pointer(d,0x6bac4)
	if table < 0 or overrides < 0 or not d.require_range(table+chapter*68,68,"Difficulty chapter record"): return null
	var levels: int = d.u8(table+chapter*68+19)
	var result := {"levels":levels,"overrides":{},"opening_passes":0}
	# Native values fit comfortably within this limit; reject corrupt inputs
	# before allocating/generating units rather than silently clamping them.
	if levels > 30: fail(d,"Excessive chapter bonus levels."); return null
	var ended := false
	for i in range(256):
		var at := overrides+i*8
		if not d.require_range(at,8,"Hard bonus override"): return null
		var character: int = d.u8(at)
		if character == 0: ended = true; break
		var bonus_levels: int = d.u32(at+4)
		if bonus_levels > 30 or result.overrides.has(character): fail(d,"Invalid hard bonus override."); return null
		result.overrides[character] = bonus_levels
	if not ended: fail(d,"Unterminated hard bonus overrides."); return null
	var root := Reader.script(d,chapter,{"event":"turn","condition":0})
	if root < 0: return null
	for command in Reader.commands(d,root):
		if command.opcode == 0x17 and d.u32(int(command.offset)+4) == 0x0806baf1:
			result.opening_passes += 1
	if d.error.is_empty(): return result
	return null

static func bonus(d: RefCounted, unit: Dictionary, params: Dictionary, initial: bool, extra_passes: int) -> bool:
	if unit.get("faction") != "enemy": return true
	if not unit.get("source_stat_offsets") is Dictionary or not unit.get("stat_caps") is Dictionary:
		return fail(d,"Enemy lacks native stat records.")
	var character := int(unit.rom_character_id)
	var overridden := int(params.overrides.get(character,params.levels))
	var stages: Array = [overridden if initial else int(params.levels)]
	for i in range(extra_passes): stages.append(overridden)
	var cl := str(unit.source_stat_offsets["class"]).hex_to_int()
	if not d.require_range(cl,72,"Hard bonus class record"): return false
	var rng := RandomNumberGenerator.new()
	# Independent of ROM address, import order and campaign RNG. Saves carry
	# the selected stats; loading one never runs this pass against live units.
	rng.seed = ("fe6_hard:"+str(unit.id)).sha256_text().substr(0,15).hex_to_int()
	var changes := {}
	for i in range(Data.STATS.size()):
		var stat: String = Data.STATS[i]
		var growth: int = d.u8(cl+27+i)
		var value := int(unit[stat])
		for levels in stages:
			if levels == 0: continue
			var total := growth*int(levels)
			@warning_ignore("integer_division") # Intentional integer truncation.
			var adjusted := total+rng.randi_range(0,maxi(0,total/4-1))-total/8
			@warning_ignore("integer_division") # Intentional integer truncation.
			var gain := adjusted/100+int(rng.randi_range(0,99) < adjusted%100)
			# UnitCheckStatOverflow uses 80 HP for red units, independently of
			# the class/player HP cap. The other caps are native class fields.
			var cap: int = 80 if i == 0 else (30 if i == 6 else d.u8(cl+19+i))
			value = mini(value+gain,cap)
		changes[stat] = value
	changes.hp = changes.max_hp
	var total_levels := 0
	for stage in stages: total_levels += int(stage)
	changes.difficulty_stat_bonuses = unit.get("difficulty_stat_bonuses",{}).duplicate(true)
	changes.difficulty_stat_bonuses.hard = {"levels":total_levels,"passes":stages}
	unit.rom_hard_mode = changes
	return d.error.is_empty()
