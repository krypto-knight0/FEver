extends RefCounted
## Personal identities stay with their character; progress lasts for one map.
const TEXT = {
	"fe7_unit_3": "After combat, gain +2 Avoid for this map (maximum +20).",
	"fe7_unit_1": "After combat, gain +2 Hit for this map (maximum +20).",
	"fe7_unit_2": "After combat, gain +2 Crit for this map (maximum +20).",
	"fe7_unit_24": "When initiating, +2 Crit per tile traveled before combat (maximum +10).",
	"fe7_unit_23": "When initiating, +2 Hit per tile traveled before combat (maximum +10).",
	"fe7_unit_29": "When initiating, +2 Avoid per tile traveled before combat (maximum +10).",
	"fe7_unit_13": "Counterattack at range 1 with any bow.",
	"fe7_unit_8": "Counterattack at range 2 with any axe.",
	"fe7_unit_17": "After healing, restore half the HP healed to the ally with the lowest HP percentage, at any distance.",
	"fe7_unit_19": "+10% weapon experience and +10 percentage points to stat growth rates.",
	"fe7_unit_28": "+10 Hit and Avoid when initiating combat.",
	"fe7_unit_35": "If uninjured since the previous own phase, +10 Crit and Avoid until injured or the next own phase.",
	"fe7_unit_38": "Play grants the ally +2 Str/Mag and +10 Hit until their next phase.",
	"fe7_unit_16": "Dealing damage doubles the next healing amount. Healing grants +5 Mag and +10 Hit through the next initiating combat.",
	"fe7_unit_44": "Start each map with +5 Str/Mag/Spd/Def/Res. Lose 1 from this bonus each even turn, becoming a penalty on turn 12.",
	"fe7_unit_26": "Other allies within 3 tiles gain +10% weapon and level XP.",
	"fe7_unit_25": "When initiating, +1 Def per tile traveled before combat (maximum +5).",
	"fe7_unit_14": "+1 maximum attack range per 2 remaining movement points, rounded down.",
	"fe7_unit_9": "+2 Atk/Spd/Def/Res during combat. After combat, take 3 damage.",
	"fe7_unit_11": "+3 Def/Res during combat while an ally is within 2 tiles.",
	"fe7_unit_6": "+3 Atk/Def during combat when not adjacent to an ally.",
	"fe7_unit_27": "After healing an ally, adjacent allies around the target recover half the HP healed, including the healer.",
	"fe7_unit_4": "+3 Atk/Spd and -3 Def/Res.",
	"fe7_unit_22": "+3 Atk/Res during combat against a foe above 75% HP.",
	"fe7_unit_51": "+3 Atk/Spd/Def/Res during combat on River, Sea, Lake or Mountain terrain.",
	"fe7_unit_30": "When initiating, +1 Spd per tile traveled before combat (maximum +5).",
	"fe7_unit_54": "If uninjured since the previous own phase, +10 Crit and +20 percentage points to Silencer's activation chance until injured or the next own phase. Requires Silencer.",
	"fe7_unit_37": "Dance grants the ally +2 Def/Res and +10 Avoid until their next phase.",
	"fe7_unit_52": "When initiating, +1 Res per tile traveled before combat (maximum +5).",
	"fe7_unit_32": "When initiating, +1 Atk per tile traveled before combat (maximum +5).",
	"fe7_unit_34": "Passable terrain costs only 1 movement point. Impassable terrain remains blocked.",
	"fe7_unit_5": "At the start of each own turn, gain +1 Atk/Spd/Def/Res (maximum +5). Reset to +0 instead if any ally is adjacent.",
	"fe7_unit_31": "When initiating, +1 Luck per tile traveled before combat (maximum +10).",
	"fe7_unit_21": "Double the support bonuses received from the paired ally.",
	"fe7_unit_15": "Double the support bonuses received from the paired ally.",
	"fe7_unit_7": "Recover 10 HP with each critical hit. After combat, lose 5 HP if no critical hit was delivered.",
	"fe7_unit_56": "Dealing damage with an axe grants +2 Atk throughout the next sword battle. Dealing damage with a sword grants +2 Atk throughout the next axe battle.",
	"fe7_unit_20": "+1 Atk/Spd/Def/Res per attached skill stack, including this personal skill (maximum +10).",
	"fe7_unit_36": "If uninjured since the previous own phase, +15 Crit until injured or the next own phase.",
	"fe7_unit_33": "During combat, +1 Atk/Spd/Def/Res per foe within 3 tiles.",
	"fe7_unit_55": "+10 Crit. Critical hits deal 10 additional damage after the critical multiplier.",
	"fe7_unit_18": "+1 Mag per learned C support, +2 per B support and +3 per A support, at any distance.",
	"fe7_unit_39": "At the start of each own turn, grant every deployed allied Lord +1 Atk/Spd/Def/Res (maximum +5). Reset these bonuses to +0 when this unit deals damage or uses an assist."
}

const FE6 = preload("res://engine/fe6_rogue_personals.gd")
const Config = preload("res://engine/personal_skill_config.gd")

static func effect_id(unit: Dictionary) -> String:
	var id := str(unit.get("rogue_personal", {}).get("id", ""))
	return str(Config.definition(id).get("effect_id", id))

static func has(unit: Dictionary, id: String) -> bool:
	return effect_id(unit) == id

static func parameter(unit: Dictionary, key: String, fallback: int) -> int:
	return int(Config.definition(str(unit.get("rogue_personal", {}).get("id", ""))).get("parameters", {}).get(key, fallback))

static func configured_stats(unit: Dictionary) -> Dictionary:
	return Config.definition(str(unit.get("rogue_personal", {}).get("id", ""))).get("stats", {})

static func title(unit: Dictionary) -> String:
	var id := str(unit.get("rogue_personal", {}).get("id", ""))
	return Config.display_name(id,str(unit.get("name","Character")).strip_edges())

static func character_identity(unit: Dictionary) -> String:
	var id := str(unit.get("id", ""))
	if unit.get("game_id", "") not in ["fe6", "fe7"]: return id
	if unit.has("fe6_unit_flags") or unit.has("native_unit_flags") or Config.definition(id).is_empty():
		id = "%s_unit_%d" % [unit.game_id,int(unit.get("rom_character_id",0))]
	# FE7's returning tutorial army has new native records. Prefer an explicit skill
	# for the new slot, otherwise follow the cartridge's conversion table.
	if unit.has("native_unit_flags") and Config.definition(id).is_empty():
		var original := str(unit.get("campaign_return_from", ""))
		if not Config.definition(original).is_empty(): id = original
	return id

static func initialize(unit: Dictionary) -> void:
	var current: Dictionary = unit.get("rogue_personal", {})
	var id := str(current.get("id", ""))
	# Personal identity belongs to this character, including fe7_unit_38/fe7_unit_37 handoffs.
	var character_id := character_identity(unit)
	if not Config.definition(character_id).is_empty(): id = character_id
	var definition := Config.definition(id)
	if definition.is_empty(): return
	var effect := str(definition.get("effect_id", id))
	if current.has("stat") or str(current.get("effect_id", current.get("id", id))) != effect:
		unit.rogue_personal_state = {}
	unit.rogue_personal = {"id":id, "effect_id":effect, "name":Config.display_name(id,str(unit.get("name","Character")).strip_edges()), "description":Config.description(id)}

static func progress(unit: Dictionary) -> Dictionary:
	return unit.get_or_add("rogue_personal_state", {})

static func temporary(unit: Dictionary, stat: String, include_aura: bool = true) -> int:
	var data: Dictionary = unit.get("rogue_personal_state", {})
	var result := int(configured_stats(unit).get(stat, 0)) if has(unit, "stat_bonus") else 0
	if (has(unit, "fe7_unit_3") and stat == "avoid") or (has(unit, "fe7_unit_1") and stat == "hit") or (has(unit, "fe7_unit_2") and stat == "crit"):
		result += mini(parameter(unit, "cap", 20), int(data.get("combats", 0)) * parameter(unit, "amount", 2))
	if has(unit, FE6.UNIT_32) and stat in ["hit", "crit"] and data.get("ready", true): result += parameter(unit, "amount", 10)
	if has(unit, "fe7_unit_35") and stat in ["crit", "avoid"] and data.get("ready", true): result += parameter(unit, "amount", 10)
	if has(unit, "fe7_unit_54") and stat == "crit" and data.get("ready", true): result += parameter(unit, "amount", 10)
	if has(unit, "fe7_unit_36") and stat == "crit" and data.get("ready", true): result += parameter(unit, "amount", 15)
	if has(unit, "fe7_unit_55") and stat == "crit": result += parameter(unit, "amount", 10)
	if stat in ["str", "magic", "speed", "def", "res"]:
		if has(unit, "fe7_unit_5"): result += mini(parameter(unit, "cap", 5), int(data.get("stacks", 0)) * parameter(unit, "amount", 1))
		if has(unit, "fe7_unit_20"): result += mini(parameter(unit, "cap", 10), attached_skills(unit) * parameter(unit, "amount", 1))
		if include_aura: result += int(data.get("fe7_unit_39_bonus", 0))
	if has(unit, "fe7_unit_4"): result += parameter(unit, "amount", 3) if stat in ["str", "magic", "speed"] else -parameter(unit, "penalty", 3) if stat in ["def", "res"] else 0
	if has(unit, "fe7_unit_16") and data.get("healing_boost", false): result += parameter(unit, "magic", 5) if stat == "magic" else parameter(unit, "hit", 10) if stat == "hit" else 0
	if has(unit, "fe7_unit_44") and stat in ["str", "magic", "speed", "def", "res"]: result += parameter(unit, "amount", 5) - int(data.get("decay", 0)) * parameter(unit, "decay", 1)
	return result

static func start_phase(state, unit: Dictionary) -> void:
	if not unit.get("rogue_personal", {}).has("id"): return
	var data := progress(unit)
	if int(data.get("phase_turn", 0)) == state.turn: return
	data.phase_turn = state.turn
	if has(unit, "fe7_unit_44") and state.turn % 2 == 0: data.decay = int(data.get("decay", 0)) + 1
	if has(unit, "fe7_unit_5"):
		data.stacks = mini(parameter(unit, "cap", 5), int(data.get("stacks", 0)) + 1) if nearby_allies(state, unit, 1).is_empty() else 0
		state.queue_skill_effect(unit, title(unit))
	if has(unit, "fe7_unit_39"):
		data.stacks = mini(parameter(unit, "cap", 5), int(data.get("stacks", 0)) + 1)
		for ally in state.units:
			if state._on_map(ally) and not state._hostile(unit, ally) and is_lord(ally):
				var before := int(progress(ally).get("fe7_unit_39_bonus", 0))
				progress(ally).fe7_unit_39_bonus = mini(parameter(unit, "cap", 5), before + parameter(unit, "amount", 1))
				if before < parameter(unit, "cap", 5): state.queue_skill_effect(ally, title(unit))
	if has(unit, "fe7_unit_35") or has(unit, "fe7_unit_54") or has(unit, "fe7_unit_36") or has(unit, FE6.UNIT_32):
		data.ready = not data.get("injured", false)
		data.injured = false

static func injured(unit: Dictionary, amount: int) -> void:
	if amount <= 0 or not (has(unit, "fe7_unit_35") or has(unit, "fe7_unit_54") or has(unit, "fe7_unit_36") or has(unit, FE6.UNIT_32)): return
	var data := progress(unit)
	data.injured = true
	data.ready = false

static func damaged(unit: Dictionary, state = null) -> void:
	if has(unit, "fe7_unit_16"): progress(unit).double_heal = true
	if has(unit, "fe7_unit_56") and unit.get("weapon", {}).get("type", "") in ["sword", "axe"]:
		progress(unit).damage_weapon = str(unit.weapon.type)
	if state != null and has(unit, "fe7_unit_39"): reset_fe7_unit_39(state, unit)

static func begin_combat(unit: Dictionary) -> void:
	if has(unit, "fe7_unit_7"): progress(unit).critical = false
	if has(unit, "fe7_unit_56"): progress(unit).erase("damage_weapon")

static func critical_hit(state, unit: Dictionary) -> void:
	if not has(unit, "fe7_unit_7"): return
	progress(unit).critical = true
	if int(unit.hp) <= 0 or not FE6.can_heal(unit): return
	var before := int(unit.hp)
	unit.hp = mini(int(unit.max_hp), before + parameter(unit, "heal", 10))
	if int(unit.hp) > before: state.queue_skill_effect(unit, title(unit))

static func attached_skills(unit: Dictionary) -> int:
	var total := 0 if unit.get("rogue_personal", {}).is_empty() else 1
	for amount in unit.get("rogue_skills", {}).values(): total += maxi(0, int(amount))
	return total

static func is_lord(unit: Dictionary) -> bool:
	if unit.has("fe6_unit_flags"): return bool(unit.get("lord",false))
	if unit.has("native_unit_flags"): return bool(int(unit.native_unit_flags) & 0x2000)
	return str(unit.get("id", "")) in ["fe7_unit_3", "fe7_unit_1", "fe7_unit_2"] or str(unit.get("class_name", "")).to_lower() in ["lord", "blade lord", "knight lord", "great lord"]

static func reset_fe7_unit_39(state, unit: Dictionary) -> void:
	progress(unit).stacks = 0
	for ally in preload("res://engine/army_roster.gd").all_units(state):
		if int(ally.get("rogue_personal_state", {}).get("fe7_unit_39_bonus", 0)) <= 0 or state._hostile(unit, ally): continue
		progress(ally).fe7_unit_39_bonus = 0
		if state._on_map(ally): state.queue_skill_effect(ally, title(unit))

static func state_stat(state, unit: Dictionary, stat: String) -> int:
	if has(unit, FE6.UNIT_11) and stat == "mov" and int(unit.hp) == int(unit.max_hp): return parameter(unit, "amount", 1)
	if has(unit, FE6.UNIT_2) and stat == "mov":
		if state.units.any(func(ally): return ally.id != unit.id and state._on_map(ally) and not state._hostile(unit, ally) and int(ally.hp) * 100 < int(ally.max_hp) * parameter(unit, "hp_percent", 75)): return parameter(unit, "amount", 3)
	return state._total_support_rank(str(unit.id)) * parameter(unit, "amount", 1) if has(unit, "fe7_unit_18") and stat == "magic" else 0

static func support_multiplier(unit: Dictionary, partner: Dictionary) -> int:
	return parameter(unit, "multiplier", 2) if (has(unit, "fe7_unit_21") and str(partner.get("support_id", partner.id)) == "fe7_unit_15") or (has(unit, "fe7_unit_15") and str(partner.get("support_id", partner.id)) == "fe7_unit_21") else 1

static func combat_finished(attacker: Dictionary, defender: Dictionary, state = null, attacker_weapon: Dictionary = {}) -> void:
	for unit in [attacker, defender]:
		if has(unit, "fe7_unit_56"):
			var data := progress(unit)
			var used_weapon: Dictionary = attacker_weapon if unit == attacker and not attacker_weapon.is_empty() else unit.get("weapon", {})
			if str(data.get("next_weapon", "")) == str(used_weapon.get("type", "")): data.erase("next_weapon")
			if data.has("damage_weapon"): data.next_weapon = "sword" if data.damage_weapon == "axe" else "axe"
			data.erase("damage_weapon")
		if state != null and has(unit, "fe7_unit_7"):
			if int(unit.hp) > 0 and not progress(unit).get("critical", false):
				var before := int(unit.hp)
				unit.hp = maxi(0, before - parameter(unit, "damage", 5))
				state.queue_skill_effect(unit, title(unit), before)
				if int(unit.hp) == 0: state._release_on_death(unit)
			progress(unit).erase("critical")
		if state != null and has(unit, "fe7_unit_9") and int(unit.hp) > 0:
			var before := int(unit.hp)
			unit.hp = maxi(0, before - parameter(unit, "damage", 3))
			state.queue_skill_effect(unit, title(unit), before)
			if int(unit.hp) == 0: state._release_on_death(unit)
		if int(unit.hp) > 0 and effect_id(unit) in ["fe7_unit_3", "fe7_unit_1", "fe7_unit_2"]:
			var data := progress(unit)
			data.combats = mini(100, int(data.get("combats", 0)) + 1)
	if has(attacker, "fe7_unit_16"): progress(attacker).healing_boost = false
	for unit in [attacker, defender]: clear_combat(unit)

static func clear_combat(unit: Dictionary) -> void:
	for key in ["fe6_combat", "fe6_combat_extra", "combat_heal_block"]: progress(unit).erase(key)

static func combat_bonus(state, unit: Dictionary, initiating: bool, foe: Dictionary = {}) -> Dictionary:
	var result := {"hit": 0, "avoid": 0, "crit": 0, "atk": 0, "speed": 0, "def": 0, "res": 0, "luck": 0, "con": 0}
	if has(unit, "combat_bonus"):
		for stat in configured_stats(unit):
			if result.has(stat): result[stat] += int(configured_stats(unit)[stat])
	if has(unit, "fe7_unit_56") and str(unit.get("rogue_personal_state", {}).get("next_weapon", "")) == str(unit.get("weapon", {}).get("type", "")) and str(unit.get("weapon", {}).get("type", "")) in ["sword", "axe"]: result.atk += parameter(unit, "amount", 2)
	if has(unit, "fe7_unit_33"):
		var foes := nearby_foes(state, unit, parameter(unit, "radius", 3)).size()
		for stat in ["atk", "speed", "def", "res"]: result[stat] += foes * parameter(unit, "amount", 1)
	if has(unit, "fe7_unit_9"):
		for stat in ["atk", "speed", "def", "res"]: result[stat] += parameter(unit, "amount", 2)
	if has(unit, "fe7_unit_11") and nearby_allies(state, unit, parameter(unit, "radius", 2)).size() > 0: result.def += parameter(unit, "amount", 3); result.res += parameter(unit, "amount", 3)
	if has(unit, "fe7_unit_6") and nearby_allies(state, unit, parameter(unit, "radius", 1)).is_empty(): result.atk += parameter(unit, "amount", 3); result.def += parameter(unit, "amount", 3)
	if has(unit, "fe7_unit_22") and int(foe.get("hp", 0)) * 100 > int(foe.get("max_hp", 0)) * parameter(unit, "hp_percent", 75): result.atk += parameter(unit, "amount", 3); result.res += parameter(unit, "amount", 3)
	if has(unit, "fe7_unit_51") and state.terrain_id_at(state.position(unit)) in [FE6.Terrain.RIVER, FE6.Terrain.SEA, FE6.Terrain.LAKE, FE6.Terrain.MOUNTAIN]:
		for stat in ["atk", "speed", "def", "res"]: result[stat] += parameter(unit, "amount", 3)
	var fe6_bonus := FE6.combat_bonus(state, unit, initiating, foe)
	for stat in fe6_bonus: result[stat] += int(fe6_bonus[stat])
	if not initiating: return result
	var tiles := int(unit.get("rogue_tiles_moved", 0)) + int(unit.get("planned_move_tiles", 0))
	if not unit.has("planned_move_tiles") and state.pending_moves.has(str(unit.id)):
		tiles += maxi(0, state.pending_moves[str(unit.id)].get("path", []).size() - 1)
	var bonus := mini(parameter(unit, "cap", 10), tiles * parameter(unit, "amount", 2))
	if has(unit, "fe7_unit_31"): result.luck += mini(parameter(unit, "cap", 10), tiles * parameter(unit, "amount", 1))
	if has(unit, "fe7_unit_24"): result.crit += bonus
	if has(unit, "fe7_unit_23"): result.hit += bonus
	if has(unit, "fe7_unit_29"): result.avoid += bonus
	if has(unit, "fe7_unit_28"): result.hit += parameter(unit, "amount", 10); result.avoid += parameter(unit, "amount", 10)
	for pair in [["fe7_unit_25", "def"], ["fe7_unit_30", "speed"], ["fe7_unit_52", "res"], ["fe7_unit_32", "atk"]]:
		if has(unit, pair[0]): result[pair[1]] += mini(parameter(unit, "cap", 5), tiles * parameter(unit, "amount", 1))
	return result

static func nearby_allies(state, unit: Dictionary, radius: int) -> Array:
	return state.units.filter(func(other): return other.id != unit.id and state._on_map(other) and not state._hostile(unit, other) and state._distance(state.position(unit), state.position(other)) <= radius)

static func nearby_foes(state, unit: Dictionary, radius: int) -> Array:
	return state.units.filter(func(other): return state._on_map(other) and state._hostile(unit, other) and state._distance(state.position(unit), state.position(other)) <= radius)

static func mentor_bonus(state, unit: Dictionary) -> int:
	if not preload("res://engine/rogue_mode.gd").active(state) or not state._on_map(unit): return 0
	var bonus := 0
	for ally in state.units:
		if state._on_map(ally) and has(ally, "fe7_unit_26") and nearby_allies(state, ally, parameter(ally, "radius", 3)).has(unit): bonus = maxi(bonus, parameter(ally, "xp_tenths", 1))
	return bonus

static func range_bonus(state, unit: Dictionary) -> int:
	if not has(unit, "fe7_unit_14"): return 0
	var cost := int(unit.get("planned_move_cost", state.pending_moves.get(str(unit.id), {}).get("cost", 0)))
	@warning_ignore("integer_division") # Intentional integer truncation.
	return maxi(0, state.effective_stat(unit, "mov") - int(unit.get("move_spent", 0)) - cost) / maxi(1, parameter(unit, "movement_per_range", 2))

static func counters(unit: Dictionary, distance: int) -> bool:
	var kind := str(unit.get("weapon", {}).get("type", ""))
	return (has(unit, "fe7_unit_13") and kind == "bow" and distance == parameter(unit, "range", 1)) or (has(unit, "fe7_unit_8") and kind == "axe" and distance == parameter(unit, "range", 2)) or (has(unit, FE6.UNIT_3) and distance == parameter(unit, "range", 2))

static func healing_amount(unit: Dictionary, amount: int) -> int:
	return amount * parameter(unit, "healing_multiplier", 2) if has(unit, "fe7_unit_16") and unit.get("rogue_personal_state", {}).get("double_heal", false) else amount

static func healed(state, unit: Dictionary, amount: int, primary: Dictionary = {}) -> void:
	if amount <= 0: return
	if has(unit, "fe7_unit_16"):
		var data := progress(unit)
		data.double_heal = false
		data.healing_boost = true
	if has(unit, "fe7_unit_27") and not primary.is_empty():
		for ally in nearby_allies(state, primary, parameter(unit, "radius", 1)):
			if state._hostile(unit, ally) or not FE6.can_heal(ally): continue
			var before := int(ally.hp)
			@warning_ignore("integer_division") # Intentional integer truncation.
			ally.hp = mini(int(ally.max_hp), before + amount * parameter(unit, "heal_percent", 50) / 100)
			if int(ally.hp) > before: state.queue_skill_effect(ally, title(unit), before)
	if not has(unit, "fe7_unit_17"): return
	var allies: Array = state.units.filter(func(u): return state._on_map(u) and not state._hostile(unit, u) and FE6.can_heal(u) and int(u.hp) < int(u.max_hp))
	allies.sort_custom(func(a, b): return int(a.hp) * int(b.max_hp) < int(b.hp) * int(a.max_hp) if int(a.hp) * int(b.max_hp) != int(b.hp) * int(a.max_hp) else str(a.id) < str(b.id))
	if allies.is_empty(): return
	var target: Dictionary = allies[0]
	@warning_ignore("integer_division") # Intentional integer truncation.
	var restored := mini(int(target.max_hp) - int(target.hp), amount * parameter(unit, "heal_percent", 50) / 100)
	var previous_hp := int(target.hp)
	target.hp += restored
	if restored > 0: state.queue_skill_effect(target, str(unit.get("rogue_personal", {}).get("name", "fe7_unit_17")), previous_hp)
	if restored > 0: state.events_log.append("%s's personal skill healed %s for %d HP." % [unit.name, target.name, restored])
