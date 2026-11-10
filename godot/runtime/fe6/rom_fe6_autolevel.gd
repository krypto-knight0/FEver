extends RefCounted
## Fresh FE6 units use live bases, deployment levels, growths and caps.
## Stable unit identities seed generation independently of ROM/import positions.
const Data = preload("res://runtime/rom_data.gd")

static func prepare(d: RefCounted, value: Variant) -> bool:
	visit(d, value, {})
	return d.error.is_empty()

static func visit(d: RefCounted, value: Variant, cache: Dictionary) -> void:
	if not d.error.is_empty(): return
	if value is Array:
		for child in value: visit(d, child, cache)
	elif value is Dictionary:
		if value.has("id") and value.has("max_hp") and value.has("rom_character_id") and value.get("source_deployment") is Dictionary and value.get("source_stat_offsets") is Dictionary:
			var key := JSON.stringify([value.id,value.source_stat_offsets,value.source_deployment,value.get("faction","")])
			if not cache.has(key): cache[key] = generate(d,value)
			value.erase("autolevel_provenance")
			value.erase("rom_hard_mode")
			value.merge(cache[key].duplicate(true),true)
			return
		for child in value.values(): visit(d,child,cache)

static func generate(d: RefCounted, unit: Dictionary) -> Dictionary:
	var character := str(unit.source_stat_offsets.character).hex_to_int()
	var cl := str(unit.source_stat_offsets["class"]).hex_to_int()
	var base: Variant = Data.unit_fields(d,{"character":character,"class":cl,"fields":Data.STATS},"fe6")
	if base == null or not d.require_range(cl,72,"Autolevel class"): return {}
	# This port uses deterministic generation, not the cartridge's saved RNG.
	# Seed from stable identity so relocating a group does not reroll its stats.
	var rng := RandomNumberGenerator.new()
	rng.seed = str(unit.id).sha256_text().substr(0, 15).hex_to_int()
	var personal: bool = unit.faction == "player"
	var levels := maxi(0, int(unit.source_deployment.get("level",unit.level)) - (d.u8(character + 11) if personal else 1))
	var stages: Array = [["base", levels]] if unit.source_deployment.autolevel else []
	for step in stages:
		var stage: int = step[1]
		if stage <= 0: continue
		for i in range(7):
			var stat: String = Data.STATS[i]
			var growth: int = d.u8(character + 28 + i) if personal else d.u8(cl + 27 + i)
			var gain := 0
			if personal:
				@warning_ignore("integer_division") # Intentional integer truncation.
				for level in range(stage): gain += growth / 100 + int(rng.randi_range(0, 99) < growth % 100)
			else:
				var total: int = growth * stage
				@warning_ignore("integer_division") # Intentional integer truncation.
				var adjusted: int = total + rng.randi_range(0, maxi(1, total / 4) - 1) - total / 8
				@warning_ignore("integer_division") # Intentional integer truncation.
				gain = adjusted / 100 + int(rng.randi_range(0, 99) < adjusted % 100)
			base[stat] = mini(int(base[stat]) + gain, 30 if stat == "luck" else d.u8(cl + 19 + i))
	base.hp = base.max_hp
	return base
