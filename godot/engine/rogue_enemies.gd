extends RefCounted
## Apply the Hard five-level enemy autolevel pass to other routes.
## Hard route formations and promoted bonuses are applied first by Difficulty.
static func apply(chapter: Dictionary) -> void:
	if chapter.get("rogue_enemy_pass", false): return
	chapter.rogue_enemy_pass = true
	# Preserve static FE7's Rogue Hard scaling. Dynamic providers already
	# supply native Hard bonuses; do not add another pass to their chapters.
	var difficulty = preload("res://engine/campaign_difficulty.gd")
	if difficulty.is_hard(chapter.get("difficulty", "normal")) and not chapter.get("dynamic_rom",false) and not str(chapter.get("id", "")).begins_with("fe6_"):
		var catalog: Dictionary = {}
		catalog.classes = {}
		visit(chapter.get("units", []), catalog)
		visit(chapter.get("events", []), catalog)
		visit(chapter.get("campaign_variants", []), catalog)
	chapter.get_or_add("rules", {}).permadeath = true
	chapter.rules.optional_convoy_merchant = true
	if difficulty.is_hard(chapter.get("difficulty", "normal")): chapter.rules.normal_mode_experience_bonus = false

static func visit(value: Variant, catalog: Dictionary) -> void:
	if value is Array:
		for entry in value: visit(entry, catalog)
	elif value is Dictionary:
		if value.get("faction", "") == "enemy" and value.has("max_hp"):
			if value.get("difficulty_stat_bonuses", {}).has("hard"): return
			var assets = preload("res://runtime/rom_assets.gd")
			if not catalog.has("classes"): catalog.classes = {}
			var class_id := str(int(value.get("rom_class_id", 0)))
			if assets.initialized() and assets.game_id == "fe7" and int(class_id) > 0 and int(class_id) <= 99 and not catalog.classes.has(class_id):
				catalog.classes[class_id] = preload("res://runtime/rom_arena.gd").class_record(assets.decoder, int(class_id), "fe7")
			var cls: Dictionary = catalog.get("classes", {}).get(str(int(value.get("rom_class_id", 0))), {})
			var random := RandomNumberGenerator.new()
			random.seed = str(value.get("id", "")).hash() + 190000
			var mapping := {"hp": "max_hp", "strength": "str", "skill": "skill", "speed": "speed", "defense": "def", "resistance": "res"}
			for source in mapping:
				var stat: String = mapping[source]
				var growth := int(cls.get("growths", {}).get(source, 0))
				var total := growth * 5
				@warning_ignore("integer_division") # Intentional integer truncation.
				var adjusted := total + random.randi_range(0, maxi(0, total / 4 - 1)) - total / 8
				@warning_ignore("integer_division") # Intentional integer truncation.
				var gain := adjusted / 100 + int(random.randi_range(0, 99) < adjusted % 100)
				value[stat] = mini(int(value.get("stat_caps", {}).get(stat, 60)), int(value.get(stat, 0)) + gain)
			value.hp = value.max_hp
			# Keep the marker so a restored or already-hard unit is not boosted twice.
			value.get_or_add("difficulty_stat_bonuses", {}).hard = {"levels": 5}
		else:
			for key in value:
				if value[key] is Dictionary or value[key] is Array: visit(value[key], catalog)
