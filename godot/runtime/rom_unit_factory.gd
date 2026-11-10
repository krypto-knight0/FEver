extends RefCounted
## Defaults for additional ROM group members. Existing members retain their
## explicit chapter adaptations; this does not emulate native event/AI code.
const Data = preload("res://runtime/rom_data.gd")
const FIELDS := ["max_hp", "str", "skill", "speed", "def", "res", "luck", "hp", "con", "promoted", "boss",
	"rom_character_id", "rom_class_id", "faction", "x", "y", "level", "mov", "experience_power",
	"source_deployment", "source_stat_offsets", "name", "class_name", "sprite", "portrait", "growths",
	"stat_caps", "weapon_exp", "movement_costs", "terrain_bonuses", "canto", "flying", "critical_bonus", "aid", "gender"]

static func create(decoder: RefCounted, game: String, at: int, id: String, policy: Dictionary, inventory: Dictionary) -> Variant:
	var fields := FIELDS.duplicate()
	if game == "fe6": fields.append_array(["experience_bonus", "experience_defeat_bonus"])
	if game == "fe7": fields.append_array(["movement_costs_rain", "weapon_rank_source", "silencer", "silencer_immune"])
	var unit: Variant = Data.read(decoder, {"game":game, "kind":"unit_record", "offset":at, "fields":fields,
		"terrain_keys":policy.symbols}, game)
	if unit == null: return null
	unit.merge(inventory)
	unit.id = id
	unit.game_id = game
	unit.exp = 0
	if policy.has("blockable_spawn"): unit.blockable_spawn = policy.blockable_spawn
	var character: int = str(unit.source_stat_offsets.character).hex_to_int()
	var cl: int = str(unit.source_stat_offsets["class"]).hex_to_int()
	var class_flags: int = decoder.u32(cl + (40 if game == "fe7" else 36))
	var flags: int = class_flags | decoder.u32(character + 40)
	unit.weapon_types = []
	var items: Array = unit.inventory.duplicate()
	if not unit.weapon.is_empty(): items.append(unit.weapon)
	if unit.source_deployment.autolevel:
		for item in items:
			var kind: String = str(item.get("type", ""))
			if int(unit.weapon_exp.get(kind, 0)) > 0:
				unit.weapon_exp[kind] = maxi(int(unit.weapon_exp[kind]), int(item.get("required_rank", 0)))
	for kind in unit.weapon_exp:
		if unit.weapon_exp[kind] > 0: unit.weapon_types.append(kind)
	if game == "fe6" and unit.weapon.get("type") == "other": unit.weapon_types.append("other")
	if game == "fe7" and unit.weapon.get("type") == "dragon":
		if decoder.layout.get("event_variant","") not in ["fe7j","fe7u"] or not unit.weapon.get("native_dragon_breath",false): return Data.invalid(decoder, "Additional dragon member requires its combat adapter.")
		unit.weapon_types.append("dragon"); unit.weapon_exp.dragon = 251
	unit.can_use_staves = int(unit.weapon_exp.get("staff", 0)) > 0
	unit.can_steal = bool((class_flags if game == "fe7" else flags) & 4) or (game == "fe7" and unit.rom_class_id in [62, 63])
	unit.can_lockpick = bool(flags & 8)
	unit.multiple_s_ranks = game == "fe6" or unit.rom_class_id in [66, 69]
	unit.mounted = bool(flags & 1)
	if unit.mounted: unit.aid_base = 20 if flags & 0x4000 else 25
	if game == "fe7":
		unit.experience_bonus = (40 if unit.rom_class_id in [31,45,62] else 60) if unit.promoted else 0
		unit.experience_defeat_bonus = 20 if unit.rom_class_id in [60,61,62] else 0
		unit.supply_provider = bool(flags & 0x2000)
		if flags & 0x30:
			unit.merge({"can_play":true, "refresh_action":"Play" if flags & 0x20 else "Dance", "play_experience":10})
	else:
		unit.can_play = unit.rom_class_id in [54,55]
	if str(unit.portrait).ends_with("/000.png"): unit.erase("portrait")
	if flags & 0x08000000 and not unit.source_deployment.items.is_empty():
		var last := int(unit.source_deployment.items[-1])
		for item in items:
			if int(item.get("rom_item_id", -1)) == last: unit.drop_item = item.duplicate(true)
	if not _ai(decoder, game, unit): return null
	_autolevel(decoder, game, unit, policy)
	return unit if decoder.error.is_empty() else null

static func _ai(decoder: RefCounted, game: String, unit: Dictionary) -> bool:
	var primary := int(unit.source_deployment.ai[0])
	var secondary := int(unit.source_deployment.ai[1])
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary == 11:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,144,[],"0bdf143e2c53083932bfd62b8c778219f47e13ba747abae1425629df8d40446d") or not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(decoder,0x3aa40,48,[],"8d3ec562e47112d38fc411b0b53ce03dc8eb78fb20486400c9898a20370a7ff9"):
			decoder.fail("FE7 AI","Changed approach-and-talk script.",at); return false
		var pair: int = decoder.ptr(at+76)
		if decoder.u8(pair+1) != decoder.u8(at+4) or decoder.u8(pair) != int(unit.get("rom_character_id",decoder.u8(pair))):
			decoder.fail("FE7 AI","Approach and talk targets disagree.",pair); return false
		unit.npc_talk_target = "fe7_unit_%d" % decoder.u8(at+4); secondary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary in [19,20,21,22,29]:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,112,[12,13,14,15,44,45,46,47],"ad37039b4192080993ada7b775f9236b2949202f1daf45bc241853b4593ac086") or not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(decoder,0x3a9fc,68,[],"98f57a6f60fb8b7a31d9767522840a96265acfc82c06bda1c8fc19f0f0b759aa") or not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(decoder,0x3aef4,32,[],"499b1c519fa303d45c6375ca92270d5c8ea2338cb75b8dd29240031a40ac10c6"):
			decoder.fail("FE7 AI","Changed region approach script.",at); return false
		var region: int = decoder.ptr(at+12); var goal: int = decoder.ptr(at+44)
		unit.ai_waypoint_region = [decoder.u8(region),decoder.u8(region+1),decoder.u8(region+2),decoder.u8(region+3)]
		unit.ai_waypoint = [decoder.u8(goal),decoder.u8(goal+1)]; unit.ai_after_waypoint = "pursue"; secondary = 0
		if unit.ai_waypoint_region[0] > unit.ai_waypoint_region[2] or unit.ai_waypoint_region[1] > unit.ai_waypoint_region[3]:
			# The US cartridge contains rectangles whose upper corner is zero.
			# Its byte-reading helper can never accept them: keep visiting the
			# goal instead of inventing a transition to free pursuit.
			unit.ai_waypoint_repeats = true
			unit.ai_waypoint_region = []

	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary in [33,34]:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,176,[4],"96679c5d106374bcbdb435959746ccf9a8e83fd11c47ee621c40fbdda40ec461") or decoder.u8(at+4) == 0:
			decoder.fail("FE7 AI","Changed allied character approach script.",at); return false
		unit.ai_pursuit_character = decoder.u8(at+4); secondary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary == 32:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,48,[],"d17226ba7937fd2f87d72bd759eb91f36b5c45e2705c2b9ffc42450ad76e7a8f"):
			decoder.fail("FE7 AI","Changed pursuit transition.",at); return false
		secondary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary == 31:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,48,[],"6ccb270052cb9066718f92b3f0e78eb7d5978faf2700b2e54da9f7c2277334da"):
			decoder.fail("FE7 AI","Changed village-raiding transition.",at); return false
		secondary = 4
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and primary == 17:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_primary",0xc07cb0)))+primary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,128,[],"3a3beaf099049c0cccde5a4c040edd7ae733efd730afdf0ded8e4fc66749b3c1"):
			decoder.fail("FE7 AI","Changed door-opening priority script.",at); return false
		unit.ai_open_doors_first = true; primary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary == 18:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,48,[],"ca7726a5c08e76f716ef6cd1aa126a9ce4383fda5402057c0117a35f6b10afab") or not preload("res://runtime/fe7/fe7_dynamic_policy.gd").signature(decoder,0x3af14,16,[],"f7673c6727e62d4cd3fcd53e799c2bf3725642400c7aa5e651dcd516971cca2a"):
			decoder.fail("FE7 AI","Changed delayed-looter script.",at); return false
		unit.ai_wait_actions = 1; primary = 16; secondary = 5
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and secondary in [14,15,16,17]:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,176,[4],"502ac80b8f653a535a2d9c00560ccaf44374f2b34564054284a23955fa1d6821") or decoder.u8(at+4) == 0:
			decoder.fail("FE7 AI","Changed named-character pursuit script.",at); return false
		# AI1 approaches a live character, then falls back to ordinary pursuit.
		# AI0 can still attack any legal target before movement is considered.
		unit.ai_pursuit_character = decoder.u8(at+4); secondary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and primary == 10:
		var at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_primary",0xc07cb0)))+primary*4)
		if not preload("res://runtime/fe7/fe7_dynamic_policy.gd").actual_signature(decoder,at,64,[4],"e2027d77d763cd4e3579874d98e9a5692e6a4c56a110c81f2035c79321e5d031") or decoder.u8(at+4) == 0:
			decoder.fail("FE7 AI","Changed preferred-character attack script.",at); return false
		# Attempt the named target first, then fall back to the ordinary attack.
		unit.ai_preferred_character = decoder.u8(at+4); primary = 0
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and primary == 0 and secondary in [23,0x19,0x1e]:
		# Tutorial, throne and palace approaches share a script.
		# Keep their live destination but
		# allow ordinary tactical decisions once there in free-control mode.
		var script_at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_secondary",0xc07ca4)))+secondary*4)
		var bytes: PackedByteArray = decoder.raw(script_at,64)
		if bytes.size() != 64: return false
		var x := int(bytes[1]); var y := int(bytes[3])
		bytes[1] = 0; bytes[3] = 0
		if bytes.hex_encode() != "0c00ff000000000000000000000000001b00ff010000000000000000000000000564ff000000000000000000000000000300ff01000000000000000000000000":
			decoder.fail("FE7 tutorial AI","Changed tutorial waypoint script.",script_at); return false
		unit.ai_mode = "pursue"; unit.ai_waypoint = [x,y]; unit.ai_after_waypoint = "attack_in_range"
		return true
	if game == "fe7" and decoder.layout.get("event_variant","") in ["fe7j","fe7u"] and primary in [7,8,18,19]:
		var script_at: int = decoder.ptr(decoder.ptr(int(decoder.layout.get("ai_primary",0xc07cb0)))+primary*4)
		var bytes: PackedByteArray = decoder.raw(script_at,32)
		if bytes.size() != 32: return false
		for offset in range(8,12): bytes[offset] = 0
		if bytes.hex_encode() != "0564ff000000000000000000000000000300ff00000000000000000000000000":
			decoder.fail("FE7 AI","Changed ignored-target AI script.",script_at); return false
		var targets: int = decoder.ptr(script_at+8)
		unit.ai_excluded_character_ids = []
		var ended := false
		for index in range(256):
			var character: int = decoder.u16(targets+index*2)
			if character == 0: ended = true; break
			if character > 255: break
			unit.ai_excluded_character_ids.append(character)
		if not ended: decoder.fail("FE7 AI","Invalid ignored-target list.",targets); return false
		primary = 0
	var modes := {0:"pursue", 3:"attack_in_range", 4:"raid", 5:"loot", 6:"pursue"}
	if game == "fe6": modes.merge({17:"attack_in_range", 18:"attack_in_range"})
	else: modes.merge({12:"escape", 13:"pursue", 0x1b:"break_walls", 0x1c:"break_walls"})
	# Target lists, waypoints and native AI routines need explicit adapters.
	# Do not silently turn an unknown scripted unit into an ordinary pursuer.
	# FE6 hard waves also use ignore-fe6_unit_2, leader-action and staff-first
	# policies. The latter two use the port's shared tactical/staff planner,
	# matching existing authored FE6 units with these native AI selectors.
	if primary not in ([0,3,6,16] if game == "fe7" else [0,3,7,13,14]) or not modes.has(secondary):
		decoder.fail("ROM unit group", "Additional member requires a scripted AI adapter.", int(str(unit.source_deployment.offset).hex_to_int()))
		return false
	unit.ai_mode = "stationary" if primary == 3 or (game == "fe7" and primary == 6 and secondary == 3) else modes[secondary]
	if unit.ai_mode == "stationary": unit.ai = "stationary"
	if game == "fe7" and primary == 6: unit.ai_no_attack = true
	if game == "fe7" and secondary == 6: unit.ai_pursuit_turns = 2
	if game == "fe6" and unit.faction == "enemy" and secondary == 5:
		unit.ai_mode = "loot"
		unit.ai_no_attack = true
	if game == "fe6" and primary == 7:
		# Reviewed AI_ACTION_IGNORING operand, a terminated u16 PID list.
		if decoder.u32(0x5c8df8) != 0xff6405:
			Data.invalid(decoder,"Unrecognized ignored-target AI.")
			return false
		var at: int = decoder.ptr(0x5c8e00)
		unit.ai_excluded_character_ids = []
		for i in range(256):
			if at < 0 or not decoder.require_range(at+i*2,2,"Ignored AI target"): return false
			var character: int = decoder.u16(at+i*2)
			if character == 0: return true
			if character > 255:
				Data.invalid(decoder,"Invalid ignored AI target.")
				return false
			unit.ai_excluded_character_ids.append(character)
		Data.invalid(decoder,"Unterminated ignored AI target list.")
		return false
	return true

static func _autolevel(decoder: RefCounted, game: String, unit: Dictionary, policy: Dictionary) -> void:
	if game == "fe7":
		unit.merge(preload("res://runtime/fe7/rom_fe7_autolevel.gd").generate(decoder, unit, int(policy.promoted_bonus), int(policy.enemy_bonus)), true)
		return
	unit.merge(preload("res://runtime/fe6/rom_fe6_autolevel.gd").generate(decoder, unit), true)
