extends RefCounted
## Typed cartridge metadata recipes. Addresses are references, never payloads.
const SYMBOLS = preload("res://engine/terrain_types.gd").SYMBOLS
const MAP_LAYOUTS := {
	"fe7": [0x31580, 152, 67, 0x3159c, 0x191c8, 0x315b8],
	"fe6": [0x2bb20, 68, 75, 0x2bb70, 0x18a7c, 0x2bb9c],
}
const STATS := ["max_hp", "str", "skill", "speed", "def", "res", "luck"]
const WEAPONS := ["sword", "lance", "axe", "bow", "staff", "anima", "light", "dark"]
const RECORD_LAYOUTS := {"fe7":[0x9a274, 52, 1, 0x178f0, 84], "fe6":[0x17680, 48, 0, 0x176e0, 72]}
const Animations = preload("res://runtime/rom_animation_data.gd")
const Battles = preload("res://runtime/rom_battle_data.gd")
const Deployments = preload("res://runtime/rom_deployments.gd")

static func integer(value: Variant, low: int = 0, high: int = 0x7fffffff) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == int(value)

static func class_experience(decoder: RefCounted, id: Variant, game: String, personal_flags: int = 0) -> Variant:
	if game != "fe6" or not integer(id, 1, 255): return invalid(decoder, "Invalid class experience recipe.")
	var table: int = decoder.ptr(RECORD_LAYOUTS.fe6[3])
	var at: int = table + int(id) * int(RECORD_LAYOUTS.fe6[4])
	if not decoder.require_range(at, 72, "Class experience"): return null
	var flags: int = decoder.u32(at + 36) | personal_flags
	var promoted := bool(flags & 0x100)
	var bonus := 0
	if promoted:
		# FE6's promoted kill value includes twenty levels of the linked base
		# class's power; the class link and both powers come from the cartridge.
		var base: int = table + decoder.u8(at + 5) * int(RECORD_LAYOUTS.fe6[4])
		if not decoder.require_range(base, 72, "Base class experience"): return null
		bonus = 20 * decoder.u8(base + 26)
	return {"experience_power":decoder.u8(at + 26), "experience_bonus":bonus, "experience_defeat_bonus":20 if flags & 4 else 0, "promoted":promoted}

static func invalid(decoder: RefCounted, reason: String) -> Variant:
	decoder.fail("ROM metadata", reason)
	return null

static func read(decoder: RefCounted, spec: Variant, game: String) -> Variant:
	if not decoder.error.is_empty(): return null
	if not spec is Dictionary or spec.get("game") != game or not MAP_LAYOUTS.has(game):
		return invalid(decoder, "Invalid metadata game or recipe.")
	var kind: String = str(spec.get("kind", ""))
	var allowed := ["game", "kind"]
	match kind:
		"number": allowed += ["offset", "size", "signed", "shift", "mask", "divisor", "test"]
		"array": allowed += ["offset", "count", "size", "signed"]
		"table": allowed += ["offset", "keys", "indices", "signed", "divisor"]
		"terrain": allowed += ["offsets", "keys"]
		"map": allowed += ["chapter", "change", "fields", "symbols", "raw_patch"]
		"unit": allowed += ["character", "class", "fields", "gains"]
		"unit_record": allowed += ["offset", "deployment", "fields", "gains", "terrain_keys"]
		"item_record": allowed += ["id", "fields"]
		"item_name": allowed += ["id"]
		"character_name": allowed += ["id", "suffix"]
		"class_experience": allowed += ["id"]
		"portrait_name": allowed += ["id", "numbered"]
		"chapter_label": allowed += ["chapter", "parts"]
		"ranks": allowed += ["character", "class"]
		"deployment": allowed += ["offset", "deployment", "fields"]
		"battle", "movement": allowed += ["offset", "fields"]
		"battle_profile": allowed += ["selector", "fields"]
		"shop", "chest": allowed += ["offset"]
		"event_reward": allowed += ["offset", "reward"]
		_: return invalid(decoder, "Unknown metadata operation.")
	for key in spec:
		if key not in allowed: return invalid(decoder, "Unknown metadata recipe field.")
	if spec.has("deployment"):
		var deployment_at := deployment_offset(decoder, spec, game)
		if deployment_at < 0: return null
		spec = spec.duplicate()
		spec.erase("deployment")
		spec.offset = deployment_at
	if kind == "chapter_label": return preload("res://runtime/rom_labels.gd").chapter(decoder,spec,game)
	if kind == "class_experience": return class_experience(decoder, spec.get("id"), game)
	if kind in ["character_name","portrait_name"]:
		if not integer(spec.get("id"),0 if kind == "portrait_name" else 1,65535) or not spec.get("numbered",false) is bool: return invalid(decoder,"Invalid display-name recipe.")
		var names = preload("res://runtime/rom_names.gd")
		var name: String = names.character(decoder,game,int(spec.id)) if kind == "character_name" else names.portrait(decoder,game,int(spec.id),spec.get("numbered",false))
		if not spec.get("suffix","") is String: return invalid(decoder,"Invalid character label suffix.")
		name += str(spec.get("suffix",""))
		if decoder.error.is_empty(): return name
		return null
	if kind == "item_record": return item_record_fields(decoder, spec, game)
	if kind == "item_name":
		if not integer(spec.get("id"), 1, 255): return invalid(decoder, "Invalid item name recipe.")
		var record := item_record(decoder, int(spec.id), game)
		return decoder.text(decoder.u16(record)) if record >= 0 else null
	if kind == "unit_record": return unit_record_fields(decoder, spec, game)
	if kind == "event_reward":
		if not integer(spec.get("offset")) or int(spec.offset) % 4 != 0 or spec.get("reward") not in ["item", "gold"]:
			return invalid(decoder, "Invalid event reward recipe.")
		return event_reward(decoder, int(spec.offset), spec.reward, game)
	if kind in ["shop", "chest"]:
		if not integer(spec.get("offset")): return invalid(decoder, "Invalid location event address.")
		return shop_stock(decoder, int(spec.offset), game) if kind == "shop" else chest_reward(decoder, int(spec.offset), game)
	if kind == "map": return map_fields(decoder, spec, game)
	if kind == "unit": return unit_fields(decoder, spec, game)
	if kind == "ranks":
		if not integer(spec.get("character")) or not integer(spec.get("class")): return invalid(decoder, "Invalid weapon rank recipe.")
		var result := {}
		var names := ["sword", "lance", "axe", "bow", "staff", "anima", "light", "dark"]
		for i in range(names.size()):
			var personal: int = decoder.u8(int(spec.character) + 20 + i)
			result[names[i]] = personal if personal else decoder.u8(int(spec["class"]) + (40 if game == "fe6" else 44) + i)
		if decoder.error.is_empty(): return result
		return null
	if kind == "deployment": return deployment_fields(decoder, spec)
	if kind in ["battle", "movement", "battle_profile"]:
		if (kind != "battle_profile" and not integer(spec.get("offset"))) or not spec.get("fields") is Array: return invalid(decoder, "Invalid animation recipe.")
		var data := Battles.profile(decoder,game,spec.get("selector")) if kind == "battle_profile" else (Animations.battle(decoder, int(spec.offset), game) if kind == "battle" else Animations.movement(decoder, int(spec.offset)))
		if not decoder.error.is_empty(): return null
		var result := {}
		for key in spec.fields:
			if not data.has(key): return invalid(decoder, "Unknown animation output field.")
			result[key] = data[key]
		return result
	if kind == "terrain":
		if not spec.get("offsets") is Array or spec.offsets.size() != 3 or not terrain_keys(spec.get("keys")):
			return invalid(decoder, "Invalid terrain bonus table.")
		for at in spec.offsets:
			if not integer(at) or not decoder.require_range(int(at), SYMBOLS.length()): return invalid(decoder, "Invalid terrain table address.")
		var result := {}
		for key in spec.keys:
			var index := SYMBOLS.find(key)
			result[key] = {"avoid": decoder.u8(int(spec.offsets[0]) + index), "defense": decoder.u8(int(spec.offsets[1]) + index), "resistance": decoder.u8(int(spec.offsets[2]) + index)}
		return result
	if not integer(spec.get("offset")) or not spec.get("signed", false) is bool or not integer(spec.get("divisor", 1), 1, 10000):
		return invalid(decoder, "Invalid numeric metadata fields.")
	var at := int(spec.offset)
	if kind == "array":
		if not integer(spec.get("count"), 0, 4096) or not integer(spec.get("size", 1), 1, 4) or int(spec.get("size", 1)) not in [1, 2, 4]: return invalid(decoder, "Invalid array encoding.")
		var result: Array = []
		var element_size := int(spec.get("size", 1))
		if not decoder.require_range(at, int(spec.count) * element_size): return null
		for i in range(int(spec.count)):
			result.append(read(decoder, {"game":game, "kind":"number", "offset":at + i * element_size, "size":element_size, "signed":spec.get("signed", false)}, game))
		return result
	if kind == "table":
		if not spec.get("keys") is Array or not spec.get("indices") is Array or spec.keys.size() != spec.indices.size() or spec.keys.size() > 256:
			return invalid(decoder, "Invalid numeric table shape.")
		var result := {}
		for i in range(spec.keys.size()):
			var key: Variant = spec.keys[i]
			if not key is String or result.has(key) or not integer(spec.indices[i], 0, 255): return invalid(decoder, "Invalid numeric table entry.")
			var table_value: int = decoder.u8(at + int(spec.indices[i]))
			if spec.get("signed", false) and table_value >= 128: table_value -= 256
			if spec.has("divisor"): result[key] = float(table_value) / int(spec.divisor)
			else: result[key] = table_value
		if decoder.error.is_empty(): return result
		return null
	if not integer(spec.get("size", 1), 1, 4) or int(spec.get("size", 1)) not in [1, 2, 4] or not integer(spec.get("shift", 0), 0, 31) or not integer(spec.get("mask", 0xffffffff), 0, 0xffffffff):
		return invalid(decoder, "Invalid number encoding.")
	var size := int(spec.get("size", 1))
	var n: int = decoder.u8(at) if size == 1 else (decoder.u16(at) if size == 2 else decoder.u32(at))
	if spec.get("signed", false) and n & (1 << (size * 8 - 1)): n -= 1 << (size * 8)
	if spec.has("shift"): n >>= int(spec.shift)
	if spec.has("mask"): n &= int(spec.mask)
	if not decoder.error.is_empty(): return null
	if spec.has("test"):
		if spec.test not in ["zero", "nonzero"]: return invalid(decoder, "Invalid numeric predicate.")
		return n == 0 if spec.test == "zero" else n != 0
	if spec.has("divisor"): return float(n) / int(spec.divisor)
	return n

static func deployment_offset(decoder: RefCounted, spec: Dictionary, game: String) -> int:
	if spec.has("deployment"):
		if spec.has("offset"):
			invalid(decoder, "Deployment cannot have both an address and a pointer path.")
			return -1
		return Deployments.address(decoder, spec.deployment, game)
	if not integer(spec.get("offset")):
		invalid(decoder, "Invalid deployment address.")
		return -1
	return int(spec.offset)

static func event_reward(decoder: RefCounted, command: int, reward: String, game: String) -> Variant:
	# Read one verified reward command. Chapter adapters retain event ordering
	# and visitor conditions; importing a reward does not execute the script.
	if not decoder.require_range(command, 8, "Event reward command"): return null
	var opcode := (0x5b if game == "fe7" else 0x26) if reward == "item" else (0x5e if game == "fe7" else 0x28)
	if decoder.u32(command) != opcode:
		return invalid(decoder, "Event command does not match the requested reward.")
	var value: int = decoder.u32(command + 4)
	if reward == "item" and item_record(decoder, value, game) < 0: return null
	return value

static func chest_reward(decoder: RefCounted, event: int, game: String) -> Variant:
	if not decoder.require_range(event, 12, "Chest event"): return null
	if decoder.u16(event) == 0 or decoder.u8(event + 10) != 18:
		return invalid(decoder, "Event does not describe a chest.")
	var id: int = decoder.u16(event + 4)
	var amount: int = decoder.u16(event + 6)
	if id == (118 if game == "fe7" else 111): return {"gold":amount}
	if amount != 0: return invalid(decoder, "Item chest contains an unexpected gold amount.")
	if item_record(decoder, id, game) < 0: return null
	return {"rom_item_id":id}

static func item_record(decoder: RefCounted, id: int, game: String) -> int:
	if id < 1 or id > 255:
		invalid(decoder, "Invalid item ID.")
		return -1
	var table: int = decoder.ptr(int(decoder.layout.get("items",0x174d4 if game == "fe7" else 0x16410)))
	if not decoder.error.is_empty(): return -1
	var stride := 36 if game == "fe7" else 32
	var record := table + id * stride
	if not decoder.require_range(record, stride, "Item record"): return -1
	if decoder.u8(record + 6) != id:
		invalid(decoder, "Item identity does not match its table record.")
		return -1
	return record

static func select_fields(decoder: RefCounted, data: Dictionary, fields: Variant) -> Variant:
	if not fields is Array or fields.is_empty(): return invalid(decoder, "Missing record output fields.")
	var result := {}
	for key in fields:
		if not key is String or not data.has(key) or result.has(key): return invalid(decoder, "Unknown or duplicate record output field.")
		result[key] = data[key]
	if decoder.error.is_empty(): return result
	return null

static func fe7_weapon_locks(flags: int) -> int:
	var result := 0
	for pair in [[0x800,0x10000],[0x1000,0x20000],[0x40000,0x10000000],[0x80000,0x20000000],[0x100000,0x40000000],[0x200000,0x80000000],[0x400,0x40000]]:
		if flags&int(pair[0]): result |= int(pair[1])
	return result

static func item_stat_bonuses(decoder: RefCounted, at: int) -> Dictionary:
	var result := {}
	if decoder.u32(at+12) == 0: return result
	var pointer: int = decoder.ptr(at+12)
	if not decoder.require_range(pointer,9,"Item stat bonuses"): return {}
	for index in range(9):
		var bonus: int = decoder.u8(pointer+index)
		if bonus: result[(STATS+["mov","con"])[index]] = bonus
	return result

static func item_record_fields(decoder: RefCounted, spec: Dictionary, game: String) -> Variant:
	if not integer(spec.get("id"), 1, 255) or not spec.get("fields") is Array:
		return invalid(decoder, "Invalid item record recipe.")
	var id := int(spec.id)
	var at := item_record(decoder, id, game)
	if at < 0: return null
	var flags: int = decoder.u32(at + 8)
	var cost: int = decoder.u16(at + 26)
	var data := {"rom_item_id":id, "source_offset":"0x%x" % at,
		"uses":decoder.u8(at + 20), "max_uses":decoder.u8(at + 20),
		"might":decoder.u8(at + 21), "hit":decoder.u8(at + 22), "weight":decoder.u8(at + 23), "crit":decoder.u8(at + 24),
		"min_range":decoder.u8(at + 25) >> 4, "max_range":decoder.u8(at + 25) & 15,
		"cost_per_use":cost, "unsellable":cost == 0, "required_rank":decoder.u8(at + 28),
		"stealable":not bool(flags & 5), "brave":bool(flags & 32), "cannot_counter":bool(flags & 128),
		"triangle_reverse":bool(flags & 256), "ignore_defense":bool(flags & 0x20000), "unrepairable":bool(flags & 0x608)}
	if game == "fe6":
		data.negate_flying_effectiveness = bool(flags & 0x4000)
		data.weapon_effect = "hp_to_one" if decoder.u8(at+31) == 3 else ""
		# IsItemEffectiveAgainst compares the native bow-list pointer before
		# checking carried shields. Dragon effectiveness is unaffected.
		data.flying_effectiveness = decoder.u32(at+16) != 0 and decoder.u32(at+16) == decoder.u32(0x16a84)
	if game == "fe7": data.weapon_exp = decoder.u8(at + 32)
	for key in ["name", "description"]:
		if key in spec.fields: data[key] = decoder.text(decoder.u16(at + (0 if key == "name" else 2)))
	if "icon" in spec.fields:
		data.icon = ("res://content/fe7/rom/item_icons/icon_%03d.png" if game == "fe7" else "res://content/fe6/rom/icons/%03d.png") % decoder.u8(at + 29)
	# Weapon categories are table data. Consumable/staff effects are still
	# explicit engine adapters; their native behavior is executable code.
	if flags & 1:
		var category: int = decoder.u8(at + 7)
		data.type = WEAPONS[category] if category < WEAPONS.size() else ("dragon" if game == "fe7" else "other")
	if "effective_class_ids" in spec.fields:
		var classes: Array = []
		if decoder.u32(at + 16) != 0:
			var pointer: int = decoder.ptr(at + 16)
			var terminated := false
			for index in range(256):
				var value: int = decoder.u8(pointer + index)
				if not decoder.error.is_empty(): return null
				if value == 0:
					terminated = true
					break
				classes.append(value)
			if not terminated: return invalid(decoder, "Unterminated item effectiveness list.")
		data.effective_class_ids = classes
	return select_fields(decoder, data, spec.fields)

static func unit_record_fields(decoder: RefCounted, spec: Dictionary, game: String) -> Variant:
	if not integer(spec.get("offset")) or not spec.get("fields") is Array or not terrain_keys(spec.get("terrain_keys", [])):
		return invalid(decoder, "Invalid unit record recipe.")
	var dep: Variant = deployment_fields(decoder, {"offset":spec.offset, "fields":["character_id", "class_id", "leader_id", "level", "autolevel", "faction", "load_position", "position", "items", "ai"]})
	if dep == null: return null
	var layout: Array = decoder.layout.get("record_layout",RECORD_LAYOUTS[game])
	var cid := int(dep.character_id)
	if cid == 0: return invalid(decoder, "Deployment terminator is not a unit.")
	var character: int = decoder.ptr(layout[0]) + (cid - int(layout[2])) * int(layout[1])
	if not decoder.require_range(character, int(layout[1])): return null
	if decoder.u8(character + 4) != cid: return invalid(decoder, "Character identity does not match its table record.")
	var class_id: int = int(dep.class_id) if dep.class_id else decoder.u8(character + 5)
	var cl: int = decoder.ptr(layout[3]) + class_id * int(layout[4])
	if class_id == 0 or not decoder.require_range(cl, int(layout[4])): return invalid(decoder, "Invalid deployment class.")
	if decoder.u8(cl + 4) != class_id: return invalid(decoder, "Class identity does not match its table record.")
	var data: Variant = unit_fields(decoder, {"character":character, "class":cl, "fields":STATS + ["hp", "con", "promoted", "boss"], "gains":spec.get("gains", [])}, game)
	if data == null: return null
	var personal_flags: int = decoder.u32(character + 40)
	var class_flags: int = decoder.u32(cl + (40 if game == "fe7" else 36))
	var flags: int = personal_flags | class_flags
	var faction: String = "neutral" if dep.faction == "npc" else dep.faction
	dep.offset = "0x%x" % int(spec.offset)
	data.merge({"rom_character_id":cid, "rom_class_id":class_id, "faction":faction,
		"x":dep.position[0], "y":dep.position[1], "level":dep.level, "mov":decoder.u8(cl + 18),
		"experience_power":decoder.u8(cl + 26), "source_deployment":dep,
		"source_stat_offsets":{"character":"0x%x" % character, "class":"0x%x" % cl},
		"canto":bool((class_flags if game == "fe7" else flags) & 2),
		"flying":bool((class_flags if game == "fe7" else flags) & (0x1000 if game == "fe7" else 0x1800)),
		"critical_bonus":(15 if game == "fe7" else 30) if flags & 0x40 else 0,
		"aid":(20 if flags & 0x4000 else 25) - int(data.con) if flags & 1 else int(data.con) - 1,
		"aid_base":20 if flags & 0x4000 else 25, "gender":"female" if flags & 0x4000 else "male",
		"silencer":bool(flags & 0x2000000), "silencer_immune":bool(flags & 0x1000000)})
	if game == "fe6":
		var experience: Variant = class_experience(decoder, class_id, game, personal_flags)
		if experience == null: return null
		data.merge(experience, true)
	if "name" in spec.fields: data.name = preload("res://runtime/rom_names.gd").character(decoder, game, cid)
	if "class_name" in spec.fields: data.class_name = decoder.text(decoder.u16(cl))
	if "sprite" in spec.fields:
		data.sprite = "res://content/%s/rom/sprites/%03d_%s.png" % [game, decoder.u8(cl + 6), dep.faction]
	if "portrait" in spec.fields:
		var portrait: int = decoder.u16(character + 6)
		if portrait == 0 and game == "fe6": portrait = decoder.u16(cl + 8)
		data.portrait = "res://content/%s/rom/portraits/%03d.png" % [game, portrait]
	data.growths = {}
	data.stat_caps = {"luck":30, "con":decoder.u8(cl + 25), "mov":15}
	data.weapon_exp = {}
	for i in range(STATS.size()):
		data.growths[STATS[i]] = decoder.u8(character + 28 + i)
		if i < 6: data.stat_caps[STATS[i]] = decoder.u8(cl + 19 + i)
	for i in range(WEAPONS.size()):
		var rank: int = decoder.u8(character + 20 + i)
		data.weapon_exp[WEAPONS[i]] = rank if rank else decoder.u8(cl + (44 if game == "fe7" else 40) + i)
	data.weapon_rank_source = {"character_offset":"0x%x" % (character + 20), "class_offset":"0x%x" % (cl + 44), "initialization":"0x17970", "autolevel":"0x17a1c"}
	var keys: Array = spec.get("terrain_keys", [])
	for key in ["movement_costs", "movement_costs_rain", "terrain_bonuses"]:
		if key not in spec.fields: continue
		var result := {}
		if key == "terrain_bonuses":
			var start := 68 if game == "fe7" else 56
			var pointers: Array = [decoder.ptr(cl + start), decoder.ptr(cl + start + 4), decoder.ptr(cl + start + 8)]
			for symbol in keys:
				var index := SYMBOLS.find(symbol)
				result[symbol] = {"avoid":decoder.u8(pointers[0] + index), "defense":decoder.u8(pointers[1] + index), "resistance":decoder.u8(pointers[2] + index)}
		else:
			if key == "movement_costs_rain" and game != "fe7": return invalid(decoder, "Rain movement is not supported by this profile.")
			var pointer: int = decoder.ptr(cl + (60 if key == "movement_costs_rain" else (56 if game == "fe7" else 52)))
			for symbol in keys:
				var cost: int = decoder.u8(pointer + SYMBOLS.find(symbol))
				result[symbol] = cost - 256 if cost >= 128 else cost
		data[key] = result
	return select_fields(decoder, data, spec.fields)

static func shop_stock(decoder: RefCounted, event: int, game: String) -> Variant:
	# Location events point to zero-terminated item-ID lists in both games.
	if not decoder.require_range(event, 12, "Shop event"): return null
	var action: int = decoder.u8(event + 10)
	if decoder.u16(event) == 0 or action not in [19, 20, 21]:
		return invalid(decoder, "Event does not describe a supported shop.")
	var stock: int = decoder.ptr(event + 4)
	# Keep validating the item table even when the stock list is empty.
	decoder.ptr(int(decoder.layout.get("items",0x174d4 if game == "fe7" else 0x16410)))
	if not decoder.error.is_empty(): return null
	var result: Array = []
	for index in range(65):
		var id: int = decoder.u16(stock + index * 2)
		if not decoder.error.is_empty(): return null
		if id == 0: return result
		if index == 64: return invalid(decoder, "Shop inventory exceeds the item limit or lacks a terminator.")
		var record := item_record(decoder, id, game)
		if record < 0: return null
		result.append({"rom_item_id":id, "price":decoder.u8(record + 20) * decoder.u16(record + 26)})
	return null

static func terrain_keys(keys: Variant) -> bool:
	if not keys is Array or keys.size() > SYMBOLS.length(): return false
	for key in keys:
		if not key is String or key.length() != 1 or SYMBOLS.find(key) < 0: return false
	return true

static func unit_fields(decoder: RefCounted, spec: Dictionary, game: String) -> Variant:
	if not integer(spec.get("character")) or not integer(spec.get("class")) or not spec.get("fields") is Array or not spec.get("gains", []) is Array or spec.get("gains", []).size() > 3:
		return invalid(decoder, "Invalid unit metadata recipe.")
	var character := int(spec.character)
	var cl := int(spec["class"])
	if not decoder.require_range(character, 48) or not decoder.require_range(cl, 72): return null
	var result := {}
	for i in range(STATS.size()):
		var base: int = decoder.u8(character + 12 + i)
		if base >= 128: base -= 256
		var class_base: int = decoder.u8(cl + 11 + i) if i < 6 else 0
		if game == "fe7" and class_base >= 128: class_base -= 256
		result[STATS[i]] = maxi(0, base + class_base)
	# These increments belong to the port's deterministic generation policy,
	# not a saved GBA RNG state. Bases and caps always come from the cartridge.
	for stage in spec.get("gains", []):
		if not stage is Array or stage.size() != 7: return invalid(decoder, "Invalid unit growth stage.")
		for i in range(7):
			if not integer(stage[i], 0, 255): return invalid(decoder, "Invalid unit growth increment.")
			var cap: int = decoder.u8(cl + 19 + i) if i < 6 else 30
			result[STATS[i]] = mini(int(result[STATS[i]]) + int(stage[i]), cap)
	var con: int = decoder.u8(character + 19)
	if con >= 128: con -= 256
	result.con = con + decoder.u8(cl + 17)
	result.hp = result.max_hp
	var flags: int = decoder.u32(character + 40) | decoder.u32(cl + (36 if game == "fe6" else 40))
	result.promoted = bool(flags & 0x100)
	result.boss = bool(flags & 0x8000)
	var selected := {}
	for key in spec.fields:
		if not result.has(key): return invalid(decoder, "Unknown unit output field.")
		selected[key] = result[key]
	return selected

static func deployment_fields(decoder: RefCounted, spec: Dictionary) -> Variant:
	if not integer(spec.get("offset")) or not spec.get("fields") is Array: return invalid(decoder, "Invalid deployment recipe.")
	var at := int(spec.offset)
	if not decoder.require_range(at, 16): return null
	var faction: int = (decoder.u8(at + 3) >> 1) & 3
	if faction > 2: return invalid(decoder, "Unknown deployment faction.")
	var items: Array = []
	for i in range(4):
		var id: int = decoder.u8(at + 8 + i)
		if id: items.append(id)
	var result := {"character_id": decoder.u8(at), "class_id": decoder.u8(at + 1), "leader_id": decoder.u8(at + 2), "level": decoder.u8(at + 3) >> 3,
		"autolevel": bool(decoder.u8(at + 3) & 1), "faction": ["player", "npc", "enemy"][faction],
		"load_position": [decoder.u8(at + 4), decoder.u8(at + 5)], "position": [decoder.u8(at + 6), decoder.u8(at + 7)],
		"items": items, "ai": [decoder.u8(at + 12), decoder.u8(at + 13), decoder.u8(at + 14), decoder.u8(at + 15)]}
	var selected := {}
	for key in spec.fields:
		if not result.has(key): return invalid(decoder, "Unknown deployment output field.")
		selected[key] = result[key]
	return selected

static func map_fields(decoder: RefCounted, spec: Dictionary, game: String) -> Variant:
	var layout: Array = decoder.layout.get("map_layout",MAP_LAYOUTS[game])
	if not integer(spec.get("chapter"), 0, int(layout[2]) - 1) or not integer(spec.get("change", -1), -1, 254) or not spec.get("fields") is Array or spec.fields.is_empty():
		return invalid(decoder, "Invalid map metadata recipe.")
	if not spec.get("raw_patch", false) is bool or (spec.get("raw_patch", false) and int(spec.get("change", -1)) < 0): return invalid(decoder, "Raw patch data requires a map change.")
	for key in spec.fields:
		if key not in ["width", "height", "terrain", "terrain_ids", "tile_ids", "mask", "x", "y"]: return invalid(decoder, "Invalid map output field.")
	if not spec.get("symbols", {}) is Dictionary: return invalid(decoder, "Invalid terrain symbol mapping.")
	for key in spec.get("symbols", {}):
		var symbol: Variant = spec.symbols[key]
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= SYMBOLS.length() or not symbol is String or symbol.length() != 1 or (SYMBOLS + "?").find(symbol) < 0:
			return invalid(decoder, "Invalid terrain symbol alias.")
	var record: int = decoder.ptr(int(layout[0])) + int(spec.chapter) * int(layout[1])
	var config_id: int = decoder.u8(record + 7)
	var map_id: int = decoder.u8(record + 8)
	if map_id == 0: return invalid(decoder, "Chapter has no map.")
	var data: PackedByteArray = decoder.lz(decoder.ptr(decoder.ptr(int(layout[3])) + map_id * 4))
	var config: PackedByteArray = decoder.lz(decoder.ptr(decoder.ptr(int(layout[4])) + config_id * 4))
	if not decoder.error.is_empty(): return null
	if data.size() < 2 or data[0] == 0 or data[1] == 0 or data.size() != 2 + data[0] * data[1] * 2: return invalid(decoder, "Map dimensions do not match its cells.")
	var width := int(data[0])
	var height := int(data[1])
	var x := 0
	var y := 0
	var patch := -1
	if int(spec.get("change", -1)) >= 0:
		var table: int = decoder.ptr(decoder.ptr(int(layout[5])) + decoder.u8(record + 11) * 4)
		for i in range(64):
			var at := table + i * 12
			var id: int = decoder.u8(at)
			if not decoder.error.is_empty(): return null
			if id == 255: break
			if id != int(spec.change): continue
			x = decoder.u8(at + 1)
			y = decoder.u8(at + 2)
			width = decoder.u8(at + 3)
			height = decoder.u8(at + 4)
			patch = decoder.ptr(at + 8)
			break
		if patch < 0: return invalid(decoder, "Map change is missing.")
		if width == 0 or height == 0 or x + width > data[0] or y + height > data[1]: return invalid(decoder, "Map change exceeds its map.")
		if not decoder.require_range(patch, width * height * 2): return null
	var terrain: Array = []
	var ids: Array = []
	var masks: Array = []
	var tiles: Array = []
	var want_terrain: bool = "terrain" in spec.fields
	var want_ids: bool = "terrain_ids" in spec.fields
	var want_masks: bool = "mask" in spec.fields
	var want_tiles: bool = "tile_ids" in spec.fields
	var raw_patch: bool = spec.get("raw_patch", false)
	var symbol_table: Array = []
	var aliases: Dictionary = spec.get("symbols", {})
	if want_terrain:
		for id in range(SYMBOLS.length()): symbol_table.append(aliases.get(str(id), SYMBOLS[id]))
	for row in range(height):
		var symbols := ""
		var row_ids: Array = []
		var mask: Array = []
		var row_tiles: Array = []
		for col in range(width):
			var base := data.decode_u16(2 + ((y + row) * data[0] + x + col) * 2)
			var tile: int = decoder.u16(patch + (row * width + col) * 2) if patch >= 0 else base
			if want_masks: mask.append(tile != 0)
			if want_tiles: row_tiles.append(tile)
			# FE7 skips zero patch cells. FE6's compiler preserves their terrain
			# and supplies a separate mask; retain each game's existing output.
			if patch >= 0 and tile == 0 and game == "fe7" and not raw_patch: tile = base
			var offset := 0x2000 + (tile >> 3) * 2 + ((tile >> 2) & 1)
			if offset >= config.size(): return invalid(decoder, "Map tile exceeds terrain configuration.")
			var id := int(config[offset])
			if id >= SYMBOLS.length(): return invalid(decoder, "Unsupported terrain identifier.")
			if want_ids: row_ids.append(id)
			if want_terrain: symbols += symbol_table[id]
		if want_terrain: terrain.append(symbols)
		if want_ids: ids.append(row_ids)
		if want_masks: masks.append(mask)
		if want_tiles: tiles.append(row_tiles)
	var data_fields := {"width": width, "height": height, "x": x, "y": y, "terrain": terrain, "terrain_ids": ids, "tile_ids": tiles, "mask": masks}
	var result := {}
	for key in spec.fields: result[key] = data_fields[key]
	return result
