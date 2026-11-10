extends RefCounted
## FE6-specific effects. Shared FE7 effects are selected by personal_skills.json.
const Config = preload("res://engine/personal_skill_config.gd")
const Terrain = preload("res://engine/terrain_types.gd")
const UNIT_13 = "fe6_unit_13"
const UNIT_9 = "fe6_unit_9"
const UNIT_66 = "fe6_unit_66"
const UNIT_24 = "fe6_unit_24"
const UNIT_33 = "fe6_unit_33"
const UNIT_34 = "fe6_unit_34"
const UNIT_37 = "fe6_unit_37"
const UNIT_2 = "fe6_unit_2"
const UNIT_23 = "fe6_unit_23"
const UNIT_16 = "fe6_unit_16"
const UNIT_14 = "fe6_unit_14"
const UNIT_60 = "fe6_unit_60"
const UNIT_58 = "fe6_unit_58"
const UNIT_32 = "fe6_unit_32"
const UNIT_22 = "fe6_unit_22"
const UNIT_1 = "fe6_unit_1"
const UNIT_38 = "fe6_unit_38"
const UNIT_8 = "fe6_unit_8"
const UNIT_10 = "fe6_unit_10"
const UNIT_25 = "fe6_unit_25"
const UNIT_4 = "fe6_unit_4"
const UNIT_64 = "fe6_unit_64"
const UNIT_56 = "fe6_unit_56"
const UNIT_15 = "fe6_unit_15"
const UNIT_61 = "fe6_unit_61"
const UNIT_42 = "fe6_unit_42"
const UNIT_53 = "fe6_unit_53"
const UNIT_29 = "fe6_unit_29"
const UNIT_63 = "fe6_unit_63"
const UNIT_30 = "fe6_unit_30"
const UNIT_26 = "fe6_unit_26"
const UNIT_3 = "fe6_unit_3"
const UNIT_39 = "fe6_unit_39"
const UNIT_11 = "fe6_unit_11"
const HEAL_BLOCK = "fe6_unit_16_heal_block"

static func has(unit: Dictionary, effect: String) -> bool:
	var id := str(unit.get("rogue_personal", {}).get("id", ""))
	return str(Config.definition(id).get("effect_id", id)) == effect

static func parameter(unit: Dictionary, key: String, fallback: int) -> int:
	return int(Config.definition(str(unit.get("rogue_personal", {}).get("id", ""))).get("parameters", {}).get(key, fallback))

static func can_heal(unit: Dictionary) -> bool:
	return not unit.get("rogue_personal_state", {}).get("combat_heal_block", false) and not unit.get("rogue_effects", []).any(func(e): return e.get("source", "") == HEAL_BLOCK)

static func terrain_cost(unit: Dictionary, terrain: int, cost: int) -> int:
	if cost <= 0: return cost
	var ids: Array = [Terrain.DESERT, Terrain.GLACIER, Terrain.FOREST] if has(unit, UNIT_30) else Terrain.HIGHLANDS if has(unit, UNIT_26) else []
	return 1 if terrain in ids else cost

static func can_guard(state, unit: Dictionary, target: Dictionary, attacker: Dictionary) -> bool:
	if not has(unit, UNIT_1) and not has(unit, UNIT_38): return false
	if attacker.is_empty() or unit.id == target.id or not state._on_map(unit) or not state._on_map(target) or state._hostile(unit, target) or state.pending_moves.has(str(unit.id)): return false
	var magic: bool = state.rules.magic_types.has(attacker.get("weapon", {}).get("type", "")) or attacker.get("weapon", {}).get("magic_damage", false)
	var any_partner: bool = state.chapter.get("dynamic_rom",false)
	if not ((has(unit, UNIT_1) and not magic and (any_partner or state.Rogue.gender(target) == "female")) or (has(unit, UNIT_38) and magic and (any_partner or state.Rogue.gender(target) == "male"))): return false
	if state._distance(state.position(unit), state.position(target)) > parameter(unit, "radius", 2): return false
	var key: String = state._pair_key(str(unit.id), str(target.id))
	var rank := clampi(int(state.support_ranks.get(key, 0)), 0, 3)
	var data: Dictionary = unit.get("rogue_personal_state", {})
	var used := int(data.get("guard_uses", {}).get(key, 0)) if int(data.get("guard_turn", -1)) == state.turn else 0
	return used < rank

static func use_guard(state, unit: Dictionary, target: Dictionary) -> void:
	var data: Dictionary = state.Rogue.Personal.progress(unit)
	if int(data.get("guard_turn", -1)) != state.turn:
		data.guard_turn = state.turn
		data.guard_uses = {}
	var key: String = state._pair_key(str(unit.id), str(target.id))
	data.guard_uses[key] = int(data.guard_uses.get(key, 0)) + 1
	state.queue_skill_effect(unit, state.Rogue.Personal.title(unit))

static func action_movement(state, unit: Dictionary) -> void:
	if not has(unit, UNIT_53) or int(unit.hp) <= 0: return
	# Busy may already have granted a fresh action; do not replace that reward.
	if not unit.acted and not unit.get("canto_active", false): return
	var remaining: int = maxi(0, state.effective_stat(unit, "mov") - int(unit.get("move_spent", 0)))
	if remaining == 0: return
	unit.canto_active = true; unit.canto_remaining = remaining
	unit.acted = false; unit.moved = false
	state.queue_skill_effect(unit, state.Rogue.Personal.title(unit))

static func combat_bonus(state, unit: Dictionary, initiating: bool, foe: Dictionary) -> Dictionary:
	var saved: Dictionary = unit.get("rogue_personal_state", {}).get("fe6_combat", {})
	if not saved.is_empty(): return saved.duplicate()
	var result := {"atk":0, "speed":0, "def":0, "res":0, "crit":0, "con":0, "hit":0, "avoid":0}
	var terrain: int = state.terrain_id_at(state.position(unit))
	var amount := 0
	if has(unit, UNIT_64) and terrain in Terrain.WATER: amount = parameter(unit, "amount", 3)
	if has(unit, UNIT_56) and terrain in Terrain.HIGHLANDS: amount = parameter(unit, "amount", 3)
	if has(unit, UNIT_15) and int(unit.hp) == int(unit.max_hp): amount = parameter(unit, "amount", 1)
	if has(unit, UNIT_61): amount = state.Rogue.Personal.nearby_allies(state, unit, 1).size() * parameter(unit, "amount", 1)
	for stat in ["atk", "speed", "def", "res"]: result[stat] += amount
	if has(unit, UNIT_39) and int(foe.get("hp", 0)) * 100 > int(foe.get("max_hp", 0)) * parameter(unit, "hp_percent", 75):
		result.atk += parameter(unit, "amount", 3); result.res += parameter(unit, "amount", 3)
	if has(unit, UNIT_4) and initiating:
		result.hit += parameter(unit, "amount", 10); result.crit += parameter(unit, "amount", 10)
	if has(unit, UNIT_23) and int(foe.get("hp", 0)) * 100 > int(foe.get("max_hp", 0)) * parameter(unit, "hp_percent", 75): result.crit += parameter(unit, "amount", 10)
	if (has(unit, UNIT_24) or has(unit, UNIT_37) or has(unit, UNIT_25)) and not state.Rogue.Personal.nearby_allies(state, unit, parameter(unit, "radius", 2)).is_empty():
		if has(unit, UNIT_24): result.crit += parameter(unit, "amount", 10)
		elif has(unit, UNIT_25): result.hit += parameter(unit, "amount", 10)
		else: result.def += parameter(unit, "amount", 2); result.res += parameter(unit, "amount", 2)
	for ally in state.units:
		if (has(ally, UNIT_60) or has(ally, UNIT_29) or has(ally, UNIT_63)) and state._on_map(ally) and state.Rogue.Personal.nearby_allies(state, ally, parameter(ally, "radius", 2)).has(unit):
			if has(ally, UNIT_60): result.atk += parameter(ally, "amount", 2); result.def += parameter(ally, "amount", 2)
			elif has(ally, UNIT_29): result.hit += parameter(ally, "amount", 10)
			else: result.avoid += parameter(ally, "amount", 10)
	if initiating and has(unit, UNIT_58):
		var tiles := int(unit.get("rogue_tiles_moved", 0)) + int(unit.get("planned_move_tiles", 0))
		if not unit.has("planned_move_tiles") and state.pending_moves.has(str(unit.id)): tiles += maxi(0, state.pending_moves[str(unit.id)].get("path", []).size() - 1)
		result.con += mini(parameter(unit, "cap", 5), tiles * parameter(unit, "amount", 1))
	return result

static func conditional_bonus(state, unit: Dictionary, foe: Dictionary, own: Dictionary, other: Dictionary) -> Dictionary:
	var saved: Dictionary = unit.get("rogue_personal_state", {}).get("fe6_combat_extra", {})
	if not saved.is_empty(): return saved.duplicate()
	var result := {"str":0, "speed":0, "crit":0, "atk":0, "def":0, "res":0, "hit":0}
	var effect := str(Config.definition(str(unit.get("rogue_personal", {}).get("id", ""))).get("effect_id", ""))
	if effect not in [UNIT_33, UNIT_34, UNIT_22, UNIT_9, UNIT_14, UNIT_8, UNIT_10, UNIT_42]: return result
	# Evaluate hit thresholds together, before either threshold bonus applies.
	if (has(unit, UNIT_33) or has(unit, UNIT_34)) and int(state._combat_stats(unit, foe, false).hit) < parameter(unit, "hit_percent", 80):
		result["str" if has(unit, UNIT_33) else "speed"] = parameter(unit, "amount", 3 if has(unit, UNIT_33) else 2)
	if effect in [UNIT_33, UNIT_34]: return result
	var own_speed := combat_speed(state, unit, foe, own)
	var other_speed := combat_speed(state, foe, unit, other)
	var threshold := int(state.rules.double_threshold)
	if has(unit, UNIT_9) and other_speed - own_speed < threshold:
		result.atk += parameter(unit, "amount", 2); result.def += parameter(unit, "amount", 2)
	if has(unit, UNIT_14) and own_speed - other_speed < threshold: result.atk += parameter(unit, "amount", 4)
	if has(unit, UNIT_22): result.atk += clampi((own_speed - other_speed - threshold) * parameter(unit, "amount", 1), 0, parameter(unit, "cap", 5))
	var difference: int = state.effective_stat(unit, "def") + int(own.def) - state.effective_stat(foe, "def") - int(other.def)
	# fe6_unit_9' speed condition is resolved before comparisons of combat Defense.
	if has(foe, UNIT_9) and own_speed - other_speed < threshold: difference -= parameter(foe, "amount", 2)
	if has(unit, UNIT_8): result.atk += clampi(difference * parameter(unit, "amount", 1), 0, parameter(unit, "cap", 5))
	if has(unit, UNIT_10): result.res += clampi(difference * parameter(unit, "amount", 1), 0, parameter(unit, "cap", 5))
	if has(unit, UNIT_42):
		var resistance: int = state.effective_stat(unit, "res") + int(own.res) - state.effective_stat(foe, "res") - int(other.res)
		if has(foe, UNIT_10): resistance -= clampi(-difference * parameter(foe, "amount", 1), 0, parameter(foe, "cap", 5))
		result.hit += clampi(resistance * parameter(unit, "amount", 2), 0, parameter(unit, "cap", 20))
	return result

static func combat_speed(state, unit: Dictionary, foe: Dictionary, bonus: Dictionary) -> int:
	var extra := 0
	if has(unit, UNIT_34) and int(state._combat_stats(unit, foe, false).hit) < parameter(unit, "hit_percent", 80): extra = parameter(unit, "amount", 2)
	return maxi(0, state.effective_stat(unit, "speed") + int(bonus.speed) + extra - maxi(0, int(unit.get("weapon", {}).get("weight", 0)) - state.effective_stat(unit, "con") - int(bonus.con)))
