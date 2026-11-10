extends RefCounted
const NativeEvents = preload("res://engine/native_event_runner.gd")
## Run state lives in chapter.rogue; skills live on units, including casualties.
## Numeric effects stack additively. Binary/action-order effects do not stack.
const Army = preload("res://engine/army_roster.gd")
const Personal = preload("res://engine/rogue_personals.gd")
const ENEMY_REWARD_ONLY = ["fast_fingers", "reroll", "expert", "cross_training", "gift_of_gab", "resurrect"]
# Compatible cartridges need not retain stock genders or English class names.
# Armor shields currently use those names; omit them alongside gender skills.
const DYNAMIC_UNAVAILABLE = ["passion", "platonic", "svalinn_shield"]
const TYPES = ["sword", "lance", "axe", "bow", "staff", "anima", "light", "dark"]
const STATS = ["max_hp", "str", "magic", "skill", "speed", "luck", "def", "res"]
const BINARY = ["fast_fingers", "omni_counter", "iotes_shield", "granis_shield", "svalinn_shield", "guardian", "multitool", "galeforce", "fury", "mercy", "busy", "pass", "vantage", "desperation", "winged_boots", "stealth", "deft_touch", "miracle", "quick_reposte", "savior"]
const ARMY_TEXT = {
	"spoils_of_war": "On chapter clear, send surviving enemies’ droppable items to Supply and divide their defeat XP evenly among deployed survivors.",
	"loyal_customer": "Shop prices -10% per stack (maximum 100%).",
	"gladiators_will": "+5 arena entries each chapter. Base allowance: 5.",
	"guidance_of_fe7_unit_39": "+5 Undo uses each chapter. Base allowance: 5.",
	"extra_training": "+5 free level-up stat rerolls for this run.",
	"alternate_reality": "Reroll all of one character's level-up stats immediately, preserving class and permanent bonuses.",
	"welcome_to_the_team": "Raise a character to the average effective level and weapon ranks of your top five living units.",
	"identity_theft": "Swap acquired skills between two characters, living or fallen. Personal skills stay with their owners.",
	"darkvision": "+5 fog vision for every ally per stack.",
	"commandos": "All allies ignore weather movement penalties.",
	"sparring_sessions": "+10% weapon experience per stack.",
	"fast_learners": "+10% experience per stack.",
	"study_sessions": "+10 percentage points to stat growths per stack.",
	"tea_time": "+10% support growth per stack.",
	"reroll": "Replace these three cards once. Then choose one upgrade."
}
const UNIT_TEXT = {
	"fast_fingers": "Use Steal on an adjacent foe to take one unequipped item, regardless of class or Speed.",
	"reroll": "Replace these three cards once. Then choose one upgrade.",
	"entangle": "Bow damage inflicts -3 movement for one turn.",
	"rupture": "Melee weapon damage inflicts -3 Str/Mag/Def for one turn.",
	"shatter": "Magic weapon damage inflicts -3 Str/Mag/Res for one turn.",
	"canto": "Move 3 tiles after attacking or assisting.",
	"shove": "Push your target one tile away after attacking, if terrain permits.",
	"drag": "Pull your target and yourself one tile backwards after attacking, if terrain permits.",
	"savior": "Move to an open tile adjacent to an ally below 50% HP, regardless of distance.",
	"martyr": "Recover the same HP you restore to allies.",
	"renewal": "Recover 10 HP at the start of each even turn.",
	"snacks": "Recover 10 HP when your only action is Wait.",
	"animal_friend": "Recover 10 HP when starting beside a mounted or flying ally.",
	"bloodlust": "Recover 25% of damage dealt by your attacks.",
	"sol": "Recover 30% of damage dealt by critical hits per stack.",
	"savage_blow": "After dealing damage in combat, deal 5 damage to enemies within 3 tiles of the target.",
	"specialist": "Double weapon triangle effects both for and against this unit.",
	"haste": "+1 movement.", "sharpshooter": "+1 maximum attack and assist range.",
	"omni_counter": "Counterattack at any distance with a usable weapon.",
	"expert": "Raise every known weapon proficiency by one rank.",
	"cross_training": "Learn one chosen new weapon type at rank D.",
	"gift_of_gab": "Increase all established support relationships by one rank, up to A.",
	"iotes_shield": "Negate flying effectiveness.", "granis_shield": "Negate cavalry effectiveness.",
	"svalinn_shield": "Negate armored effectiveness.",
	"guardian": "Once per turn, take an attack aimed at an adjacent ally.",
	"multitool": "Open ordinary doors and chests without keys or lockpicks.",
	"galeforce": "Once per turn, move and act again after defeating a target you attacked.",
	"fury": "Once per turn, attack again if your target survives, including breakable walls and trees. Movement requires Canto.",
	"mercy": "Once per turn, move and act again after assisting an ally (except music).",
	"busy": "Once per turn, move and act again after Interact or Talk.",
	"pass": "Move through enemy tiles.",
	"entrench": "+4 Def/Res until your next phase when your only action is Wait.",
	"passion": "+2 damage dealt, -2 received beside an opposite-gender ally.",
	"platonic": "+2 damage dealt, -2 received beside a same-gender ally.",
	"inspire": "Adjacent allies deal +3 damage.", "defender": "Adjacent allies receive -3 damage.",
	"killstreak": "+3 Str/Mag/Spd/Hit after an initiating kill, until the end of your next player turn.",
	"commitment": "+20 percentage points to all stat growths.",
	"lone_wolf": "+3 Atk while the skill owner has no adjacent allies.",
	"pack_tactics": "+3 Str/Mag against an enemy with adjacent allies.",
	"precise_blow": "+20 Hit when initiating.", "precise_stance": "+20 Hit when attacked.",
	"confidence": "+20 Hit at full HP.", "defiance": "+20 Hit below 25% HP.",
	"hit_up": "+10 Hit.", "avd_up": "+10 Avoid.",
	"alert": "+10 Avoid until your next phase when your only action is Wait.",
	"hunter": "+20 Avoid when initiating.", "energetic": "+20 Avoid at full HP.",
	"gambit": "+20 Avoid below 25% HP.", "intimidate": "Adjacent enemies have -10 Avoid.",
	"reckless": "+20 Crit below 50% HP when initiating.", "crit_up": "+10 Crit.",
	"wrath": "+30 Crit at or below 50% HP when attacked.", "wary": "+20 Crit Avoid.",
	"str_up": "+2 Str.", "mag_up": "+2 Mag.", "spd_up": "+2 Spd.", "def_up": "+2 Def.", "res_up": "+2 Res.",
	"fierce_blow": "+4 Str/Mag when initiating.", "sturdy_blow": "+4 Def when initiating.", "warding_blow": "+4 Res when initiating.",
	"fierce_stance": "+4 Str/Mag when attacked.", "sturdy_stance": "+4 Def when attacked.", "warding_stance": "+4 Res when attacked.",
	"defiant_str": "+4 Str below 25% HP.", "defiant_mag": "+4 Mag below 25% HP.",
	"defiant_def": "+4 Def below 25% HP.", "defiant_res": "+4 Res below 25% HP.",
	"vantage": "Counter first at or below 50% HP.",
	"desperation": "At or below 50% HP, your normal follow-up occurs before the counter when initiating.",
	"winged_boots": "Use flying terrain movement costs.",
	"stealth": "While not adjacent to an enemy, enemies prefer another ally they can attack this action.",
	"lucky_seven": "+5 to a random Str, Mag, Spd, Def, Res, Hit or Avoid stat for this phase and the following enemy phase.",
	"deft_touch": "Weapons and staves lose durability only every other use.",
	"miracle": "Survive a fatal hit at 1 HP if above 1 HP: Luck% chance, capped at 50%.",
	"quick_reposte": "Guaranteed follow-up when attacked at 50% HP or higher.",
	"resurrect": "Revive a fallen ally with skills intact; catch up to your top five living units."
}

static func active(state) -> bool:
	return state != null and preload("res://engine/campaign_difficulty.gd").is_rogue(state.chapter.get("difficulty", ""))

static func skill_available(id: String, dynamic_rom: bool) -> bool:
	return not dynamic_rom or not DYNAMIC_UNAVAILABLE.has(id)

static func count(unit: Dictionary, id: String) -> int:
	return int(unit.get("rogue_skills", {}).get(id, 0)) + (int(unit.get("rogue_skills", {}).get("vampire", 0)) if id == "sol" else 0)

static func army(state, id: String) -> int:
	return int(state.chapter.get("rogue", {}).get("army", {}).get(id, 0)) if active(state) else 0

static func title(id: String) -> String:
	return {"vampire": "Sol", "fury": "Deathmatch", "gladiators_will": "Gladiator's Will", "iotes_shield": "Iote's Shield", "granis_shield": "Grani's Shield", "quick_reposte": "Quick Reposte"}.get(id, id.replace("_", " ").capitalize())

static func initialize_unit(state, unit: Dictionary) -> void:
	if not active(state): return
	if unit.get("faction", "") == "enemy":
		initialize_enemy(state, unit)
		return
	if unit.get("faction", "") != "player": return
	if not unit.has("magic"): unit.magic = int(unit.str)
	if not unit.has("rogue_native_types"):
		unit.rogue_native_types = unit.get("weapon_types", []).duplicate()
		if unit.rogue_native_types.is_empty():
			for kind in unit.get("weapon_exp", {}):
				if int(unit.weapon_exp[kind]) > 0: unit.rogue_native_types.append(kind)
	if not unit.has("rogue_skills"):
		unit.rogue_skills = {}
	if not unit.has("rogue_personal"):
		var stat: String = ["str", "magic", "speed", "def", "res"][posmod(str(unit.id).hash(), 5)]
		unit.rogue_personal = {"name": str(unit.name) + "'s Potential", "stat": stat, "amount": 2}
		if str(unit.id).begins_with("fe6_unit_") or state.chapter.get("dynamic_rom",false):
			# Use character IDs, never shared names
			# FE6 placeholders cannot inherit a FE7 personal effect.
			unit.rogue_personal.id = Personal.character_identity(unit)
			unit.rogue_personal.description = "+2 " + {"str":"Strength","magic":"Magic","speed":"Speed","def":"Defense","res":"Resistance"}[stat] + ". Placeholder personal skill."
	Personal.initialize(unit)
	if not unit.has("rogue_growth_gains"): unit.rogue_growth_gains = {}
	if not unit.has("rogue_level_count"):
		# Separate estimated pre-recruitment growth from the character's bases.
		# Later level-ups record their exact gains, including promotion carryover.
		unit.rogue_level_count = maxi(0, effective_level(unit) - 1)
		for stat in STATS:
			var rate := int(unit.get("growths", {}).get(stat, unit.get("growths", {}).get("str", 0) if stat == "magic" else 0))
			@warning_ignore("integer_division") # Intentional integer truncation.
			unit.rogue_growth_gains[stat] = mini(maxi(0, int(unit.get(stat, 0)) - (10 if stat == "max_hp" else 0)), rate * int(unit.rogue_level_count) / 100)

static func initialize_enemy(state, unit: Dictionary) -> void:
	if unit.has("rogue_enemy_skills"): return
	unit.rogue_enemy_skills = true
	if not unit.has("magic"): unit.magic = int(unit.str)
	unit.rogue_skills = {}
	var advanced: bool = unit.get("boss", false) or unit.get("promoted", false)
	var pool: Array = UNIT_TEXT.keys().filter(func(id): return not ENEMY_REWARD_ONLY.has(id)) if advanced else ["str_up", "mag_up", "spd_up", "def_up", "res_up"]
	pool = pool.filter(func(id): return skill_available(id,state.chapter.get("dynamic_rom",false)))
	var equipment: Array = [unit.get("weapon", {})] + unit.get("inventory", [])
	if not equipment.any(func(w): return w.get("type", "") in ["sword", "lance", "axe", "bow"] and not w.get("magic_damage", false)): pool.erase("str_up")
	if not equipment.any(func(w): return w.get("type", "") in ["anima", "light", "dark", "staff"] or w.get("magic_damage", false)): pool.erase("mag_up")
	for _i in range(3 if unit.get("boss", false) else 1):
		var index: int = state.rng.randi_range(0, pool.size() - 1)
		unit.rogue_skills[pool[index]] = 1
		pool.remove_at(index)

static func setup(state, previous = null, completed: int = 0) -> void:
	if not active(state): return
	if previous != null and active(previous):
		state.chapter.rogue = previous.chapter.rogue.duplicate(true)
		for key in ["offer", "chosen", "rerolled", "morale_target"]: state.chapter.rogue.erase(key)
		state.chapter.rogue.undo_used = 0
		state.chapter.rogue.arena_used = 0
	elif not state.chapter.has("rogue"):
		state.chapter.rogue = {"army": {}, "completed": completed, "undo_used": 0, "arena_used": 0, "training": 0}
	state.chapter.rogue.completed = completed
	state.rules.permadeath = true
	state.rules.optional_convoy_merchant = true
	if previous != null and active(previous):
		for unit in Army.all_units(previous):
			if unit.faction == "player" and int(unit.hp) <= 0:
				state.chapter.rogue.get_or_add("fallen", {})[str(unit.id)] = unit.duplicate(true)
		for id in state.chapter.rogue.get("fallen", {}):
			var current: Dictionary = state.get_unit(str(id))
			if current.is_empty():
				var fallen: Dictionary = state.chapter.rogue.fallen[id].duplicate(true)
				fallen.benched = true; fallen.x = 0; fallen.y = 0
				state.chapter.get_or_add("reserve_units", []).append(fallen)
			else:
				current.hp = 0; current.casualty_mode = "permanent"
	for unit in Army.all_units(state): initialize_unit(state, unit)
	configure_deployment(state)
	prepare_morale(state)

static func configure_deployment(state) -> void:
	if not active(state): return
	# Native opening scripts build the formation after setup. Reapply the limit
	# without resetting run progress or rolling unit skills a second time.
	var slots: Array = state.chapter.get("deployment", {}).get("slots", []).duplicate(true)
	if slots.is_empty():
		for unit in state.units:
			if unit.faction == "player" and int(unit.hp) > 0: slots.append({"unit_id": unit.id, "x": unit.x, "y": unit.y})
	var forced := Army.forced_ids(state)
	forced.erase("convoy_merchant")
	slots.sort_custom(func(a, b): return forced.has(str(a.get("unit_id", ""))) and not forced.has(str(b.get("unit_id", ""))))
	slots = slots.slice(0, 6)
	state.chapter.deployment = {"slots": slots, "limit": slots.size(), "forced": forced.slice(0, 6)}
	state.chapter.explicit_forced_deployment = true

static func prepare_morale(state) -> void:
	if not state.rules.get("shatter_morale", false): return
	state.chapter.get_or_add("rogue", {})
	if state.chapter.rogue.has("morale_target"): return
	var recruits: Array = preload("res://engine/chapter_preview.gd")._recruits(state.chapter)
	recruits.append_array(state.chapter.get("future_recruits", []))
	var enemies: Array = state.chapter.get("units", state.units).filter(func(u): return u.get("faction", "") == "enemy" and not recruits.has(str(u.id)))
	if state.chapter.get("objective", {}).get("type", "") == "survive":
		for event in state.chapter.get("events", []):
			for unit in NativeEvents.spawn_templates(event):
				if unit.get("faction", "") == "enemy" and not recruits.has(str(unit.id)): enemies.append(unit)
	enemies.sort_custom(func(a, b): return strength(a) > strength(b) if strength(a) != strength(b) else str(a.id) < str(b.id))
	state.chapter.rogue.morale_target = str(enemies[0].id) if not enemies.is_empty() else ""
	state.chapter.rogue.morale_enemy = enemies[0].duplicate(true) if not enemies.is_empty() else {}

static func morale_broken(state) -> bool:
	if not state.rules.get("shatter_morale", false): return false
	prepare_morale(state)
	var target: Dictionary = state.get_unit(str(state.chapter.rogue.get("morale_target", "")))
	return not target.is_empty() and target.get("faction", "") == "enemy" and int(target.hp) <= 0

static func strength(unit: Dictionary) -> int:
	var result := 0
	for stat in STATS: result += int(unit.get(stat, 0))
	return result

static func is_army_offer(state) -> bool:
	var completed := int(state.chapter.rogue.get("completed", 0))
	return completed > 0 and completed % 5 == 0

static func candidates(state, skill: String) -> Array:
	return Army.all_units(state).filter(func(u): return u.get("faction", "") == "player" and (int(u.hp) <= 0 if skill == "resurrect" else true if skill == "identity_theft" else Army.eligible(u)) and (not BINARY.has(skill) or count(u, skill) == 0) and (skill != "cross_training" or TYPES.any(func(t): return int(u.get("weapon_exp", {}).get(t, 0)) == 0)))

static func offer(state) -> Array:
	if not active(state) or state.chapter.rogue.get("chosen", false): return []
	if state.chapter.rogue.has("offer"):
		var saved: Array = state.chapter.rogue.offer
		for i in range(saved.size()):
			if saved[i] == "vampire": saved[i] = "sol"
			if saved[i] == "shatter_morale":
				for replacement in ARMY_TEXT:
					if replacement not in ["reroll", "identity_theft", "alternate_reality", "welcome_to_the_team"] and not saved.has(replacement):
						saved[i] = replacement
						break
		remember_offer(state, saved)
		return saved
	var pool: Array = []
	var army_offer := is_army_offer(state)
	for skill in (ARMY_TEXT if army_offer else UNIT_TEXT):
		if not skill_available(skill,state.chapter.get("dynamic_rom",false)): continue
		if skill == "reroll" and state.chapter.rogue.get("rerolled", false): continue
		# Dynamic routes have native table indices, not a reliable chapter number.
		var chapter_number := int(state.chapter.rogue.get("completed",0))+1 if state.chapter.get("dynamic_rom",false) else int(state.chapter.get("chapter_number",0))
		if skill in ["alternate_reality", "welcome_to_the_team"] and chapter_number < 20: continue
		if army_offer and skill in ["commandos", "shatter_morale", "spoils_of_war"] and army(state, skill) > 0: continue
		if skill == "identity_theft" and candidates(state, skill).size() < 2: continue
		if not army_offer and skill != "reroll" and candidates(state, skill).is_empty(): continue
		pool.append(skill)
	var result: Array = []
	while result.size() < 3 and not pool.is_empty():
		var index: int = state.rng.randi_range(0, pool.size()-1)
		result.append(pool[index]); pool.remove_at(index)
	state.chapter.rogue.offer = result
	remember_offer(state, result)
	return result

static func remember_offer(state, offered: Array) -> void:
	var record: Dictionary = state.chapter.rogue.get_or_add("history", {}).get_or_add(str(state.chapter.id), {})
	if not record.has("original_offer"): record.original_offer = offered.duplicate()
	record.offer = offered.duplicate()
	record.chapter_title = str(state.chapter.get("title", state.chapter.id))

static func choose(state, skill: String, target_id: String = "", second_id: String = "", weapon_type: String = "") -> bool:
	if not active(state) or state.chapter.get("deployment_complete", false) or not offer(state).has(skill): return false
	if not skill_available(skill,state.chapter.get("dynamic_rom",false)): return false
	var run: Dictionary = state.chapter.rogue
	if skill == "reroll":
		if run.get("rerolled", false): return false
		run.rerolled = true; run.erase("offer"); offer(state)
		return true
	var targeted := not is_army_offer(state) or skill in ["alternate_reality", "welcome_to_the_team", "identity_theft"]
	var unit: Dictionary = state.get_unit(target_id)
	if targeted and not candidates(state, skill).has(unit): return false
	var other: Dictionary = state.get_unit(second_id)
	if skill == "identity_theft" and (target_id == second_id or not candidates(state, skill).has(other)): return false
	if skill == "cross_training" and (not TYPES.has(weapon_type) or int(unit.get("weapon_exp", {}).get(weapon_type, 0)) > 0): return false
	if is_army_offer(state):
		run.army[skill] = army(state, skill) + 1
		match skill:
			"extra_training": run.training = int(run.get("training", 0)) + 5
			"alternate_reality": reroll_all(state, unit)
			"welcome_to_the_team": catch_up(state, unit)
			"identity_theft":
				var skills: Dictionary = unit.rogue_skills
				unit.rogue_skills = other.rogue_skills
				other.rogue_skills = skills
				var learned: Array = unit.get("rogue_learned_types", [])
				unit.rogue_learned_types = other.get("rogue_learned_types", [])
				other.rogue_learned_types = learned
				for recipient in [unit, other]:
					recipient.weapon_types = recipient.get("rogue_native_types", []).duplicate()
					for kind in recipient.rogue_learned_types:
						if not recipient.get_or_add("weapon_types", []).has(kind): recipient.weapon_types.append(kind)
						recipient.get_or_add("weapon_exp", {})[kind] = maxi(1, int(recipient.weapon_exp.get(kind, 0)))
					recipient.can_use_staves = recipient.weapon_types.has("staff")
	else:
		match skill:
			"resurrect":
				catch_up(state, unit); unit.hp = unit.max_hp; unit.recovery_chapters = 0; unit.erase("casualty_mode")
				run.get_or_add("fallen", {}).erase(target_id)
			"expert":
				var thresholds: Array = state.rules.get("weapon_rank_thresholds", {}).values()
				thresholds.sort()
				for kind in unit.get("weapon_exp", {}):
					var value := int(unit.weapon_exp[kind])
					if value <= 0: continue
					for threshold in thresholds:
						if threshold > value: unit.weapon_exp[kind] = threshold; break
			"cross_training":
				unit.get_or_add("rogue_learned_types", []).append(weapon_type)
				unit.get_or_add("weapon_exp", {})[weapon_type] = int(state.rules.weapon_rank_thresholds.D)
				if not unit.get_or_add("weapon_types", []).has(weapon_type): unit.weapon_types.append(weapon_type)
				if weapon_type == "staff": unit.can_use_staves = true
			"gift_of_gab":
				for key in state.support_points:
					if str(key).split("|").has(state._support_identity(target_id)):
						state.support_ranks[key] = mini(3, int(state.support_ranks.get(key, 0)) + 1)
		unit.rogue_skills[skill] = count(unit, skill) + 1
		if skill == "sol": unit.rogue_skills.erase("vampire")
	run.chosen = true
	var record: Dictionary = run.get_or_add("history", {}).get_or_add(str(state.chapter.id), {})
	record.merge({"chosen": skill, "recipient": target_id if targeted else "", "second_recipient": second_id, "weapon_type": weapon_type}, true)
	state.events_log.append("Rogue upgrade: %s%s" % [title(skill), " → " + str(unit.name) if targeted else ""])
	return true

static func catch_up(state, unit: Dictionary) -> void:
	var top: Array = Army.all_units(state).filter(func(u): return Army.eligible(u) and u.id != unit.id)
	top.sort_custom(func(a, b): return effective_level(a) > effective_level(b))
	top = top.slice(0, 5)
	if top.is_empty(): return
	var levels := 0
	for other in top: levels += effective_level(other)
	var target := int(round(float(levels) / top.size()))
	# Promote through the existing class catalog when crossing the tier boundary.
	if target > 20 and not unit.get("promoted", false):
		for entry in state.rules.get("promotion_catalog", {}).get("promotions", []):
			if entry.get("from_class", -1) == int(unit.get("rom_class_id", -2)):
				var cls: Dictionary = state._class_definition(int(entry.get("to_class", -1)))
				if not cls.is_empty(): state._apply_class_change(unit, cls); unit.level = 1
				break
	while effective_level(unit) < target and int(unit.level) < 20:
		var gains := roll_stats(state, unit)
		record_level(unit, gains)
		unit.level = int(unit.level) + 1
		unit.exp = 0
	for kind in unit.get("weapon_exp", {}):
		if int(unit.weapon_exp[kind]) <= 0: continue
		var points := 0
		for other in top:
			var best := 1
			for value in other.get("weapon_exp", {}).values(): best = maxi(best, int(value))
			points += best
		unit.weapon_exp[kind] = maxi(int(unit.weapon_exp[kind]), mini(251, int(round(float(points) / top.size()))))

static func effective_level(unit: Dictionary) -> int:
	return int(unit.level) + (20 if unit.get("promoted", false) else 0)

static func growth(state, unit: Dictionary, stat: String) -> int:
	var base := int(unit.get("growths", {}).get(stat, unit.get("growths", {}).get("str", 0) if stat == "magic" else unit.get("growths", {}).get("hp", 0) if stat == "max_hp" else 0))
	return maxi(0, base + (20 * count(unit, "commitment") + 10 * army(state, "study_sessions") + (Personal.parameter(unit, "growth", 10) if Personal.has(unit, "fe7_unit_19") else 0) if stat in STATS and unit.get("faction", "") == "player" else 0))

static func record_level(unit: Dictionary, gains: Dictionary) -> void:
	if not unit.has("rogue_skills"): return
	unit.rogue_level_count = int(unit.get("rogue_level_count", 0)) + 1
	for stat in gains: unit.rogue_growth_gains[stat] = int(unit.rogue_growth_gains.get(stat, 0)) + int(gains[stat])
	unit.rogue_last_level = gains.duplicate(true)

static func roll_stats(state, unit: Dictionary) -> Dictionary:
	var gains := {}
	for stat in STATS:
		var rate := growth(state, unit, stat)
		@warning_ignore("integer_division") # Intentional integer truncation.
		var gain := rate / 100 + int(state.rng.randi_range(0, 99) < rate % 100)
		gain = mini(gain, maxi(0, int(unit.get("stat_caps", {}).get(stat, state.rules.stat_caps.get("str" if stat == "magic" else stat, 60))) - int(unit.get(stat, 0))))
		unit[stat] = int(unit.get(stat, 0)) + gain
		gains[stat] = gain
	return gains

static func reroll_level(state, unit: Dictionary) -> bool:
	if not active(state) or int(state.chapter.rogue.get("training", 0)) <= 0 or not unit.has("rogue_last_level"): return false
	state.chapter.rogue.training -= 1
	var old_hp := int(unit.max_hp)
	for stat in unit.rogue_last_level:
		unit[stat] -= int(unit.rogue_last_level[stat])
		unit.rogue_growth_gains[stat] = int(unit.rogue_growth_gains.get(stat, 0)) - int(unit.rogue_last_level[stat])
	var gains := roll_stats(state, unit)
	for stat in gains: unit.rogue_growth_gains[stat] = int(unit.rogue_growth_gains.get(stat, 0)) + int(gains[stat])
	unit.rogue_last_level = gains
	var hp_change := int(unit.max_hp) - old_hp
	unit.hp = clampi(int(unit.hp) + (hp_change if hp_change < 0 or Personal.FE6.can_heal(unit) else 0), 1, int(unit.max_hp))
	return true

static func reroll_all(state, unit: Dictionary) -> void:
	for stat in unit.rogue_growth_gains: unit[stat] -= int(unit.rogue_growth_gains[stat])
	unit.rogue_growth_gains = {}
	for _i in range(int(unit.get("rogue_level_count", 0))):
		var gains := roll_stats(state, unit)
		for stat in gains: unit.rogue_growth_gains[stat] = int(unit.rogue_growth_gains.get(stat, 0)) + int(gains[stat])
	unit.hp = int(unit.max_hp) if Personal.FE6.can_heal(unit) else mini(int(unit.hp), int(unit.max_hp))

static func permanent(unit: Dictionary, stat: String) -> int:
	var skill: String = {"str": "str_up", "magic": "mag_up", "speed": "spd_up", "def": "def_up", "res": "res_up"}.get(stat, "")
	var result := 2 * count(unit, skill) if not skill.is_empty() else count(unit, "haste") if stat == "mov" else 0
	if unit.get("rogue_personal", {}).get("stat", "") == stat: result += int(unit.rogue_personal.amount)
	return result

static func temporary(unit: Dictionary, stat: String) -> int:
	var result := Personal.temporary(unit, stat)
	for active_effect in unit.get("rogue_effects", []): result += int(active_effect.get("stats", {}).get(stat, 0))
	if int(unit.get("hp", 0)) * 4 < int(unit.get("max_hp", 1)):
		result += 4 * count(unit, {"str": "defiant_str", "magic": "defiant_mag", "def": "defiant_def", "res": "defiant_res"}.get(stat, ""))
	return result

static func effect(state, unit: Dictionary, source: String, stats: Dictionary, display_name: String = "") -> void:
	var effects: Array = unit.get_or_add("rogue_effects", [])
	for i in range(effects.size()-1, -1, -1):
		if effects[i].source == source: effects.remove_at(i)
	# Debuffs applied before a target's phase last through that phase; buffs
	# granted in its own phase expire at its next phase.
	if stats.values().any(func(value): return int(value) != 0): state.queue_skill_effect(unit, title(source) if display_name.is_empty() else display_name)
	var entry := {"source": source, "stats": stats, "expires": state.turn + 1 + (1 if unit.faction == "player" and state.phase == "enemy" else 0), "faction": unit.faction}
	if source == "killstreak" and unit.faction == "player":
		entry.expires = state.turn + 2
		entry.player_phase_end = state.turn + 1
	effects.append(entry)

static func end_player_phase(state) -> void:
	if not active(state): return
	for unit in state.units:
		unit.rogue_effects = unit.get("rogue_effects", []).filter(func(e): return int(e.get("player_phase_end", state.turn + 1)) > state.turn)

static func heal(unit: Dictionary, amount: int) -> void:
	if int(unit.hp) > 0 and Personal.FE6.can_heal(unit): unit.hp = mini(int(unit.max_hp), int(unit.hp) + maxi(0, amount))

static func heal_effect(state, unit: Dictionary, skill: String, amount: int) -> void:
	var previous := int(unit.hp)
	heal(unit, amount)
	if int(unit.hp) > previous: state.queue_skill_effect(unit, title(skill), previous)

static func adjacent(state, unit: Dictionary, allied: bool = true) -> Array:
	return state.units.filter(func(other): return other.id != unit.id and state._on_map(other) and state._distance(state.position(unit), state.position(other)) == 1 and (not state._hostile(unit, other) if allied else state._hostile(unit, other)))

static func start_phase(state, unit: Dictionary) -> void:
	Personal.start_phase(state, unit)
	unit.rogue_tiles_moved = 0
	unit.rogue_effects = unit.get("rogue_effects", []).filter(func(e): return int(e.expires) > state.turn)
	unit.rogue_used = {}
	unit.rogue_action_taken = false
	unit.erase("rogue_fury")
	if state.turn % 2 == 0: heal_effect(state, unit, "renewal", 10 * count(unit, "renewal"))
	if adjacent(state, unit).any(func(u): return u.get("flying", false) or is_mounted(u)): heal_effect(state, unit, "animal_friend", 10 * count(unit, "animal_friend"))
	if count(unit, "lucky_seven") > 0:
		var stats: Array = ["str", "magic", "speed", "def", "res", "hit", "avoid"]
		effect(state, unit, "lucky_seven", {stats[state.rng.randi_range(0, 6)]: 5 * count(unit, "lucky_seven")})

static func wait_effect(state, unit: Dictionary) -> void:
	if not active(state): return
	unit.rogue_tiles_moved = 0
	if unit.get("rogue_action_taken", false) or unit.get("traded", false) or unit.get("canto_active", false): return
	heal_effect(state, unit, "snacks", 10 * count(unit, "snacks"))
	effect(state, unit, "entrench", {"def": 4 * count(unit, "entrench"), "res": 4 * count(unit, "entrench")})
	effect(state, unit, "alert", {"avoid": 10 * count(unit, "alert")})

static func refresh(unit: Dictionary, skill: String, movement: bool = true) -> bool:
	if count(unit, skill) == 0 or unit.get_or_add("rogue_used", {}).get(skill, false) or int(unit.hp) <= 0: return false
	if skill != "fury": unit.erase("rogue_fury")
	unit.rogue_used[skill] = true
	unit.get_or_add("skill_notifications", []).append(title(skill))
	unit.acted = false; unit.canto_active = false; unit.canto_remaining = 0
	unit.moved = not movement; unit.move_spent = 0; unit.traded = false
	return true

static func canto(unit: Dictionary) -> void:
	if count(unit, "canto") <= 0 or int(unit.hp) <= 0: return
	unit.acted = false; unit.moved = false
	unit.canto_active = true; unit.canto_remaining = 3 * count(unit, "canto")
	unit.get_or_add("skill_notifications", []).append("Canto")

static func after_action(state, unit: Dictionary, kind: String, healed: int = 0) -> void:
	if not active(state): return
	unit.rogue_tiles_moved = 0
	unit.rogue_action_taken = true
	if kind == "assist":
		if Personal.has(unit, "fe7_unit_16") and Personal.parameter(unit, "assist_boost", 0) > 0: Personal.progress(unit).healing_boost = true
		if Personal.has(unit, "fe7_unit_39"): Personal.reset_fe7_unit_39(state, unit)
		heal_effect(state, unit, "martyr", healed * count(unit, "martyr"))
		if not refresh(unit, "mercy"): canto(unit)
	elif kind == "staff_attack": canto(unit)
	elif kind == "busy": refresh(unit, "busy")
	state.flush_skill_notifications()

static func after_combat(state, attacker: Dictionary, defender: Dictionary, dealt_damage: bool = false) -> void:
	if not active(state): return
	Personal.combat_finished(attacker, defender, state)
	attacker.rogue_tiles_moved = 0
	if int(attacker.hp) <= 0: return
	attacker.rogue_action_taken = true
	var killed := int(defender.hp) <= 0
	if killed:
		var bonus := 3 * count(attacker, "killstreak")
		effect(state, attacker, "killstreak", {"str": bonus, "magic": bonus, "speed": bonus, "hit": bonus})
	var splash := 5 * count(attacker, "savage_blow")
	if splash > 0 and dealt_damage:
		for enemy in state.units:
			if not state._on_map(enemy) or not state._hostile(attacker, enemy) or state._distance(state.position(defender), state.position(enemy)) > 3: continue
			var previous_hp := int(enemy.hp)
			enemy.hp = maxi(0, int(enemy.hp) - splash)
			state.queue_skill_effect(enemy, "Savage Blow", previous_hp)
			Personal.injured(enemy, splash)
			state.events_log.append("Savage Blow: %s takes %d damage." % [enemy.name, splash])
			if int(enemy.hp) == 0:
				state._release_on_death(enemy)
				state._collect_drops([{"attacker_id": attacker.id, "defender_id": enemy.id, "remaining_hp": 0}])
	if not killed:
		var delta: Vector2i = state.position(defender) - state.position(attacker)
		var direction := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
		if int(defender.hp) > 0 and direction != Vector2i.ZERO:
			for _i in range(count(attacker, "shove")):
				var cell: Vector2i = state.position(defender) + direction
				if not state.unit_at(cell).is_empty() or state.movement_cost(defender, cell) <= 0: break
				defender.x = cell.x; defender.y = cell.y; state._sync_carried(defender)
				state.queue_skill_effect(attacker, "Shove")
			for _i in range(count(attacker, "drag")):
				var cell: Vector2i = state.position(attacker) - direction
				var pulled: Vector2i = state.position(defender) - direction
				var occupant: Dictionary = state.unit_at(pulled)
				if not state.unit_at(cell).is_empty() or state.movement_cost(attacker, cell) <= 0 or state.movement_cost(defender, pulled) <= 0 or (not occupant.is_empty() and occupant.id != attacker.id): break
				defender.x = pulled.x; defender.y = pulled.y
				attacker.x = cell.x; attacker.y = cell.y
				state._sync_carried(attacker); state._sync_carried(defender)
				state.queue_skill_effect(attacker, "Drag")
	if killed and refresh(attacker, "galeforce"): return
	if not killed and refresh(attacker, "fury", count(attacker, "canto") > 0):
		attacker.rogue_fury = true
		return
	canto(attacker)

static func on_damage(state, attacker: Dictionary, defender: Dictionary, damage: int, critical: bool = false) -> void:
	if not active(state) or damage <= 0: return
	Personal.damaged(attacker, state)
	if Personal.has(attacker, Personal.FE6.UNIT_16):
		effect(state, defender, Personal.FE6.HEAL_BLOCK, {})
		state.queue_skill_effect(attacker, Personal.title(attacker))
	if critical: heal_effect(state, attacker, "sol", int(damage * 0.3 * count(attacker, "sol")))
	var previous_hp := int(attacker.hp)
	heal(attacker, int(damage * 0.25 * count(attacker, "bloodlust")))
	if int(attacker.hp) > previous_hp: state.queue_skill_effect(attacker, "Bloodlust")
	var kind := str(attacker.weapon.get("type", ""))
	var magic: bool = kind in ["anima", "light", "dark"] or attacker.weapon.get("magic_damage", false)
	if kind == "bow" and count(attacker, "entangle") > 0: effect(state, defender, "entangle", {"mov": -3 * count(attacker, "entangle")})
	var skill := "shatter" if magic else "rupture" if kind in ["sword", "lance", "axe"] else ""
	var penalty := -3 * count(attacker, skill)
	if penalty < 0: effect(state, defender, skill, {"str": penalty, "magic": penalty, "res" if magic else "def": penalty})

static func combat_bonus(state, unit: Dictionary, foe: Dictionary, initiating: bool) -> Dictionary:
	var result := {"atk": 0, "speed": 0, "def": 0, "res": 0, "hit": 0, "avoid": 0, "crit": 0, "ddg": 0, "damage": 0, "guard": 0, "luck": 0, "con": 0, "str": 0}
	if not active(state): return result
	var full := int(unit.hp) == int(unit.max_hp)
	var low := int(unit.hp) * 4 < int(unit.max_hp)
	result.atk = 4 * count(unit, "fierce_blow" if initiating else "fierce_stance")
	result.def = 4 * count(unit, "sturdy_blow" if initiating else "sturdy_stance")
	result.res = 4 * count(unit, "warding_blow" if initiating else "warding_stance")
	result.atk += 3 * count(unit, "lone_wolf") if adjacent(state, unit).is_empty() else 0
	result.atk += 3 * count(unit, "pack_tactics") if not adjacent(state, foe).is_empty() else 0
	result.hit = 10 * count(unit, "hit_up") + 20 * count(unit, "precise_blow" if initiating else "precise_stance") + temporary(unit, "hit")
	if full: result.hit += 20 * count(unit, "confidence")
	if low: result.hit += 20 * count(unit, "defiance")
	result.avoid = 10 * count(unit, "avd_up") + temporary(unit, "avoid")
	if initiating: result.avoid += 20 * count(unit, "hunter")
	if full: result.avoid += 20 * count(unit, "energetic")
	if low: result.avoid += 20 * count(unit, "gambit")
	result.crit = 10 * count(unit, "crit_up") + temporary(unit, "crit")
	var personal := Personal.combat_bonus(state, unit, initiating, foe)
	for key in personal: result[key] += int(personal[key])
	if initiating and int(unit.hp) * 2 < int(unit.max_hp): result.crit += 20 * count(unit, "reckless")
	if not initiating and int(unit.hp) * 2 <= int(unit.max_hp): result.crit += 30 * count(unit, "wrath")
	result.ddg = 20 * count(unit, "wary")
	var same := false; var opposite := false
	for ally in adjacent(state, unit):
		if gender(ally) == gender(unit): same = true
		else: opposite = true
		result.damage += 3 * count(ally, "inspire")
		result.guard += 3 * count(ally, "defender")
	var social := 2 * ((count(unit, "platonic") if same else 0) + (count(unit, "passion") if opposite else 0))
	result.damage += social; result.guard += social
	for enemy in adjacent(state, unit, false): result.avoid -= 10 * count(enemy, "intimidate")
	return result

static func gender(unit: Dictionary) -> String:
	if unit.has("gender"): return str(unit.gender)
	var id := str(unit.get("id", ""))
	var game := str(unit.get("game_id", "fe6" if id.begins_with("fe6_unit_") else "fe7"))
	var number := int(unit.get("rom_character_id", id.trim_prefix(game + "_unit_").to_int()))
	if game == "fe6":
		return "female" if number in [2,3,5,10,14,17,22,30,38,40,41,43,44,45,46,47,48,49,53,54,55,61,62,63,68,99,101,102] else "male"
	# Include alternate tutorial/enemy records as well as playable identities.
	return "female" if game == "fe7" and number in [3,14,15,17,20,27,29,30,31,33,37,43,45,49,52,55,81,91,133,158] else "male"

static func is_mounted(unit: Dictionary) -> bool:
	return unit.get("mounted",false) if unit.has("fe6_unit_flags") or unit.has("native_unit_flags") else unit.get("canto",false)

static func shield(unit: Dictionary) -> bool:
	var cls := str(unit.get("class_name", "")).to_lower()
	var mounted := is_mounted(unit)
	return (count(unit, "iotes_shield") > 0 and unit.get("flying", false)) or (count(unit, "granis_shield") > 0 and (mounted and not unit.get("flying", false))) or (count(unit, "svalinn_shield") > 0 and (cls in ["knight", "general"] or cls.contains("armored") or unit.get("tags", []).has("armored")))

static func guardian(state, target: Dictionary, attacker: Dictionary = {}) -> Dictionary:
	if not active(state): return target
	for unit in state.units:
		if Personal.FE6.can_guard(state, unit, target, attacker): return unit
	for unit in adjacent(state, target):
		if count(unit, "guardian") > 0 and not unit.get("rogue_used", {}).get("guardian", false) and not state.pending_moves.has(str(unit.id)): return unit
	return target

static func use_guardian(state, unit: Dictionary, target: Dictionary, attacker: Dictionary) -> void:
	if Personal.FE6.can_guard(state, unit, target, attacker): Personal.FE6.use_guard(state, unit, target)
	else: unit.get_or_add("rogue_used", {})["guardian"] = true

static func price(state, base: int, buyer: Dictionary = {}) -> int:
	if not active(state): return base
	return maxi(0, int(ceil(base * maxf(0, 1.0 - 0.1 * army(state, "loyal_customer") - (Personal.parameter(buyer, "discount_percent", 10) / 100.0 if Personal.has(buyer, Personal.FE6.UNIT_66) else 0.0)))))

static func remaining(state, kind: String) -> int:
	return maxi(0, 5 + 5 * army(state, "guidance_of_fe7_unit_39" if kind == "undo" else "gladiators_will") - int(state.chapter.rogue.get(kind + "_used", 0)))

static func chapter_clear(state) -> void:
	if army(state, "spoils_of_war") <= 0 or state.chapter.get("spoils_awarded", false): return
	state.chapter.spoils_awarded = true
	var players: Array = state.units.filter(func(u): return u.faction == "player" and int(u.hp) > 0 and not u.get("benched", false))
	players.sort_custom(func(a, b): return str(a.id) < str(b.id))
	if players.is_empty(): return
	var pool := 0
	for enemy in state.units:
		if enemy.faction != "enemy" or not state._on_map(enemy): continue
		var value := 0
		for unit in players: value += preload("res://engine/combat_experience.gd").amount(unit, enemy, true, true)
		pool += roundi(float(value) / players.size())
		if enemy.get("drop_claimed", false): continue
		var drops: Array = []
		for item in [enemy.weapon] + enemy.inventory:
			if state.item_drops(enemy, item) and int(item.get("uses", 0)) > 0: drops.append(item.duplicate(true))
		if drops.is_empty() and not enemy.get("drop_item", {}).is_empty() and int(enemy.drop_item.get("uses", 0)) > 0: drops.append(enemy.drop_item.duplicate(true))
		for item in drops:
			item.erase("droppable")
			state._give_item("", item, true)
		if not drops.is_empty(): enemy.drop_claimed = true
	for i in range(players.size()):
		@warning_ignore("integer_division") # Intentional integer truncation.
		var reward: Dictionary = state._award_experience(players[i], pool / players.size() + (1 if i < pool % players.size() else 0))
		if int(reward.amount) > 0: state.experience_queue.append(reward)
	state.events_log.append("Spoils of War: %d XP shared by %d deployed units; enemy drops sent to Supply." % [pool, players.size()])
