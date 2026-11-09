extends RefCounted
## Fresh chapter generation only. Bases, growths, levels and caps come from ROM;
## stable unit identities seed the port's RNG independently of import order.
const Data = preload("res://runtime/rom_data.gd")

static func promoted_bonus(d: RefCounted, hard: bool) -> int:
	var jp: bool = d.layout.get("event_variant","") == "fe7j"
	return d.u8((0x34d58 if hard else 0x34d50) if jp else (0x34880 if hard else 0x34878))

static func chapter_bonus(d: RefCounted, chapter: int, route: int) -> int:
	if route != 3 or chapter < 0: return 0
	var at: int = d.ptr(int(d.layout.get("chapters",0x31580)))+chapter*int(d.layout.get("chapter_stride",152))
	return d.u8(at+20)

static func generate(d: RefCounted, unit: Dictionary, promoted_levels: int, enemy_levels: int, promoted_npcs: bool = false) -> Dictionary:
	var character := str(unit.source_stat_offsets.get("character", "")).hex_to_int()
	var cl := str(unit.source_stat_offsets.get("class", "")).hex_to_int()
	var base: Variant = Data.unit_fields(d, {"character":character, "class":cl, "fields":Data.STATS+["promoted"]}, "fe7")
	if base == null or not d.require_range(cl,84,"Autolevel class"): return {}
	var level := int(unit.source_deployment.get("level",unit.get("level",1)))
	if level < 1 or level > 31: d.fail("FE7 autolevel", "Invalid deployment level."); return {}
	var stages: Array = []
	var automatic: bool = unit.source_deployment.get("autolevel",false)
	if automatic: stages.append(["base",maxi(0,level-1)])
	var enemy: bool = unit.get("faction") == "enemy"
	# Route difficulty policies mirror the native extra enemy-level passes.
	# These are generation rules; no precomputed stat rolls are retained.
	if (enemy or (promoted_npcs and unit.get("faction") == "neutral")) and automatic and base.promoted: stages.append(["promoted",promoted_levels])
	if enemy: stages.append(["hard",enemy_levels])
	base.erase("promoted")
	base.difficulty_stat_bonuses = {}
	for stage in stages:
		var levels := int(stage[1])
		if levels <= 0: continue
		var rng := RandomNumberGenerator.new()
		rng.seed = ("fe7:"+str(unit.id)+":"+str(stage[0])).sha256_text().substr(0,15).hex_to_int()
		for i in range(6):
			var growth: int = d.u8(cl+27+i)
			var total := growth*levels
			@warning_ignore("integer_division") # Intentional integer truncation.
			var adjusted := total+rng.randi_range(0,maxi(0,total/4-1))-total/8
			@warning_ignore("integer_division") # Intentional integer truncation.
			var gain := adjusted/100+int(rng.randi_range(0,99)<adjusted%100)
			var stat: String = Data.STATS[i]
			base[stat] = mini(int(base[stat])+gain,d.u8(cl+19+i))
		if stage[0] != "base": base.difficulty_stat_bonuses[stage[0]] = {"levels":levels}
	base.hp = base.max_hp
	return base
