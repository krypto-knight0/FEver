extends RefCounted
## Atomic, bounded control flow. Plan every branch before committing any effects.
## Conditions read live flags, route, difficulty and the triggering character.
## Native choices suspend at explicit continuation frames; other waits stay bounded.
const Fe6 = preload("res://engine/fe6_event_actions.gd")
const ScriptedCombat = preload("res://engine/fe7_scripted_combat.gd")
const Preparation = preload("res://engine/fe7_preparation.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const MAX_COMMANDS := 2048
const MAX_STEPS := 8192
const MAX_DEPTH := 16
const MAX_PENDING_SOUNDS := 256

static func keys(value: Dictionary, required: Array, optional: Array = []) -> bool:
	return required.all(func(k): return value.has(k)) and value.keys().all(func(k): return k in required or k in optional)

static func valid_test(test: Variant, profile: String = "fe7") -> bool:
	if not test is Dictionary or not test.get("kind") is String: return false
	match test.kind:
		"enemy_count_at_most": return profile == "fe7" and keys(test,["kind","maximum"]) and Flags.integer(test.maximum,0,255)
		"route_support_flag": return profile == "fe7" and keys(test,["kind","route","support","flag"]) and Flags.integer(test.route,2,3) and test.support is Dictionary and test.support.get("kind") == "support_rank" and valid_test(test.support,profile) and Flags.valid_id(test.flag,"any",profile)
		"phase_terrain": return profile == "fe7" and keys(test,["kind","phase","x","y","terrain"]) and test.phase in ["player","enemy","npc"] and Flags.integer(test.x,0,255) and Flags.integer(test.y,0,255) and Flags.integer(test.terrain,0,64)
		"occupied_tiles": return profile == "fe7" and keys(test,["kind","tiles","faction"]) and test.faction in ["player","enemy","neutral"] and test.tiles is Array and not test.tiles.is_empty() and test.tiles.size() <= 32 and test.tiles.all(func(t):return t is Array and t.size() == 2 and t.all(func(v):return Flags.integer(v,0,255)))
		"unit_hp_zero","usable_weapon": return profile == "fe7" and keys(test,["kind","character"]) and Flags.integer(test.character,1,255)
		"unit_class_level": return profile == "fe7" and keys(test,["kind","character","class_id","minimum"]) and Flags.integer(test.character,1,255) and Flags.integer(test.class_id,1,255) and Flags.integer(test.minimum,1,127)
		"unit_corner": return profile == "fe7" and keys(test,["kind","character","maximum_x","maximum_y"]) and Flags.integer(test.character,1,255) and Flags.integer(test.maximum_x,0,255) and Flags.integer(test.maximum_y,0,255)
		"support_rank": return profile == "fe7" and keys(test,["kind","first","second","minimum"]) and Flags.integer(test.first,1,255) and Flags.integer(test.second,1,255) and Flags.integer(test.minimum,1,3)
		"battle_lord": return profile == "fe7" and keys(test,["kind"])
		"enemy_count_at_least": return profile == "fe7" and keys(test,["kind","minimum"]) and Flags.integer(test.minimum,1,255)
		"active_dead": return profile == "fe7" and keys(test,["kind"])
		"funds": return profile == "fe7" and keys(test,["kind","minimum"]) and Flags.integer(test.minimum,0,999999)
		"flag_pair": return profile == "fe7" and keys(test,["kind","set","clear"]) and Flags.valid_id(test.set,"any",profile) and Flags.valid_id(test.clear,"any",profile)
		"experience_rosters": return profile == "fe7" and keys(test,["kind","first","second"]) and Fe6.ids(test.first) and Fe6.ids(test.second)
		"desert_find": return profile == "fe7" and keys(test,["kind","classes","denominator"]) and Fe6.ids(test.classes) and Flags.integer(test.denominator,1,255)
		"chapter_experience": return profile == "fe7" and keys(test,["kind","minimum"]) and Flags.integer(test.minimum,1,65535)
		"combined_levels": return profile == "fe7" and keys(test,["kind","characters","minimum"]) and Fe6.ids(test.characters) and Flags.integer(test.minimum,1,65535)
		"campaign_level_flag": return profile == "fe7" and keys(test,["kind","character","minimum","flag"]) and Flags.integer(test.character,1,255) and Flags.integer(test.minimum,1,127) and Flags.valid_id(test.flag,"any",profile)
		"occupied_tile": return profile == "fe7" and keys(test,["kind","x","y","faction"]) and Flags.integer(test.x,0,255) and Flags.integer(test.y,0,255) and test.faction in ["player","enemy","neutral"]
		"active_any","battle_any": return profile == "fe7" and keys(test,["kind","characters"]) and test.characters is Array and not test.characters.is_empty() and test.characters.size() <= 255 and test.characters.all(func(id):return Flags.integer(id,1,255))
		"unvisited_terrain": return profile == "fe7" and keys(test,["kind","flag","x","y","excluded"]) and Flags.valid_id(test.flag,"any",profile) and Flags.integer(test.x,0,255) and Flags.integer(test.y,0,255) and Flags.integer(test.excluded,0,255)
		"constant": return profile == "fe7" and keys(test,["kind","value"]) and test.value is bool
		"fe6": return profile == "fe6" and Fe6.valid_test(test)
		"flag": return keys(test,["kind","flag"]) and Flags.integer(test.flag,0,164) and (Flags.valid_id(test.flag,"any",profile) or int(test.flag) in [0,100])
		"count": return keys(test,["kind","condition"]) and Flags.valid_condition(test.condition,profile)
		"route": return keys(test,["kind","value"]) and Flags.integer(test.value,1,3)
		"hard": return keys(test,["kind"])
		"choice": return profile == "fe7" and keys(test,["kind"])
		"casualty": return profile == "fe7" and keys(test,["kind","character"]) and Flags.integer(test.character,1,255)
		"unit_at": return profile == "fe7" and keys(test,["kind","character","faction","x","y"]) and Flags.integer(test.character,1,255) and test.faction in ["player","enemy","neutral"] and Flags.integer(test.x,0,255) and Flags.integer(test.y,0,255)
		"unit_count": return profile == "fe7" and keys(test,["kind","faction","maximum","ready"]) and test.faction in ["player","enemy","neutral"] and Flags.integer(test.maximum,0,255) and test.ready is bool
		"fielded": return profile == "fe7" and keys(test,["kind","character"]) and Flags.integer(test.character,1,255)
		"active": return keys(test,["kind","character"]) and Flags.integer(test.character,0,255)
		"phase": return keys(test,["kind","value"]) and test.value in ["player","enemy","npc"]
		"turn_after": return profile in ["fe6","fe7"] and keys(test,["kind","value"]) and Flags.integer(test.value,0,255)
		"turn_at_least": return profile == "fe7" and keys(test,["kind","value"]) and Flags.integer(test.value,0,65535)
		"ambush_roll": return profile == "fe6" and keys(test,["kind","denominator","cap"]) and Flags.integer(test.denominator,1,255) and Flags.integer(test.cap,1,128)
		"presence","roster_presence": return keys(test,["kind","character","factions"],["include_dead","deployed"] if profile == "fe7" else []) and test.get("include_dead",false) is bool and test.get("deployed",false) is bool and Flags.integer(test.character,1,255) and test.factions is Array and not test.factions.is_empty() and test.factions.all(func(f):return f in ["player","enemy","neutral"])
		"affiliation": return keys(test,["kind","character","faction"]) and Flags.integer(test.character,1,255) and test.faction in ["player","enemy","neutral"]
	return false

static func valid_item(item: Variant) -> bool:
	if not item is Dictionary or item.is_empty(): return false
	for field in ["rom_item_id","uses","max_uses","might","hit","weight","crit","min_range","max_range"]:
		if item.has(field) and not Flags.integer(item[field],0,65535): return false
	for field in ["name","kind","type","staff_effect","game_id"]:
		if item.has(field) and not item[field] is String: return false
	return item.get("opens",[]) is Array and item.get("requires_staves",false) is bool

static func valid_effect(effect: Variant, allow_choice: bool = false) -> bool:
	if not effect is Dictionary or effect.size() != 1: return false
	if effect.has("ai_changes"):
		if not effect.ai_changes is Array or effect.ai_changes.size() > 256: return false
		for change in effect.ai_changes:
			if change is Dictionary and keys(change,["unit_id","ai_mode"]) and change.unit_id is String and change.ai_mode == "escape": continue
			if not change is Dictionary or not keys(change,["x","y","ai_mode"],["source_offset"]) or not Flags.integer(change.x,0,65535) or not Flags.integer(change.y,0,65535) or change.ai_mode != "pursue" or not change.get("source_offset","") is String: return false
		return true
	if effect.has("map_change"):
		var patch: Variant = effect.map_change
		if not patch is Dictionary or not Flags.integer(patch.get("x"),0,65535) or not Flags.integer(patch.get("y"),0,65535) or not patch.get("terrain") is Array or patch.terrain.is_empty() or not patch.terrain.all(func(row):return row is String and not row.is_empty()): return false
		var width: int = patch.terrain[0].length()
		if not patch.terrain.all(func(row):return row.length() == width): return false
		if patch.has("mask"):
			if not patch.mask is Array or patch.mask.size() != patch.terrain.size(): return false
			for row in patch.mask:
				if not row is Array or row.size() != width or not row.all(func(cell):return cell is bool or Flags.integer(cell,0,1)): return false
		return true
	if effect.has("weather"): return Flags.integer(effect.weather,0,6) and int(effect.weather) in [0,1,2,4,5,6]
	if effect.has("fog_radius"): return Flags.integer(effect.fog_radius,0,255)
	if effect.has("rom_sound"): return Flags.integer(effect.rom_sound,0,65535)
	if effect.has("reward"):
		return effect.reward is Dictionary and keys(effect.reward,["gold"]) and Flags.integer(effect.reward.gold,0,999999)
	if effect.has("give_items"):
		return effect.give_items is Array and effect.give_items.all(func(gift):return gift is Dictionary and keys(gift,["unit_id","item"]) and gift.unit_id is String and valid_item(gift.item))
	if effect.has("give_item_to_actor"): return valid_item(effect.give_item_to_actor)
	if effect.has("dialogue"):
		if not effect.dialogue is Array or effect.dialogue.size() > 1024: return false
		for page in effect.dialogue:
			if not page is Dictionary or not page.get("text","") is String or not page.get("speaker","") is String: return false
			if page.get("native_choice",false) and not allow_choice: return false
		return true
	if effect.has("change_faction"):
		if not effect.change_faction is Array or effect.change_faction.size() > 256: return false
		for change in effect.change_faction:
			if not change is Dictionary or not keys(change,["unit_id","faction"]) or not change.unit_id is String or change.faction not in ["player","enemy","neutral"]: return false
		return true
	if effect.has("spawns"):
		if not effect.spawns is Array or effect.spawns.size() > 128: return false
		var ids := {}
		for unit in effect.spawns:
			if not unit is Dictionary or not unit.get("id") is String or unit.id.is_empty() or ids.has(unit.id) or unit.get("faction") not in ["player","enemy","neutral"]: return false
			ids[unit.id] = true
			for field in ["x","y","max_hp"]:
				if not Flags.integer(unit.get(field),0,65535): return false
			for field in ["hp","level","exp","str","skill","speed","luck","def","res","mov","con","rom_class_id","rom_character_id"]:
				if unit.has(field) and not Flags.integer(unit[field],0,65535): return false
			for field in ["weapon","drop_item","temporary_bonuses","weapon_exp","growths","stat_caps","movement_costs","terrain_bonuses","rogue_skills"]:
				if not unit.get(field,{}) is Dictionary: return false
			if not unit.get("inventory",[]) is Array or not unit.get("weapon_types",[]) is Array: return false
			if not unit.get("weapon",{}).is_empty() and not valid_item(unit.weapon): return false
			for item in unit.get("inventory",[]):
				if not valid_item(item): return false
		return true
	return false

static func valid_deployment_context(context: Variant) -> bool:
	return context is Dictionary and keys(context,["route","mode"]) and Flags.integer(context.route,2,3) and context.mode in ["normal","hard"]

static func validate(program: Variant, profile: String = "fe7") -> String:
	if not program is Dictionary or not keys(program,["version","scripts"],["completion_flag","deployment_context","entry"]) or program.version != 1 or not program.scripts is Array or program.scripts.is_empty() or program.scripts.size() > 64: return "Invalid native program header."
	if program.has("entry"):
		if profile != "fe7" or not program.entry is Array or program.entry.is_empty() or program.entry.size() > MAX_DEPTH: return "Invalid continuation stack."
		for frame in program.entry:
			if not frame is Dictionary or not keys(frame,["script","pc"]) or not Flags.integer(frame.script,0,program.scripts.size()-1): return "Invalid continuation frame."
			if not program.scripts[int(frame.script)] is Array or not Flags.integer(frame.pc,0,program.scripts[int(frame.script)].size()-1): return "Invalid continuation position."
	if program.has("deployment_context") and not valid_deployment_context(program.deployment_context): return "Invalid native deployment context."
	if not Flags.integer(program.get("completion_flag",0),0,164) or (program.get("completion_flag",0) != 0 and not Flags.valid_id(program.completion_flag,"any",profile)): return "Invalid completion flag."
	var total := 0
	for script in program.scripts:
		if not script is Array or script.is_empty(): return "Empty native script."
		total += script.size()
		if total > MAX_COMMANDS: return "Native program exceeds its command limit."
		for command in script:
			if not command is Dictionary or not command.get("op") is String: return "Invalid native command."
			match command.op:
				"fe7_final_formation":
					if profile != "fe7" or not keys(command,["op","fixed","slots","exclude","fallback","scene_only"]) or not command.scene_only is bool or not command.fixed is Array or command.fixed.size() > 64 or not command.fixed.all(func(p):return p is Dictionary and keys(p,["character","x","y"]) and Flags.integer(p.character,1,255) and Flags.integer(p.x,0,255) and Flags.integer(p.y,0,255)) or not command.slots is Array or command.slots.size() > 64 or not command.slots.all(func(p):return p is Array and p.size() == 2 and p.all(func(v):return Flags.integer(v,0,255))) or not command.exclude is Array or not command.exclude.all(func(v):return Flags.integer(v,1,255)) or not valid_effect({"spawns":command.fallback}): return "Invalid final formation."
				"campaign_end","fe7_clear_enemies":
					if profile != "fe7" or not keys(command,["op"]): return "Invalid finale action."
				"fe7_exp_baseline":
					if profile != "fe7" or not keys(command,["op"]): return "Invalid experience baseline."
				"fe7_casualty":
					if profile != "fe7" or not keys(command,["op","character"]) or not Flags.integer(command.character,1,255): return "Invalid native casualty."
				"fe7_unit_state":
					if profile != "fe7" or not keys(command,["op","character","field","value"]) or not Flags.integer(command.character,1,255) or command.field not in ["acted","escaped"] or not command.value is bool: return "Invalid native unit state."
				"fe7_ring_status":
					if profile != "fe7" or not keys(command,["op","character","bonuses"]) or not Flags.integer(command.character,1,255) or not command.bonuses is Dictionary or not keys(command.bonuses,["def","res"]) or not ScriptedCombat.valid_ring(command.bonuses): return "Invalid native ring status."
				"fe7_performer_swap":
					if profile != "fe7" or not keys(command,["op","first","second"]) or not Flags.integer(command.first,1,255) or not Flags.integer(command.second,1,255) or command.first == command.second: return "Invalid native performer swap."
				"fe7_retain_actor":
					if profile != "fe7" or not keys(command,["op","character","fallback"]) or not Flags.integer(command.character,1,255) or not valid_effect({"spawns":command.fallback}): return "Invalid retained scene actor."
				"fe7_grants":
					if profile != "fe7" or not keys(command,["op","gifts"]) or not command.gifts is Array or command.gifts.size() > 64 or not command.gifts.all(func(g):return g is Dictionary and keys(g,["character","item"]) and Flags.integer(g.character,1,255) and valid_item(g.item)): return "Invalid native inventory grants."
				"fe7_bonus":
					if profile != "fe7" or not keys(command,["op","character","flags","items"],["default_without_lyn"]) or not Flags.integer(command.character,1,255) or not command.flags is Array or command.flags.size() != 2 or not command.flags.all(func(f):return Flags.valid_id(f,"campaign",profile)) or not command.items is Array or command.items.size() != 4 or command.items[0] != {} or not command.items.slice(1).all(valid_item) or (command.has("default_without_lyn") and not valid_item(command.default_without_lyn)): return "Invalid native bonus item."
				"fe7_convoy_level":
					if profile != "fe7" or not keys(command,["op","character","flag"]) or not Flags.integer(command.character,1,255) or not Flags.valid_id(command.flag,"any",profile): return "Invalid convoy completion."
				"fe7_promote":
					if profile != "fe7" or not keys(command,["op","character"]) or not Flags.integer(command.character,1,255): return "Invalid forced promotion."
				"fe7_ballista":
					if profile != "fe7" or not keys(command,["op","character"]) or not Flags.integer(command.character,1,255): return "Invalid ballista actor."
				"fe7_prepare":
					if profile != "fe7" or not keys(command,["op","players","enemies"]) or not valid_effect({"spawns":command.players}) or not valid_effect({"spawns":command.enemies}) or command.players.is_empty() or not command.players.all(func(u):return u.faction == "player") or not command.enemies.all(func(u):return u.faction != "player"): return "Invalid native preparation army."
				"choice":
					if profile != "fe7" or not keys(command,["op","page"]) or not valid_effect({"dialogue":[command.page]},true) or command.page.get("native_choice") != true: return "Invalid native choice."
				"scene_unit":
					if profile != "fe7" or command.get("action") not in ["move","move_at","move_path","move_path_at","remove","remove_at","ai","ai_at","refresh","visibility","return","withdraw","move_next"] or not Fe6.valid(command): return "Invalid FE7 scene unit action."
				"scripted_battle":
					if profile != "fe7" or not keys(command,["op","attacker","defender","automatic","rounds"],["ballista","scene_only","ring"]) or not command.get("scene_only",false) is bool or not ScriptedCombat.valid(command): return "Invalid scripted combat."
				"defeat":
					if profile != "fe7" or not keys(command,["op"]): return "Invalid native defeat."
				"fe7_victory":
					if profile != "fe7" or not keys(command,["op"]): return "Invalid native victory."
				"fe7_cleanup":
					if profile != "fe7" or not keys(command,["op"],["heal"]) or not command.get("heal",true) is bool: return "Invalid FE7 chapter cleanup."
				"fe7_formation":
					if profile != "fe7" or not keys(command,["op"]): return "Invalid FE7 formation cleanup."
				"fe6":
					if profile != "fe6" or not Fe6.valid(command): return "Invalid FE6 callback action."
				"random_flag":
					if profile != "fe6" or not keys(command,["op","flags"]) or not command.flags is Array or command.flags.is_empty() or command.flags.size() > 32 or not command.flags.all(func(f):return Flags.valid_id(f,"chapter","fe6")): return "Invalid flag lottery."
				"ambush_begin":
					if profile != "fe6" or not keys(command,["op","normal_limit","hard_limit","flag"]) or not Flags.integer(command.normal_limit,1,255) or not Flags.integer(command.hard_limit,1,255) or not Flags.valid_id(command.flag,"chapter","fe6"): return "Invalid ambush counter."
				"destination":
					var root := "res://content/fe6/chapters/" if profile == "fe6" else "res://content/fe7/dynamic/"
					if not keys(command,["op","path"]) or not command.path is String or (not command.path.is_empty() and (not command.path.begins_with(root) or command.path.contains("..") or not command.path.ends_with(".json"))): return "Invalid destination."
				"end","nop":
					if not keys(command,["op"]): return "Invalid terminal command."
				"set","clear":
					if not keys(command,["op","flag"]) or not Flags.valid_id(command.flag,"any",profile): return "Invalid native flag operand."
				"jump":
					if not keys(command,["op","target"]) or not Flags.integer(command.target,0,script.size()-1): return "Invalid jump target."
				"branch":
					if not keys(command,["op","target","test","when"]) or not command.when is bool or not valid_test(command.test,profile) or not Flags.integer(command.target,0,script.size()-1): return "Invalid branch."
				"call","tail":
					if not keys(command,["op","script"]) or not Flags.integer(command.script,0,program.scripts.size()-1): return "Invalid call target."
				"effect":
					if not keys(command,["op","effect"],["mode"]) or command.get("mode","normal") not in ["normal","hard"] or not valid_effect(command.effect): return "Unsupported or malformed action."
				"focus":
					if not keys(command,["op","character"]) or not Flags.integer(command.character,1,255): return "Invalid native camera target."
				"visitor_dialogue":
					if not keys(command,["op","pages"]) or not command.pages is Dictionary or command.pages.is_empty(): return "Invalid visitor dialogue table."
					for character in command.pages:
						if not str(character).is_valid_int() or not Flags.integer(int(character),1,255) or not valid_effect({"dialogue":command.pages[character]}): return "Invalid visitor dialogue entry."
				"conditional_dialogue":
					if not keys(command,["op","test","yes","no"]) or not valid_test(command.test,profile) or not valid_effect({"dialogue":command.yes}) or not valid_effect({"dialogue":command.no}): return "Invalid conditional dialogue."
				"faction":
					if not keys(command,["op","character","faction"]) or not Flags.integer(command.character,1,255) or command.faction not in ["player","enemy","neutral"]: return "Invalid native faction change."
				"set_gold":
					if profile != "fe7" or not keys(command,["op","amount"]) or not Flags.integer(command.amount,0,999999): return "Invalid native starting funds."
				"spend_gold":
					if profile != "fe7" or not keys(command,["op","amount"]) or not Flags.integer(command.amount,0,999999): return "Invalid native gold cost."
				"gold":
					if not keys(command,["op","amount","mode"]) or not Flags.integer(command.amount,1,999999) or command.mode not in ["active","party"]: return "Invalid native gold reward."
				_: return "Unsupported native command: " + command.op
	return ""

static func spawn_templates(event: Dictionary) -> Array:
	# Catalog readers need the same unit templates for art, previews and schedules,
	# regardless of whether an event uses declarative effects or a native program.
	if not event.has("native_program"): return event.get("spawns", [])
	var result: Array = []
	for script in event.native_program.scripts:
		for command in script:
			if command.op == "effect": result.append_array(command.effect.get("spawns", []))
			elif command.op == "fe7_prepare": result.append_array(command.enemies)
	return result

static func recruitment_ids(event: Dictionary, visitor: int = -1) -> Array[String]:
	# Preview possible recruits without running a program or applying its effects.
	# A conditional conversation can advertise a recruit before its conditions hold.
	var ids: Array[String] = []
	var changes: Array = event.get("change_faction",[]).duplicate()
	var spawns: Array = event.get("spawns",[]).duplicate()
	for command in recruitment_commands(event,visitor):
		if command.op == "faction" and command.faction == "player":
			var game_id := str(event.get("game_id","fe7" if str(event.get("id","")).begins_with("fe7_") else "fe6"))
			changes.append({"unit_id":"%s_unit_%d" % [game_id,int(command.character)],"faction":"player"})
		if command.op == "effect":
			changes.append_array(command.effect.get("change_faction",[]))
			spawns.append_array(command.effect.get("spawns",[]))
	for change in changes:
		if change.get("faction") == "player" and not ids.has(str(change.unit_id)): ids.append(str(change.unit_id))
	for unit in spawns:
		if unit.get("faction") == "player" and not ids.has(str(unit.id)): ids.append(str(unit.id))
	return ids

static func recruitment_commands(event: Dictionary, visitor: int) -> Array:
	# Follow only control flow. Unknown flag/presence conditions may take either
	# branch; a specific visitor resolves native active-character tests. This
	# discovers recruitment-site requirements without executing any script.
	var scripts: Array = event.get("native_program",{}).get("scripts",[])
	var pending: Array = [[0,0]] if not scripts.is_empty() else []
	var seen := {}
	var result: Array = []
	while not pending.is_empty():
		var cursor: Array = pending.pop_back()
		var key := "%d:%d" % cursor
		if seen.has(key): continue
		seen[key] = true
		var script := int(cursor[0]); var pc := int(cursor[1])
		if script < 0 or script >= scripts.size() or pc < 0 or pc >= scripts[script].size(): continue
		var command: Dictionary = scripts[script][pc]
		result.append(command)
		if command.op == "end": continue
		if command.op == "tail": pending.append([int(command.script),0]); continue
		if command.op == "jump": pending.append([script,int(command.target)]); continue
		if command.op == "branch":
			if visitor >= 0 and command.test.kind == "active":
				pending.append([script,int(command.target) if (visitor == int(command.test.character)) == bool(command.when) else pc+1])
				continue
			pending.append([script,int(command.target)])
		pending.append([script,pc+1])
	return result

static func recruitment_visitors(event: Dictionary) -> Dictionary:
	var visitors: Array[int] = [0] # Anonymous visitor tests the unrestricted path.
	for command in recruitment_commands(event,-1):
		if command.op == "branch" and command.test.kind == "active" and not visitors.has(int(command.test.character)): visitors.append(int(command.test.character))
	var result := {}
	for visitor in visitors:
		for id in recruitment_ids(event,visitor):
			var choices: Array = result.get_or_add(id,[])
			if visitor == 0: choices.append("")
			elif not choices.has(""): choices.append("fe6_unit_%d" % visitor)
	return result

static func valid_sound_queue(value: Variant) -> bool:
	return value is Array and value.size() <= MAX_PENDING_SOUNDS and value.all(func(id): return Flags.integer(id,0,65535))

static func valid_dispatch_state(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 16384: return false
	for id in value:
		var stamp: Variant = value[id]
		if not id is String or id.is_empty() or not stamp is Dictionary or not keys(stamp,["turn","phase"]) or not Flags.integer(stamp.turn,1,2147483647) or stamp.phase not in ["player","enemy","npc"]: return false
	return true

static func validate_event(event: Dictionary, profile: String = "fe7") -> String:
	var error := validate(event.get("native_program"),profile)
	if not error.is_empty(): return error
	if event.get("trigger") not in ["victory","native_choice","talk"] and event.native_program.scripts.any(func(script):return script.any(func(c):return c.op == "choice")): return "Interactive native choices require a conversation or chapter ending."
	if not event.get("native_repeat",false) is bool or (event.get("native_repeat",false) and event.get("trigger") not in (["turn","native_flag","enter_region","visit"] if profile == "fe6" else ["turn","enter_region"])): return "Repeated native dispatch requires a supported trigger."
	for key in ["spawns","dialogue","dialogue_by_unit","reward","give_item_to_actor","give_items","map_change","map_changes","change_faction","remove_units","relocate_units","activate_events","set_story_flags","native_flags_set","native_flags_clear","result","promote_units","schedule_departure","ai_changes","fog_radius","rom_sound","weather","weather_effect","complete_level","message","duel_recruit"]:
		if event.has(key): return "Native programs cannot mix declarative effect fields: " + key
	return ""

static func route_id(b) -> int:
	if b.chapter.has("native_route"):
		return int(b.chapter.native_route) if Flags.integer(b.chapter.native_route,1,3) else 0
	var id := str(b.chapter.get("id",""))
	return 1 if id.begins_with("fe7_tutorial_") else (2 if id.begins_with("fe7_eli_") else (3 if id.begins_with("fe7_hec_") else 0))

static func test_value(b, state: Dictionary, test: Dictionary, context: Dictionary) -> bool:
	match test.kind:
		"enemy_count_at_most": return context.get("presence_units",b.units).filter(func(u):return u.faction == "enemy" and int(u.hp) > 0).size() <= int(test.maximum)
		"route_support_flag": return int(b.chapter.get("native_route",1)) == int(test.route) and Flags.has_flag(state,int(test.flag)) and test_value(b,state,test.support,context)
		"phase_terrain":
			var rows: Array = context.get("terrain",b.terrain)
			return b.phase == test.phase and int(test.y) < rows.size() and int(test.x) < rows[int(test.y)].length() and preload("res://runtime/rom_data.gd").SYMBOLS.find(rows[int(test.y)][int(test.x)]) == int(test.terrain)
		"occupied_tiles": return context.get("presence_units",b.units).any(func(u):return u.faction == test.faction and int(u.hp) > 0 and not u.get("benched",false) and not u.get("escaped",false) and str(u.get("rescued_by","")).is_empty() and test.tiles.any(func(t):return int(u.x) == int(t[0]) and int(u.y) == int(t[1])))
		"unit_hp_zero","usable_weapon","unit_class_level","unit_corner":
			var units: Array = context.get("presence_units",b.units).filter(func(u):return int(u.get("rom_character_id",0)) == int(test.character))
			if units.is_empty(): return false
			var unit: Dictionary = units[0]
			if test.kind == "unit_hp_zero": return int(unit.hp) == 0
			if test.kind == "unit_corner": return int(unit.x) <= int(test.maximum_x) and int(unit.y) <= int(test.maximum_y)
			if test.kind == "unit_class_level": return unit.faction == "player" and int(unit.hp) > 0 and not unit.get("benched",false) and not unit.get("escaped",false) and int(unit.get("rom_class_id",0)) == int(test.class_id) and int(unit.level) >= int(test.minimum)
			return ([unit.get("weapon",{})]+unit.get("inventory",[])).any(func(w):return b.can_equip_weapon(unit,w) and (w.get("unbreakable",false) or int(w.get("uses",0)) > 0))
		"active_dead": return int(b.get_unit(str(context.get("unit_id",""))).get("hp",0)) <= 0
		"funds": return int(context.get("gold",b.gold)) >= int(test.minimum)
		"flag_pair": return Flags.has_flag(state,int(test.set)) and not Flags.has_flag(state,int(test.clear))
		"experience_rosters":
			var totals := [0,0]
			for unit in context.get("presence_units",b.units+b.chapter.get("reserve_units",[])):
				if unit.faction != "player" or int(unit.hp) <= 0: continue
				var id := int(unit.get("rom_character_id",0))
				for side in range(2):
					if (test.first if side == 0 else test.second).any(func(member):return int(member) == id): totals[side] += int(b.chapter.get("fe7_experience",{}).get(str(id),0))
			return totals[0] > totals[1]
		"chapter_experience": return int(b.chapter.get("fe7_earned_experience",0))-int(b.chapter.get("fe7_exp_baseline",0)) >= int(test.minimum)
		"combined_levels":
			var total := 0
			for unit in context.get("presence_units",b.units+b.chapter.get("reserve_units",[])):
				if unit.faction == "player" and int(unit.hp) > 0 and test.characters.any(func(id):return int(id) == int(unit.get("rom_character_id",0))): total += int(unit.level)
			return total >= int(test.minimum)

		"campaign_level_flag":
			if not Flags.has_flag(state,int(test.flag)): return false
			var army: Array = b.units+b.chapter.get("reserve_units",[])
			var candidates: Array = army.filter(func(u):return int(u.get("rom_character_id",0)) == int(test.character))
			if candidates.is_empty():
				var carried: Dictionary = b.chapter.get("campaign_roster",{}).get("fe7_unit_%d" % int(test.character),{})
				if not carried.is_empty(): candidates.append(carried)
			return candidates.any(func(u):return int(u.get("level",0)) >= int(test.minimum))
		"occupied_tile": return context.get("presence_units",b.units).any(func(u):return u.faction == test.faction and int(u.hp) > 0 and not u.get("benched",false) and not u.get("escaped",false) and not u.get("rescued_by","") and u.x == test.x and u.y == test.y)
		"support_rank": return int(b.support_ranks.get(b._pair_key("fe7_unit_%d" % int(test.first),"fe7_unit_%d" % int(test.second)),0)) >= int(test.minimum)
		"battle_lord","battle_any":
			var characters: Array = [{1:3,2:1,3:2}.get(int(b.chapter.get("native_route",1)),3)] if test.kind == "battle_lord" else test.characters
			return ["attacker_id","defender_id"].any(func(key):return characters.any(func(id):return int(id) == int(b.get_unit(str(context.get(key,""))).get("rom_character_id",0))))
		"enemy_count_at_least": return context.get("presence_units",b.units).filter(func(u):return u.faction == "enemy" and int(u.hp) > 0).size() >= int(test.minimum)
		"active_any":
			var character := int(b.get_unit(str(context.get("unit_id",context.get("attacker_id","")))).get("rom_character_id",0))
			return test.characters.any(func(id):return int(id) == character)
		"unvisited_terrain":
			if Flags.has_flag(state,int(test.flag)) or int(test.x) >= b.width or int(test.y) >= b.height: return false
			var rows: Array = context.get("terrain",b.terrain)
			var symbol: String = rows[int(test.y)][int(test.x)]
			var terrain_id: int = preload("res://engine/terrain_types.gd").SYMBOLS.find(symbol)
			return terrain_id >= 0 and terrain_id != int(test.excluded)
		"unit_at": return context.get("presence_units",b.units).any(func(u):return int(u.get("rom_character_id",0)) == int(test.character) and u.faction == test.faction and u.x == test.x and u.y == test.y)
		"unit_count": return context.get("presence_units",b.units).filter(func(u):return u.faction == test.faction and int(u.hp) > 0 and not u.get("escaped",false) and (not test.ready or (not u.get("acted",false) and not u.get("benched",false)))).size() <= int(test.maximum)
		"constant": return bool(test.value)
		"fe6": return Fe6.test(b,state,test,context)
		"flag": return Flags.has_flag(state,int(test.flag))
		"count": return Flags.matches(state,test.condition)
		"hard": return preload("res://engine/campaign_difficulty.gd").is_hard(b.chapter.get("difficulty","normal"))
		"choice": return bool(context.get("native_choice",false))
		"active":
			var actor: Dictionary = b.get_unit(str(context.get("unit_id",context.get("attacker_id",""))))
			return int(actor.get("rom_character_id",0)) == int(test.character)
		"route":
			return route_id(b) == int(test.value)
		"phase": return b.phase == test.value
		"turn_after": return b.turn > int(test.value)
		"turn_at_least": return b.turn >= int(test.value)
		"roster_presence": return (b.units+b.chapter.get("reserve_units",[])).any(func(unit):return int(unit.get("rom_character_id",0)) == int(test.character) and int(unit.get("hp",0)) > 0 and unit.get("faction") in test.factions)
		"casualty": return (b.units+b.chapter.get("reserve_units",[])).any(func(unit):return int(unit.get("rom_character_id",0)) == int(test.character) and int(unit.get("hp",1)) <= 0 and unit.get("faction") == "player")
		"fielded": return context.get("presence_units",b.units).any(func(unit):return int(unit.get("rom_character_id",0)) == int(test.character) and int(unit.hp) > 0 and not unit.get("benched",false) and not unit.get("escaped",false) and int(unit.x) >= 0 and int(unit.y) >= 0 and int(unit.x) < b.width and int(unit.y) < b.height)
		"presence": return context.get("presence_units",b.units).any(func(unit):return int(unit.get("rom_character_id",0)) == int(test.character) and (int(unit.hp) > 0 or test.get("include_dead",false)) and unit.faction in test.factions and (not test.get("deployed",false) or (not unit.get("benched",false) and not unit.get("escaped",false))))
		"affiliation":
			# Native character lookup checks player slots first, then NPC/enemy.
			for faction in ["player","neutral","enemy"]:
				if context.get("presence_units",b.units).any(func(unit):return int(unit.get("rom_character_id",0)) == int(test.character) and unit.faction == faction): return faction == test.faction
	return false

static func plan(b, program: Dictionary, context: Dictionary) -> Dictionary:
	var error := validate(program,Flags.game(b.chapter))
	if error.is_empty() and program.has("deployment_context"):
		var selected: Dictionary = program.deployment_context
		if int(selected.route) != route_id(b) or (selected.mode == "hard") != (preload("res://engine/campaign_difficulty.gd").is_hard(b.chapter.get("difficulty","normal"))): error = "Native deployment context disagrees with the battle."
	if not error.is_empty(): return {"error":error}
	var state: Dictionary = b.native_event_state.duplicate(true)
	var query_context := context.duplicate()
	query_context.gold = b.gold
	query_context.presence_units = b.units.map(func(unit):return {"rom_character_id":unit.get("rom_character_id",0),"hp":unit.hp,"faction":unit.faction,"x":unit.x,"y":unit.y})
	var projection = null
	var scene_projection = null
	if Flags.game(b.chapter) == "fe7":
		projection = b.get_script().new()
		projection.chapter = b.chapter.duplicate(true); projection.rules = b.rules.duplicate(true)
		projection.units = b.units.duplicate(true); projection.terrain = b.terrain.duplicate(true)
		projection.width = b.width; projection.height = b.height; projection.turn = b.turn; projection.phase = b.phase
		projection.rng.state = b.rng.state
		query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
		query_context.terrain = projection.terrain
	var lottery := RandomNumberGenerator.new()
	lottery.state = b.rng.state
	var randomized := false
	var spawned := 0
	var flag := int(program.get("completion_flag",0))
	if flag and Flags.has_flag(state,flag): return {"error":"","skipped":true,"commands":[]}
	var commands: Array = []
	var sound_count: int = b.native_sound_queue.size()
	if flag:
		Flags.set_flag(state,flag)
		commands.append({"op":"set","flag":flag})
	var stack: Array = program.get("entry",[{"script":0,"pc":0}]).duplicate(true)
	for step in range(MAX_STEPS):
		if stack.is_empty():
			if randomized: commands.append({"op":"rng_state","state":lottery.state})
			return {"error":"","skipped":false,"commands":commands}
		var frame: Dictionary = stack[-1]
		var script: Array = program.scripts[int(frame.script)]
		if int(frame.pc) >= script.size(): return {"error":"Native script fell through without END."}
		var command: Dictionary = script[int(frame.pc)]
		frame.pc += 1
		match command.op:
			"fe7_final_formation":
				if projection.Army.all_units(projection).is_empty() and projection.chapter.get("campaign_roster",{}).is_empty():
					for unit in command.fallback: projection._spawn_unit(unit.duplicate(true),true)
					commands.append({"op":"effect","effect":{"spawns":command.fallback}})
				var placements: Array = command.fixed.duplicate(true)
				var index := 0
				for unit in projection.units:
					if unit.faction != "player" or int(unit.hp) <= 0 or unit.get("benched",false) or unit.get("escaped",false) or int(unit.rom_character_id) in command.exclude or index >= command.slots.size(): continue
					placements.append({"character":unit.rom_character_id,"x":command.slots[index][0],"y":command.slots[index][1]}); index += 1
				for placement in placements:
					if not command.scene_only and (int(placement.x) >= projection.width or int(placement.y) >= projection.height): return {"error":"Native final formation is outside the map."}
					var move: Dictionary = {"op":"scene_unit","action":"move","character":placement.character,"x":placement.x,"y":placement.y}
					if command.scene_only: commands.append({"op":"effect","effect":{"dialogue":[{"text":"","native_control":true,"fe6_scene_command":move}]}})
					else: Fe6.commit(projection,move); commands.append(move)
				query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
			"fe7_retain_actor":
				if scene_projection == null: continue
				var actors: Array = scene_projection.units.filter(func(u):return int(u.rom_character_id) == int(command.character) and u.faction == "player")
				if actors.is_empty(): continue # Actor was loaded on the battle map already.
				var retained: Array = []
				if projection.Army.all_units(projection).is_empty() and projection.chapter.get("campaign_roster",{}).is_empty(): retained.append_array(command.fallback.duplicate(true))
				retained = retained.filter(func(u):return int(u.rom_character_id) != int(command.character))
				retained.append(actors[0].duplicate(true))
				for unit in retained: projection._spawn_unit(unit,true)
				commands.append({"op":"effect","effect":{"spawns":retained}})
				query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
			"fe7_grants":
				for gift in command.gifts:
					var recipients: Array = projection.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(gift.character))
					var scene_recipient := false
					if recipients.is_empty() and scene_projection != null:
						recipients = scene_projection.units.filter(func(u):return int(u.rom_character_id) == int(gift.character)); scene_recipient = true
					if recipients.is_empty(): return {"error":"Native inventory grant has no recipient."}
					var recipient: Dictionary = recipients[0]
					if recipient.inventory.size()+(0 if recipient.weapon.is_empty() else 1) >= 5: continue
					if recipient.weapon.is_empty() and projection.can_equip_weapon(recipient,gift.item): recipient.weapon = gift.item.duplicate(true)
					else: recipient.inventory.append(gift.item.duplicate(true))
					if not scene_recipient: commands.append({"op":"fe7_inventory_result","unit_id":recipient.id,"weapon":recipient.weapon.duplicate(true),"inventory":recipient.inventory.duplicate(true)})
			"fe7_bonus":
				var selector := (1 if Flags.has_flag(state,int(command.flags[0])) else 0)+(2 if Flags.has_flag(state,int(command.flags[1])) else 0)
				var bonus: Dictionary = command.items[selector]
				if selector == 0:
					if projection.chapter.get("story_flags",{}).get("fe7_lyn_completed",false): continue
					bonus = command.get("default_without_lyn",{})
					if bonus.is_empty(): continue
				var recipients: Array = projection.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(command.character))
				if recipients.is_empty(): return {"error":"Native bonus has no recipient."}
				var recipient: Dictionary = recipients[0]
				# Native UnitAddItem silently declines when all five slots are full.
				if recipient.inventory.size()+(0 if recipient.weapon.is_empty() else 1) >= 5: continue
				recipient.inventory.append(bonus.duplicate(true))
				commands.append({"op":"fe7_inventory_result","unit_id":recipient.id,"inventory":recipient.inventory.duplicate(true)})
			"fe7_promote":
				var recipients: Array = (projection.units+projection.chapter.get("reserve_units",[])).filter(func(u):return int(u.get("rom_character_id",0)) == int(command.character) and u.faction == "player" and int(u.hp) > 0)
				if recipients.is_empty(): return {"error":"Native promotion has no living recipient."}
				var recipient: Dictionary = recipients[0]
				if recipient.get("promoted",false): continue
				var options: Array = projection.rules.get("promotion_catalog",{}).get("promotions",[]).filter(func(p):return int(p.from_class) == int(recipient.rom_class_id))
				if options.size() != 1 or projection._class_definition(int(options[0].to_class)).is_empty(): return {"error":"Native promotion class is unavailable."}
				var promotion := {"op":"fe6_commit","action":"promote","character":command.character,"class_id":int(options[0].to_class)}
				Fe6.commit(projection,promotion); commands.append(promotion)
			"fe7_ballista":
				var problem := mount_ballista(projection,int(command.character))
				if not problem.is_empty(): return {"error":problem}
				commands.append(command)
			"fe7_prepare":
				var problem := Preparation.apply(projection,command)
				if not problem.is_empty(): return {"error":problem}
				query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
				commands.append(command)
			"choice":
				var continuation := program.duplicate(true)
				continuation.completion_flag = 0; continuation.entry = stack.duplicate(true)
				if not validate(continuation,"fe7").is_empty(): return {"error":"Invalid choice continuation."}
				if randomized: commands.append({"op":"rng_state","state":lottery.state})
				commands.append({"op":"choice_wait","program":continuation,"page":command.page})
				return {"error":"","skipped":false,"commands":commands}
			"fe7_convoy_level":
				projection.rng.state = lottery.state
				var resolved := convoy_level(projection,command)
				lottery.state = projection.rng.state; randomized = true
				commands.append(resolved)
				if not str(resolved.get("unit_id","")).is_empty():
					Flags.set_flag(state,int(command.flag)); commands.append({"op":"set","flag":int(command.flag)})
			"scripted_battle":
				if command.get("scene_only",false):
					if scene_projection == null: return {"error":"Cutaway battle has no scene map."}
					var scene_combat := ScriptedCombat.resolve(scene_projection,command)
					if not scene_combat.error.is_empty(): return scene_combat
					commands.append({"op":"effect","effect":{"dialogue":[{"text":"","native_control":true,"scripted_combat":scene_combat.presentation}]}})
					for id in scene_combat.deaths:
						commands.append({"op":"effect","effect":{"dialogue":[{"text":"","native_control":true,"fe6_scene_command":{"op":"scene_unit","action":"remove","character":int(scene_projection.get_unit(id).rom_character_id)}}]}})
					continue
				projection.rng.state = lottery.state
				var combat := ScriptedCombat.resolve(projection,command)
				if not combat.error.is_empty(): return combat
				lottery.state = projection.rng.state; randomized = true
				commands.append(combat)
			"scene_unit":
				Fe6.commit(projection,command)
				query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
				if command.action == "move_next":
					# Resolve against projected placements once, then use the same
					# destination for gameplay and the story actor playback.
					var sources: Array = projection.units.filter(func(u):return int(u.get("rom_character_id",0)) == int(command.character) and int(u.hp) > 0)
					if not sources.is_empty(): commands.append({"op":"scene_unit","action":"move","character":command.character,"x":int(sources[0].x),"y":int(sources[0].y)})
				else: commands.append(command)
			"campaign_end","fe7_clear_enemies","fe7_cleanup","fe7_formation","fe7_casualty","fe7_unit_state","fe7_ring_status","fe7_performer_swap","fe7_exp_baseline":
				fe7_world_action(projection,command)
				query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
				commands.append(command)
			"defeat","fe7_victory": commands.append(command)
			"fe6":
				var action := Fe6.plan(b,state,command,lottery)
				if not action.error.is_empty(): return action
				commands.append_array(action.commands)
				if command.action == "lottery": randomized = true
				if command.action == "remove":
					query_context.presence_units = query_context.presence_units.filter(func(u):return int(u.rom_character_id) != int(command.character))
					if projection != null: Fe6.commit(projection,command)
				elif command.action in ["move","move_at","move_path","move_next"] and projection != null: Fe6.commit(projection,command)
			"end": stack.pop_back()
			"destination": commands.append(command)
			"random_flag":
				randomized = true
				var selected := int(command.flags[lottery.randi_range(0,command.flags.size()-1)])
				Flags.set_flag(state,selected)
				commands.append({"op":"set","flag":selected})
			"ambush_begin":
				var count := int(b.chapter.get("fe6_ambush_count",0))+1
				var limit := int(command.hard_limit if preload("res://engine/campaign_difficulty.gd").is_hard(b.chapter.get("difficulty","normal")) else command.normal_limit)
				commands.append({"op":"ambush_state","count":count})
				if count < limit:
					Flags.set_flag(state,int(command.flag),false)
					commands.append({"op":"clear","flag":command.flag})
			"jump": frame.pc = int(command.target)
			"branch":
				if command.test.kind == "choice" and not context.get("native_choice") is bool: return {"error":"Native choice branch has no answer."}
				if command.test.kind == "affiliation" and not query_context.presence_units.any(func(unit):return int(unit.rom_character_id) == int(command.test.character)): return {"error":"Native affiliation query has no matching unit."}
				if command.test.kind == "route" and route_id(b) == 0: return {"error":"Native route branch requires an explicit route context."}
				if command.test.kind == "active" and b.get_unit(str(context.get("unit_id",context.get("attacker_id","")))).is_empty(): return {"error":"Native character branch has no active unit."}
				var value: bool
				if command.test.kind == "ambush_roll":
					randomized = true
					value = lottery.randi_range(0,int(command.test.denominator)-1) == 0 and spawned < int(command.test.cap)
				elif command.test.kind == "fe6" and command.test.test == "delayed_flags":
					var f: Array = command.test.flags
					value = b.phase == "enemy" and Flags.has_flag(state,int(f[2]))
					if b.phase == "enemy" and not value:
						for pair in [[f[1],f[2]],[f[0],f[1]]]:
							if Flags.has_flag(state,int(pair[0])):
								Flags.set_flag(state,int(pair[1])); commands.append({"op":"set","flag":pair[1]})
				elif command.test.kind == "desert_find" or (command.test.kind == "fe6" and command.test.test == "desert_find"):
					var actor: Dictionary = b.get_unit(str(context.get("unit_id","")))
					value = false
					if b.phase == "player" and not actor.is_empty() and actor.get("faction") == "player":
						value = command.test.classes.any(func(id):return int(id) == int(actor.rom_class_id))
						if not value: randomized = true; value = lottery.randi_range(0,int(command.test.denominator)-1) == 0
				else: value = test_value(b,state,command.test,query_context)
				if value == command.when: frame.pc = int(command.target)
			"call":
				if stack.size() >= MAX_DEPTH or stack.any(func(f):return int(f.script) == int(command.script)): return {"error":"Cyclic or excessive native calls."}
				stack.append({"script":int(command.script),"pc":0})
			"tail": frame.script = int(command.script); frame.pc = 0
			"set","clear":
				Flags.set_flag(state,int(command.flag),command.op == "set")
				commands.append(command)
			"effect":
				if command.has("mode") and (command.mode == "hard") != (preload("res://engine/campaign_difficulty.gd").is_hard(b.chapter.get("difficulty","normal"))): continue
				for page in command.effect.get("dialogue",[]):
					if page.has("fe7_scene_map"):
						scene_projection = b.get_script().new()
						scene_projection.chapter = {"game_id":"fe7"}; scene_projection.rules = b.rules.duplicate(true)
						scene_projection.chapter.native_battle_terrain = page.fe7_scene_map.get("native_battle_terrain",{}).duplicate(true)
						scene_projection.terrain = page.fe7_scene_map.terrain.duplicate(true)
						scene_projection.width = int(page.fe7_scene_map.width); scene_projection.height = int(page.fe7_scene_map.height)
						scene_projection.phase = b.phase; scene_projection.rng.state = b.rng.state
					if scene_projection != null:
						for unit in page.get("fe6_scene_units",[]): scene_projection._spawn_unit(unit.duplicate(true))
						if page.has("fe6_scene_command"): Fe6.commit(scene_projection,page.fe6_scene_command)
				if command.effect.has("give_item_to_actor") and b.get_unit(str(context.get("unit_id",""))).is_empty(): return {"error":"Native item reward has no active unit."}
				if command.effect.has("rom_sound"):
					sound_count += 1
					if sound_count > MAX_PENDING_SOUNDS: return {"error":"Native sound queue exceeds its limit."}
				for unit in command.effect.get("spawns",[]):
					if int(unit.x) >= b.width or int(unit.y) >= b.height: return {"error":"Native deployment is outside this map."}
					if Flags.game(b.chapter) == "fe6":
						if projection == null:
							projection = b.get_script().new()
							projection.chapter = b.chapter.duplicate(true); projection.rules = b.rules.duplicate(true)
							projection.units = b.units.duplicate(true); projection.terrain = b.terrain.duplicate(true)
							projection.width = b.width; projection.height = b.height; projection.turn = b.turn
							projection.rng.state = b.rng.state
							# Replay prior placement-relevant effects on the private model.
							# This includes a REMOVE before the first LOAD (Idunn).
							for earlier in commands:
								if earlier.op == "fe6" and earlier.action in ["remove","move","move_at","move_path","move_next"]: Fe6.commit(projection,earlier)
								elif earlier.op == "faction":
									for existing in projection.units:
										if int(existing.get("rom_character_id",0)) == int(earlier.character) and int(existing.hp) > 0:
											existing.faction = earlier.faction; break
								elif earlier.get("effect",{}).has("map_change"): projection._apply_map_change(earlier.effect)
						projection._spawn_unit(unit)
						query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
					else:
						var placed: Dictionary = unit.duplicate(true)
						placed.id = context.get("native_spawn_ids",{}).get(unit.id,unit.id)
						projection._spawn_unit(placed,context.get("initial_deployment",false))
						query_context.presence_units = projection.units+projection.chapter.get("reserve_units",[])
					spawned += 1
				if command.effect.has("map_change"):
					var patch: Dictionary = command.effect.map_change
					if int(patch.y)+patch.terrain.size() > b.height or patch.terrain.any(func(row):return int(patch.x)+row.length() > b.width): return {"error":"Native map change is outside this map."}
					if projection != null: projection._apply_map_change(command.effect)
				for change in command.effect.get("ai_changes",[]):
					if change.has("x") and (int(change.x) >= b.width or int(change.y) >= b.height): return {"error":"Native AI selection is outside this map."}
				commands.append(command)
			"visitor_dialogue":
				var actor: Dictionary = b.get_unit(str(context.get("unit_id","")))
				var character := str(int(actor.get("rom_character_id",0)))
				if not command.pages.has(character): return {"error":"Native switch has no dialogue selector for this actor."}
				commands.append({"op":"effect","effect":{"dialogue":command.pages[character]}})
			"conditional_dialogue":
				if command.test.kind == "affiliation" and not query_context.presence_units.any(func(unit):return int(unit.rom_character_id) == int(command.test.character)): return {"error":"Native affiliation query has no matching unit."}
				commands.append({"op":"effect","effect":{"dialogue":command.yes if test_value(b,state,command.test,query_context) else command.no}})
			"focus": commands.append(command)
			"faction":
				for unit in query_context.presence_units:
					if int(unit.rom_character_id) == int(command.character) and int(unit.hp) > 0:
						unit.faction = command.faction
						break
				commands.append(command)
			"spend_gold":
				if int(query_context.gold) >= int(command.amount):
					query_context.gold = int(query_context.gold)-int(command.amount); commands.append(command)
			"set_gold": query_context.gold = command.amount; commands.append(command)
			"gold":
				var actor: Dictionary = b.get_unit(str(context.get("unit_id",context.get("attacker_id",""))))
				if command.mode == "active" and actor.is_empty(): return {"error":"Native gold reward has no active unit."}
				if command.mode == "party" or actor.get("faction","") == "player": query_context.gold = int(query_context.gold)+int(command.amount)
				commands.append(command)
	return {"error":"Native event exceeded its execution budget."}

static func execute(b, event: Dictionary, context: Dictionary) -> bool:
	if b.chapter.has("native_pending_choice"): return false
	context = context.duplicate()
	if not context.has("unit_id") and context.has("attacker_id"): context.unit_id = context.attacker_id
	if event.get("trigger") == "chapter_start" and b.chapter.get("dynamic_rom",false): context.initial_deployment = true
	if event.get("native_repeat",false) and Flags.game(b.chapter) == "fe7":
		context.native_spawn_ids = {}
		for script in event.get("native_program",{}).get("scripts",[]):
			for command in script:
				for unit in command.get("effect",{}).get("spawns",[]):
					context.native_spawn_ids[unit.id] = "native_%s_%s_%d_%s" % [str(event.id).sha256_text().left(16),str(unit.id).sha256_text().left(16),b.turn,b.phase]
	var error := validate_event(event,Flags.game(b.chapter))
	var result := plan(b,event.native_program,context) if error.is_empty() else {"error":error}
	if not result.error.is_empty():
		var id := str(event.get("id","native"))
		if not b.native_event_errors.has(id):
			b.native_event_errors[id] = result.error
			b.events_log.append("Native event %s could not run: %s" % [id,result.error])
			var tree = Engine.get_main_loop()
			if tree is SceneTree:
				var diagnostics = tree.root.get_node_or_null("Diagnostics")
				if diagnostics: diagnostics.record("native_event_failed",{"chapter":b.chapter.get("id",""),"event":id,"reason":result.error})
		return false
	var unit_remap := {}
	var scripted_deaths: Array = []
	var opening_scene: bool = (Flags.game(b.chapter) == "fe6" or b.chapter.get("native_opening_scene",false)) and event.get("trigger") == "chapter_start" and b.chapter.get("intro",[]).is_empty()
	if event.get("trigger") == "chapter_start" and b.chapter.get("dynamic_rom",false): context.initial_deployment = true
	var presentation_scene: bool = opening_scene or (b.chapter.get("dynamic_rom",false) and (event.get("trigger") == "victory" or event.get("native_scene",false)))
	var scene_actors := {}
	if presentation_scene:
		var actions: Array = [{"type":"begin","hide_units":true}]
		for unit in b.units:
			if (not opening_scene or unit.get("faction") != "player") and b._on_map(unit):
				var actor := Fe6.scene_actor(unit)
				scene_actors[actor.id] = actor
				actions.append(actor.duplicate(true))
		b.dialogue_queue.append({"text":"","native_control":true,"scene_type":"map","scene_actions":actions})
	var occurrence := str(b.phase)
	if Flags.game(b.chapter) == "fe6" and event.get("trigger") == "native_flag": occurrence += "_%d" % int(b.chapter.get("fe6_ambush_count",0))
	if event.get("native_repeat",false):
		# A recurring LOAD needs an occurrence identity, not the first wave's ID.
		# This depends only on stable event/template identities and dispatch phase.
		for command in result.commands:
			for unit in command.get("effect",{}).get("spawns",[]):
				if Flags.game(b.chapter) == "fe6" and str(unit.id).begins_with("fe6_unit_"): continue
				# Named FE7 reinforcements retain identity for talks, death flags,
				# and campaign transfer (a recruit may share a recurring escort script).
				if Flags.game(b.chapter) == "fe7" and (unit.faction != "enemy" or unit.get("boss",false) or not str(unit.get("portrait","")).is_empty()): continue
				unit_remap[unit.id] = "native_%s_%s_%d_%s" % [str(event.id).sha256_text().left(16),str(unit.id).sha256_text().left(16),b.turn,occurrence]
	for original in result.commands:
		var command: Dictionary = original.duplicate(true) if presentation_scene else original
		if presentation_scene: Fe6.queue_opening_scene(b,command,scene_actors)
		if command.op in ["fe6","fe6_commit","scene_unit"]: Fe6.commit(b,command)
		elif command.op == "combat_commit":
			if command.has("emplacements"): b.chapter.emplacements = command.emplacements.duplicate(true)
			for id in command.updates:
				var unit: Dictionary = b.get_unit(str(id))
				unit.merge(command.updates[id].duplicate(true),true)
			scripted_deaths.append_array(command.deaths)
			b.dialogue_queue.append({"text":"","native_control":true,"scripted_combat":command.presentation})
			var actions: Array = []
			for id in command.updates:
				if not scene_actors.has(id) or not command.updates[id].has("hp"): continue
				if int(command.updates[id].hp) <= 0:
					scene_actors.erase(id)
					actions.append({"type":"remove","id":id})
				else:
					scene_actors[id].hp = command.updates[id].hp
					actions.append(scene_actors[id].duplicate(true))
			if not actions.is_empty(): b.dialogue_queue.append({"text":"","native_control":true,"scene_actions":actions})
		elif command.op in ["campaign_end","fe7_clear_enemies","fe7_formation","fe7_cleanup","fe7_casualty","fe7_unit_state","fe7_ring_status","fe7_performer_swap","fe7_exp_baseline"]: fe7_world_action(b,command)
		elif command.op == "defeat": b.outcome = "defeat"
		elif command.op == "fe7_victory": b.chapter.native_event_victory = true
		elif command.op == "fe7_convoy_result":
			b.chapter.placed_traps = b.chapter.get("placed_traps",[]).filter(func(t):return t.kind != "light_rune")
			if not str(command.get("unit_id","")).is_empty():
				var unit: Dictionary = b.get_unit(command.unit_id)
				unit.merge(command.changes,true)
				if not command.reward.get("levels",[]).is_empty(): b.experience_queue.append(command.reward)
		elif command.op == "fe7_prepare": Preparation.apply(b,command)
		elif command.op == "fe7_inventory_result":
			b.get_unit(command.unit_id).inventory = command.inventory.duplicate(true)
			if command.has("weapon"): b.get_unit(command.unit_id).weapon = command.weapon.duplicate(true)
		elif command.op == "fe7_ballista": mount_ballista(b,int(command.character))
		elif command.op == "choice_wait":
			var identity := str(event.id)+"_"+str(command.program.entry).sha256_text().left(12)
			b.chapter.native_pending_choice = {"id":identity,"program":command.program,"context":context}
			var page: Dictionary = command.page.duplicate(true)
			page.native_choice_id = identity
			b.dialogue_queue.append(page)
		elif command.op == "rng_state": b.rng.state = command.state
		elif command.op == "ambush_state": b.chapter.fe6_ambush_count = command.count
		elif command.op == "destination":
			b.chapter.native_next_chapter = command.path
			if command.path.is_empty(): b.chapter.erase("next_chapter")
			else: b.chapter.next_chapter = command.path
		elif command.op == "effect": b._apply_event_effects(rebind(command.effect,unit_remap),context)
		elif command.op == "focus":
			for unit in b.units:
				if int(unit.get("rom_character_id",0)) == int(command.character) and b._on_map(unit):
					b._apply_event_effects({"dialogue":[{"text":"","native_control":true,"scene_actions":[{"type":"focus","x":int(unit.x),"y":int(unit.y)}]}]},context)
					break
		elif command.op == "faction":
			# Native character lookup takes the first matching live unit slot.
			for unit in b.units:
				if int(unit.get("rom_character_id",0)) == int(command.character) and int(unit.hp) > 0:
					b._apply_event_effects({"change_faction":[{"unit_id":str(unit.id),"faction":command.faction}]},context)
					break
		elif command.op == "spend_gold": b.gold -= int(command.amount)
		elif command.op == "set_gold": b.gold = int(command.amount)
		elif command.op == "gold":
			var actor: Dictionary = b.get_unit(str(context.get("unit_id",context.get("attacker_id",""))))
			if command.mode == "party" or actor.get("faction","") == "player": b._apply_event_effects({"reward":{"gold":int(command.amount)}},context)
		else: Flags.set_flag(b.native_event_state,int(command.flag),command.op == "set")
	if opening_scene and b.chapter.get("dynamic_rom",false) and not b.chapter.get("native_preparations_ready",false):
		b.chapter.deployment.slots = []
		for unit in b.units:
			if unit.faction == "player" and b._on_map(unit):
				b.chapter.deployment.slots.append({"unit_id":unit.id,"x":unit.x,"y":unit.y})
				# Opening arrivals outside the selectable party, such as imprisoned
				# allies, stay at their scripted position during preparation.
				if not b.chapter.get("dynamic_party_ids",[]).has(unit.id) and not b.chapter.deployment.forced.has(unit.id): b.chapter.deployment.forced.append(unit.id)
		for slot in b.chapter.get("dynamic_extra_slots",[]):
			if not b.chapter.deployment.slots.any(func(s):return s.x == slot.x and s.y == slot.y): b.chapter.deployment.slots.append(slot.duplicate())
		b.Rogue.configure_deployment(b)
	for id in scripted_deaths: b._run_events("unit_defeated",{"unit_id":id})
	return true

static func valid_pending_choice(value: Variant) -> bool:
	if not value is Dictionary or not keys(value,["id","program","context"]) or not value.id is String or value.id.is_empty() or not value.context is Dictionary: return false
	return validate(value.program,"fe7").is_empty() and value.program.has("entry") and int(value.program.get("completion_flag",0)) == 0

static func mount_ballista(b, character: int) -> String:
	for unit in b.units:
		if int(unit.get("rom_character_id",0)) != character or not b._on_map(unit): continue
		var weapon: Dictionary = b.emplacement_weapon(unit)
		if weapon.is_empty(): return "Native ballista actor has no usable siege engine."
		# The shared engine derives mounting from position, including dismounting
		# when moving away. Keep selection on this weapon without copying its ammo.
		unit.last_used_weapon = b._weapon_signature(weapon)
		return ""
	return "Native ballista actor is missing."

static func answer_choice(b, identity: String, answer: bool) -> bool:
	var pending: Variant = b.chapter.get("native_pending_choice")
	if not valid_pending_choice(pending) or pending.id != identity: return false
	var context: Dictionary = pending.context.duplicate(true); context.native_choice = answer
	b.chapter.erase("native_pending_choice")
	if execute(b,{"id":identity,"trigger":"native_choice","native_program":pending.program},context): return true
	b.chapter.native_pending_choice = pending
	return false

static func rebind(value: Variant, unit_remap: Dictionary) -> Variant:
	if unit_remap.is_empty(): return value
	if value is String: return unit_remap.get(value,value)
	if value is Array: return value.map(func(child):return rebind(child,unit_remap))
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = rebind(value[key],unit_remap)
		return result
	return value

static func fe7_world_action(b, command: Dictionary) -> void:
	if command.op == "campaign_end": b.chapter.campaign_end = true
	elif command.op == "fe7_clear_enemies": b.units = b.units.filter(func(u):return u.faction != "enemy")
	elif command.op == "fe7_exp_baseline": b.chapter.fe7_exp_baseline = int(b.chapter.get("fe7_earned_experience",0))
	elif command.op == "fe7_casualty":
		for unit in b.units+b.chapter.get("reserve_units",[]):
			if int(unit.get("rom_character_id",0)) != int(command.character): continue
			unit.hp = 0; unit.casualty_mode = "permanent"
			b._release_on_death(unit)
			break
	elif command.op in ["fe7_unit_state","fe7_ring_status"]:
		for unit in b.units+b.chapter.get("reserve_units",[]):
			if int(unit.get("rom_character_id",0)) != int(command.character): continue
			if command.op == "fe7_ring_status": unit.ring_bonuses = command.bonuses.duplicate()
			else: unit[command.field] = command.value
			break
	elif command.op == "fe7_performer_swap":
		var army: Array = b.units+b.chapter.get("reserve_units",[])
		var first: Array = army.filter(func(u):return int(u.get("rom_character_id",0)) == int(command.first))
		var second: Array = army.filter(func(u):return int(u.get("rom_character_id",0)) == int(command.second))
		if first.is_empty() or second.is_empty(): return # Native helper also permits missing units.
		# The native routine swaps constitution/movement bonuses, not class bases.
		for key in ["con","mov"]:
			var first_base := int(first[0].get("native_class_"+key,first[0][key]))
			var second_base := int(second[0].get("native_class_"+key,second[0][key]))
			var first_bonus := int(first[0][key])-first_base
			first[0][key] = first_base+int(second[0][key])-second_base
			second[0][key] = second_base+first_bonus
		for unit in [first[0],second[0]]:
			if not unit.get("mounted",false): unit.aid = int(unit.con)-1
		for key in ["level","exp","max_hp","hp","str","skill","speed","def","res","luck","inventory","weapon"]:
			var saved: Variant = first[0][key]
			first[0][key] = second[0][key]; second[0][key] = saved
		if b.Rogue.active(b):
			# The native performer exchange transfers training. Acquired Rogue
			# progress follows that training; each performer keeps their personal.
			var ranks: Array = [first[0].weapon_exp.duplicate(),second[0].weapon_exp.duplicate()]
			for key in ["magic","rogue_skills","rogue_growth_gains","rogue_level_count","rogue_learned_types"]:
				var saved: Variant = first[0].get(key)
				if second[0].has(key): first[0][key] = second[0][key]
				else: first[0].erase(key)
				if saved != null: second[0][key] = saved
				else: second[0].erase(key)
			for index in range(2):
				var unit: Dictionary = [first[0],second[0]][index]
				unit.weapon_types = unit.get("rogue_native_types",[]).duplicate()
				for kind in unit.get("rogue_learned_types",[]):
					if not unit.weapon_types.has(kind): unit.weapon_types.append(kind)
					unit.weapon_exp[kind] = maxi(1,int(ranks[1-index].get(kind,1)))
				unit.can_use_staves = unit.weapon_types.has("staff")
	elif command.op == "fe7_formation":
		var lord_id: int = {1:3,2:1,3:2}.get(int(b.chapter.get("native_route",1)),3)
		var lords: Array = b.units.filter(func(u):return int(u.get("rom_character_id",0)) == lord_id and b._on_map(u))
		if not lords.is_empty():
			for unit in b.units:
				if unit.faction == "player" and unit.id != lords[0].id and unit.x == lords[0].x and unit.y == lords[0].y:
					unit.benched = true; unit.x = -1; unit.y = -1
	elif command.op == "fe7_cleanup":
		b.units = b.units.filter(func(u):return u.faction == "player")
		for unit in b.units:
			if command.get("heal",true) and int(unit.hp) > 0: unit.hp = unit.max_hp; unit.status = ""; unit.status_turns = 0

static func convoy_level(b, command: Dictionary) -> Dictionary:
	# Native trap type 12 is Light Rune. Our overlay preserves underlying terrain.
	b.chapter.placed_traps = b.chapter.get("placed_traps",[]).filter(func(t):return t.kind != "light_rune")
	var result := {"op":"fe7_convoy_result","unit_id":"","changes":{},"reward":{}}
	for unit in b.units:
		if int(unit.get("rom_character_id",0)) != int(command.character) or unit.faction != "player" or int(unit.hp) <= 0 or unit.get("benched",false) or unit.get("escaped",false): continue
		result.unit_id = unit.id
		if int(unit.level) < 20:
			# Reuse the engine's growth/cap rules and deterministic saved RNG.
			# The native helper grants exactly one level, even without combat XP.
			var disabled: bool = unit.get("disable_experience",false)
			var hp: int = unit.hp
			var maximum: int = b.rules.max_level
			var threshold: int = b.rules.experience_per_level
			unit.disable_experience = false; unit.exp = 0
			b.rules.max_level = 20; b.rules.experience_per_level = 100
			result.reward = b._award_experience(unit,100)
			b.rules.max_level = maximum; b.rules.experience_per_level = threshold
			unit.exp = 0; unit.hp = hp; unit.disable_experience = disabled
			for key in ["level","exp","hp","max_hp","str","skill","speed","luck","def","res"]: result.changes[key] = unit[key]
		break
	return result
