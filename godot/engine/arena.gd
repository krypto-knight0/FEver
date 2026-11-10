extends RefCounted
## A wager owns a separate combat state; the map never gains a temporary enemy.
const Battle = preload("res://engine/battle_state.gd")
const TYPES := ["sword", "lance", "axe", "bow", "staff", "anima", "light", "dark"]
var catalog: Dictionary
var map: RefCounted
var duel: RefCounted
var unit_id := ""
var weapon_index := -1
var wager := 0
var active := false
var result := ""
var order: Array = []
var strikes: Array = []
var rewards: Array = []

func _init() -> void:
	var assets = preload("res://runtime/rom_assets.gd")
	if assets.initialized():
		# Optional arena-data failures must not invalidate a loaded campaign.
		var decoder: RefCounted = assets.decoder
		if assets.dynamic_content != null:
			decoder = (preload("res://runtime/fe7/fe7_dynamic_profile.gd") if assets.game_id == "fe7" else preload("res://runtime/fe6/fe6_dynamic_profile.gd")).decoder(assets.decoder.rom)
		catalog = preload("res://runtime/rom_arena.gd").read(decoder, assets.item_catalog, assets.game_id)
	else: catalog = {}

static func best_type(unit: Dictionary) -> String:
	var best := ""
	var points := 0
	for kind in TYPES:
		if kind == "staff": continue
		var rank := int(unit.get("weapon_exp", {}).get(kind, 0))
		if rank > points: points = rank; best = kind
	return best

static func value(unit: Dictionary, faced_type: String) -> int:
	return (int(unit.max_hp) + int(unit.str) + int(unit.skill) + int(unit.speed)) * 2 + int(unit.luck) + int(unit.con) + int(unit.res if faced_type in ["anima", "light", "dark"] else unit.def) * 2 + (int(unit.str) if unit.get("game_id", "") == "fe6" and int(unit.get("critical_bonus",0)) > 0 else 0)

static func difficulty(gold: int) -> String:
	if gold < 600: return "Very easy"
	if gold < 700: return "Easy"
	if gold < 800: return "Medium"
	if gold < 900: return "Hard"
	return "Very hard"

func offer(state: RefCounted, id: String, auto_weapon: bool = false) -> Dictionary:
	map = state; unit_id = id
	if catalog.is_empty(): return {"ok":false,"reason":"Arena data could not be read from this cartridge."}
	var fe6: bool = catalog.get("game_id", "fe7") == "fe6"
	if map.Rogue.active(map) and map.Rogue.remaining(map, "arena") <= 0: return {"ok": false, "reason": "No arena entries remain this chapter."}
	var player: Dictionary = map.get_unit(id)
	var site: Dictionary = map.interaction_at_unit(id)
	if site.get("type", "") != "arena" or map.turn > int(site.get("last_turn", 999)) or not map._can_command(player): return {"ok":false,"reason":"The arena is closed."}
	weapon_index = -2
	for i in range(-1, player.inventory.size()):
		var item: Dictionary = player.weapon if i == -1 else player.inventory[i]
		if i >= 0 and not auto_weapon: break
		if item.get("type", "") != "staff" and map.can_equip_weapon(player, item): weapon_index = i; break
	if weapon_index == -2: return {"ok":false,"reason":"Equip a usable combat weapon to enter the arena."}
	var equipped: Dictionary = player.weapon if weapon_index == -1 else player.inventory[weapon_index]
	var kind := str(equipped.type)
	var group := "bow" if kind == "bow" else "magic" if kind in ["anima", "light", "dark"] else "melee"
	var promoted: bool = player.get("promoted", false)
	var choices: Array = catalog.lists[group].filter(func(candidate_id): return bool(str(catalog.classes[str(int(candidate_id))].attributes).hex_to_int() & 0x100) == promoted)
	if choices.is_empty(): return {"ok":false,"reason":"No arena opponent matches this class tier."}
	var cid := int(choices[map.rng.randi_range(0, choices.size()-1)])
	var cls: Dictionary = catalog.classes[str(cid)]
	var rolled_level := maxi(1, int(player.level) + map.rng.randi_range(-4,4))
	var level := mini(20, rolled_level)
	var effective_level := int(floor((rolled_level if fe6 else level) * ((1.8 if fe6 else 2.4) if map.rules.get("hard_mode", false) else 1.2)))
	var enemy := {"id":"arena_opponent","name":"Gladiator","faction":"enemy","rom_class_id":cid,"class_name":cls.name,"promoted":promoted,"level":level,"exp":0,"con":cls.constitution,"mov":cls.movement,"weapon_exp":cls.weapon_ranks.duplicate(true),"inventory":[],"growths":{},"x":1,"y":0,"terrain_bonuses":{}}
	enemy.game_id = str(catalog.get("game_id","fe7"))
	enemy.rom_character_id = 0
	var fields := {"max_hp":"hp","str":"strength","skill":"skill","speed":"speed","def":"defense","res":"resistance","luck":"luck"}
	for field in fields:
		enemy[field] = int(cls.bases.get(fields[field],0))
		var stages: Array = ([19] if promoted else []) + [maxi(0,effective_level-1)] if fe6 else [effective_level]
		for levels in stages:
			var growth := int(cls.growths.get(fields[field],0)) * int(levels)
			@warning_ignore("integer_division") # Intentional integer truncation.
			var increase: int = growth + map.rng.randi_range(0, maxi(0,growth/4-1)) - growth/8
			@warning_ignore("integer_division") # Intentional integer truncation.
			enemy[field] += increase/100 + int(map.rng.randi_range(0,99) < increase%100)
		if fe6: enemy[field] = mini(int(enemy[field]),int(cls.caps[fields[field]]))
	if fe6:
		enemy.game_id = "fe6"
		enemy.rom_character_id = 0xe1
		enemy.merge(cls.experience, true)
		enemy.critical_bonus = 30 if str(cls.attributes).hex_to_int() & 0x40 else 0
	var enemy_kind := best_type(enemy)
	for _i in range(10 if fe6 else 9):
		var pv := value(player,enemy_kind); var ev := value(enemy,kind)
		if pv < ev * 0.8:
			for field in fields: enemy[field] = maxi(1 if field == "max_hp" else 0, int(enemy[field])-1)
		elif ev < pv * 0.8:
			for field in fields: enemy[field] = int(enemy[field]) + (2 if field == "max_hp" else 1)
		else: break
	@warning_ignore("integer_division") # Intentional integer truncation.
	wager = maxi(1, 800 + 10 * ((value(enemy,kind)-value(player,enemy_kind)) / (2 if fe6 else 1)))
	enemy.weapon = catalog.weapons[str(int(catalog.basic[TYPES.find(enemy_kind)]))].duplicate(true)
	# Upgrade along the ROM's weapon ladder when the basic weapon cannot hurt
	# this defender. Opponent WEXP accommodates the arena-issued weapon.
	var ladder: Array = []
	for item_id in catalog.rankup:
		if int(item_id) == 255: break
		if int(item_id) == 0: continue
		var weapon: Dictionary = catalog.weapons[str(int(item_id))]
		if weapon.type == enemy_kind: ladder.append(weapon)
	var defense := int(player.res if enemy_kind in ["anima","light","dark"] else player.def)
	for weapon in ladder:
		if int(enemy.str)+int(enemy.weapon.might)-defense >= 1: break
		enemy.weapon = weapon.duplicate(true)
	enemy.weapon_exp[enemy_kind] = maxi(int(enemy.weapon_exp[enemy_kind]),int(enemy.weapon.get("required_rank",1)))
	enemy.hp = enemy.max_hp
	enemy.silencer = bool(str(cls.attributes).hex_to_int() & 0x2000000)
	var fighter: Dictionary = player.duplicate(true)
	fighter.weapon = (player.weapon if weapon_index == -1 else player.inventory[weapon_index]).duplicate(true)
	fighter.inventory = []; fighter.terrain_bonuses = {}; fighter.temporary_bonuses = {}; fighter.ring_bonuses = {}
	fighter.x = 0; fighter.y = 0; fighter.acted = false; fighter.moved = false
	# Arena combat is mutually in range, even for bow versus melee pairings.
	fighter.weapon.min_range = 1; fighter.weapon.max_range = 1
	enemy.weapon.min_range = 1; enemy.weapon.max_range = 1
	duel = Battle.new()
	duel.load_chapter({"units":[fighter,enemy],"terrain":[".."],"objective":{"type":"event","event_id":"arena_done"},"seed":map.rng.randi(),"rules":{"arena":true,"permadeath":true,"durability_mode":"normal","supports_enabled":false,"experience_model":map.rules.get("experience_model","gba"),"normal_mode_experience_bonus":map.rules.get("normal_mode_experience_bonus",false),"triangle_hit":map.rules.get("triangle_hit",15),"triangle_damage":map.rules.get("triangle_damage",1),"effectiveness_multiplier":map.rules.get("effectiveness_multiplier",2)}})
	# The arena's isolated combat state must retain cartridge progression policy.
	for key in ["weapon_rank_thresholds","weapon_exp_unpromoted_cap","weapon_exp_cap","weapon_exp_kill_multiplier"]:
		duel.rules[key] = map.rules[key].duplicate(true) if map.rules[key] is Dictionary else map.rules[key]
	if map.Rogue.active(map):
		duel.chapter.difficulty = preload("res://engine/campaign_difficulty.gd").normalize(map.chapter.difficulty)
		duel.chapter.rogue = map.chapter.rogue.duplicate(true)
		# The separate arena already generated its Hard opponent; do not run
		# chapter initialization or enemy scaling on this duel a second time.
		duel.combat_initiator = unit_id
		duel.turn = map.turn
		duel.support_ranks = map.support_ranks.duplicate(true)
		map.Rogue.initialize_unit(duel, duel.get_unit("arena_opponent"))
		map.Rogue.start_phase(duel, duel.get_unit("arena_opponent"))
	if auto_weapon: _select_matchup_weapon(player)
	return {"ok":true,"wager":wager,"difficulty":difficulty(wager),"class":cls.name,"level":level,"weapon":enemy.weapon.name,"player_weapon":duel.get_unit(unit_id).weapon.name}

func _select_matchup_weapon(player: Dictionary) -> void:
	var fighter: Dictionary = duel.get_unit(unit_id)
	var best: Dictionary = fighter.weapon
	var score := -1.0
	# As on the map, choose expected damage over the whole exchange. Arena
	# range is normalized for every candidate, including bows and siege tomes.
	for index in range(-1, player.inventory.size()):
		var item: Dictionary = player.weapon if index == -1 else player.inventory[index]
		if item.get("type", "") == "staff" or not map.can_equip_weapon(player, item): continue
		fighter.weapon = item.duplicate(true)
		fighter.weapon.min_range = 1; fighter.weapon.max_range = 1
		var stats: Dictionary = duel.forecast(unit_id,"arena_opponent").attacker
		var expected := float(stats.damage) * float(stats.hit) / 100.0 * int(stats.strikes)
		if expected > score:
			score = expected; weapon_index = index; best = fighter.weapon
	fighter.weapon = best

func begin() -> bool:
	if active or duel == null or map.gold < wager or not map._can_command(map.get_unit(unit_id)): return false
	duel.turn = map.turn
	if map.combat_cheat_active(): duel.rules.cheat_combat_turn = map.turn
	else: duel.rules.erase("cheat_combat_turn")
	map.commit_move(unit_id)
	if map.get_unit(unit_id).acted: return false
	if map.Rogue.active(map):
		if map.Rogue.remaining(map, "arena") <= 0: return false
		map.chapter.rogue.arena_used = int(map.chapter.rogue.get("arena_used", 0)) + 1
		duel.get_unit(unit_id).rogue_tiles_moved = int(map.get_unit(unit_id).get("rogue_tiles_moved", 0))
		duel._begin_rogue_combat(duel.get_unit(unit_id), duel.get_unit("arena_opponent"))
	map.gold -= wager
	map.get_unit(unit_id).acted = true
	active = true
	return true

func next_strike() -> Dictionary:
	if not active: return {}
	var player: Dictionary = duel.get_unit(unit_id)
	var enemy: Dictionary = duel.get_unit("arena_opponent")
	if player.hp <= 0: finish("defeat"); return {}
	if enemy.hp <= 0: finish("victory"); return {}
	if int(player.weapon.uses) <= 0 or int(enemy.weapon.uses) <= 0: finish("exhausted"); return {}
	if order.is_empty():
		order = duel.combat_order(player, enemy)
	var pair: Array = order.pop_front()
	var strike: Dictionary = duel._strike(pair[0],pair[1])
	strikes.append(strike)
	_sync()
	if map.Rogue.active(map) and str(strike.attacker_id) == unit_id and int(strike.get("damage", 0)) > 0 and not strike.get("backfire", false) and map.Rogue.Personal.has(map.get_unit(unit_id), "fe7_unit_39"):
		map.Rogue.Personal.reset_fe7_unit_39(map, map.get_unit(unit_id))
	# Settle lethal or exhausting blows before an animation/lifecycle yield,
	# so suspending during the cutscene saves a complete, consistent result.
	if player.hp <= 0 or enemy.hp <= 0: finish()
	elif int(player.weapon.uses) <= 0 or int(enemy.weapon.uses) <= 0: finish("exhausted")
	return strike

func _sync() -> void:
	var player: Dictionary = duel.get_unit(unit_id)
	var real: Dictionary = map.get_unit(unit_id)
	real.hp = player.hp
	real.status = player.get("status", "")
	real.status_turns = player.get("status_turns", 0)
	real.weapon_exp = player.weapon_exp.duplicate(true)
	if map.Rogue.active(map):
		for key in ["rogue_durability", "rogue_wexp_fraction", "rogue_effects", "rogue_used", "rogue_personal_state"]:
			if player.has(key): real[key] = player[key].duplicate(true) if player[key] is Array or player[key] is Dictionary else player[key]
	var weapon: Dictionary = real.weapon if weapon_index == -1 else real.inventory[weapon_index]
	weapon.uses = player.weapon.uses
	if player.hp <= 0: real.casualty_mode = "permanent"

func finish(reason: String = "yield") -> void:
	if not active: return
	var player: Dictionary = duel.get_unit(unit_id)
	var enemy: Dictionary = duel.get_unit("arena_opponent")
	# A queued yield cannot reverse a blow that has already landed.
	result = "defeat" if player.hp <= 0 else "victory" if enemy.hp <= 0 else reason
	active = false
	_sync()
	if map.Rogue.active(map) and not strikes.is_empty():
		var real: Dictionary = map.get_unit(unit_id)
		map.Rogue.Personal.combat_finished(real, enemy, map, player.weapon)
		player.hp = real.hp
		player.rogue_personal_state = real.get("rogue_personal_state", {}).duplicate(true)
		if int(player.hp) <= 0: result = "defeat"; real.casualty_mode = "permanent"
	if map.Rogue.active(map):
		map.Rogue.Personal.clear_combat(map.get_unit(unit_id))
		map.Rogue.Personal.clear_combat(player)
		map.Rogue.Personal.clear_combat(enemy)
		map.get_unit(unit_id).rogue_tiles_moved = 0
	if not strikes.is_empty(): preload("res://engine/fe7_campaign_rank.gd").combat(map,player,enemy)
	if result == "victory":
		map.gold += wager * 2
		# The map awards the real experience; apply Fast Learners only there.
		if map.Rogue.active(map): duel.chapter.rogue.army.fast_learners = 0
		var experience: Array = duel._combat_experience(player,enemy,strikes)
		for reward in experience:
			if reward.unit_id == unit_id: rewards.append(map._award_experience(map.get_unit(unit_id),int(reward.amount)))
	if result == "defeat":
		map._release_on_death(map.get_unit(unit_id))
		map._run_events("unit_defeated")
		map._check_objective()
	map.events_log.append("Arena: %s · %s · %d G wager." % [map.get_unit(unit_id).name,result,wager])
