extends RefCounted
## A data-driven GBA-style experience policy; class metadata belongs to the pack.
static func amount(unit: Dictionary, enemy: Dictionary, damaged: bool, killed: bool, normal_mode_bonus: bool = false, silencer_kill: bool = false, game: String = "fe7") -> int:
	if not damaged: return 1
	var power := maxi(1, int(unit.get("experience_power", 3)))
	var enemy_power := maxi(1, int(enemy.get("experience_power", 3)))
	var promoted := bool(unit.get("promoted", false))
	var enemy_promoted := bool(enemy.get("promoted", false))
	var minimum := 0 if game == "fe6" else 1
	@warning_ignore("integer_division") # Intentional integer truncation.
	var damage_exp := maxi(minimum, int((31 + int(enemy.level) + (20 if enemy_promoted else 0) - int(unit.level) - (20 if promoted else 0)) / power))
	if not killed: return damage_exp
	var own_value := int(unit.level) * power + int(unit.get("experience_bonus", 60 if promoted else 0))
	var enemy_value := int(enemy.level) * enemy_power + int(enemy.get("experience_bonus", 60 if enemy_promoted else 0))
	var difference := float(enemy_value - own_value)
	if game != "fe6" and normal_mode_bonus and difference <= 0: difference = enemy_value - own_value / 2.0
	var bonus := 20 + (40 if enemy.get("boss", false) else 0) + int(enemy.get("experience_defeat_bonus", 0))
	return clampi(int(ceil(damage_exp + maxf(0, difference + bonus) * (2 if silencer_kill and game != "fe6" else 1))), minimum, 100)
