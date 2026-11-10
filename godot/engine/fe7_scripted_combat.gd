extends RefCounted
## Event combat is resolved on the native runner's private placement model.
## Commit only changed fields; playback never calculates damage a second time.
const Flags = preload("res://engine/native_event_flags.gd")

static func valid(c: Dictionary) -> bool:
	if c.has("ring") and (not c.ring is Dictionary or not c.ring.get("ring_bonuses") is Dictionary or not valid_ring(c.ring.ring_bonuses)): return false
	if c.has("ballista") and c.ballista != true: return false
	if not Flags.integer(c.get("attacker"),1,255) or not Flags.integer(c.get("defender"),1,255) or c.attacker == c.defender or not c.get("automatic") is bool or not c.get("rounds") is Array or c.rounds.size() > 64: return false
	if c.automatic: return c.rounds.is_empty()
	return not c.rounds.is_empty() and c.rounds.all(func(r):return r is Dictionary and r.size() == (5 if r.has("silencer") else 4) and r.get("silencer",false) is bool and r.get("counter") is bool and r.get("miss") is bool and r.get("critical") is bool and Flags.integer(r.get("damage"),0,127))

static func resolve(b, c: Dictionary) -> Dictionary:
	var attackers: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.attacker) and int(u.hp) > 0)
	var defenders: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.defender) and int(u.hp) > 0)
	if attackers.is_empty() or defenders.is_empty(): return {"error":"Scripted combat needs two living participants."}
	var a: Dictionary = attackers[0]; var z: Dictionary = defenders[0]
	if c.has("ring"):
		# The event supplies a synthetic one-use ring for presentation. Its
		# following status callback owns the bonus; no HP or inventory cost.
		return {"error":"","op":"combat_commit","updates":{},"deaths":[],"presentation":{"units":[a.duplicate(true),z.duplicate(true)],"strikes":[],"ring":c.ring.duplicate(true),"terrain":b.terrain.duplicate(),"rules":b.rules.duplicate(true),"native_battle_terrain":b.chapter.get("native_battle_terrain",{}).duplicate(true)}}
	var before: Array = b.units.duplicate(true)
	var held_weapon: Dictionary = a.weapon
	if c.get("ballista",false):
		var siege: Dictionary = b.emplacement_weapon(a)
		if siege.is_empty() or int(siege.uses) <= 0: return {"error":"Scripted ballista attack requires a usable emplacement."}
		a.weapon = siege
	# Native event combat may select a usable weapon from another inventory
	# slot, and may challenge an allied/neutral recruit.
	for unit in [a,z]:
		if b._armed(unit): continue
		for index in range(unit.inventory.size()):
			if not b.can_equip_weapon(unit,unit.inventory[index]): continue
			var previous: Dictionary = unit.weapon
			unit.weapon = unit.inventory[index]
			if previous.is_empty(): unit.inventory.remove_at(index)
			else: unit.inventory[index] = previous
			break
	if not b._armed(a) or not b._armed(z): return {"error":"Scripted combat requires supported equipped weapons."}
	var snapshots := [a.duplicate(true),z.duplicate(true)]
	var strikes: Array = []
	b.combat_initiator = a.id
	if c.automatic:
		for pair in b.combat_order(a,z,true):
			if int(pair[0].hp) <= 0 or int(pair[1].hp) <= 0: break
			if b._armed(pair[0]): strikes.append(b._strike(pair[0],pair[1]))
	else:
		for hit in c.rounds:
			var actor: Dictionary = z if hit.counter else a
			var victim: Dictionary = a if hit.counter else z
			if int(actor.hp) <= 0 or int(victim.hp) <= 0: break
			var old_hp := int(victim.hp)
			var damage := mini(old_hp,0 if hit.miss else int(hit.damage))
			if hit.get("silencer",false) and not hit.miss: damage = old_hp
			var stats: Dictionary = b._combat_stats(actor,victim)
			var counter: Dictionary = b._combat_stats(victim,actor)
			victim.hp = old_hp-damage
			b._consume_use(actor.weapon,actor)
			var strike := {"phase":b.phase,"attacker_id":actor.id,"defender_id":victim.id,"damage_target_id":victim.id,"hit":not hit.miss,"critical":hit.critical,"damage":damage,"previous_hp":old_hp,"remaining_hp":victim.hp,"attacker_previous_hp":actor.hp,"attacker_remaining_hp":actor.hp,"healed":0,"attacker_stats":stats,"defender_stats":counter}
			if hit.get("silencer",false): strike.silencer = true; strike.critical = true
			strike.weapon_experience = b._award_weapon_experience(actor,actor.weapon,int(victim.hp) == 0)
			strikes.append(strike)
			if int(victim.hp) == 0:
				if victim.faction == "player": victim.casualty_mode = "permanent" if b.rules.get("permadeath",true) else "injured"
				b._release_on_death(victim)
	b.combat_initiator = ""
	if c.get("ballista",false): a.last_used_weapon = b._weapon_signature(a.weapon); a.weapon = held_weapon
	a.acted = true
	var updates := {}; var deaths: Array = []
	for original in before:
		var current: Dictionary = b.get_unit(str(original.id))
		var changed := {}
		for key in current:
			if not original.has(key) or current[key] != original[key]: changed[key] = current[key]
		if not changed.is_empty(): updates[original.id] = changed.duplicate(true)
		if int(original.hp) > 0 and int(current.hp) == 0: deaths.append(original.id)
	var result := {"error":"","op":"combat_commit","updates":updates,"deaths":deaths,"presentation":{"units":snapshots,"strikes":strikes,"terrain":b.terrain.duplicate(),"rules":b.rules.duplicate(true),"native_battle_terrain":b.chapter.get("native_battle_terrain",{}).duplicate(true)}}
	if c.get("ballista",false): result.emplacements = b.chapter.emplacements.duplicate(true)
	return result

static func valid_ring(bonuses: Dictionary) -> bool:
	return not bonuses.is_empty() and bonuses.keys().all(func(k):return k in ["attack","def","res","crit","avoid"]) and bonuses.values().all(func(v):return Flags.integer(v,10,10))
