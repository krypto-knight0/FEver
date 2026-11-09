extends RefCounted
const STAT_REVEAL_DELAY := 0.55

static func magic(unit: Dictionary) -> bool:
	if unit.has("rogue_native_types"):
		return ["staff", "anima", "light", "dark"].any(func(kind): return kind in unit.rogue_native_types)
	var ranks: Dictionary = unit.get("weapon_exp", {})
	return ["staff", "anima", "light", "dark"].any(func(kind): return int(ranks.get(kind, 0)) > 0 or kind in unit.get("weapon_types", []))

static func power(unit: Dictionary, short: bool = false) -> String:
	return ("Mag" if short else "Magic") if magic(unit) else ("Str" if short else "Strength")

static func power_key(unit: Dictionary) -> String:
	return "magic" if magic(unit) and unit.has("magic") else "str"

static func level_keys(unit: Dictionary) -> Array:
	return ["max_hp", power_key(unit), "skill", "speed", "luck", "def", "res"]
