extends RefCounted
## Bounded effects for reviewed FE6 finale callbacks, evaluated against live state.
const Flags = preload("res://engine/native_event_flags.gd")

static func ids(value, max_id: int = 255) -> bool:
	return value is Array and value.size() <= 256 and value.all(func(v):return Flags.integer(v,1,max_id))

static func valid_test(t: Dictionary) -> bool:
	match t.get("test",""):
		"turn_area": return Flags.integer(t.get("after"),0,255) and t.get("rect") is Array and t.rect.size() == 4 and t.rect.all(func(v):return Flags.integer(v,0,255))
		"areas": return t.get("rectangles") is Array and t.rectangles.size() <= 8 and t.rectangles.all(func(r):return r is Array and r.size() == 4 and r.all(func(v):return Flags.integer(v,0,255))) and t.get("outside") is bool and t.get("phase") == "enemy"
		"experience": return ids(t.get("left")) and ids(t.get("right"))
		"delayed_flags": return Flags.valid_flags(t.get("flags"),"chapter","fe6") and t.flags.size() == 3
		"desert_find": return ids(t.get("classes")) and Flags.integer(t.get("denominator"),1,255)
		"area": return t.get("rect") is Array and t.rect.size() == 4 and t.rect.all(func(v):return Flags.integer(v,0,255)) and t.get("phase") in ["any","enemy"]
		"wave": return Flags.valid_id(t.get("enabled"),"chapter","fe6") and (t.get("disabled") == 0 or Flags.valid_id(t.get("disabled"),"chapter","fe6")) and Flags.valid_id(t.get("cap"),"chapter","fe6") and Flags.integer(t.get("parity"),0,1)
		"items": return ids(t.get("items")) and not t.items.is_empty()
		"male": return ids(t.get("characters")) and ids(t.get("classes"))
		"nonblue_count": return Flags.integer(t.get("minimum"),1,191)
	return false

static func test(b, state: Dictionary, t: Dictionary, context: Dictionary) -> bool:
	match t.test:
		"turn_area": return b.turn > int(t.after) and b.units.any(func(u):return b._on_map(u) and u.faction == "player" and u.x >= t.rect[0] and u.y >= t.rect[1] and u.x <= t.rect[2] and u.y <= t.rect[3])
		"areas":
			var inside: bool = t.rectangles.any(func(rect):return b.units.any(func(u):return b._on_map(u) and u.faction == "player" and u.x >= rect[0] and u.y >= rect[1] and u.x <= rect[2] and u.y <= rect[3]))
			return b.phase == t.phase and inside != t.outside
		"experience": return b._event_conditions({"conditions":{"native_experience_compare":{"left":t.left,"right":t.right}}})
		"area":
			return (t.phase == "any" or b.phase == t.phase) and b.units.any(func(u):return b._on_map(u) and u.faction == "player" and u.x >= t.rect[0] and u.y >= t.rect[1] and u.x <= t.rect[2] and u.y <= t.rect[3])
		"wave": return b.phase == "enemy" and b.turn%2 == int(t.parity) and Flags.has_flag(state,int(t.enabled)) and not Flags.has_flag(state,int(t.disabled)) and not Flags.has_flag(state,int(t.cap))
		"items":
			var found: Array = []
			var items: Array = b.inventory.duplicate()
			for u in b.units+b.chapter.get("reserve_units",[]):
				if u.faction == "player" and int(u.hp) > 0:
					items.append(u.get("weapon",{})); items.append_array(u.get("inventory",[]))
			for item in items:
				if int(item.get("uses",0)) > 0: found.append(int(item.get("rom_item_id",0)))
			return t.items.all(func(id):return found.has(int(id)))
		"male":
			var actor: Dictionary = b.get_unit(str(context.get("unit_id","")))
			return not actor.is_empty() and not t.characters.any(func(id):return int(id) == int(actor.get("rom_character_id",0))) and not t.classes.any(func(id):return int(id) == int(actor.get("rom_class_id",0)))
		"nonblue_count": return context.get("presence_units",b.units).filter(func(u):return int(u.hp) > 0 and u.faction != "player" and not u.get("escaped",false)).size() >= int(t.minimum)
	return false

static func valid(c: Dictionary) -> bool:
	match c.get("action",""):
		"visibility": return Flags.integer(c.get("character"),1,255) and c.get("hidden") is bool
		"return","withdraw": return Flags.integer(c.get("character"),1,255)
		"ai_at": return ["from_x","from_y"].all(func(k):return Flags.integer(c.get(k),0,255)) and valid_ai(c.get("settings"))
		"refresh": return Flags.integer(c.get("character"),1,255)
		"remove_at": return ["from_x","from_y"].all(func(k):return Flags.integer(c.get(k),0,255))
		"move_next": return Flags.integer(c.get("character"),1,255) and Flags.integer(c.get("target"),1,255)
		"kill": return Flags.integer(c.get("character"),1,255)
		"scripted_battle": return Flags.integer(c.get("attacker"),1,255) and Flags.integer(c.get("defender"),1,255) and c.get("rounds") is Array and c.rounds.size() <= 64 and c.rounds.all(func(r):return r is Dictionary and r.get("counter") is bool and r.get("miss") is bool and r.get("critical") is bool and Flags.integer(r.get("damage"),0,255))
		"ai": return Flags.integer(c.get("character"),1,255) and valid_ai(c.get("settings"))
		"trap_uses": return Flags.integer(c.get("x"),0,255) and Flags.integer(c.get("y"),0,255) and Flags.integer(c.get("uses"),0,255)
		"move": return Flags.integer(c.get("character"),1,255) and Flags.integer(c.get("x"),-128,255) and Flags.integer(c.get("y"),-128,255)
		"move_at": return ["from_x","from_y","x","y"].all(func(k):return Flags.integer(c.get(k),-128,255))
		"move_path_at":
			var path := c.duplicate(); path.action = "move_path"; path.character = 1
			return ["from_x","from_y"].all(func(k):return Flags.integer(c.get(k),-128,255)) and valid(path)
		"move_path": return Flags.integer(c.get("character"),1,255) and c.get("steps") is Array and c.steps.size() <= 512 and c.steps.all(func(s):return s is Array and s.size() == 2 and Flags.integer(s[0],-1,1) and Flags.integer(s[1],-1,1) and abs(int(s[0]))+abs(int(s[1])) == 1)
		"promote": return Flags.integer(c.get("character"),1,255) and Flags.integer(c.get("class_id"),1,255)
		"remove": return Flags.integer(c.get("character"),1,255)
		"clear_range","increment_flags": return Flags.valid_flags(c.get("flags"),"chapter","fe6")
		"lottery": return Flags.valid_flags(c.get("flags"),"chapter","fe6") and Flags.integer(c.get("count"),1,c.flags.size()) and Flags.integer(c.get("denominator"),1,255)
		"step_traps": return valid_traps(c.get("traps"))
		"save_dragon": return Flags.integer(c.get("item"),1,255) and Flags.valid_id(c.get("flag"),"campaign","fe6")
		"ending": return Flags.integer(c.get("chapter"),1,44) and Flags.valid_id(c.get("flag"),"campaign","fe6") and Flags.integer(c.get("character"),1,255)
		"game_end": return true
		"speeches":
			if not c.get("pages") is Dictionary or c.pages.size() > 255: return false
			return c.pages.keys().all(func(k):return str(k).is_valid_int() and c.pages[k] is Array and c.pages[k].all(func(p):return p is Dictionary and p.get("text","") is String))
	return false

static func valid_ai(value) -> bool:
	if not value is Dictionary or value.get("ai_mode") not in ["pursue","escape","stationary","attack_in_range","loot","raid"]: return false
	for key in value:
		match key:
			"ai_mode": pass
			"ai_wait_actions":
				if not Flags.integer(value[key],0,1): return false
			"ai":
				if value[key] not in ["","stationary"]: return false
			"ai_no_attack","ai_random_move","ai_waypoint_reached","ai_waypoint_repeats","ai_approach_complete":
				if not value[key] is bool: return false
			"ai_after_waypoint":
				if value[key] not in ["attack_in_range","pursue"]: return false
			"ai_approach_character","ai_escape_if_missing_character","ai_preferred_character","ai_pursuit_character":
				if not Flags.integer(value[key],0,255): return false
			"ai_excluded_character_ids":
				if not ids(value[key]): return false
			"npc_talk_target":
				if not value[key] is String or (not value[key].is_empty() and not value[key].begins_with("fe6_unit_") and not value[key].begins_with("fe7_unit_")): return false
			"ai_waypoint_region":
				if not value[key] is Array or value[key].size() not in [0,4] or not value[key].all(func(v):return Flags.integer(v,0,255)): return false
				if value[key].size() == 4 and (value[key][0] > value[key][2] or value[key][1] > value[key][3]): return false
			"ai_waypoint","npc_escape":
				if not value[key] is Array or value[key].size() not in [0,2] or not value[key].all(func(v):return Flags.integer(v,0,255)): return false
			"ai_escape_points":
				if not value[key] is Array or value[key].size() > 64 or not value[key].all(func(p):return p is Array and p.size() == 2 and p.all(func(v):return Flags.integer(v,0,255))): return false
			_: return false
	return true

static func plan(b, state: Dictionary, c: Dictionary, lottery: RandomNumberGenerator) -> Dictionary:
	var result: Array = []
	match c.action:
		"clear_range","increment_flags","lottery":
			var selected: Array = c.flags.duplicate()
			if c.action == "increment_flags":
				selected = selected.filter(func(f):return not Flags.has_flag(state,int(f))).slice(0,1)
			elif c.action == "lottery":
				selected = []
				# Native cyclic rejection lottery, bounded so malformed inputs cannot hang.
				for attempt in range(65536):
					var flag := int(c.flags[attempt%c.flags.size()])
					if not selected.has(flag) and lottery.randi_range(0,int(c.denominator)-1) == 0: selected.append(flag)
					if selected.size() == int(c.count): break
				if selected.size() != int(c.count): return {"error":"Chest lottery exceeded its budget."}
			for flag in selected:
				Flags.set_flag(state,int(flag),c.action != "clear_range")
				result.append({"op":"clear" if c.action == "clear_range" else "set","flag":int(flag)})
		"save_dragon":
			if b.chapter.get("fe6_last_battle_items",[]).any(func(id):return int(id) == int(c.item)):
				Flags.set_flag(state,int(c.flag)); result.append({"op":"set","flag":c.flag})
		"ending":
			var fe6_unit_3: bool = (b.units+b.chapter.get("reserve_units",[])).any(func(u):return u.faction == "player" and int(u.hp) > 0 and int(u.get("rom_character_id",0)) == int(c.character))
			var ending := 2 if int(b.chapter.get("rom_chapter_index",0)) != int(c.chapter) else (0 if fe6_unit_3 and Flags.has_flag(state,int(c.flag)) else 1)
			result.append({"op":"fe6_commit","action":"ending","value":ending})
		"promote":
			if b._class_definition(int(c.class_id)).is_empty(): return {"error":"Native promotion class is unavailable."}
			result.append(c)
		"step_traps":
			if c.traps.any(func(t):return t.x >= b.width or t.y >= b.height): return {"error":"Step trap is outside this map."}
			result.append(c)
		"speeches":
			for u in b.units:
				var key := str(int(u.get("rom_character_id",0)))
				if b._on_map(u) and u.faction == "player" and c.pages.has(key): result.append({"op":"effect","effect":{"dialogue":c.pages[key]}})
		_: result.append(c)
	return {"error":"","commands":result}

static func scene_actor(unit: Dictionary) -> Dictionary:
	var actor := {"type":"spawn"}
	for key in ["id","rom_character_id","rom_class_id","sprite","faction","x","y","hp","max_hp"]:
		if unit.has(key): actor[key] = unit[key]
	return actor

static func queue_opening_scene(b, command: Dictionary, actors: Dictionary) -> void:
	var actions: Array = []
	for unit in command.get("effect",{}).get("spawns",[]):
		var actor := scene_actor(unit)
		actors[actor.id] = actor
		actions.append(actor.duplicate(true))
	for page in command.get("effect",{}).get("dialogue",[]):
		page.erase("fe7_scene_map")
		if page.has("fe6_scene_command"):
			queue_opening_scene(b,page.fe6_scene_command,actors)
			page.erase("fe6_scene_command")
		for unit in page.get("fe6_scene_units",[]):
			var actor := scene_actor(unit)
			actors[actor.id] = actor
			actions.append(actor.duplicate(true))
		page.erase("fe6_scene_units")
		if page.has("fe6_scene_move"):
			var move: Dictionary = page.fe6_scene_move
			for actor in actors.values():
				if int(actor.get("rom_character_id",0)) == int(move.character):
					actions.append({"type":"move","id":actor.id,"path":[[move.x,move.y]]})
					actor.x = move.x; actor.y = move.y
					break
			page.erase("fe6_scene_move")
	if command.get("action") == "visibility":
		for actor in actors.values():
			if int(actor.get("rom_character_id",0)) == int(command.character):
				actions.append({"type":"remove","id":actor.id} if command.hidden else actor.duplicate(true))
	if command.get("action") in ["remove","remove_at","withdraw"]:
		for id in actors.keys():
			if movement_matches(actors[id],command):
				actions.append({"type":"remove","id":id})
				actors.erase(id)
	if command.get("action") in ["move","move_at","move_path","move_path_at"]:
		for actor in actors.values():
			if movement_matches(actor,command):
				var path := movement_path(actor,command)
				if not path.is_empty():
					actions.append({"type":"move","id":actor.id,"path":path})
					actor.x = path[-1][0]; actor.y = path[-1][1]
				break
	if not actions.is_empty(): b.dialogue_queue.append({"text":"","native_control":true,"scene_actions":actions})

static func commit(b, c: Dictionary) -> void:
	match c.action:
		"move_next":
			var sources: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.character) and int(u.hp) > 0)
			var targets: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.target) and b._on_map(u))
			if sources.is_empty() or targets.is_empty(): return
			var target: Dictionary = targets[0]
			var origin := Vector2i(int(sources[0].x),int(sources[0].y))
			var cells := [Vector2i(target.x-1,target.y),Vector2i(target.x+1,target.y),Vector2i(target.x,target.y-1),Vector2i(target.x,target.y+1)]
			cells = cells.filter(func(cell):return cell.x >= 0 and cell.y >= 0 and cell.x < b.width and cell.y < b.height and b.unit_at(cell).is_empty() and b._move_cost(sources[0],cell) > 0)
			cells.sort_custom(func(a,z):return origin.distance_squared_to(a) < origin.distance_squared_to(z))
			if not cells.is_empty(): sources[0].x = cells[0].x; sources[0].y = cells[0].y
		"scripted_battle":
			var attackers: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.attacker))
			var defenders: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(c.defender))
			if attackers.is_empty() or defenders.is_empty(): return
			for hit in c.rounds:
				var source: Dictionary = defenders[0] if hit.counter else attackers[0]
				var target: Dictionary = attackers[0] if hit.counter else defenders[0]
				var damage := 0 if hit.miss else int(hit.damage)
				target.hp = maxi(0,int(target.hp)-damage)
				b.dialogue_queue.append({"speaker":source.name,"portrait":source.get("portrait",""),"text":"%s misses %s." % [source.name,target.name] if hit.miss else "%s hits %s for %d damage%s" % [source.name,target.name,damage," (critical)." if hit.critical else "."]})
		"refresh":
			for unit in b.units:
				if int(unit.get("rom_character_id",0)) == int(c.character) and int(unit.hp) > 0:
					unit.acted = false; unit.moved = false; unit.move_spent = 0
					unit.canto_active = false; unit.canto_remaining = 0
					break
		"kill":
			for unit in b.units:
				if int(unit.get("rom_character_id",0)) != int(c.character): continue
				unit.hp = 0
				if unit.faction == "player": unit.casualty_mode = "permanent" if b.rules.get("permadeath",true) else "injured"
				b._release_on_death(unit)
				b._run_events("unit_defeated",{"unit_id":str(unit.id)})
				break
		"withdraw":
			# REPA hides/undeploys the native slot; it does not erase its progress.
			for unit in b.units.duplicate():
				if int(unit.get("rom_character_id",0)) != int(c.character): continue
				b.units.erase(unit)
				if unit.faction == "player":
					unit.benched = true; unit.x = 0; unit.y = 0
					b.chapter.get_or_add("reserve_units",[]).append(unit)
				break
		"return":
			for unit in b.units+b.chapter.get("reserve_units",[]):
				if int(unit.get("rom_character_id",0)) == int(c.character): unit.erase("escaped")
		"ai","ai_at":
			for unit in b.units:
				var matches: bool = int(unit.get("rom_character_id",0)) == int(c.get("character",0)) if c.action == "ai" else (unit.faction != "player" and b._on_map(unit) and int(unit.x) == int(c.from_x) and int(unit.y) == int(c.from_y))
				if matches and (unit.faction != "player" or c.get("op") == "scene_unit"):
					if c.get("op") == "scene_unit":
						# FE7 replaces both AI selectors. Discard derived restrictions
						# from the previous selector before installing the new policy.
						for key in ["ai","ai_no_attack","ai_waypoint","ai_waypoint_region","ai_waypoint_reached","ai_waypoint_repeats","ai_after_waypoint","ai_excluded_character_ids","ai_pursuit_turns","ai_preferred_character","ai_pursuit_character","ai_wait_actions","ai_open_doors_first","npc_talk_target"]: unit.erase(key)
					for key in c.settings: unit[key] = c.settings[key].duplicate(true) if c.settings[key] is Array or c.settings[key] is Dictionary else c.settings[key]
		"trap_uses":
			for site in b.chapter.get("emplacements",[]):
				if site.x == c.x and site.y == c.y: site.weapon.uses = c.uses
			for wall in b.destructibles:
				if wall.x == c.x and wall.y == c.y: wall.hp = c.uses; wall.max_hp = maxi(int(wall.max_hp),int(c.uses))
		"move","move_at","move_path","move_path_at":
			for u in b.units:
				if movement_matches(u,c) and int(u.hp) > 0:
					var path := movement_path(u,c)
					if not path.is_empty(): u.x = path[-1][0]; u.y = path[-1][1]
					break
		"ending": b.chapter.fe6_ending = c.value
		"game_end": b.chapter.campaign_end = true; b.chapter.erase("next_chapter"); b.chapter.native_next_chapter = ""
		"step_traps": b.chapter.fe6_step_traps = c.traps.duplicate(true)
		"promote":
			for u in b.units+b.chapter.get("reserve_units",[]):
				if int(u.get("rom_character_id",0)) == int(c.character) and u.faction == "player" and int(u.hp) > 0 and int(u.get("rom_class_id",0)) != int(c.class_id): b._apply_class_change(u,b._class_definition(int(c.class_id)))
		"remove":
			for u in b.units.duplicate():
				if int(u.get("rom_character_id",0)) == int(c.character): b.units.erase(u)
		"remove_at":
			for u in b.units:
				if movement_matches(u,c) and b._on_map(u):
					b.units.erase(u)
					break

static func valid_traps(value) -> bool:
	if not value is Array or value.size() > 64: return false
	return value.all(func(t):return t is Dictionary and t.get("type") in ["fire","pike"] and Flags.integer(t.get("x"),0,255) and Flags.integer(t.get("y"),0,255) and Flags.integer(t.get("direction",0),0,3))

static func movement_matches(unit: Dictionary, command: Dictionary) -> bool:
	return int(unit.get("rom_character_id",0)) == int(command.character) if command.action not in ["move_at","move_path_at","remove_at"] else (unit.x == command.from_x and unit.y == command.from_y)

static func movement_path(unit: Dictionary, command: Dictionary) -> Array:
	if command.action not in ["move_path","move_path_at"]: return [[command.x,command.y]]
	var result: Array = []
	var cell := [int(unit.x),int(unit.y)]
	for delta in command.steps:
		cell = [cell[0]+int(delta[0]),cell[1]+int(delta[1])]
		result.append(cell)
	return result

static func step(b, unit: Dictionary) -> Dictionary:
	if not b._on_map(unit): return {}
	for trap in b.chapter.get("fe6_step_traps",[]):
		if int(trap.x) != int(unit.x) or int(trap.y) != int(unit.y): continue
		if unit.get("can_steal",false):
			b.chapter.fe6_step_traps.erase(trap)
			b.events_log.append("%s disarmed a trap." % unit.name)
			return {}
		var before := int(unit.hp)
		var damage := 10 if trap.type == "fire" else maxi(0,10-b.effective_stat(unit,"def"))
		unit.hp = maxi(0,before-damage)
		if b.Rogue.active(b): b.Rogue.Personal.injured(unit, before - int(unit.hp))
		var result := {"unit_id":str(unit.id),"target_id":str(unit.id),"previous_hp":before,"remaining_hp":int(unit.hp),"damage":before-int(unit.hp),"recovered":false,"trap_name":str(trap.type).capitalize()+" trap"}
		b.events_log.append("%s triggered a %s trap: %d damage." % [unit.name,trap.type,result.damage])
		if int(unit.hp) <= 0:
			if unit.faction == "player": unit.casualty_mode = "permanent" if b.rules.get("permadeath",true) else "injured"
			b._release_on_death(unit); b._run_events("unit_defeated",{"unit_id":str(unit.id)})
		if b.phase != "player" or b.auto_playing: b.phase_actions.append({"type":"trap","result":result.duplicate(true)})
		else: b.pending_trap_effects.append(result.duplicate(true))
		return result
	return {}
