class_name BattleState
extends RefCounted
## Deterministic, view-independent tactical battle state. All pack data is JSON-safe.
## The current rules cover a vertical slice; advanced FE systems are intentionally absent.

const NativeRunner = preload("res://engine/native_event_runner.gd")
const NativeFlags = preload("res://engine/native_event_flags.gd")
const Rules = preload("res://engine/battle_rules.gd")
const Terrain = preload("res://engine/terrain_types.gd")
const Staff = preload("res://engine/staff_actions.gd")
const Traps = preload("res://engine/placed_traps.gd")
const MapCycles = preload("res://engine/timed_map_changes.gd")
const Rogue = preload("res://engine/rogue_mode.gd")
const Army = preload("res://engine/army_roster.gd")
const DIRECTIONS = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const DURABILITY_MODES = ["normal", "repair_paid", "repair_free", "infinite"]

var units: Array = []
var terrain: Array = []
var width: int = 0
var height: int = 0
var phase: String = "player"
var turn: int = 1
var outcome: String = ""
var events_log: Array = []
var chapter: Dictionary = {}
var rules: Dictionary = {}
var interactions: Array = []
var fired_events: Array = []
var native_event_state: Dictionary = NativeFlags.empty_state()
var native_events_ready := false
var native_sound_queue: Array = []
var native_flags_inherited := false
var native_event_errors: Dictionary = {}
var native_event_turns: Dictionary = {}
var support_points: Dictionary = {}
var support_ranks: Dictionary = {}
var support_used_pairs: Array = []
var support_last_gain_turn := 0
var support_chapter_gain := 0
var inventory: Array = []
var gold: int = 0
var chapter_repairs_applied := false
var dialogue_queue: Array = []
var experience_queue: Array = []
var pending_moves: Dictionary = {}
var phase_combat: Array = []
var phase_actions: Array = []
var _turn_sequence: Dictionary = {}
var last_movement_effect: Dictionary = {}
var last_preview_path: Array = []
var pending_trap_effects: Array = []
var auto_playing := false
var _vision_key: Array = []
var _vision_cells: Dictionary = {}
var destructibles: Array = []
var map_patches: Array = []
var combat_initiator := ""
var pending_skill_effects: Array = []
var combat_guard := ""
var combat_guard_cell := Vector2i(-1, -1)
var rng := RandomNumberGenerator.new()

func load_chapter(data: Dictionary, overrides: Dictionary = {}, permanent_flags: Variant = null) -> void:
	_turn_sequence.clear()
	data = preload("res://engine/campaign_difficulty.gd").chapter(data, str(overrides.get("difficulty", data.get("difficulty", "normal"))))
	chapter = data.duplicate(true)
	chapter.reward_notices = []
	rules = Rules.defaults()
	_merge(rules, data.get("rules", {}))
	_identify_terrain(data.get("rules", {}).get("terrain", {}))
	_merge(rules, overrides)
	preload("res://engine/recruitment_levels.gd").apply_chapter(self)
	if not DURABILITY_MODES.has(str(rules.get("durability_mode", "normal"))): rules.durability_mode = "normal"
	chapter_repairs_applied = false
	terrain = data.get("terrain", []).duplicate(true)
	height = terrain.size()
	width = str(terrain[0]).length() if height > 0 else 0
	units = []
	if Rogue.active(self): rng.seed = int(data.get("seed", 7))
	for definition in chapter.get("units", []):
		units.append(_normalize_unit(definition))
	if chapter.has("reserve_units"):
		chapter.reserve_units = chapter.reserve_units.map(func(unit): return _normalize_unit(unit))
	chapter.emplacements = data.get("emplacements", []).duplicate(true)
	for unit in units:
		if not unit.has("ballista_adaptation"): continue
		var site := {"x": int(unit.x), "y": int(unit.y), "weapon": unit.weapon.duplicate(true), "sprite": "res://content/fe7/rom/sprites/079_npc.png"}
		chapter.emplacements.append(site)
		unit.weapon = site.weapon
	phase = "player"
	turn = 1
	outcome = ""
	events_log = []
	fired_events = []
	native_event_state = NativeFlags.empty_state(NativeFlags.game(chapter))
	native_events_ready = false
	native_sound_queue.clear()
	native_event_errors = {}
	native_event_turns = {}
	native_flags_inherited = permanent_flags != null and NativeFlags.valid_flags(permanent_flags,"campaign",NativeFlags.game(chapter))
	if native_flags_inherited:
		native_event_state.permanent_flags = permanent_flags.map(func(flag): return int(flag))
		native_event_state.permanent_flags.sort()
	pending_moves = {}
	phase_combat = []
	phase_actions = []
	pending_skill_effects.clear()
	last_movement_effect = {}
	pending_trap_effects = []
	destructibles = []
	map_patches = []
	# Opening patches synchronize doors. Install this chapter's sites first;
	# otherwise they are missed (or a reused state updates the previous map).
	interactions = chapter.get("interactions", []).duplicate(true)
	for change in data.get("initial_map_changes", []): _apply_map_change({"id": "opening", "map_change": change})
	for definition in data.get("destructibles", []):
		destructibles.append(_normalize_structure(definition))
	support_points = {}
	support_ranks = {}
	support_used_pairs = []
	support_last_gain_turn = 0
	support_chapter_gain = 0
	for pair in data.get("support_pairs", []):
		var key := _pair_key(str(pair.get("a", "")), str(pair.get("b", "")))
		support_points[key] = int(pair.get("points", 0))
		support_ranks[key] = int(pair.get("rank", 0))
	inventory = data.get("inventory", []).duplicate(true)
	gold = int(data.get("gold", 0))
	dialogue_queue = data.get("dialogue", []).duplicate(true)
	experience_queue = []
	if not Rogue.active(self): rng.seed = int(data.get("seed", 7))
	events_log.append("Player phase — turn 1")
	if Rogue.active(self): Rogue.setup(self)
	_run_events("start")
	_run_events("turn")
	_check_objective()

func _merge(target: Dictionary, incoming: Dictionary) -> void:
	for key in incoming:
		if incoming[key] is Dictionary and target.get(key) is Dictionary:
			_merge(target[key], incoming[key])
		else:
			target[key] = incoming[key]

func _normalize_unit(definition: Dictionary) -> Dictionary:
	var unit := definition.duplicate(true)
	var values := {"id": "unit", "name": "Unit", "faction": "player", "x": 0, "y": 0, "max_hp": 20, "str": 5, "skill": 5, "speed": 5, "luck": 0, "def": 2, "res": 0, "con": 5, "mov": 5, "acted": false, "moved": false, "weapon": {}, "inventory": [], "level": 1, "exp": 0, "growths": {}, "move_spent": 0, "canto_active": false, "canto_remaining": 0, "traded": false, "last_used_weapon": "", "carrying_id": "", "rescued_by": ""}
	for key in values:
		if not unit.has(key):
			unit[key] = values[key]
	unit["hp"] = int(unit.get("hp", unit["max_hp"]))
	unit["weapon"] = _normalize_item(unit["weapon"], true)
	var normalized_items: Array = []
	for item in unit["inventory"]:
		if item is Dictionary and not item.is_empty():
			normalized_items.append(_normalize_item(item))
	unit["inventory"] = normalized_items
	# Older dynamic FE6 saves put the first staff in the weapon slot. Staff
	# menus/AI use inventory indexes; append it without shifting saved indexes.
	if unit.has("fe6_unit_flags") and unit.weapon.get("kind") == "staff":
		unit.inventory.append(unit.weapon)
		unit.weapon = {}
	if unit.get("drop_item", {}) is Dictionary and not unit.get("drop_item", {}).is_empty():
		unit["drop_item"] = _normalize_item(unit.drop_item)
	unit["level"] = clampi(int(unit["level"]), 1, maxi(1, int(rules.get("max_level", 20))))
	unit["exp"] = clampi(int(unit["exp"]), 0, maxi(1, int(rules.get("experience_per_level", 100))) - 1)
	unit["temporary_bonuses"] = unit.get("temporary_bonuses", {}).duplicate(true)
	if unit.has("weapon_exp"):
		unit.weapon_exp = unit.weapon_exp.duplicate(true)
		for kind in unit.weapon_exp: unit.weapon_exp[kind] = clampi(int(unit.weapon_exp[kind]), 0, int(rules.get("weapon_exp_cap", 251)))
	var class_definition := _class_definition(int(unit.get("rom_class_id", -1)))
	if class_definition.has("movement_costs"): unit.movement_costs = class_definition.movement_costs.duplicate(true)
	if not unit.has("stat_caps") and class_definition.has("stat_caps"): unit.stat_caps = class_definition.stat_caps.duplicate(true)
	Rogue.initialize_unit(self, unit)
	return unit

func _normalize_item(definition: Dictionary, equipped: bool = false) -> Dictionary:
	if definition.is_empty():
		return {}
	var item := definition.duplicate(true)
	if item.get("game_id") == "fe6" and item.get("triangle_reverse",false) and not item.has("triangle_multiplier"):
		item.triangle_multiplier = 1 # Also repair pre-fix dynamic suspend inventories.
	if (int(item.get("rom_item_id", -1)) == 87 and item.get("game_id", "fe7") == "fe7" and not str(chapter.get("id", "")).begins_with("fe6_")) or (item.get("requires_staves", false) and item.get("opens", []).has("door")):
		item.merge({"kind":"staff", "type":"staff", "staff_effect":"unlock", "healing":0, "min_range":1, "max_range":2}, true)
	var kind := str(item.get("kind", ""))
	if kind.is_empty():
		if str(item.get("type", "")) == "staff":
			kind = "staff"
		elif item.has("healing"):
			kind = "consumable"
		elif equipped or item.has("type") or item.has("might"):
			kind = "weapon"
		else:
			kind = "item"
	item["kind"] = kind
	var defaults: Dictionary = {"name": "Item", "uses": 1}
	if kind == "weapon":
		defaults = {"name": "Weapon", "type": "sword", "might": 0, "hit": 100, "crit": 0, "weight": 0, "min_range": 1, "max_range": 1, "uses": 40}
	elif kind == "staff":
		var heal_default := 0 if item.has("temporary_bonuses") or item.has("staff_effect") or item.get("healing_full", false) else 10
		defaults = {"name": "Heal staff", "type": "staff", "healing": heal_default, "min_range": 1, "max_range": 1, "uses": 30}
	for key in defaults:
		if not item.has(key):
			item[key] = defaults[key]
	item["uses"] = maxi(0, int(item["uses"]))
	item["max_uses"] = maxi(int(item["uses"]), int(item.get("max_uses", item["uses"])))
	return item

func set_durability_mode(mode: String) -> bool:
	if not DURABILITY_MODES.has(mode): return false
	rules.durability_mode = mode
	return true

func apply_chapter_repairs() -> Dictionary:
	# The campaign calls this after carrying over inventories and gold, before
	# capturing its restart checkpoint. Suspend/undo restore this flag verbatim.
	var result := {"repaired_uses": 0, "cost": 0}
	if chapter_repairs_applied: return result
	chapter_repairs_applied = true
	var mode := str(rules.get("durability_mode", "normal"))
	var items: Array = inventory.duplicate()
	for unit in Army.all_units(self):
		if unit.faction != "player" or int(unit.hp) <= 0: continue
		items.append(unit.weapon)
		items.append_array(unit.inventory)
	for item in items:
		if not item is Dictionary or item.is_empty(): continue
		mode = str(rules.get("durability_mode" if _durable_item(item) else "item_durability_mode", "normal"))
		if mode not in ["repair_paid", "repair_free"]: continue
		var missing := maxi(0, int(item.get("max_uses", item.get("uses", 0))) - int(item.get("uses", 0)))
		if missing == 0: continue
		item.uses = int(item.get("uses", 0)) + missing
		result.repaired_uses += missing
		if mode == "repair_paid": result.cost += missing * maxi(0, int(item.get("cost_per_use", 0)))
	gold -= int(result.cost)
	if int(result.repaired_uses) > 0:
		events_log.append("Chapter repairs restored %d uses%s." % [int(result.repaired_uses), " for %d gold" % int(result.cost) if int(result.cost) > 0 else " for free"])
	return result

func _durable_item(item: Dictionary) -> bool:
	return not item.is_empty() and str(item.get("kind", "staff" if item.get("type", "") == "staff" else "weapon" if item.has("might") else "item")) in ["weapon", "staff"]

func _consume_use(item: Dictionary, owner: Dictionary = {}) -> void:
	if Rogue.count(owner, "deft_touch") > 0 and _durable_item(item):
		owner.rogue_durability = int(owner.get("rogue_durability", 0)) + 1
		if int(owner.rogue_durability) % 2 == 1: return
	if item.get("unbreakable", false): return
	if str(rules.get("durability_mode" if _durable_item(item) else "item_durability_mode", "normal")) == "infinite": return
	item.uses = maxi(0, int(item.get("uses", 0)) - 1)

func get_unit(id: String) -> Dictionary:
	# Avoid allocating the combined army for each lookup during rendering,
	# movement and command availability checks.
	for unit in units:
		if str(unit["id"]) == id:
			return unit
	for unit in chapter.get("reserve_units", []):
		if str(unit["id"]) == id:
			return unit
	return {}

func _normalize_structure(definition: Dictionary) -> Dictionary:
	var structure := _normalize_unit(definition)
	structure.kind = "structure"
	structure.faction = "neutral"
	structure.name = definition.get("name", "Cracked wall")
	structure.max_hp = int(definition.get("max_hp", definition.get("hp", 30)))
	structure.hp = int(definition.get("hp", structure.max_hp))
	structure.weapon = {}
	structure.mov = 0
	structure.def = int(definition.get("def", 0))
	structure.res = int(definition.get("res", 0))
	structure.acted = true
	structure.broken = bool(definition.get("broken", int(structure.hp) <= 0))
	return structure

func get_target(id: String) -> Dictionary:
	var unit := get_unit(id)
	if not unit.is_empty(): return unit if str(unit.get("rescued_by", "")).is_empty() else {}
	for structure in destructibles:
		if str(structure.id) == id: return structure
	return {}

func target_at(pos: Vector2i) -> Dictionary:
	var unit := unit_at(pos)
	if not unit.is_empty(): return unit
	for structure in destructibles:
		if int(structure.hp) > 0 and position(structure) == pos: return structure
	return {}

func unit_at(pos: Vector2i) -> Dictionary:
	for unit in units:
		if _on_map(unit) and position(unit) == pos:
			return unit
	return {}

func _on_map(unit: Dictionary) -> bool:
	return not unit.is_empty() and not unit.get("benched", false) and int(unit.get("hp", 0)) > 0 and str(unit.get("rescued_by", "")).is_empty() and not bool(unit.get("escaped", false))

func visible_cells(observer_overrides: Dictionary = {}) -> Dictionary:
	var fog := int(rules.get("fog_radius", 0))
	if fog <= 0: return {}
	var key: Array = [fog, width, height]
	var observers: Array = []
	var army_vision := 5 * Rogue.army(self, "darkvision")
	for original in units:
		var unit: Dictionary = observer_overrides.get(str(original.id), original)
		if unit.faction not in ["player", "neutral"] or not _on_map(unit): continue
		var vision := fog + army_vision + (5 if unit.get("can_lockpick", false) else 0) + int(unit.get("vision_bonus", 0))
		var origin := committed_position(unit)
		key.append([origin, vision])
		observers.append([origin, vision])
	for light in chapter.get("torch_lights", []):
		var observer := [Vector2i(int(light.x), int(light.y)), int(light.radius)]
		key.append(observer); observers.append(observer)
	if key == _vision_key: return _vision_cells
	_vision_key = key
	_vision_cells = {}
	if fog <= 0: return _vision_cells
	for observer in observers:
		var vision: int = observer[1]
		for dy in range(-vision, vision + 1):
			for dx in range(-vision + absi(dy), vision - absi(dy) + 1):
				var cell: Vector2i = observer[0] + Vector2i(dx, dy)
				if in_bounds(cell): _vision_cells[cell] = true
	return _vision_cells

func committed_position(unit: Dictionary) -> Vector2i:
	var origin: Dictionary = pending_moves.get(str(unit.id), unit)
	return Vector2i(origin.x, origin.y)

func visible_to_player(unit: Dictionary) -> bool:
	if _under_roof(unit): return false
	if unit.get("faction", "") != "enemy" or int(rules.get("fog_radius", 0)) <= 0: return true
	return visible_cells().has(position(unit))

func _concealed_from(unit: Dictionary, occupant: Dictionary) -> bool:
	return unit.get("faction", "") == "player" and occupant.get("faction", "") == "enemy" and not visible_to_player(occupant)

func _has_numeric_id(values: Array, wanted: int) -> bool:
	# JSON.parse_string represents numbers as floats; Array.has is type-strict.
	for value in values:
		if (value is int or value is float) and float(value) == float(wanted): return true
	return false

func _hostile(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a.id == b.id: return false
	if str(a.get("status", "")) == "berserk": return true
	if a.faction == b.faction: return false
	if a.get("kind", "") == "structure" or b.get("kind", "") == "structure": return true
	for group in rules.get("allied_factions", []):
		if group.has(a.faction) and group.has(b.faction): return false
	return true

func _sync_carried(carrier: Dictionary) -> void:
	var passenger := get_unit(str(carrier.get("carrying_id", "")))
	if not passenger.is_empty():
		passenger.x = int(carrier.x)
		passenger.y = int(carrier.y)

func position(unit: Dictionary) -> Vector2i:
	if not combat_guard.is_empty() and str(unit.get("id", "")) == combat_guard and combat_guard_cell.x >= 0:
		return combat_guard_cell
	return Vector2i(int(unit.get("x", -1)), int(unit.get("y", -1)))

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height

func terrain_at(pos: Vector2i) -> Dictionary:
	if not in_bounds(pos) or pos.x >= str(terrain[pos.y]).length():
		return {"name": "Outside map", "cost": -1}
	return rules["terrain"].get(str(terrain[pos.y])[pos.x], {"name": "Plain", "cost": 1})

func _identify_terrain(definitions: Dictionary) -> void:
	# Pack definitions use the ROM symbol alphabet. Defaults have explicit IDs
	# because the original prototype used different symbols for a few terrains.
	for symbol in definitions:
		rules.terrain[symbol] = rules.terrain[symbol].duplicate(true)
		rules.terrain[symbol]["terrain_id"] = definitions[symbol].get("terrain_id", Terrain.from_symbol(str(symbol)))

func terrain_id_at(pos: Vector2i) -> int:
	if not in_bounds(pos) or pos.x >= str(terrain[pos.y]).length(): return Terrain.UNKNOWN
	var symbol: String = str(terrain[pos.y])[pos.x]
	return int(terrain_at(pos).get("terrain_id", Terrain.from_symbol(symbol)))

func _move_cost(unit: Dictionary, pos: Vector2i) -> int:
	var cost := _base_move_cost(unit, pos)
	if not Rogue.active(self): return cost
	if cost > 0 and Rogue.Personal.has(unit, "fe7_unit_34"): return 1
	return Rogue.Personal.FE6.terrain_cost(unit, terrain_id_at(pos), cost)

func _base_move_cost(unit: Dictionary, pos: Vector2i) -> int:
	if not in_bounds(pos):
		return -1
	if Traps.at(self, pos).get("kind", "") == "light_rune": return -1
	for structure in destructibles:
		if int(structure.hp) > 0 and position(structure) == pos: return -1
	if Rogue.count(unit, "winged_boots") > 0:
		for cls in rules.get("promotion_catalog", {}).get("classes", {}).values():
			if cls.get("flying", false): return int(cls.get("movement_costs", {}).get(str(terrain[pos.y])[pos.x], -1))
		return 1 if _cheat_destination(pos) else -1
	var tile: String = str(terrain[pos.y])[pos.x]
	var costs: Dictionary = unit.get("movement_costs_rain", unit.get("movement_costs", {})) if int(rules.get("weather", 0)) == 4 and not rules.get("ignore_weather", false) and not (unit.get("faction", "") == "player" and Rogue.army(self, "commandos") > 0) else unit.get("movement_costs", {})
	if costs.has(tile):
		return int(costs[tile])
	var defaults: Dictionary = rules.get("terrain_class_defaults",{}).get(str(int(unit.get("rom_class_id",0))),{}).get("movement_costs",{})
	if defaults.has(tile): return int(defaults[tile])
	if bool(unit.get("flying", false)) and tile != "#":
		return 1
	return int(terrain_at(pos).get("cost", 1))

func movement_cost(unit: Dictionary, pos: Vector2i) -> int:
	# Public, read-only counterpart used by terrain inspection and route previews.
	return _move_cost(unit, pos)

func cheat_movement_active(unit: Dictionary) -> bool:
	return phase == "player" and unit.get("faction", "") == "player" and int(rules.get("cheat_move_turn", -1)) == turn

func _cheat_destination(cell: Vector2i) -> bool:
	if not in_bounds(cell): return false
	if Traps.at(self, cell).get("kind", "") == "light_rune": return false
	if destructibles.any(func(site): return int(site.hp) > 0 and position(site) == cell): return false
	var tile := terrain_at(cell)
	if Terrain.blocks_free_movement(terrain_id_at(cell), NativeFlags.game(chapter)): return false
	if int(tile.get("cost", -1)) > 0: return true
	var symbol: String = str(terrain[cell.y])[cell.x]
	for definition in rules.get("promotion_catalog", {}).get("classes", {}).values():
		if int(definition.get("movement_costs", {}).get(symbol, -1)) > 0: return true
	return false

func enable_free_movement() -> bool:
	if phase != "player" or not outcome.is_empty(): return false
	for id in pending_moves.keys(): cancel_move(str(id))
	rules.cheat_move_turn = turn
	for unit in units:
		if unit.faction != "player" or not _on_map(unit): continue
		unit.acted = false; unit.moved = false; unit.traded = false
		unit.move_spent = 0; unit.canto_active = false; unit.canto_remaining = 0
	events_log.append("Cheat: free movement for this player turn.")
	return true

func enable_combat_cheat() -> bool:
	if phase != "player" or not outcome.is_empty(): return false
	rules.cheat_combat_turn = turn
	events_log.append("Cheat: player units deal 99 damage and take 0 damage this turn.")
	return true

func combat_cheat_active() -> bool:
	return int(rules.get("cheat_combat_turn", -1)) == turn

func defeat_current_enemies() -> int:
	if phase != "player" or not outcome.is_empty(): return 0
	for id in pending_moves.keys(): cancel_move(str(id))
	var recruit_ids := preload("res://engine/chapter_preview.gd")._recruits(chapter)
	recruit_ids.append_array(chapter.get("future_recruits", []))
	for unit in units:
		if recruit_ids.has(str(unit.id)) and _on_map(unit) and unit.faction != "player":
			unit.faction = "player"
			Army.restore_campaign_unit(self, unit)
			events_log.append("%s was recruited by cheat." % unit.name)
	var targets: Array = units.filter(func(unit): return unit.faction == "enemy" and _on_map(unit))
	for enemy in targets:
		enemy.hp = 0
		_release_on_death(enemy)
		if not enemy.get("drop_claimed", false):
			var items: Array = enemy.get("stolen_items", []).duplicate(true)
			var drop: Dictionary = enemy.get("drop_item", {}).duplicate(true)
			for carried in [enemy.weapon] + enemy.inventory:
				if _same_item(carried, drop): drop = carried.duplicate(true); break
			if not drop.is_empty() and int(drop.get("uses", 0)) > 0: items.append(drop)
			for item in items:
				item.erase("droppable")
				_give_item("", item)
			gold += int(enemy.get("stolen_gold", 0))
			enemy.drop_claimed = true
		events_log.append("%s was defeated by cheat." % enemy.name)
	_run_events("unit_defeated")
	_check_objective()
	return targets.size()

func reachable(unit: Dictionary) -> Dictionary:
	if not _on_map(unit) or bool(unit["acted"]) or unit.get("status", "") == "sleep":
		return {}
	var origin := position(unit)
	if cheat_movement_active(unit):
		var cells: Dictionary = {origin:0}
		for y in range(height):
			for x in range(width):
				var cell := Vector2i(x, y)
				var occupant := unit_at(cell)
				if _cheat_destination(cell) and (occupant.is_empty() or occupant.id == unit.id) and not _reserved_origin(cell, str(unit.id)): cells[cell] = 0
		return cells
	if bool(unit.get("moved", false)):
		return {origin: 0}
	var costs: Dictionary = _movement_search(unit, origin, _movement_budget(unit)).costs
	if Rogue.count(unit, "savior") > 0 and not unit.get("canto_active", false):
		for ally in units:
			if ally.id == unit.id or not _on_map(ally) or _hostile(unit, ally) or int(ally.hp) * 2 >= int(ally.max_hp): continue
			for direction in DIRECTIONS:
				var cell: Vector2i = position(ally) + direction
				if _move_cost(unit, cell) > 0 and unit_at(cell).is_empty(): costs[cell] = 0
	# Resolve occupancy and fog once for the whole query, not once per tile.
	var occupied := {}
	var vision := visible_cells() if unit.faction == "player" and int(rules.get("fog_radius", 0)) > 0 else {}
	for other in units:
		if not _on_map(other) or other.id == unit.id: continue
		if unit.faction == "player" and other.faction == "enemy" and (_under_roof(other) or (int(rules.get("fog_radius", 0)) > 0 and not vision.has(position(other)))): continue
		occupied[position(other)] = true
	# Allies may be crossed but never occupied at the end of a move.
	for cell in costs.keys():
		if occupied.has(cell):
			costs.erase(cell)
		elif _reserved_origin(cell, str(unit["id"])):
			costs.erase(cell)
	return costs

func _movement_budget(unit: Dictionary) -> int:
	if unit.get("canto_active", false): return int(unit.get("canto_remaining", 0))
	if unit.get("traded", false): return maxi(0, (effective_stat(unit, "mov") if Rogue.active(self) else int(unit.get("mov", 5))) - int(unit.get("move_spent", 0))) if unit.get("canto", false) else 0
	if unit.get("rogue_fury", false): return 3 * Rogue.count(unit, "canto")
	return maxi(0, effective_stat(unit, "mov")) if Rogue.active(self) else int(unit.get("mov", 5))

func _movement_search(unit: Dictionary, origin: Vector2i, budget: int = -1, envelope: Dictionary = {}) -> Dictionary:
	# Stable Dijkstra traversal is shared by legal movement and its presentation.
	var costs: Dictionary = {origin: 0}
	var previous: Dictionary = {}
	var frontier: Array = [origin]
	# Occupancy and terrain cannot change within a single search. Resolve them
	# once instead of scanning the army on every edge of the search graph.
	var blockers: Dictionary = {}
	var vision := visible_cells() if unit.faction == "player" and int(rules.get("fog_radius", 0)) > 0 else {}
	if Rogue.count(unit, "pass") == 0:
		for other in units:
			if not _on_map(other) or not _hostile(other, unit): continue
			if unit.faction == "player" and other.faction == "enemy" and (_under_roof(other) or (int(rules.get("fog_radius", 0)) > 0 and not vision.has(position(other)))): continue
			blockers[position(other)] = true
	var step_costs: Dictionary = {}
	while not frontier.is_empty():
		var next_index := 0
		for index in range(1, frontier.size()):
			if int(costs[frontier[index]]) < int(costs[frontier[next_index]]):
				next_index = index
		var current: Vector2i = frontier.pop_at(next_index)
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not envelope.is_empty() and not envelope.has(next):
				continue
			if blockers.has(next): continue
			if not step_costs.has(next): step_costs[next] = _move_cost(unit, next)
			var step := int(step_costs[next])
			if step <= 0:
				continue
			var total := int(costs[current]) + step
			if budget >= 0 and total > budget:
				continue
			if not costs.has(next) or total < int(costs[next]):
				costs[next] = total
				previous[next] = current
				if not frontier.has(next):
					frontier.append(next)
	return {"costs": costs, "previous": previous}

func movement_path(id: String, destination: Vector2i, from_cell: Vector2i = Vector2i(-1, -1)) -> Array:
	# Presentation-only query: no phase, action, event, pending-move, or RNG changes.
	# An explicit origin lets callers animate the reverse of a canceled preview.
	var unit := get_unit(id)
	if not _on_map(unit) or not in_bounds(destination):
		return []
	var origin := position(unit) if from_cell == Vector2i(-1, -1) else from_cell
	if not in_bounds(origin):
		return []
	if cheat_movement_active(unit):
		return [origin, destination] if reachable(_planning_unit(unit)).has(destination) else []
	var occupant := unit_at(destination)
	if (not occupant.is_empty() and str(occupant.id) != id and not _concealed_from(unit, occupant)) or _reserved_origin(destination, id):
		return []
	var planning := _planning_unit(unit)
	if Rogue.count(unit, "savior") > 0 and reachable(planning).has(destination) and int(reachable(planning)[destination]) == 0: return [origin, destination]
	var envelope: Dictionary = _movement_search(planning, position(planning), _movement_budget(planning)).costs
	if not envelope.has(origin) or not envelope.has(destination):
		return []
	var search := _movement_search(unit, origin, -1, envelope)
	if not search.costs.has(destination):
		return []
	var path: Array = [destination]
	var cursor := destination
	while cursor != origin:
		cursor = search.previous[cursor]
		path.push_front(cursor)
	return path

func range_overlay(id: String) -> Dictionary:
	var unit := get_unit(id)
	var empty := {"movement": {}, "attack": [], "beneficial": []}
	if not _on_map(unit):
		return empty
	var planning := _planning_unit(unit)
	if unit.faction == "enemy":
		# Inspection shows the next enemy action even during the player's phase.
		planning.acted = false
		planning.moved = false
		if str(planning.get("ai_mode", planning.get("ai", "aggressive"))) == "stationary":
			planning.mov = 0
	var movement := reachable(planning)
	var attack_cells: Dictionary = {}
	var beneficial_cells: Dictionary = {}
	var weapons: Array = [planning.weapon]
	weapons.append_array(planning.inventory)
	for weapon in weapons:
		var helpful := can_use_staff(planning, weapon)
		if (not can_equip_weapon(planning, weapon) and not helpful) or planning.get("canto_active", false): continue
		for origin in movement:
			var candidate := planning.duplicate()
			candidate.planned_move_cost = int(movement[origin])
			var limits := item_range(candidate, weapon)
			var minimum := limits.x
			var maximum := mini(width + height, limits.y)
			for dy in range(-maximum, maximum + 1):
				for dx in range(-maximum + absi(dy), maximum - absi(dy) + 1):
					var cell: Vector2i = origin + Vector2i(dx, dy)
					if absi(dx) + absi(dy) >= minimum and in_bounds(cell) and not movement.has(cell):
						if helpful: beneficial_cells[cell] = true
						else: attack_cells[cell] = true
	if bool(planning.get("can_play", false)) and not planning.get("canto_active", false):
		for origin in movement:
			for direction in DIRECTIONS:
				var cell: Vector2i = origin + direction
				if in_bounds(cell) and not movement.has(cell): beneficial_cells[cell] = true
	var siege := emplacement_weapon(unit)
	if not siege.is_empty() and not planning.get("canto_active", false):
		for y in range(height):
			for x in range(width):
				var cell := Vector2i(x, y)
				var distance := _distance(position(unit), cell)
				if distance >= int(siege.min_range) and distance <= int(siege.max_range) and not movement.has(cell): attack_cells[cell] = true
	return {"movement": movement, "attack": attack_cells.keys(), "beneficial": beneficial_cells.keys()}

func _reserved_origin(cell: Vector2i, except_id: String) -> bool:
	for id in pending_moves:
		var origin: Dictionary = pending_moves[id]
		if id != except_id and cell == Vector2i(int(origin.x), int(origin.y)):
			return true
	return false

func enemy_range_overlay() -> Dictionary:
	# Pure inspection query: union each living enemy's legal movement and weapons.
	var movement: Dictionary = {}
	var attacks: Dictionary = {}
	for unit in units:
		if unit.faction != "enemy" or not _on_map(unit) or not visible_to_player(unit): continue
		var overlay := range_overlay(str(unit.id))
		for cell in overlay.movement: movement[cell] = true
		for cell in overlay.attack: attacks[cell] = true
	for cell in movement: attacks.erase(cell)
	return {"movement": movement, "attack": attacks.keys()}

func _planning_unit(unit: Dictionary) -> Dictionary:
	var copy := unit.duplicate(false)
	if pending_moves.has(str(unit.id)):
		var origin: Dictionary = pending_moves[str(unit.id)]
		copy.x = int(origin.x)
		copy.y = int(origin.y)
		copy.moved = false
	return copy

func preview_move(id: String, destination: Vector2i) -> bool:
	# Preview changes only position. Position events run once when the action is committed.
	var unit := get_unit(id)
	if not _can_act(unit) or unit.faction != "player":
		return false
	if not pending_moves.is_empty() and not pending_moves.has(id):
		return false
	if bool(unit.moved) and not pending_moves.has(id) and not cheat_movement_active(unit):
		return false
	var planning := _planning_unit(unit)
	var cells := reachable(planning)
	if not cells.has(destination):
		return false
	last_movement_effect = {}
	var path := Traps.movement_path(self, unit, movement_path(id, destination, position(planning)))
	if path.is_empty(): return false
	last_preview_path = path.duplicate()
	destination = path.back()
	if not pending_moves.has(id):
		pending_moves[id] = {"x": int(unit.x), "y": int(unit.y), "moved": bool(unit.moved)}
	pending_moves[id]["cost"] = int(cells[destination])
	pending_moves[id]["path"] = path.map(func(cell): return [cell.x, cell.y])
	unit.x = destination.x
	unit.y = destination.y
	unit.moved = true
	_sync_carried(unit)
	# Entering a mine is an irreversible movement action, unlike a normal preview.
	if path.size() > 1 and Traps.interrupts(unit) and Traps.at(self, destination).get("kind", "") == "mine": commit_move(id)
	return true

func cancel_move(id: String) -> bool:
	if not pending_moves.has(id):
		return false
	var unit := get_unit(id)
	if unit.is_empty() or bool(unit.acted):
		return false
	var origin: Dictionary = pending_moves[id]
	var occupant := unit_at(Vector2i(int(origin.x), int(origin.y)))
	if not occupant.is_empty() and occupant.id != id:
		return false
	unit.x = int(origin.x)
	unit.y = int(origin.y)
	unit.moved = bool(origin.get("moved", false))
	_sync_carried(unit)
	pending_moves.erase(id)
	return true

func commit_move(id: String) -> bool:
	if not pending_moves.has(id):
		return false
	var unit := get_unit(id)
	if not _can_act(unit):
		return false
	var origin: Dictionary = pending_moves[id]
	var cost := int(origin.get("cost", 0))
	var last_safe := Vector2i(int(origin.x), int(origin.y))
	var walked_cost := 0
	var walked_tiles := 0
	var first := true
	if not origin.has("path"):
		origin.path = movement_path(id, position(unit), last_safe).map(func(cell): return [cell.x, cell.y])
	for coordinates in origin.get("path", []):
		if not coordinates is Array or coordinates.size() != 2: continue
		var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
		if first: first = false
		else:
			walked_cost += maxi(0, _move_cost(unit, cell))
			walked_tiles += 1
		if Rogue.count(unit, "pass") == 0 and units.any(func(other): return _on_map(other) and _hostile(unit, other) and position(other) == cell):
			unit.x = last_safe.x
			unit.y = last_safe.y
			unit.acted = true
			_sync_carried(unit)
			events_log.append("%s's movement was stopped by a hidden enemy." % unit.name)
			break
		if not units.any(func(other): return str(other.id) != id and _on_map(other) and position(other) == cell):
			last_safe = cell
			if walked_cost > 0 and Traps.interrupts(unit) and Traps.at(self, cell).get("kind", "") == "mine":
				unit.x = cell.x
				unit.y = cell.y
				_sync_carried(unit)
				cost = walked_cost
				Traps.trigger(self, unit)
				break
	if not origin.has("cost"):
		cost = int(reachable(_planning_unit(unit)).get(position(unit), 0))
	if Rogue.active(self): unit.rogue_tiles_moved = int(unit.get("rogue_tiles_moved", 0)) + walked_tiles
	unit.move_spent = int(unit.move_spent) + cost
	if unit.canto_active:
		unit.canto_remaining = maxi(0, int(unit.canto_remaining) - cost)
		if int(unit.canto_remaining) == 0:
			unit.canto_active = false
			unit.acted = true
	pending_moves.erase(id)
	if _on_map(unit): _run_events("position", {"unit_id": id, "x": int(unit.x), "y": int(unit.y)})
	return true

func attack_approach(id: String, target_id: String, weapon_key: String = "") -> Dictionary:
	# Pure planning: shortest movement cost; stable row/column order breaks ties.
	var unit := _unit_with_weapon(id, weapon_key)
	var target := get_target(target_id)
	if not _can_command(unit) or target.is_empty() or int(target.hp) <= 0 or not _hostile(unit, target) or not _armed(unit) or _concealed_from(unit, target):
		return {"ok": false}
	if _in_range(unit, target):
		return {"ok": true, "cell": position(unit), "cost": 0}
	if weapon_key == "emplacement": return {"ok": false}
	if bool(unit.moved) and not pending_moves.has(id):
		return {"ok": false}
	var cells := reachable(_planning_unit(unit))
	var best := Vector2i(-1, -1)
	var best_cost := 2147483647
	for cell in cells:
		var distance := _distance(cell, position(target))
		var candidate := unit.duplicate()
		candidate.planned_move_cost = int(cells[cell])
		if distance < item_range(candidate, unit.weapon).x or distance > item_range(candidate, unit.weapon).y:
			continue
		var cost := int(cells[cell])
		if cost < best_cost or (cost == best_cost and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))):
			best = cell
			best_cost = cost
	return {"ok": true, "cell": best, "cost": best_cost} if best.x >= 0 else {"ok": false}

func assist_approach(id: String, target_id: String, index: int = -1, kind: String = "staff") -> Dictionary:
	# The same weighted approach search as attacks, without mutating a preview,
	# consuming a staff use, awarding experience, or refreshing the target.
	var unit := get_unit(id)
	var target := get_unit(target_id)
	if not _can_command(unit) or unit.faction != "player" or (not pending_moves.is_empty() and not pending_moves.has(id)):
		return {"ok": false}
	var limits := Vector2i.ONE
	if kind == "play":
		if not _can_play_for(unit, target): return {"ok": false}
	elif kind == "staff":
		var item := _inventory_item(unit, index)
		if not can_use_staff(unit, item) or not _staff_benefits(unit, target, item): return {"ok": false}
		limits = item_range(unit, item)
	else:
		return {"ok": false}
	var distance := _distance(position(unit), position(target))
	if distance >= limits.x and distance <= limits.y:
		return {"ok": true, "cell": position(unit), "cost": 0}
	if bool(unit.moved) and not pending_moves.has(id): return {"ok": false}
	var cells := reachable(_planning_unit(unit))
	var best := Vector2i(-1, -1)
	var best_cost := 2147483647
	for cell in cells:
		distance = _distance(cell, position(target))
		if distance < limits.x or distance > limits.y: continue
		var cost := int(cells[cell])
		if cost < best_cost or (cost == best_cost and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))):
			best = cell
			best_cost = cost
	return {"ok": true, "cell": best, "cost": best_cost} if best.x >= 0 else {"ok": false}

func assist_options(id: String, target_id: String) -> Array:
	var unit := get_unit(id)
	if not _can_command(unit): return []
	var options: Array = []
	var approach := assist_approach(id, target_id, -1, "play")
	if approach.ok:
		options.append({"kind": "play", "index": -1, "item": {}, "label": "Play", "approach": approach})
	for index in range(unit.inventory.size()):
		approach = assist_approach(id, target_id, index)
		if approach.ok:
			var item: Dictionary = unit.inventory[index]
			options.append({"kind": "staff", "index": index, "item": item.duplicate(true), "label": str(item.get("name", "Staff")), "approach": approach})
	return options

func _can_act(unit: Dictionary) -> bool:
	if int(unit.get("reinforcement_ready_turn", 0)) > turn: return false
	return _on_map(unit) and not _under_roof(unit) and outcome.is_empty() and (unit["faction"] == phase or (phase == "npc" and unit.faction == "neutral")) and not bool(unit["acted"]) and str(unit.get("status", "")) != "sleep"

func _under_roof(unit: Dictionary) -> bool:
	return unit.get("concealed_by_roof", false) and in_bounds(position(unit)) and str(terrain[int(unit.y)])[int(unit.x)] == "H"

func _can_command(unit: Dictionary) -> bool:
	return _can_act(unit) and not unit.get("canto_active", false) and (auto_playing or str(unit.get("status", "")) != "berserk")

func _finish_noncombat(unit: Dictionary, ends_action: bool = true) -> void:
	if bool(unit.get("canto", false)) and unit.faction == "player":
		var remaining := maxi(0, (effective_stat(unit, "mov") if Rogue.active(self) else int(unit.mov)) - int(unit.move_spent))
		unit.canto_remaining = remaining
		unit.canto_active = remaining > 0
		unit.acted = remaining == 0
		unit.moved = false if remaining > 0 else true
	elif ends_action:
		unit.acted = true
	if ends_action:
		if Rogue.active(self): unit.rogue_action_taken = true
		Traps.trigger(self, unit, true)

	_search_after_action(unit)

func _search_after_action(unit: Dictionary) -> void:
	if chapter.get("native_search_events",false) and unit.get("acted",false) and _on_map(unit):
		_run_events("action_complete",{"unit_id":unit.id,"x":int(unit.x),"y":int(unit.y)})

func rescue_targets(id: String) -> Array:
	var carrier := get_unit(id)
	if carrier.get("rogue_fury", false): return []
	if not _can_command(carrier) or carrier.faction != "player" or not str(carrier.carrying_id).is_empty(): return []
	var result: Array = []
	for passenger in units:
		if not _on_map(passenger) or passenger.id == id or passenger.faction not in ["player", "neutral"] or not str(passenger.carrying_id).is_empty(): continue
		if pending_moves.has(str(passenger.id)) or passenger.get("unrescuable", false): continue
		if _distance(position(carrier), position(passenger)) == 1 and rescue_aid(carrier) >= int(passenger.con): result.append(passenger)
	return result

func rescue_aid(unit: Dictionary) -> int:
	# Packs may supply an exact class-derived aid, or dynamic constitution formula.
	if unit.has("aid_base"): return maxi(0, int(unit.aid_base) - int(unit.con))
	return maxi(0, int(unit.get("aid", int(unit.get("con", 1)) - 1)))

func transfer_targets(id: String, giving: bool = false) -> Array:
	var actor := get_unit(id)
	if not _can_command(actor) or actor.faction != "player" or (not pending_moves.is_empty() and not pending_moves.has(id)): return []
	var targets: Array = []
	for ally in units:
		if not _on_map(ally) or ally.faction != "player" or ally.id == id or pending_moves.has(str(ally.id)): continue
		if _distance(position(actor), position(ally)) != 1: continue
		var donor: Dictionary = actor if giving else ally
		var receiver: Dictionary = ally if giving else actor
		var passenger := get_unit(str(donor.carrying_id))
		if passenger.is_empty() or int(passenger.hp) <= 0 or not str(receiver.carrying_id).is_empty(): continue
		if rescue_aid(receiver) >= int(passenger.con): targets.append(ally)
	return targets

func transfer_rescue(id: String, target_id: String, giving: bool = false) -> Dictionary:
	var ally := get_unit(target_id)
	if ally.is_empty() or not transfer_targets(id, giving).has(ally): return {"ok": false, "reason": "Choose an adjacent carrier or ally with enough Aid."}
	var actor := get_unit(id)
	commit_move(id)
	if actor.acted: return {"ok": false, "reason": "Movement was interrupted."}
	var donor: Dictionary = actor if giving else ally
	var receiver: Dictionary = ally if giving else actor
	var passenger := get_unit(str(donor.carrying_id))
	donor.carrying_id = ""
	receiver.carrying_id = str(passenger.id)
	passenger.rescued_by = str(receiver.id)
	_sync_carried(receiver)
	# Like trading, transferring commits movement but preserves the main action.
	actor.traded = true
	actor.moved = not actor.get("canto", false) or int(actor.move_spent) >= int(actor.mov)
	events_log.append("%s passed %s to %s." % [donor.name, passenger.name, receiver.name])
	return {"ok": true, "passenger_id": str(passenger.id)}

func rescue_unit(id: String, target_id: String) -> Dictionary:
	var targets := rescue_targets(id)
	var passenger := get_unit(target_id)
	if passenger.is_empty() or not targets.has(passenger): return {"ok": false, "reason": "Choose an adjacent ally within this unit's Aid."}
	var carrier := get_unit(id)
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	carrier.carrying_id = target_id
	passenger.rescued_by = id
	passenger.acted = true
	passenger.moved = true
	passenger.canto_active = false
	passenger.canto_remaining = 0
	_sync_carried(carrier)
	_finish_noncombat(carrier)
	Rogue.after_action(self, carrier, "assist")
	events_log.append("%s rescued %s." % [carrier.name, passenger.name])
	_run_events("rescue", {"unit_id": id, "target_id": target_id})
	return {"ok": true, "rescued_id": target_id}

func drop_cells(id: String) -> Array:
	var carrier := get_unit(id)
	if carrier.get("rogue_fury", false): return []
	if not _can_command(carrier) or carrier.faction != "player": return []
	var passenger := get_unit(str(carrier.carrying_id))
	if passenger.is_empty() or int(passenger.hp) <= 0: return []
	var result: Array = []
	for direction in DIRECTIONS:
		var cell: Vector2i = position(carrier) + direction
		if _move_cost(passenger, cell) > 0 and unit_at(cell).is_empty() and not _reserved_origin(cell, id): result.append(cell)
	return result

func drop_unit(id: String, cell: Vector2i) -> Dictionary:
	if not drop_cells(id).has(cell): return {"ok": false, "reason": "Choose an empty adjacent tile the rescued ally can enter."}
	var carrier := get_unit(id)
	var passenger := get_unit(str(carrier.carrying_id))
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	_release_passenger(carrier, cell)
	_finish_noncombat(carrier)
	Rogue.after_action(self, carrier, "assist")
	Traps.trigger(self, passenger, true)
	events_log.append("%s dropped %s." % [carrier.name, passenger.name])
	_run_events("drop", {"unit_id": id, "target_id": str(passenger.id), "x": cell.x, "y": cell.y})
	return {"ok": true, "dropped_id": str(passenger.id)}

func _release_passenger(carrier: Dictionary, cell: Vector2i) -> void:
	var passenger := get_unit(str(carrier.get("carrying_id", "")))
	carrier.carrying_id = ""
	if passenger.is_empty(): return
	passenger.rescued_by = ""
	passenger.x = cell.x
	passenger.y = cell.y
	passenger.acted = true
	passenger.moved = true
	passenger.canto_active = false
	passenger.canto_remaining = 0

func _release_on_death(carrier: Dictionary) -> void:
	NativeFlags.defeat(self,carrier)
	var passenger := get_unit(str(carrier.get("carrying_id", "")))
	if passenger.is_empty(): return
	var origin := position(carrier)
	# Flying carriers may fall over terrain their passenger cannot occupy.
	# Place the survivor on the nearest legal free tile, with stable row/column ties.
	for radius in range(width + height):
		for y in range(height):
			for x in range(width):
				var cell := Vector2i(x, y)
				if _distance(origin, cell) == radius and _move_cost(passenger, cell) > 0 and unit_at(cell).is_empty() and not _reserved_origin(cell, str(carrier.id)):
					_release_passenger(carrier, cell)
					return
	# A completely impassable/full map still must not silently kill the passenger.
	_release_passenger(carrier, origin)

func move_unit(id: String, destination: Vector2i) -> bool:
	var unit := get_unit(id)
	if not _can_act(unit) or bool(unit.get("moved", false)):
		return false
	var cells := reachable(unit)
	if not cells.has(destination):
		return false
	last_movement_effect = {}
	var path := Traps.movement_path(self, unit, movement_path(id, destination))
	if path.is_empty(): return false
	destination = path.back()
	if phase != "player" or auto_playing:
		if path.size() > 1:
			phase_actions.append({"type": "move", "unit_id": id, "path": path})
	unit["x"] = destination.x
	unit["y"] = destination.y
	unit["moved"] = true
	_sync_carried(unit)
	unit.move_spent = int(unit.move_spent) + int(cells[destination])
	if Rogue.active(self): unit.rogue_tiles_moved = int(unit.get("rogue_tiles_moved", 0)) + maxi(0, path.size() - 1)
	if unit.canto_active:
		unit.canto_remaining = maxi(0, int(unit.canto_remaining) - int(cells[destination]))
		if int(unit.canto_remaining) == 0:
			unit.canto_active = false
			unit.acted = true
	if path.size() > 1: Traps.trigger(self, unit)
	if _on_map(unit): _run_events("position", {"unit_id": id, "x": destination.x, "y": destination.y})
	return true

func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _armed(unit: Dictionary) -> bool:
	return can_equip_weapon(unit, unit.get("weapon", {}))

func magic_sealed(cell: Vector2i) -> bool:
	for unit in units:
		if int(unit.get("magic_seal_radius", 0)) > 0 and (not unit.get("magic_seal_enemy_only",false) or unit.faction == "enemy") and _on_map(unit) and _distance(position(unit), cell) <= int(unit.magic_seal_radius): return true
	return false

func _in_range(attacker: Dictionary, defender: Dictionary) -> bool:
	if str(attacker.get("status", "")) == "sleep": return false
	if rules.get("magic_types", []).has(attacker.get("weapon", {}).get("type", "")) and (magic_sealed(position(attacker)) or str(attacker.get("status", "")) == "silence"): return false
	if attacker.get("faction", "") == "player" and not visible_to_player(defender): return false
	if not _on_map(attacker) or not _on_map(defender) or not _armed(attacker):
		return false
	var distance := _distance(position(attacker), position(defender))
	return distance >= item_range(attacker, attacker.weapon).x and distance <= item_range(attacker, attacker.weapon).y if Rogue.active(self) else distance >= int(attacker["weapon"].get("min_range", 1)) and distance <= int(attacker["weapon"].get("max_range", 1))

func attack_targets(id: String) -> Array:
	var attacker := get_unit(id)
	var targets: Array = []
	if not _can_command(attacker):
		return targets
	for unit in units + destructibles:
		if _on_map(unit) and _hostile(attacker, unit) and _in_range(attacker, unit):
			targets.append(unit)
	return targets

func _attack_speed(unit: Dictionary) -> int:
	return attack_speed(unit)

func attack_speed(unit: Dictionary, weapon: Variant = null) -> int:
	var equipped := unit
	if weapon != null:
		equipped = unit.duplicate()
		equipped.weapon = weapon
	return maxi(0, effective_stat(equipped, "speed") - maxi(0, int(equipped.get("weapon", {}).get("weight", 0)) - effective_stat(equipped, "con")))

func effective_stat(unit: Dictionary, stat: String) -> int:
	var value := int(unit.get(stat, 0)) + int(unit.get("temporary_bonuses", {}).get(stat, 0)) + int(unit.get("ring_bonuses", {}).get(stat, 0)) + int(unit.get("weapon", {}).get("stat_bonuses", {}).get(stat, 0))
	if stat in ["skill", "speed"] and not str(unit.get("carrying_id", "")).is_empty():
		value /= maxi(1, int(rules.get("carrying_stat_divisor", 2)))
	return maxi(0, value + Rogue.permanent(unit, stat) + Rogue.temporary(unit, stat) + Rogue.Personal.state_stat(self, unit, stat)) if Rogue.active(self) else value

func _triangle(attacker: Dictionary, defender: Dictionary) -> int:
	var atype: String = str(attacker.get("weapon", {}).get("type", ""))
	var dtype: String = str(defender.get("weapon", {}).get("type", ""))
	atype = str(attacker.get("weapon", {}).get("triangle_type",atype))
	dtype = str(defender.get("weapon", {}).get("triangle_type",dtype))
	if _distance(position(attacker), position(defender)) > 1:
		if attacker.get("weapon", {}).has("ranged_fixed_damage"): atype = "light"
		if defender.get("weapon", {}).has("ranged_fixed_damage"): dtype = "light"
	var value := 0
	if rules["triangle"].get(atype, "none") == dtype:
		value = 1
	if rules["triangle"].get(dtype, "none") == atype:
		value = -1
	var a_reverse := bool(attacker.get("weapon", {}).get("triangle_reverse", false))
	var d_reverse := bool(defender.get("weapon", {}).get("triangle_reverse", false))
	# Two reversing weapons cancel each other. A single one changes the
	# matchup for both combatants, including the defender's counterattack.
	if a_reverse != d_reverse:
		var item: Dictionary = attacker.weapon if a_reverse else defender.weapon
		value *= -maxi(1, int(item.get("triangle_multiplier", 2)))
	return value * (1 + Rogue.count(attacker, "specialist") + Rogue.count(defender, "specialist"))

func support_bonuses(id: String) -> Dictionary:
	var result := {"atk": 0, "def": 0, "hit": 0, "avo": 0, "crit": 0, "ddg": 0}
	var unit := _support_unit(id)
	if not bool(rules.get("supports_enabled", true)) or not _on_map(unit) or unit.faction != "player": return result
	var totals := {"atk": 0.0, "def": 0.0, "hit": 0.0, "avo": 0.0, "crit": 0.0, "ddg": 0.0}
	var affinities: Dictionary = rules.get("support_affinities", {})
	var remaining := int(rules.support_total_cap)
	var partners: Array = []
	var identity := str(unit.get("support_id", unit.id))
	# Resolve only nearby support partners once. Sorting the entire roster with
	# repeated identity lookups made each combat forecast scale cubically.
	for other in units:
		if other.id == unit.id or other.faction != "player" or not _on_map(other): continue
		if _distance(position(unit), position(other)) > int(rules.support_range): continue
		var other_identity := str(other.get("support_id", other.id))
		var key := identity + "|" + other_identity if identity < other_identity else other_identity + "|" + identity
		var rank := int(support_ranks.get(key, 0))
		if rank > 0: partners.append({"unit":other, "rank":rank})
	partners.sort_custom(func(a, b): return a.rank > b.rank if a.rank != b.rank else str(a.unit.id) < str(b.unit.id))
	for entry in partners:
		var other: Dictionary = entry.unit
		var rank := mini(int(entry.rank), remaining)
		if rank <= 0: continue
		remaining -= rank
		var own: Dictionary = affinities.get(str(unit.get("affinity", "")).to_lower(), {})
		var partner: Dictionary = affinities.get(str(other.get("affinity", "")).to_lower(), {})
		var multiplier := Rogue.Personal.support_multiplier(unit, other) if Rogue.active(self) else 1
		for stat in totals:
			totals[stat] += (float(own.get(stat, 0.0)) + float(partner.get(stat, 0.0))) * rank * multiplier
	# Preserve half points across partners, then floor once for the final stat.
	for stat in result: result[stat] = int(floor(totals[stat]))
	return result

func triangle_attack_members(attacker: Dictionary, defender: Dictionary) -> Array:
	var sisters := ["fe7_unit_29", "fe7_unit_30", "fe7_unit_31"]
	if attacker.get("faction", "") != "player" or not sisters.has(str(attacker.get("id", ""))) or defender.get("kind", "") == "structure": return []
	if not combat_initiator.is_empty() and combat_initiator != str(attacker.id): return []
	if not _on_map(defender) or not _hostile(attacker, defender): return []
	var occupied := {}
	for id in sisters:
		var sister: Dictionary = attacker if id == str(attacker.id) else get_unit(id)
		if not _on_map(sister) or sister.get("faction", "") != "player" or _distance(position(sister), position(defender)) != 1: return []
		if occupied.has(position(sister)): return []
		occupied[position(sister)] = true
	return sisters

func _begin_rogue_combat(attacker: Dictionary, defender: Dictionary) -> void:
	for unit in [attacker, defender]: Rogue.Personal.begin_combat(unit)
	# Freeze start-of-combat conditions for every strike, including arena rounds.
	var first := Rogue.Personal.FE6.combat_bonus(self, attacker, true, defender)
	var second := Rogue.Personal.FE6.combat_bonus(self, defender, false, attacker)
	Rogue.Personal.progress(attacker).fe6_combat = first
	Rogue.Personal.progress(defender).fe6_combat = second
	var rb := Rogue.combat_bonus(self, attacker, defender, true)
	var db := Rogue.combat_bonus(self, defender, attacker, false)
	var extra_a := Rogue.Personal.FE6.conditional_bonus(self, attacker, defender, rb, db)
	var extra_d := Rogue.Personal.FE6.conditional_bonus(self, defender, attacker, db, rb)
	Rogue.Personal.progress(attacker).fe6_combat_extra = extra_a
	Rogue.Personal.progress(defender).fe6_combat_extra = extra_d
	Rogue.Personal.progress(attacker).combat_heal_block = Rogue.Personal.has(defender, Rogue.Personal.FE6.UNIT_16)
	Rogue.Personal.progress(defender).combat_heal_block = Rogue.Personal.has(attacker, Rogue.Personal.FE6.UNIT_16)

func _combat_stats(attacker: Dictionary, defender: Dictionary, resolve_personal: bool = true) -> Dictionary:
	var weapon: Dictionary = attacker.get("weapon", {})
	var initiating := combat_initiator.is_empty() or combat_initiator == str(attacker.id)
	var rb := Rogue.combat_bonus(self, attacker, defender, initiating)
	var db := Rogue.combat_bonus(self, defender, attacker, not initiating)
	if resolve_personal and Rogue.active(self):
		var extra_a := Rogue.Personal.FE6.conditional_bonus(self, attacker, defender, rb, db)
		var extra_d := Rogue.Personal.FE6.conditional_bonus(self, defender, attacker, db, rb)
		for stat in extra_a: rb[stat] += int(extra_a[stat])
		for stat in extra_d: db[stat] += int(extra_d[stat])
	var attack_luck := effective_stat(attacker, "luck") + int(rb.luck)
	var defense_luck := effective_stat(defender, "luck") + int(db.luck)
	var attacker_speed := maxi(0, effective_stat(attacker, "speed") + int(rb.speed) - maxi(0, int(weapon.get("weight", 0)) - effective_stat(attacker, "con") - int(rb.con)))
	var defense_speed := maxi(0, effective_stat(defender, "speed") + int(db.speed) - maxi(0, int(defender.get("weapon", {}).get("weight", 0)) - effective_stat(defender, "con") - int(db.con)))
	var can_attack := int(attacker["hp"]) > 0 and (_in_range(attacker, defender) or (not initiating and _armed(attacker) and (Rogue.count(attacker, "omni_counter") > 0 or (Rogue.active(self) and Rogue.Personal.counters(attacker, _distance(position(attacker), position(defender)))))))
	if Rogue.active(self) and (str(attacker.get("status", "")) == "sleep" or (rules.magic_types.has(weapon.get("type", "")) and (str(attacker.get("status", "")) == "silence" or magic_sealed(position(attacker))))): can_attack = false
	if defender.get("kind", "") == "structure":
		var structure_power := int(attacker.str)
		if Rogue.active(self): structure_power = effective_stat(attacker, "magic" if attacker.has("magic") and (rules.magic_types.has(weapon.get("type", "")) or weapon.get("magic_damage", false)) else "str") + int(rb.atk)
		return {"name": attacker.name, "hp": attacker.hp, "damage": maxi(0, structure_power + int(weapon.get("might", 0)) - int(defender.def)), "hit": 100, "crit": 0, "strikes": 1 if can_attack else 0, "can_attack": can_attack, "attack_speed": attacker_speed}
	var triangle := _triangle(attacker, defender)
	var magic: bool = rules["magic_types"].has(weapon.get("type", "")) or weapon.get("magic_damage", false)
	var defense := effective_stat(defender, "res" if magic else "def") + int(db.res if magic else db.def)
	if not bool(defender.get("flying", false)):
		defense += _terrain_combat_bonus(defender, "resistance" if magic else "defense")
	var support_attack := support_bonuses(str(attacker.id))
	var support_defense := support_bonuses(str(defender.id))
	defense += int(support_defense.def)
	if weapon.get("ignore_defense", false): defense = 0
	var might := int(weapon.get("might", 0))
	var effective: bool = _has_numeric_id(weapon.get("effective_class_ids", []), int(defender.get("rom_class_id", -1)))
	for category in weapon.get("effective_against", []):
		if defender.get("tags", []).has(category) or (category == "flying" and defender.get("flying", false)):
			effective = true
	if Rogue.shield(defender): effective = false
	if weapon.get("flying_effectiveness",false) and ([defender.get("weapon",{})]+defender.get("inventory",[])).any(func(item):return item.get("negate_flying_effectiveness",false)): effective = false
	might += triangle * int(rules["triangle_damage"])
	if effective: might *= int(weapon.get("effectiveness_multiplier", rules.get("effectiveness_multiplier", 2)))
	var power := effective_stat(attacker, "magic" if magic and attacker.has("magic") else "str") + int(rb.atk) + (0 if magic and attacker.has("magic") else int(rb.str))
	@warning_ignore("integer_division") # Native magic swords halve integer strength.
	if weapon.get("half_strength", false): power = (power + (1 if weapon.get("round_half_strength_up",false) else 0)) / 2
	var damage := maxi(0, power + might + int(support_attack.atk) + int(attacker.get("ring_bonuses", {}).get("attack", 0)) - defense)
	damage = maxi(0, damage + int(rb.damage) - int(db.guard))
	if weapon.has("fixed_damage"): damage = int(weapon.fixed_damage)
	if weapon.has("ranged_fixed_damage") and _distance(position(attacker), position(defender)) > 1: damage = int(weapon.ranged_fixed_damage)
	@warning_ignore("integer_division") # Intentional integer truncation.
	if weapon.get("weapon_effect", "") == "halve_hp": damage = (int(defender.hp) + 1) / 2
	if weapon.get("weapon_effect", "") == "hp_to_one": damage = maxi(1,int(defender.hp)-1)
	if combat_cheat_active():
		if defender.faction == "player": damage = 0
		elif attacker.faction == "player": damage = 99
	var avoid := defense_speed * 2 + defense_luck + int(support_defense.avo)
	if not bool(defender.get("flying", false)):
		avoid += _terrain_combat_bonus(defender, "avoid")
	@warning_ignore("integer_division") # Intentional integer truncation.
	var hit := int(weapon.get("hit", 0)) + effective_stat(attacker, "skill") * 2 + attack_luck / 2 + triangle * int(rules["triangle_hit"]) + int(support_attack.hit) - avoid
	@warning_ignore("integer_division") # Intentional integer truncation.
	var crit := int(weapon.get("crit", 0)) + effective_stat(attacker, "skill") / 2 + int(support_attack.crit) - defense_luck - int(support_defense.ddg)
	var s_bonus := 5 if int(attacker.get("weapon_exp", {}).get(str(weapon.get("type", "")), 0)) >= 251 else 0
	hit = clampi(hit + s_bonus + int(rb.hit) - int(db.avoid) - int(defender.get("ring_bonuses", {}).get("avoid", 0)), 0, 100)
	crit = clampi(crit + s_bonus + int(rb.crit) - int(db.ddg) + int(attacker.get("critical_bonus", 0)) + int(attacker.get("ring_bonuses", {}).get("crit", 0)), 0, 100)
	if weapon.get("weapon_effect", "") in ["halve_hp","hp_to_one"] or weapon.get("no_critical", false): crit = 0
	if weapon.has("ranged_fixed_damage") and _distance(position(attacker), position(defender)) > 1: crit = 0
	if ([defender.get("weapon",{})]+defender.get("inventory",[])).any(func(item):return item.get("negate_critical",false)): crit = 0
	var triangle_attack: bool = initiating and can_attack and not triangle_attack_members(attacker, defender).is_empty()
	if triangle_attack: hit = 100; crit = 100
	if combat_cheat_active() and attacker.faction == "player": hit = 100
	var strikes := 2 if attacker_speed - defense_speed >= int(rules["double_threshold"]) else 1
	if not initiating and Rogue.count(attacker, "quick_reposte") > 0 and int(attacker.hp) * 2 >= int(attacker.max_hp): strikes = 2
	if weapon.get("weapon_effect", "") in ["halve_hp","hp_to_one"]: strikes = 1
	strikes *= 2 if weapon.get("brave", false) else 1
	strikes = (strikes if weapon.get("unbreakable",false) or str(rules.get("durability_mode", "normal")) == "infinite" else mini(strikes, int(weapon.get("uses", 0)))) if can_attack else 0
	return {"name": attacker["name"], "hp": attacker["hp"], "damage": damage, "hit": hit, "crit": crit, "strikes": strikes, "can_attack": can_attack, "attack_speed": attacker_speed, "triangle_attack": triangle_attack, "luck": attack_luck, "critical_damage_bonus": Rogue.Personal.parameter(attacker, "critical_damage", 10) if Rogue.active(self) and Rogue.Personal.has(attacker, "fe7_unit_55") else 0}

func _terrain_combat_bonus(unit: Dictionary, kind: String) -> int:
	var cell := position(unit)
	var symbol := str(terrain[cell.y])[cell.x] if in_bounds(cell) else "."
	var defaults: Dictionary = rules.get("terrain_class_defaults",{}).get(str(int(unit.get("rom_class_id",0))),{}).get("terrain_bonuses",{}).get(symbol,{})
	return int(unit.get("terrain_bonuses", {}).get(symbol, {}).get(kind, defaults.get(kind,terrain_at(cell).get(kind, 0))))

func forecast(attacker_id: String, defender_id: String) -> Dictionary:
	var attacker := get_unit(attacker_id)
	var defender := get_target(defender_id)
	if not _on_map(attacker) or not _on_map(defender) or not _hostile(attacker, defender) or _concealed_from(attacker, defender):
		return {}
	var old_guard := combat_guard
	var old_guard_cell := combat_guard_cell
	if combat_guard.is_empty() and defender.get("kind", "") != "structure":
		var guard := Rogue.guardian(self, defender, attacker)
		if guard.id != defender.id:
			combat_guard_cell = position(defender)
			defender = guard
			combat_guard = str(guard.id)
	var old_initiator := combat_initiator
	combat_initiator = attacker_id
	var counter := _combat_stats(defender, attacker)
	if attacker.get("weapon", {}).get("cannot_counter", false) or defender.get("weapon", {}).get("cannot_counter", false): counter.can_attack = false; counter.strikes = 0
	var result := {"attacker_id": attacker_id, "defender_id": defender_id, "attacker": _combat_stats(attacker, defender), "defender": counter}
	combat_initiator = old_initiator
	if not combat_guard.is_empty(): result.guardian_id = combat_guard
	combat_guard = old_guard
	combat_guard_cell = old_guard_cell
	return result

func combat_order(attacker: Dictionary, defender: Dictionary, scripted: bool = false) -> Array:
	var preview := {"attacker":_combat_stats(attacker,defender),"defender":_combat_stats(defender,attacker)} if scripted else forecast(str(attacker.id),str(defender.id))
	if preview.is_empty(): return []
	if scripted and (attacker.weapon.get("cannot_counter",false) or defender.weapon.get("cannot_counter",false)): preview.defender.strikes = 0
	var order: Array = []
	var a := int(preview.attacker.strikes)
	var d := int(preview.defender.strikes)
	var a_batch := 2 if attacker.weapon.get("brave", false) else 1
	var d_batch := 2 if defender.weapon.get("brave", false) else 1
	if Rogue.count(defender, "vantage") > 0 and int(defender.hp) * 2 <= int(defender.max_hp):
		for _i in range(mini(d, d_batch)): order.append([defender, attacker])
		d = maxi(0, d - d_batch)
	if Rogue.count(attacker, "desperation") > 0 and int(attacker.hp) * 2 <= int(attacker.max_hp): a_batch = a
	for _round in range(2):
		for _i in range(mini(a, a_batch)): order.append([attacker, defender])
		for _i in range(mini(d, d_batch)): order.append([defender, attacker])
		a = maxi(0, a - a_batch); d = maxi(0, d - d_batch)
	return order

func attack(attacker_id: String, defender_id: String) -> Dictionary:
	var attacker := get_unit(attacker_id)
	var defender := get_target(defender_id)
	if not _can_command(attacker) or defender.is_empty() or int(defender["hp"]) <= 0 or not _hostile(attacker, defender) or not _in_range(attacker, defender) or _concealed_from(attacker, defender):
		return {"ok": false, "strikes": [], "outcome": outcome}
	if defender.get("kind", "") == "structure":
		return _attack_structure(attacker, defender)
	commit_move(attacker_id)
	if attacker.acted or not _in_range(attacker, defender): return {"ok": false, "strikes": [], "outcome": outcome}
	_wake_stationary_defender(defender)
	_run_events("battle", {"attacker_id": attacker_id, "defender_id": defender_id})
	combat_initiator = attacker_id
	var guard := Rogue.guardian(self, defender, attacker)
	if guard.id != defender.id:
		Rogue.use_guardian(self, guard, defender, attacker)
		combat_guard_cell = position(defender)
		defender = guard
		combat_guard = str(guard.id)
	if Rogue.active(self):
		_begin_rogue_combat(attacker, defender)
	if NativeFlags.game(chapter) == "fe6": chapter.fe6_last_battle_items = [int(attacker.weapon.get("rom_item_id",0)),int(defender.weapon.get("rom_item_id",0))]
	var order := combat_order(attacker, defender)
	var strikes: Array = []
	for pair in order:
		if int(pair[0]["hp"]) <= 0 or int(pair[1]["hp"]) <= 0:
			break
		if _armed(pair[0]):
			strikes.append(_strike(pair[0], pair[1]))
	if phase in ["enemy","npc"] or auto_playing:
		# Separate stationary enemies' encounters even when no walk intervenes.
		phase_actions.append({"type": "combat_end"})
	attacker["acted"] = true
	Rogue.after_combat(self, attacker, defender, strikes.any(func(s): return str(s.attacker_id) == attacker_id and int(s.get("damage", 0)) > 0 and not s.get("backfire", false)))
	flush_skill_notifications()
	combat_initiator = ""
	combat_guard = ""
	combat_guard_cell = Vector2i(-1, -1)
	var item_rewards := _collect_drops(strikes)
	preload("res://engine/fe7_campaign_rank.gd").combat(self,attacker,defender)
	var experience := _combat_experience(attacker, defender, strikes)
	if (phase in ["enemy","npc"] or auto_playing) and not experience.is_empty():
		phase_actions.append({"type": "experience", "rewards": experience.duplicate(true)})
	Traps.trigger(self, attacker, true)
	_run_events("unit_defeated", {"attacker_id":attacker_id,"defender_id":defender_id})
	_search_after_action(attacker)
	_check_objective()
	return {"ok": true, "strikes": strikes, "outcome": outcome, "experience": experience, "item_rewards": item_rewards}

func _give_item(unit_id: String, definition: Dictionary, force_convoy: bool = false) -> Dictionary:
	if definition.is_empty():
		return {}
	var item := _normalize_item(definition)
	var recipient := {} if force_convoy else get_unit(unit_id)
	if not force_convoy and recipient.is_empty() and NativeFlags.game(chapter) == "fe6":
		recipient = get_unit("fe6_unit_1")
		if recipient.is_empty(): recipient = get_unit("fe6_unit_1")
		unit_id = str(recipient.get("id", unit_id))
	var destination := "convoy"
	if not recipient.is_empty() and recipient.faction == "player" and int(recipient.hp) > 0 and recipient.inventory.size() < int(rules.inventory_capacity):
		recipient.inventory.append(item)
		destination = "unit"
		events_log.append("%s received %s." % [recipient.name, item.name])
	else:
		inventory.append(item)
		events_log.append("%s was sent to the convoy." % item.name)
	var delivery := {"unit_id": unit_id, "destination": destination, "item": item.duplicate(true)}
	chapter.get_or_add("reward_notices", []).append({"give_item": item.duplicate(true), "item_delivery": delivery, "unit_id": unit_id})
	return delivery

func _attack_structure(attacker: Dictionary, structure: Dictionary) -> Dictionary:
	commit_move(str(attacker.id))
	if get_unit(str(attacker.id)).acted: return {"ok": false, "strikes": [], "outcome": outcome}
	var stats := _combat_stats(attacker, structure)
	if Rogue.active(self): Rogue.Personal.begin_combat(attacker)
	var before := int(structure.hp)
	var damage := int(stats.damage)
	structure.hp = maxi(0, before - damage)
	_consume_use(attacker.weapon, attacker)
	attacker.last_used_weapon = _weapon_signature(attacker.weapon)
	attacker.acted = true
	attacker.canto_active = false
	attacker.canto_remaining = 0
	var strike := {"attacker_id": attacker.id, "defender_id": structure.id, "hit": true, "critical": false, "damage": damage, "previous_hp": before, "remaining_hp": structure.hp, "attacker_stats": stats, "defender_stats": _combat_stats(structure, attacker), "structure": true}
	if phase in ["enemy","npc"] or auto_playing:
		phase_combat.append(strike.duplicate(true))
		phase_actions.append({"type": "strike", "strike": strike.duplicate(true)})
		phase_actions.append({"type": "combat_end"})
	if int(structure.hp) <= 0 and not structure.broken:
		structure.broken = true
		_apply_map_change(structure)
	events_log.append("%s damaged %s for %d." % [attacker.name, structure.name, damage])
	if Rogue.active(self):
		if damage > 0: Rogue.Personal.damaged(attacker, self)
		Rogue.Personal.combat_finished(attacker, structure, self)
		attacker.rogue_tiles_moved = 0
		attacker.rogue_action_taken = true
		if int(structure.hp) > 0 and Rogue.refresh(attacker, "fury", Rogue.count(attacker, "canto") > 0): attacker.rogue_fury = true
		flush_skill_notifications()
	Traps.trigger(self, attacker, true)
	return {"ok": true, "strikes": [strike], "outcome": outcome, "experience": [], "item_rewards": []}

func _apply_map_change(structure: Dictionary) -> void:
	for extra in structure.get("map_changes", []):
		_apply_map_change({"id": structure.get("id", "linked"), "map_change": extra})
	for site in interactions:
		if structure.get("linked_sites", []).has(str(site.get("id", ""))):
			# Closing the other route village is not a visit to that village.
			if site.get("type") == "village" and not site.get("used",false): site.closed_without_visit = true
			site.used = true
			NativeFlags.site(self,site)
	var change: Dictionary = structure.get("map_change", {})
	var rows: Array = change.get("terrain", [])
	for y in range(rows.size()):
		for x in range(str(rows[y]).length()):
			if change.has("mask") and not bool(change.mask[y][x]): continue
			var cell := Vector2i(int(change.get("x", structure.get("x", 0))) + x, int(change.get("y", structure.get("y", 0))) + y)
			if in_bounds(cell):
				var row := str(terrain[cell.y])
				terrain[cell.y] = row.substr(0, cell.x) + str(rows[y])[x] + row.substr(cell.x + 1)
	if rows.is_empty():
		var row := str(terrain[int(structure.y)])
		terrain[int(structure.y)] = row.substr(0, int(structure.x)) + str(structure.get("destroyed_terrain", ".")) + row.substr(int(structure.x) + 1)
	_sync_open_doors()
	if not str(change.get("image", "")).is_empty():
		var patch := change.duplicate(true)
		patch["destructible_id"] = str(structure.get("id", "event"))
		if patch.has("cycle_id"):
			for i in range(map_patches.size()):
				if map_patches[i].get("cycle_id") == patch.cycle_id:
					map_patches[i] = patch
					return
		map_patches.append(patch)

func _sync_open_doors() -> void:
	for site in interactions:
		if chapter.get("dynamic_rom",false) and NativeFlags.game(chapter) == "fe7" and site.get("type") == "door" and in_bounds(position(site)):
			var open: bool = str(terrain[int(site.y)])[int(site.x)] != "D"
			if open and not site.get("used",false):
				site.used = true; site.native_opened = true
			elif not open and site.get("native_opened",false):
				site.used = false; site.erase("native_opened")
			continue
		if site.get("type") == "door" and not site.get("used", false) and in_bounds(position(site)) and str(terrain[int(site.y)])[int(site.x)] != "D":
			site.used = true
			NativeFlags.site(self, site)

func _collect_drops(strikes: Array) -> Array:
	var rewards: Array = []
	for strike in strikes:
		if strike.get("backfire", false) or int(strike.get("remaining_hp", 1)) > 0:
			continue
		var defeated := get_unit(str(strike.get("defender_id", "")))
		var victor := get_unit(str(strike.get("attacker_id", "")))
		if defeated.is_empty() or victor.is_empty() or victor.faction != "player" or int(victor.hp) <= 0 or bool(defeated.get("drop_claimed", false)):
			continue
		var items: Array = defeated.get("stolen_items", []).duplicate(true)
		var item: Dictionary = defeated.get("drop_item", {})
		if not item.is_empty():
			# Preserve uses actually remaining on the enemy's item at defeat.
			for carried in [defeated.weapon] + defeated.inventory:
				if _same_item(carried,item):
					item=carried.duplicate(true)
					break
			if int(item.get("uses",0))>0: items.append(item)
		if items.is_empty() and int(defeated.get("stolen_gold", 0)) <= 0: continue
		defeated["drop_claimed"] = true
		for drop in items:
			drop.erase("droppable")
			rewards.append(_give_item(str(victor.id), drop))
		if int(defeated.get("stolen_gold", 0)) > 0:
			var recovered := int(defeated.stolen_gold)
			gold += recovered
			rewards.append({"unit_id": str(victor.id), "destination": "gold", "gold": recovered})
			events_log.append("Recovered %d gold from %s." % [recovered, defeated.name])
	return rewards

func _combat_experience(attacker: Dictionary, defender: Dictionary, strikes: Array) -> Array:
	var rewards: Array = []
	for pair in [[attacker, defender], [defender, attacker]]:
		var unit: Dictionary = pair[0]
		var opponent: Dictionary = pair[1]
		if unit["faction"] != "player" or int(unit["hp"]) <= 0:
			continue
		var attempted := false
		var dealt_damage := false
		var killed := false
		for strike in strikes:
			if str(strike["attacker_id"]) == str(unit["id"]):
				attempted = true
				dealt_damage = dealt_damage or (int(strike["damage"]) > 0 and not strike.get("backfire", false))
				killed = killed or (int(strike["remaining_hp"]) == 0 and not strike.get("backfire", false))
		if not attempted:
			if rules.get("experience_model", "") in ["gba", "fe6"] and strikes.any(func(strike): return str(strike.get("defender_id", "")) == str(unit.id)):
				rewards.append(_award_experience(unit, 1))
			continue
		var level_difference := int(opponent.get("level", 1)) - int(unit["level"])
		var amount := int(rules["miss_experience"])
		if dealt_damage:
			amount = maxi(1, int(rules["combat_experience"]) + level_difference * int(rules["level_difference_experience"]))
		if killed:
			amount += maxi(0, int(rules["kill_experience"]) + level_difference * int(rules["kill_level_difference_experience"]))
		if rules.get("experience_model", "") in ["gba", "fe6"]:
			var silencer_kill := killed and strikes.any(func(s): return s.get("silencer", false) and s.attacker_id == unit.id)
			amount = preload("res://engine/combat_experience.gd").amount(unit, opponent, dealt_damage, killed, bool(rules.get("normal_mode_experience_bonus", false)), silencer_kill, "fe6" if rules.experience_model == "fe6" else "fe7")
		rewards.append(_award_experience(unit, amount))
	return rewards

func _award_experience(unit: Dictionary, amount: int) -> Dictionary:
	if unit.get("disable_experience",false): amount = 0
	var before_level := int(unit.level)
	var before_exp := int(unit.exp)
	var before_stats := _stat_snapshot(unit)
	var levels: Array = []
	var max_level := maxi(1, int(rules["max_level"]))
	var threshold := maxi(1, int(rules["experience_per_level"]))
	var awarded := maxi(0, amount)
	if unit.faction == "player":
		var scaled := amount * (Rogue.army(self, "fast_learners") + Rogue.Personal.mentor_bonus(self, unit)) + int(unit.get("rogue_exp_fraction", 0))
		@warning_ignore("integer_division") # Intentional integer truncation.
		awarded += scaled / 10
		if Rogue.active(self): unit.rogue_exp_fraction = scaled % 10
	if int(unit["level"]) >= max_level:
		unit["exp"] = 0
		awarded = 0
	else:
		awarded = mini(awarded, (max_level - int(unit["level"])) * threshold - int(unit["exp"]))
		unit["exp"] = int(unit["exp"]) + awarded
		while int(unit["exp"]) >= threshold and int(unit["level"]) < max_level:
			var level_before_stats := _stat_snapshot(unit)
			unit["exp"] = int(unit["exp"]) - threshold
			unit["level"] = int(unit["level"]) + 1
			var gains: Dictionary = {}
			var growths: Dictionary = unit.get("growths", {})
			var caps: Dictionary = rules["stat_caps"].duplicate(true)
			_merge(caps, unit.get("stat_caps", {}))
			for stat in (["max_hp", "str", "magic", "skill", "speed", "luck", "def", "res", "con", "mov"] if unit.has("magic") else ["max_hp", "str", "skill", "speed", "luck", "def", "res", "con", "mov"]):
				var rate := Rogue.growth(self, unit, stat) if Rogue.active(self) else maxi(0, int(growths.get(stat, growths.get("hp", 0) if stat == "max_hp" else 0)))
				@warning_ignore("integer_division") # Intentional integer truncation.
				var gain := rate / 100
				if rate % 100 > 0 and rng.randi_range(0, 99) < rate % 100:
					gain += 1
				gain = mini(gain, maxi(0, int(caps.get(stat, 99)) - int(unit[stat])))
				if gain > 0:
					unit[stat] = int(unit[stat]) + gain
					gains[stat] = gain
					if stat == "max_hp":
						Rogue.heal(unit, gain)
			Rogue.record_level(unit, gains)
			levels.append({"level": int(unit["level"]), "gains": gains, "before_stats": level_before_stats, "after_stats": _stat_snapshot(unit)})
			events_log.append("%s reached level %d." % [unit["name"], int(unit["level"])])
		if int(unit["level"]) >= max_level:
			unit["exp"] = 0
	if awarded > 0:
		if unit.get("faction", "") == "player":
			chapter.earned_experience = int(chapter.get("earned_experience", 0)) + awarded
			if chapter.get("dynamic_rom",false) and unit.get("native_tracks_experience",false):
				chapter.fe7_earned_experience = int(chapter.get("fe7_earned_experience",0))+awarded
				var totals: Dictionary = chapter.get_or_add("fe7_experience",{})
				var character := str(int(unit.get("rom_character_id",0)))
				totals[character] = mini(4000,int(totals.get(character,0))+awarded) # Native battle-record cap.
			if NativeFlags.game(chapter) == "fe6" and NativeFlags.integer(unit.get("rom_character_id",0),1,255):
				var totals: Dictionary = chapter.get_or_add("fe6_experience",{})
				var character := str(int(unit.get("rom_character_id",0)))
				totals[character] = mini(4000,int(totals.get(character,0))+awarded)
		events_log.append("%s gained %d EXP." % [unit["name"], awarded])
	var reward := {"unit_id": unit["id"], "amount": awarded, "levels": levels, "before_level": before_level, "before_exp": before_exp, "after_level": int(unit.level), "after_exp": int(unit.exp), "threshold": threshold, "before_stats": before_stats, "after_stats": _stat_snapshot(unit)}
	var promotion := _auto_promote_lord(unit)
	if not promotion.is_empty(): reward.auto_promotion = promotion
	return reward

func _auto_promote_lord(unit: Dictionary) -> Dictionary:
	if not rules.get("auto_promote_lords", false) or unit.get("faction") != "player" or int(unit.get("level", 1)) < 20 or unit.get("promoted", false): return {}
	var class_id := int(unit.get("rom_class_id", -1))
	if class_id not in ([1] if NativeFlags.game(chapter) == "fe6" else [1, 2, 3]): return {}
	for route in rules.get("promotion_catalog", {}).get("promotions", []):
		if int(route.from_class) != class_id: continue
		var definition := _class_definition(int(route.to_class))
		if definition.is_empty(): continue
		var before := _stat_snapshot(unit)
		_apply_class_change(unit, definition)
		var gains := {}
		for stat in before: gains[stat] = int(unit.get(stat, 0)) - int(before[stat])
		events_log.append("%s automatically promoted to %s." % [unit.name, unit.class_name])
		return {"target_id":unit.id, "promotion":true, "class_name":unit.class_name, "before_stats":before, "after_stats":_stat_snapshot(unit), "stat_gains":gains}
	return {}

func _stat_snapshot(unit: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for stat in (["max_hp", "str", "magic", "skill", "speed", "luck", "def", "res", "con", "mov"] if unit.has("magic") else ["max_hp", "str", "skill", "speed", "luck", "def", "res", "con", "mov"]):
		result[stat] = int(unit.get(stat, 0))
	return result

func _inventory_item(unit: Dictionary, index: int) -> Dictionary:
	if unit.is_empty() or index < 0 or index >= unit.get("inventory", []).size():
		return {}
	return unit["inventory"][index]

func can_equip_weapon(unit: Dictionary, item: Dictionary) -> bool:
	if item.is_empty() or item.get("kind", "weapon") != "weapon" or int(item.get("uses", 0)) <= 0:
		return false
	if unit.has("weapon_types") and not unit.weapon_types.has(str(item.get("type", ""))):
		return false
	if not _meets_weapon_rank(unit, item): return false
	var required := int(item.get("required_unit_flags",0))
	if int(unit.get("native_unit_flags",unit.get("fe6_unit_flags",0))) & required != required: return false
	if item.has("allowed_character_ids") and not _has_numeric_id(item.allowed_character_ids, int(unit.get("rom_character_id", -1))):
		return false
	if item.has("allowed_class_ids") and not _has_numeric_id(item.allowed_class_ids, int(unit.get("rom_class_id", -1))): return false
	return not item.has("allowed_units") or item.allowed_units.has(str(unit.id))

func _meets_weapon_rank(unit: Dictionary, item: Dictionary) -> bool:
	# Packs without rank metadata retain their existing type-based permissions.
	return not unit.has("weapon_exp") or int(unit.weapon_exp.get(str(item.get("type", "")), 0)) >= int(item.get("required_rank", 0))

func weapon_rank_progress(unit_or_id: Variant) -> Array:
	var unit: Dictionary = get_unit(str(unit_or_id)) if unit_or_id is String else unit_or_id
	if unit.is_empty(): return []
	var points: Dictionary = unit.get("weapon_exp", {})
	var kinds: Array = unit.get("weapon_types", []).duplicate()
	for kind in points:
		if not kinds.has(kind) and int(points[kind]) > 0: kinds.append(kind)
	var result: Array = []
	var thresholds: Dictionary = rules.get("weapon_rank_thresholds", {})
	for kind in kinds:
		var value := int(points.get(kind, 0))
		var rank := "—"
		var minimum := 0
		var next := 0
		var next_rank := ""
		for name in thresholds:
			var threshold := int(thresholds[name])
			if value >= threshold:
				rank = str(name)
				minimum = threshold
			elif next == 0:
				next = threshold
				next_rank = str(name)
		var cap := _weapon_exp_cap(unit, str(kind))
		var maxed := value >= cap
		var progress := 1.0 if next <= minimum else clampf(float(value - minimum) / float(next - minimum), 0.0, 1.0)
		result.append({"type": str(kind), "rank": rank, "points": value, "minimum": minimum, "next": next, "next_rank": next_rank, "progress": progress, "maxed": maxed, "cap": cap})
	return result

func _weapon_exp_cap(unit: Dictionary, kind: String) -> int:
	var cap := int(rules.get("weapon_exp_cap", 251))
	if not bool(unit.get("promoted", false)): return mini(cap, int(rules.get("weapon_exp_unpromoted_cap", 181)))
	if not bool(unit.get("multiple_s_ranks", false)):
		var top := int(rules.get("weapon_rank_thresholds", {}).get("S", cap))
		for other in unit.get("weapon_exp", {}):
			if other != kind and int(unit.weapon_exp[other]) >= top: return mini(cap, top - 1)
	return cap

func _award_weapon_experience(unit: Dictionary, item: Dictionary, killed: bool = false) -> Dictionary:
	if item.get("no_weapon_exp", false): return {}
	var kind := str(item.get("type", ""))
	var amount := maxi(0, int(item.get("weapon_exp", 0)))
	# The use that exhausts a weapon or staff yields no WEXP.
	if kind.is_empty() or amount == 0 or int(item.get("uses", 0)) <= 0: return {}
	if not unit.has("weapon_exp"):
		unit.weapon_exp = {}
		for supported in unit.get("weapon_types", [kind]): unit.weapon_exp[supported] = 1
	var previous := int(unit.weapon_exp.get(kind, 0))
	if previous <= 0: return {}
	if killed: amount *= int(rules.get("weapon_exp_kill_multiplier", 2))
	if unit.faction == "player":
		var scaled := amount * (Rogue.army(self, "sparring_sessions") + Rogue.Personal.mentor_bonus(self, unit) + (Rogue.Personal.parameter(unit, "xp_tenths", 1) if Rogue.active(self) and Rogue.Personal.has(unit, "fe7_unit_19") else 0)) + int(unit.get("rogue_wexp_fraction", 0))
		@warning_ignore("integer_division") # Intentional integer truncation.
		amount += scaled / 10
		if Rogue.active(self): unit.rogue_wexp_fraction = scaled % 10
	var total := maxi(previous, mini(_weapon_exp_cap(unit, kind), previous + amount))
	unit.weapon_exp[kind] = total
	return {"unit_id": str(unit.id), "type": kind, "previous": previous, "total": total, "gained": total - previous}

func _weapon_signature(item: Dictionary) -> String:
	return str(item.get("rom_item_id", "")) + ":" + str(item.get("name", "")) + ":" + str(item.get("type", ""))

func _weapon_index(key: String) -> int:
	if key in ["", "equipped"]: return -1
	if key.begins_with("inventory:") and key.trim_prefix("inventory:").is_valid_int():
		return int(key.trim_prefix("inventory:"))
	return -2

func _unit_with_weapon(id: String, key: String) -> Dictionary:
	var unit := get_unit(id)
	if unit.is_empty(): return {}
	if key.is_empty(): return unit
	var index := _weapon_index(key)
	var weapon: Dictionary = emplacement_weapon(unit) if key == "emplacement" else (unit.weapon if index == -1 else _inventory_item(unit, index))
	if not can_equip_weapon(unit, weapon): return {}
	var copy := unit.duplicate(true)
	copy.weapon = weapon.duplicate(true)
	return copy

func emplacement_weapon(unit: Dictionary) -> Dictionary:
	if unit.is_empty() or not _on_map(unit): return {}
	for site in chapter.get("emplacements", []):
		if position(unit) == Vector2i(site.x, site.y) and can_equip_weapon(unit, site.weapon):
			return site.weapon
	return {}

func weapon_options(id: String, target_id: String = "", include_approach: bool = true) -> Array:
	var unit := get_unit(id)
	var options: Array = []
	if unit.is_empty() or not _can_command(unit): return options
	var siege := emplacement_weapon(unit)
	if not siege.is_empty() and _weapon_signature(unit.weapon) != _weapon_signature(siege):
		var preview := forecast_with_weapon(id, target_id, "emplacement") if not target_id.is_empty() else {}
		options.append({"key": "emplacement", "index": -2, "weapon": siege.duplicate(true), "can_attack": preview.get("attacker", {}).get("can_attack", false), "approach": attack_approach(id, target_id, "emplacement") if include_approach and not target_id.is_empty() else {"ok": false}, "last_used": _weapon_signature(siege) == str(unit.last_used_weapon), "forecast": preview})
	for index in range(-1, unit.inventory.size()):
		var item: Dictionary = unit.weapon if index == -1 else unit.inventory[index]
		if not can_equip_weapon(unit, item): continue
		var key := "equipped" if index == -1 else "inventory:%d" % index
		var preview := forecast_with_weapon(id, target_id, key) if not target_id.is_empty() else {}
		options.append({"key": key, "index": index, "weapon": item.duplicate(true), "can_attack": bool(preview.get("attacker", {}).get("can_attack", false)), "approach": attack_approach(id, target_id, key) if include_approach and not target_id.is_empty() else {"ok": false}, "last_used": _weapon_signature(item) == str(unit.last_used_weapon), "forecast": preview})
	options.sort_custom(func(a, b): return (a.last_used and not b.last_used) if a.last_used != b.last_used else int(a.index) < int(b.index))
	return options

func can_attack_with_any_weapon(id: String, target_id: String) -> bool:
	# Command visibility needs only range/equipment legality, not a movement
	# search and two combat forecasts for every weapon of every map unit.
	var unit := get_unit(id)
	var target := get_target(target_id)
	if not _can_command(unit) or not _on_map(target) or not _hostile(unit, target) or _concealed_from(unit, target): return false
	for item in [unit.weapon] + unit.inventory + [emplacement_weapon(unit)]:
		if not can_equip_weapon(unit, item): continue
		var armed := unit.duplicate()
		armed.weapon = item
		if _in_range(armed, target): return true
	return false

func forecast_with_weapon(attacker_id: String, defender_id: String, key: String) -> Dictionary:
	var attacker := _unit_with_weapon(attacker_id, key)
	var defender := get_target(defender_id)
	if not _on_map(attacker) or not _on_map(defender) or not _hostile(attacker, defender) or _concealed_from(attacker, defender):
		return {}
	if Rogue.active(self):
		var previous_initiator := combat_initiator
		var previous_guard := combat_guard
		var previous_guard_cell := combat_guard_cell
		var guard := Rogue.guardian(self, defender, attacker)
		if guard.id != defender.id:
			combat_guard_cell = position(defender)
			defender = guard
			combat_guard = str(guard.id)
		combat_initiator = attacker_id
		var counter := _combat_stats(defender, attacker)
		if attacker.weapon.get("cannot_counter", false) or defender.weapon.get("cannot_counter", false): counter.can_attack = false; counter.strikes = 0
		var result := {"attacker_id": attacker_id, "defender_id": defender_id, "weapon_key": key, "attacker": _combat_stats(attacker, defender), "defender": counter}
		if not combat_guard.is_empty(): result.guardian_id = combat_guard
		combat_initiator = previous_initiator; combat_guard = previous_guard
		combat_guard_cell = previous_guard_cell
		return result
	return {"attacker_id": attacker_id, "defender_id": defender_id, "weapon_key": key, "attacker": _combat_stats(attacker, defender), "defender": _combat_stats(defender, attacker)}

func preferred_weapon(id: String, target_id: String) -> String:
	var unit := get_unit(id)
	var best := ""
	var score := -1.0
	for option in weapon_options(id, target_id, false):
		if not option.can_attack: continue
		if int(unit.get("manual_weapon_turn", -1)) == turn and option.key == "equipped": return "equipped"
		var stats: Dictionary = option.forecast.attacker
		var expected := float(stats.damage) * float(stats.hit) / 100.0 * int(stats.strikes)
		if expected > score: score = expected; best = str(option.key)
	return best

func best_attack_approach(id: String, target_id: String) -> Dictionary:
	for option in weapon_options(id):
		var approach := attack_approach(id, target_id, str(option.key))
		if approach.get("ok", false):
			approach["weapon_key"] = option.key
			return approach
	return {"ok": false}

func attack_with_weapon(attacker_id: String, defender_id: String, key: String) -> Dictionary:
	var unit := get_unit(attacker_id)
	var chosen := _unit_with_weapon(attacker_id, key)
	var target := get_target(defender_id)
	if not _can_command(unit) or chosen.is_empty() or target.is_empty() or int(target.hp) <= 0 or not _hostile(unit, target) or not _in_range(chosen, target):
		return {"ok": false, "strikes": [], "outcome": outcome}
	var index := _weapon_index(key)
	if index >= 0 and not equip_item(attacker_id, index):
		return {"ok": false, "strikes": [], "outcome": outcome}
	if key == "emplacement":
		var previous: Dictionary = unit.weapon
		unit.weapon = emplacement_weapon(unit)
		var result := attack(attacker_id, defender_id)
		unit.weapon = previous
		return result
	return attack(attacker_id, defender_id)

func equip_item(unit_id: String, index: int, manual: bool = true) -> bool:
	var unit := get_unit(unit_id)
	if not _can_command(unit) or unit["faction"] != "player":
		return false
	var item := _inventory_item(unit, index)
	if not can_equip_weapon(unit, item):
		return false
	var previous: Dictionary = unit["weapon"]
	unit["weapon"] = item
	if manual: unit.manual_weapon_turn = turn
	if previous.is_empty():
		unit["inventory"].remove_at(index)
	else:
		unit["inventory"][index] = previous
	events_log.append("%s equipped %s." % [unit["name"], item["name"]])
	return true

func trade_item(unit_id: String, other_id: String, index: int) -> bool:
	var actor := get_unit(unit_id)
	if actor.is_empty() or index < 0 or index >= actor.inventory.size(): return false
	var recipient := get_unit(other_id)
	return not recipient.is_empty() and swap_items(unit_id, other_id, index, recipient.inventory.size())

func can_trade(actor_id: String, other_id: String) -> bool:
	var actor := get_unit(actor_id)
	var other := get_unit(other_id)
	if not _can_act(actor) or actor.faction != "player" or not _on_map(other) or other.faction != "player" or actor_id == other_id:
		return false
	if actor.canto_active and (actor.moved or pending_moves.has(actor_id)): return false
	return _distance(position(actor), position(other)) == 1

func trade_partners(actor_id: String) -> Array:
	var partners: Array = []
	for unit in units:
		if can_trade(actor_id, str(unit.id)): partners.append(unit)
	return partners

func can_access_supply(id: String) -> bool:
	var unit := get_unit(id)
	if preparing() and not unit.is_empty() and unit.faction == "player" and int(unit.hp) > 0: return true
	if not _on_map(unit) or unit.faction != "player" or phase != "player" or not outcome.is_empty(): return false
	if not pending_moves.is_empty() and not pending_moves.has(id): return false
	if str(unit.get("id", "")) == "convoy_merchant": return true
	if str(rules.get("supply_access", "lords")) == "anywhere": return true
	if not _can_command(unit): return false
	if unit.get("supply_provider", false): return true
	for other in units:
		if other.faction == "player" and other.get("supply_provider", false) and _on_map(other) and _distance(position(unit), position(other)) <= int(rules.get("supply_range", 1)): return true
	return false

func preparing() -> bool:
	return turn == 1 and not chapter.get("deployment_complete", false) and not chapter.get("deployment", {}).get("slots", []).is_empty()

func _commit_supply_exchange(unit: Dictionary) -> bool:
	if preparing(): return true
	var was_acted := bool(unit.acted)
	commit_move(str(unit.id))
	if not was_acted and unit.acted: return false
	# Like trading, storage preserves the remaining action and mounted movement.
	# The optional anytime access never restores a spent action or Canto budget.
	if not unit.acted and not unit.canto_active:
		unit.traded = true
		unit.moved = not bool(unit.get("canto", false)) or int(unit.move_spent) >= int(unit.mov)
	return true

func supply_store(id: String, slot: int) -> Dictionary:
	if not can_access_supply(id): return {"ok": false, "reason": "Move beside a lord to access Supply."}
	var unit := get_unit(id)
	if not _valid_slot(unit, slot): return {"ok": false, "reason": "Choose an item to store."}
	var item := _slot_item(unit, slot)
	if item.is_empty() or item.get("untradeable", false): return {"ok": false, "reason": "This item cannot be stored."}
	if not _commit_supply_exchange(unit): return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	inventory.append(item)
	_put_slot(unit, slot, {})
	events_log.append("%s stored %s in Supply." % [unit.name, item.get("name", "Item")])
	return {"ok": true}

func supply_take(id: String, index: int) -> Dictionary:
	if not can_access_supply(id): return {"ok": false, "reason": "Move beside a lord to access Supply."}
	var unit := get_unit(id)
	if index < 0 or index >= inventory.size(): return {"ok": false, "reason": "Choose an item from Supply."}
	if unit.inventory.size() >= int(rules.inventory_capacity): return {"ok": false, "reason": "This unit's inventory is full. Store an item first."}
	var item := _normalize_item(inventory[index])
	if not _commit_supply_exchange(unit): return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	inventory.remove_at(index)
	unit.inventory.append(item)
	events_log.append("%s took %s from Supply." % [unit.name, item.get("name", "Item")])
	return {"ok": true}

func inventory_slots(id: String) -> Array:
	var unit := get_unit(id)
	if unit.is_empty(): return []
	var slots: Array = [{"slot": -1, "item": unit.weapon.duplicate(true), "equipped": true}]
	for index in range(unit.inventory.size()):
		slots.append({"slot": index, "item": unit.inventory[index].duplicate(true), "equipped": false})
	if unit.inventory.size() < int(rules.inventory_capacity):
		slots.append({"slot": unit.inventory.size(), "item": {}, "equipped": false})
	return slots

func _slot_item(unit: Dictionary, slot: int) -> Dictionary:
	return unit.weapon if slot == -1 else _inventory_item(unit, slot)

func _valid_slot(unit: Dictionary, slot: int) -> bool:
	return slot == -1 or (slot >= 0 and slot <= unit.inventory.size() and slot < int(rules.inventory_capacity))

func _put_slot(unit: Dictionary, slot: int, item: Dictionary) -> void:
	if slot == -1:
		unit.weapon = item
	elif slot == unit.inventory.size():
		if not item.is_empty(): unit.inventory.append(item)
	elif item.is_empty():
		unit.inventory.remove_at(slot)
	else:
		unit.inventory[slot] = item

func swap_items(actor_id: String, other_id: String, actor_slot: int, other_slot: int) -> bool:
	if not can_trade(actor_id, other_id): return false
	var actor := get_unit(actor_id)
	var other := get_unit(other_id)
	if not _valid_slot(actor, actor_slot) or not _valid_slot(other, other_slot): return false
	var a := _slot_item(actor, actor_slot)
	var b := _slot_item(other, other_slot)
	if a.is_empty() and b.is_empty(): return false
	if a.get("untradeable", false) or b.get("untradeable", false): return false
	if actor_slot == -1 and not b.is_empty() and not can_equip_weapon(actor, b): return false
	if other_slot == -1 and not a.is_empty() and not can_equip_weapon(other, a): return false
	commit_move(actor_id)
	if get_unit(actor_id).acted: return false
	_put_slot(actor, actor_slot, b)
	_put_slot(other, other_slot, a)
	if not actor.canto_active:
		# Trading commits the approach but preserves the unit's main action.
		# Mounted units may use their remaining movement before that action.
		actor.traded = true
		actor.moved = not bool(actor.get("canto", false)) or int(actor.move_spent) >= int(actor.mov)
	events_log.append("%s and %s traded items." % [actor.name, other.name])
	return true

func use_item(unit_id: String, index: int, target_id: String = "", destination: Vector2i = Vector2i(-1, -1), repair_slot: int = -2) -> Dictionary:
	var unit := get_unit(unit_id)
	if unit.get("rogue_fury", false): return {"ok": false, "reason": "Deathmatch allows only another attack or Wait."}
	if not _can_command(unit) or (not pending_moves.is_empty() and not pending_moves.has(unit_id)):
		return {"ok": false, "reason": "This unit cannot act."}
	var item := _inventory_item(unit, index)
	if item.is_empty() or int(item.get("uses", 0)) <= 0:
		return {"ok": false, "reason": "The item has no remaining uses."}
	if unit.faction != "player" and item.get("kind", "") != "staff": return {"ok": false, "reason": "Only staff actions are available."}
	if item.get("kind", "") == "trap": return Traps.place(self, unit, index, destination)
	if is_promotion_item(item):
		if not target_id.is_empty() and target_id != unit_id: return {"ok": false, "reason": "Promotion items can only be used on the acting unit."}
		return promote_unit(unit_id, index)
	var target := get_unit(unit_id if target_id.is_empty() else target_id)
	if item.get("kind", "") == "staff" and item.get("staff_effect", "") in ["warp", "rescue", "repair", "torch", "unlock"]:
		return Staff.execute(self, unit, index, target, destination, repair_slot)
	if not _on_map(target) or (_hostile(unit, target) and not item.has("inflict_status")):
		return {"ok": false, "reason": "Choose a living ally."}
	var is_staff: bool = str(item.get("kind", "")) == "staff"
	if item.has("ring_bonuses"):
		if not unit.get("can_play", false) or target.id == unit.id or target.faction != "player" or _distance(position(unit),position(target)) != 1:
			return {"ok": false, "reason": "A dancer or bard can use this ring on an adjacent ally."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		target.ring_bonuses = item.ring_bonuses.duplicate(true)
		_consume_use(item, unit)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		var reward := _award_experience(unit, int(unit.get("play_experience", 10)))
		events_log.append("%s used %s on %s." % [unit.name, item.name, target.name])
		return {"ok": true, "target_id": str(target.id), "item_name": str(item.name), "temporary_bonuses": target.ring_bonuses.duplicate(), "experience": [reward], "levels": reward.levels}
	if not is_staff and str(item.get("kind", "")) != "consumable":
		return {"ok": false, "reason": "This item cannot be used."}
	if is_staff:
		if not can_use_staff(unit, item): return {"ok": false, "reason": "This unit cannot use that staff."}
		if not helpful_targets(unit_id, index).has(str(target.id)):
			return {"ok": false, "reason": "Choose an ally who benefits from this staff within range."}
	elif target["id"] != unit_id:
		return {"ok": false, "reason": "Healing consumables can only be used on the acting unit."}
	if item.has("inflict_status"):
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		var accuracy := status_staff_accuracy(unit, target)
		var hit := rng.randi_range(0, 99) < accuracy
		if hit:
			target.status = str(item.inflict_status)
			target.status_turns = int(item.get("status_duration", 5))
		_consume_use(item, unit)
		var status_result := {"ok": true, "target_id": str(target.id), "status_hit": hit, "status": str(item.inflict_status), "item_name": str(item.name), "uses_left": int(item.uses)}
		status_result.merge(_staff_rewards(unit, item), true)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		events_log.append("%s used %s on %s: %s." % [unit.name, item.name, target.name, "hit" if hit else "miss"])
		return status_result
	if item.has("cure_status"):
		if str(target.get("status", "")) != str(item.cure_status): return {"ok": false, "reason": "This unit does not have that condition."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		target.status = ""; target.status_turns = 0
		_consume_use(item, unit)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		return {"ok": true, "target_id": unit_id, "restored": true, "item_name": str(item.name), "experience": []}
	if item.has("vision_bonus"):
		if int(rules.get("fog_radius", 0)) <= 0: return {"ok": false, "reason": "There is no fog to illuminate."}
		if int(unit.get("vision_bonus", 0)) >= int(item.vision_bonus): return {"ok": false, "reason": "This unit's torch is already at full strength."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		unit.vision_bonus = int(item.vision_bonus)
		_consume_use(item, unit)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		var vision_result := {"ok": true, "target_id": unit_id, "item_name": item.name, "vision_bonus": unit.vision_bonus, "experience": []}
		if is_staff: vision_result.merge(_staff_rewards(unit, item), true)
		return vision_result
	if item.has("temporary_bonuses"):
		var bonuses: Dictionary = {}
		for key in item.temporary_bonuses:
			if key not in ["str", "skill", "speed", "def", "res", "luck"]: continue
			var value := maxi(0, int(item.temporary_bonuses[key]))
			if value > int(target.temporary_bonuses.get(key, 0)): bonuses[key] = value
		if bonuses.is_empty(): return {"ok": false, "reason": "This item's protection is already at full strength."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		target.temporary_bonuses.merge(bonuses, true)
		_consume_use(item, unit)
		var staff_reward := _staff_rewards(unit, item) if is_staff else {}
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		events_log.append("%s used %s." % [unit.name, item.name])
		var bonus_result := {"ok": true, "temporary_bonuses": bonuses, "target_id": str(target.id), "item_name": item.name, "uses_left": int(item.uses), "experience": [], "levels": []}
		bonus_result.merge(staff_reward, true)
		return bonus_result
	if is_staff and str(item.get("staff_effect", "")) == "restore":
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		target.status = ""
		target.status_turns = 0
		_consume_use(item, unit)
		var restore_result := {"ok": true, "target_id": str(target.id), "restored": true, "item_name": str(item.name), "uses_left": int(item.uses)}
		restore_result.merge(_staff_rewards(unit, item), true)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		events_log.append("%s restored %s." % [unit.name, target.name])
		return restore_result
	if item.has("growth_boost"):
		if unit.get("growth_boost_used",false): return {"ok":false,"reason":"This unit has already received a growth boost."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok":false,"reason":"A hidden enemy blocked the movement."}
		var amount := int(item.growth_boost)
		for key in ["max_hp","str","skill","speed","luck","def","res"]:
			unit.growths[key] = int(unit.growths.get(key,unit.growths.get("hp",0) if key == "max_hp" else 0))+amount
		unit.growth_boost_used = true
		_consume_use(item,unit)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		events_log.append("%s used %s." % [unit.name,item.name])
		return {"ok":true,"growth_boost":amount,"target_id":unit_id,"item_name":item.name,"experience":[],"levels":[]}
	if item.has("stat_boosts"):
		var gains: Dictionary = {}
		for key in item.stat_boosts:
			if key not in ["max_hp", "str", "skill", "speed", "def", "res", "luck", "con", "mov"]: continue
			var cap := int(unit.get("stat_caps", {}).get(key, rules.stat_caps.get(key, 60)))
			var gain := mini(maxi(0, cap - int(unit.get(key, 0))), int(item.stat_boosts[key]))
			if gain > 0: gains[key] = gain
		if gains.is_empty(): return {"ok": false, "reason": "This unit has already reached the item's stat limit."}
		commit_move(unit_id)
		if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		for key in gains: unit[key] = int(unit.get(key, 0)) + int(gains[key])
		if gains.has("max_hp"): Rogue.heal(unit, int(gains.max_hp))
		_consume_use(item, unit)
		if int(item.uses) <= 0: unit.inventory.remove_at(index)
		_finish_noncombat(unit)
		if is_staff: Rogue.after_action(self, unit, "staff_attack" if _hostile(unit, target) else "assist")
		events_log.append("%s used %s." % [unit.name, item.name])
		return {"ok": true, "stat_gains": gains, "target_id": unit_id, "item_name": item.name, "uses_left": int(item.uses), "experience": [], "levels": []}
	var healing := maxi(0, int(item.get("healing", 0)))
	if is_staff:
		healing += maxi(0, effective_stat(unit, "magic" if unit.has("magic") else "str") if Rogue.active(self) else int(unit.get("magic", unit["str"])))
	if bool(item.get("healing_full", false)): healing = int(target.max_hp)
	if is_staff and Rogue.active(self): healing = Rogue.Personal.healing_amount(unit, healing)
	var previous_hp := int(target.hp)
	var healed := mini(healing, int(target["max_hp"]) - int(target["hp"])) if Rogue.Personal.FE6.can_heal(target) else 0
	var saint: bool = item.get("staff_effect","") == "saint"
	if healed <= 0 and not (saint and units.any(func(u):return _on_map(u) and not _hostile(unit,u) and ((int(u.hp)<int(u.max_hp) and Rogue.Personal.FE6.can_heal(u)) or u.get("status","") not in ["","none"]))):
		return {"ok": false, "reason": "The target cannot recover HP right now." if not Rogue.Personal.FE6.can_heal(target) else "The target does not need healing."}
	commit_move(unit_id)
	if get_unit(unit_id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	target["hp"] = int(target["hp"]) + healed
	var total_healed := healed
	if is_staff and item.get("heal_all", false):
		var limits := item_range(unit,item)
		for ally in units:
			if ally.id != target.id and _on_map(ally) and not _hostile(unit,ally) and _distance(position(unit),position(ally)) <= limits.y:
				var amount := (int(ally.max_hp) if item.get("healing_full",false) else healing) if Rogue.Personal.FE6.can_heal(ally) else 0
				total_healed += mini(int(ally.max_hp) - int(ally.hp), amount)
				ally.hp = mini(int(ally.max_hp),int(ally.hp)+amount)
	if saint:
		for ally in units:
			if _on_map(ally) and not _hostile(unit,ally): ally.status = "none"; ally.status_turns = 0
	_consume_use(item, unit)
	_finish_noncombat(unit)
	if is_staff and Rogue.active(self): Rogue.Personal.healed(self, unit, healed, target)
	if is_staff: Rogue.after_action(self, unit, "assist", total_healed)
	var result := {"ok": true, "healed": healed, "previous_hp": previous_hp, "remaining_hp": int(target.hp), "max_hp": int(target.max_hp), "target_id": target["id"], "item_name": item["name"], "uses_left": int(item["uses"]), "experience": [], "levels": []}
	events_log.append("%s used %s: %s recovered %d HP." % [unit["name"], item["name"], target["name"], healed])
	if int(item["uses"]) == 0:
		unit["inventory"].remove_at(index)
	if is_staff:
		result.merge(_staff_rewards(unit, item), true)
	return result

func set_promotion_catalog(catalog: Dictionary) -> void:
	# Packs install the catalog after loading or restoring a chapter. Movement
	# tables are safe to refresh independently of earned stats and class changes.
	rules.promotion_catalog = catalog.duplicate(true)
	for unit in Army.all_units(self):
		var definition := _class_definition(int(unit.get("rom_class_id", -1)))
		for key in ["movement_costs", "movement_costs_rain", "terrain_bonuses", "stat_caps"]:
			if definition.has(key): unit[key] = definition[key].duplicate(true)
		for key in ["experience_power", "experience_bonus", "experience_defeat_bonus", "critical_bonus", "promoted", "silencer"]:
			if definition.has(key): unit[key] = definition[key]

func _class_definition(class_id: int) -> Dictionary:
	return rules.get("promotion_catalog", {}).get("classes", {}).get(str(class_id), {})

func is_promotion_item(item: Dictionary) -> bool:
	if item.get("kind", "") == "promotion" or item.get("promotion", false): return true
	var item_id := int(item.get("rom_item_id", -1))
	if item_id < 0: return false
	for route in rules.get("promotion_catalog", {}).get("promotions", []):
		if _has_numeric_id(route.get("items", []), item_id): return true
	return false

func promotion_options(id: String, index: int) -> Array:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.faction != "player": return []
	var item := _inventory_item(unit, index)
	if item.is_empty() or int(item.get("uses", 0)) <= 0: return []
	var result: Array = []
	for route in rules.get("promotion_catalog", {}).get("promotions", []):
		if int(route.get("from_class", -1)) != int(unit.get("rom_class_id", -2)): continue
		if not _has_numeric_id(route.get("items", []), int(item.get("rom_item_id", -3))): continue
		var preview := promotion_preview(id, index, int(route.get("to_class", -1)))
		if preview.ok: result.append(preview)
	return result

func promotion_preview(id: String, index: int, target_class: int = -1) -> Dictionary:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.faction != "player" or (not pending_moves.is_empty() and not pending_moves.has(id)):
		return {"ok": false, "reason": "This unit cannot act."}
	var item := _inventory_item(unit, index)
	if item.is_empty() or int(item.get("uses", 0)) <= 0: return {"ok": false, "reason": "A promotion item with remaining uses is required."}
	var primary := str(chapter.get("route", "fe7_unit_2" if str(chapter.get("id", "")).contains("fe7_hec_") else "fe7_unit_1"))
	if int(item.get("rom_item_id", -1)) == 0x89 and id == primary:
		return {"ok": false, "reason": "The primary Lord promotes automatically through the story."}
	var class_id := int(unit.get("rom_class_id", -1))
	var route: Dictionary = {}
	for candidate in rules.get("promotion_catalog", {}).get("promotions", []):
		if int(candidate.get("from_class", -2)) != class_id: continue
		if target_class >= 0 and int(candidate.get("to_class", -1)) != target_class: continue
		if not _has_numeric_id(candidate.get("items", []), int(item.get("rom_item_id", -3))): continue
		route = candidate
		break
	if route.is_empty(): return {"ok": false, "reason": "This class cannot promote with %s." % str(item.get("name", "that item"))}
	var minimum := int(route.get("minimum_level", rules.get("promotion_minimum_level", 10)))
	if int(unit.level) < minimum: return {"ok": false, "reason": "Reach level %d before using %s." % [minimum, str(item.name)]}
	var definition := _class_definition(int(route.to_class))
	if definition.is_empty(): return {"ok": false, "reason": "The promoted class is not available in this content pack."}
	var preview := unit.duplicate(true)
	_apply_class_change(preview, definition)
	var gains: Dictionary = {}
	for key in _stat_snapshot(unit):
		if int(preview.get(key, 0)) != int(unit.get(key, 0)): gains[key] = int(preview.get(key, 0)) - int(unit.get(key, 0))
	return {"ok": true, "unit_id": id, "from_class": class_id, "to_class": int(route.to_class), "class_name": str(definition.get("class_name", definition.get("class", "Promoted class"))), "minimum_level": minimum, "stat_gains": gains, "before_stats": _stat_snapshot(unit), "after_stats": _stat_snapshot(preview), "weapon_exp": preview.get("weapon_exp", {}).duplicate(true)}

func promote_unit(id: String, index: int, target_class: int = -1) -> Dictionary:
	var result := promotion_preview(id, index, target_class)
	if not result.ok: return result
	var unit := get_unit(id)
	var item := _inventory_item(unit, index)
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	_apply_class_change(unit, _class_definition(int(result.to_class)))
	# Promotion follows item durability independently of weapon durability.
	_consume_use(item, unit)
	result.merge({"promotion": true, "target_id": id, "item_name": str(item.name), "uses_left": int(item.uses), "experience": [], "levels": []}, true)
	if int(item.uses) == 0: unit.inventory.remove_at(index)
	_finish_noncombat(unit)
	events_log.append("%s promoted to %s." % [unit.name, unit.class_name])
	return result

func _apply_class_change(unit: Dictionary, definition: Dictionary) -> void:
	var original := _class_definition(int(unit.get("rom_class_id", -1)))
	var caps: Dictionary = rules.stat_caps.duplicate(true)
	_merge(caps, definition.get("stat_caps", {}))
	var hp_before := int(unit.max_hp)
	for key in ["max_hp", "str", "skill", "speed", "luck", "def", "res"]:
		var gain := int(definition.get("promotion_gains", {}).get(key, 0))
		if definition.get("promotion_base_difference", false): gain = int(definition.get("base_stats", {}).get(key, 0)) - int(original.get("base_stats", {}).get(key, 0))
		unit[key] = clampi(int(unit.get(key, 0)) + gain, 1 if key == "max_hp" else 0, int(caps.get(key, 60)))
	for key in ["con", "mov"]:
		var old_base := int(original.get("base_stats", {}).get(key, unit.get(key, 0)))
		var new_base := int(definition.get("base_stats", {}).get(key, old_base))
		unit[key] = clampi(int(unit.get(key, 0)) + new_base - old_base, 0, int(caps.get(key, 30)))
	if Rogue.active(self) and unit.has("magic"): unit.magic = mini(int(caps.get("str", 30)), int(unit.magic) + int(definition.get("promotion_gains", {}).get("str", 0)))
	Rogue.heal(unit, int(unit.max_hp) - hp_before)
	unit.level = 1
	unit.exp = 0
	unit.rom_class_id = int(definition.get("rom_class_id", unit.get("rom_class_id", -1)))
	unit.class_name = str(definition.get("class_name", definition.get("class", "Promoted class")))
	unit.stat_caps = caps
	unit.promoted = bool(definition.get("promoted", true))
	unit.multiple_s_ranks = bool(definition.get("multiple_s_ranks", false))
	if definition.has("can_steal"): unit.can_steal = bool(definition.can_steal)
	for key in ["experience_power", "experience_bonus", "experience_defeat_bonus", "boss", "critical_bonus"]:
		if definition.has(key): unit[key] = definition[key]
	for key in ["canto", "flying", "mounted", "can_use_staves", "can_lockpick", "can_play", "silencer"]: unit[key] = bool(definition.get(key, false))
	for key in ["weapon_types", "movement_costs", "movement_costs_rain", "terrain_bonuses"]:
		if definition.has(key): unit[key] = definition[key].duplicate(true)
	if definition.has("fe6_class_flags"):
		preload("res://engine/fe6_unit_traits.gd").apply(unit,int(definition.fe6_class_flags),int(unit.get("fe6_personal_flags",0)))
	if Rogue.active(self):
		unit.rogue_native_types = unit.get("weapon_types", []).duplicate()
		for kind in unit.get("rogue_learned_types", []):
			if not unit.get_or_add("weapon_types", []).has(kind): unit.weapon_types.append(kind)
	if definition.has("sprites"):
		unit.sprite = str(definition.sprites.get(str(unit.faction), unit.get("sprite", "")))
	elif definition.has("sprite"): unit.sprite = definition.sprite
	if definition.has("aid_base") and bool(definition.get("mounted", true)):
		# A character's personal traits can override its class's mounted Aid
		# base. Keep that difference when changing class (for example fe7_unit_29).
		if not unit.has("aid_base") or int(unit.aid_base) == int(original.get("aid_base", unit.aid_base)):
			unit.aid_base = definition.aid_base
	else: unit.erase("aid_base")
	unit.aid = rescue_aid(unit) if unit.has("aid_base") else maxi(0, int(unit.con) - 1)
	if not unit.has("weapon_exp"): unit.weapon_exp = {}
	# ROM weapon-table order determines which rank wins the single-S cap.
	for kind in ["sword", "lance", "axe", "bow", "staff", "anima", "light", "dark"]:
		if not definition.get("weapon_exp", {}).has(kind): continue
		var rank_gain := int(definition.weapon_exp[kind])
		if definition.get("promotion_base_difference", false) or definition.get("promotion_rank_difference",false): rank_gain -= int(original.get("weapon_exp", {}).get(kind, 0))
		unit.weapon_exp[kind] = clampi(int(unit.weapon_exp.get(kind, 0)) + rank_gain, 0, _weapon_exp_cap(unit, str(kind)))
	unit.move_spent = mini(int(unit.get("move_spent", 0)), int(unit.mov))
	unit.last_used_weapon = ""

func _staff_rewards(unit: Dictionary, item: Dictionary) -> Dictionary:
	if unit.faction != "player": return {"experience": [], "levels": [], "weapon_experience": {}}
	var amount := int(item.get("experience", rules["staff_experience"]))
	if bool(unit.get("promoted", false)): amount /= maxi(1, int(rules.get("staff_promoted_experience_divisor", 2)))
	var reward := _award_experience(unit, amount)
	return {"experience": [reward], "levels": reward.levels, "weapon_experience": _award_weapon_experience(unit, item)}

func item_range(unit: Dictionary, item: Dictionary) -> Vector2i:
	var maximum := int(item.get("max_range", 1))
	@warning_ignore("integer_division") # Intentional integer truncation.
	if bool(item.get("range_magic_half", false)): maximum = int(item.get("magic_range_bonus", 0)) + maxi(int(item.get("magic_range_min", 1)), (effective_stat(unit, "magic" if unit.has("magic") else "str") if Rogue.active(self) else int(unit.get("magic", unit.get("str", 0)))) / 2)
	maximum += Rogue.count(unit, "sharpshooter")
	if Rogue.active(self) and item.get("type", "") != "staff" and item.has("might"): maximum += Rogue.Personal.range_bonus(self, unit)
	return Vector2i(maxi(0, int(item.get("min_range", 1))), maxi(1, maximum))

func can_use_staff(unit: Dictionary, item: Dictionary) -> bool:
	if magic_sealed(position(unit)) or str(unit.get("status", "")) in ["sleep", "silence"]: return false
	if item.is_empty() or str(item.get("kind", "")) != "staff" or int(item.get("uses", 0)) <= 0: return false
	if not bool(unit.get("can_use_staves", false)) and not unit.get("weapon_types", []).has("staff"): return false
	if not _meets_weapon_rank(unit, item): return false
	if item.has("allowed_character_ids") and not _has_numeric_id(item.allowed_character_ids, int(unit.get("rom_character_id", -1))): return false
	if item.has("allowed_units") and not item.allowed_units.has(str(unit.id)): return false
	return int(item.get("healing", 0)) > 0 or bool(item.get("healing_full", false)) or item.has("temporary_bonuses") or item.has("inflict_status") or item.has("vision_bonus") or str(item.get("staff_effect", "")) in ["restore", "warp", "rescue", "repair", "torch", "unlock"]

func status_staff_accuracy(unit: Dictionary, target: Dictionary) -> int:
	if unit.get("game_id", "") == "fe6":
		return clampi(30 + effective_stat(unit, "skill") + 6 * (effective_stat(unit, "str") - effective_stat(target, "res")) - _distance(position(unit), position(target)), 0, 100)
	# FE7U GetStaffAccuracy, 0x2A66C: classes 0x45/0x46 are immune.
	if int(target.get("rom_class_id", 0)) in [69, 70]: return 0
	return clampi(30 + effective_stat(unit, "skill") + 5 * (effective_stat(unit, "magic" if Rogue.active(self) and unit.has("magic") else "str") - effective_stat(target, "res")) - 2 * _distance(position(unit), position(target)), 0, 100)

func helpful_targets(id: String, index: int) -> Array:
	var unit := get_unit(id)
	if not _can_command(unit) or (not pending_moves.is_empty() and not pending_moves.has(id)): return []
	var item := _inventory_item(unit, index)
	if not can_use_staff(unit, item): return []
	var limits := item_range(unit, item)
	var result: Array = []
	for target in units:
		var distance := _distance(position(unit), position(target))
		if distance < limits.x or distance > limits.y: continue
		if not _staff_benefits(unit, target, item): continue
		result.append(str(target.id))
	return result

func _staff_benefits(unit: Dictionary, target: Dictionary, item: Dictionary) -> bool:
	if item.get("staff_effect", "") in ["torch", "unlock"]: return false
	if item.has("vision_bonus"): return unit.id == target.id and int(rules.get("fog_radius", 0)) > 0 and int(unit.get("vision_bonus", 0)) < int(item.vision_bonus)
	if item.has("inflict_status"):
		return _on_map(target) and _hostile(unit, target) and not _concealed_from(unit, target) and str(target.get("status", "")) in ["", "none"] and status_staff_accuracy(unit, target) > 0
	if not _on_map(target) or str(target.id) == str(unit.id) or _hostile(unit, target): return false
	if item.get("staff_effect", "") in ["warp", "rescue"]: return not Staff.destinations(self, unit, item, target).is_empty()
	if item.get("staff_effect", "") == "repair": return not Staff.repair_slots(self, target).is_empty()
	if int(item.get("healing", 0)) > 0 or bool(item.get("healing_full", false)):
		if int(target.hp) < int(target.max_hp) and Rogue.Personal.FE6.can_heal(target): return true
	if item.get("staff_effect","") == "saint" and units.any(func(u):return _on_map(u) and not _hostile(unit,u) and ((int(u.hp)<int(u.max_hp) and Rogue.Personal.FE6.can_heal(u)) or u.get("status","") not in ["","none"])): return true
	if str(item.get("staff_effect", "")) == "restore" and str(target.get("status", "")) not in ["", "none"]: return true
	for key in item.get("temporary_bonuses", {}):
		if int(item.temporary_bonuses[key]) > int(target.get("temporary_bonuses", {}).get(key, 0)): return true
	return false

func staff_options(id: String) -> Array:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.faction != "player": return []
	var result: Array = []
	for index in range(unit.inventory.size()):
		var item: Dictionary = unit.inventory[index]
		if not can_use_staff(unit, item): continue
		var targets := helpful_targets(id, index)
		result.append({"index": index, "item": item.duplicate(true), "targets": targets})
	return result

func silencer_chance(attacker: Dictionary, defender: Dictionary) -> int:
	var chance := 25 if defender.get("boss", false) else 50
	if Rogue.active(self) and Rogue.Personal.has(attacker, "fe7_unit_54") and attacker.get("rogue_personal_state", {}).get("ready", true): chance += Rogue.Personal.parameter(attacker, "silencer", 20)
	return chance

func _strike(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var stats := _combat_stats(attacker, defender)
	var defender_stats := _combat_stats(defender, attacker)
	var roll := rng.randi_range(0, 99)
	if bool(rules["two_roll_hit"]):
		@warning_ignore("integer_division") # Intentional integer truncation.
		roll = (roll + rng.randi_range(0, 99)) / 2
	var hit: bool = roll < int(stats["hit"])
	var critical: bool = hit and rng.randi_range(0, 99) < int(stats["crit"])
	var damage: int = int(stats["damage"]) * (int(rules["critical_multiplier"]) if critical else 1) if hit else 0
	if critical: damage += int(stats.get("critical_damage_bonus", 0))
	var effect := str(attacker.weapon.get("weapon_effect", ""))
	var silencer: bool = critical and bool(attacker.get("silencer", _class_definition(int(attacker.get("rom_class_id", -1))).get("silencer", false))) and not defender.get("silencer_immune", false) and rng.randi_range(0, 99) < silencer_chance(attacker, defender)
	if silencer: damage = int(defender.hp)
	var backfire := hit and effect == "devil" and rng.randi_range(0, 99) < clampi(31 - int(stats.get("luck", effective_stat(attacker, "luck"))), 0, 100)
	var victim: Dictionary = attacker if backfire else defender
	var attacker_previous_hp := int(attacker.hp)
	_consume_use(attacker.weapon, attacker)
	attacker.last_used_weapon = _weapon_signature(attacker.weapon)
	var previous_hp := int(victim.hp)
	var victim_luck := int((stats if backfire else defender_stats).get("luck", effective_stat(victim, "luck")))
	if Rogue.count(victim, "miracle") > 0 and previous_hp > 1 and damage >= previous_hp and rng.randi_range(0, 99) < mini(50, victim_luck): damage = previous_hp - 1
	if combat_cheat_active():
		if victim.faction == "player": damage = 0
		elif attacker.faction == "player" and hit: damage = 99
	damage = mini(damage, previous_hp)
	victim.hp = maxi(0, previous_hp - damage)
	if Rogue.active(self): Rogue.Personal.injured(victim, damage)
	if hit and not backfire: Rogue.on_damage(self, attacker, defender, damage, critical)
	if critical and not backfire and Rogue.active(self): Rogue.Personal.critical_hit(self, attacker)
	if hit and effect == "drain": Rogue.heal(attacker, damage)
	if hit and effect == "poison" and int(defender.hp) > 0: defender.status = "poison"; defender.status_turns = 5
	var result := {"phase": phase, "attacker_id": attacker.id, "defender_id": defender.id, "damage_target_id": victim.id, "hit": hit, "critical": critical, "silencer": silencer, "backfire": backfire, "damage": damage, "remaining_hp": victim.hp, "previous_hp": previous_hp, "attacker_previous_hp": attacker_previous_hp, "attacker_remaining_hp": attacker.hp, "healed": maxi(0, int(attacker.hp) - attacker_previous_hp), "attacker_stats": stats, "defender_stats": defender_stats}
	if not combat_guard.is_empty():
		result.attacker_cell = [position(attacker).x, position(attacker).y]
		result.defender_cell = [position(defender).x, position(defender).y]
	if stats.get("triangle_attack", false):
		result.triangle_attack = true
		result.triangle_members = ["fe7_unit_29", "fe7_unit_30", "fe7_unit_31"]
		events_log.append("Triangle Attack! fe7_unit_29, fe7_unit_30 and fe7_unit_31 surround %s." % defender.name)
	if int(attacker.weapon.get("rom_item_id", 0)) in [52, 53, 54]:
		result.attacker_weapon = JSON.parse_string(JSON.stringify(attacker.weapon))
	if int(defender.weapon.get("rom_item_id", 0)) in [52, 53, 54]:
		result.defender_weapon = JSON.parse_string(JSON.stringify(defender.weapon))
	for site in chapter.get("emplacements", []):
		if position(attacker) == Vector2i(site.x, site.y) and _weapon_signature(attacker.weapon) == _weapon_signature(site.weapon):
			site.weapon.uses = attacker.weapon.uses
	result["weapon_experience"] = {} if attacker.weapon.has("ranged_fixed_damage") and _distance(position(attacker), position(defender)) > 1 else _award_weapon_experience(attacker, attacker.weapon, not backfire and int(defender.hp) == 0)
	events_log.append("%s → %s: %s" % [attacker["name"], victim["name"], ("%s%d damage" % ["CRITICAL! " if critical else "", damage]) if hit else "miss"])
	if int(victim.hp) == 0:
		if victim.faction == "player": victim.casualty_mode = "permanent" if bool(rules.get("permadeath", true)) else "injured"
		events_log.append("%s was defeated." % victim.name)
		var passenger := get_unit(str(victim.carrying_id))
		_release_on_death(victim)
		if not passenger.is_empty(): result["released_passenger"] = {"unit_id": passenger.id, "x": passenger.x, "y": passenger.y}
	if int(attacker["weapon"]["uses"]) == 0:
		events_log.append("%s's %s broke." % [attacker["name"], attacker["weapon"]["name"]])
	if phase in ["enemy","npc"] or auto_playing:
		phase_combat.append(result.duplicate(true))
		phase_actions.append({"type": "strike", "strike": result.duplicate(true)})
	return result

func wait_unit(id: String) -> void:
	var unit := get_unit(id)
	if _can_act(unit):
		commit_move(id)
		if unit.acted: return
		for site in interactions:
			if site.get("hidden", false) and position(unit) == Vector2i(int(site.x), int(site.y)):
				site.hidden = false
				site.discovered = true
				events_log.append("Discovered a secret shop.")
				if _can_unlock(unit, site): return
		Rogue.wait_effect(self, unit)
		unit["acted"] = true
		unit.canto_active = false
		unit.canto_remaining = 0
		Traps.trigger(self, unit, true)
		_run_events("wait", {"unit_id": id, "x": int(unit.x), "y": int(unit.y)})
		_check_objective()

func end_player_turn() -> Array:
	begin_enemy_phase()
	while not _turn_sequence.is_empty() and not chapter.has("native_pending_choice"): step_enemy_phase()
	return phase_combat.duplicate(true)

func begin_enemy_phase() -> Array:
	_turn_sequence.clear()
	phase_combat = []
	phase_actions = []
	pending_skill_effects.clear()
	if phase != "player" or not outcome.is_empty():
		return []
	for id in pending_moves.keys():
		commit_move(str(id))
	for unit in units:
		if unit.faction == "player":
			if _on_map(unit):
				Traps.trigger(self, unit, true)
				_run_events("wait", {"unit_id": str(unit.id), "x": int(unit.x), "y": int(unit.y), "phase_end":true})
			unit.canto_active = false
			unit.canto_remaining = 0
	# Landing on a Mine while ending the phase precedes every enemy action.
	for effect in pending_trap_effects: phase_actions.append({"type": "trap", "result": effect.duplicate(true)})
	pending_trap_effects.clear()
	_check_objective()
	if not outcome.is_empty(): return phase_actions.duplicate(true)
	if not str(chapter.get("id", "")).begins_with("fe6_"): _apply_map_hazards()
	_check_objective()
	if not outcome.is_empty(): return phase_actions.duplicate(true)
	# The UI presents each step before calculating the next unit's action.
	# Synchronous engine clients use end_player_turn(), with identical RNG/order.
	_turn_sequence = {"stage":"berserk", "index":0, "support":_pending_support_gains(), "ids":[]}
	for unit in units:
		if unit.faction == "player" and str(unit.get("status", "")) == "berserk": _turn_sequence.ids.append(str(unit.id))
	return phase_actions.duplicate(true)

func step_enemy_phase() -> Array:
	if _turn_sequence.is_empty() or chapter.has("native_pending_choice"): return []
	var start := phase_actions.size()
	var stage := str(_turn_sequence.stage)
	var ids: Array = _turn_sequence.ids
	var index := int(_turn_sequence.index)
	if index < ids.size() and (outcome.is_empty() or stage != "enemy"):
		_turn_sequence.index = index + 1
		var unit := get_unit(str(ids[index]))
		if stage == "berserk":
			auto_playing = true
			if _can_act(unit): _enemy_action(unit)
			auto_playing = false
		elif stage == "enemy":
			_enemy_action(unit)
			if Rogue.active(self):
				for _extra in range(5):
					if not _can_act(unit): break
					_enemy_action(unit)
			phase_actions.append({"type":"acted", "unit_id":str(ids[index])})
		elif stage == "npc" and unit.get("faction", "") == "neutral" and _on_map(unit):
			if not str(unit.get("npc_talk_target","")).is_empty():
				_npc_talk_action(unit)
			elif unit.has("npc_escape") or unit.get("ai_mode","") == "escape":
				if unit.has("npc_escape"): unit.ai_escape = unit.npc_escape
				unit.moved = false; unit.acted = false; unit.move_spent = 0
				_escape_enemy(unit)
			elif _armed(unit): _enemy_action(unit)
		return phase_actions.slice(start)
	match stage:
		"berserk":
			Rogue.end_player_phase(self)
			phase = "enemy"
			for unit in units:
				if _on_map(unit) and unit.has("departure_turn") and turn >= int(unit.departure_turn): _apply_event_effects({"remove_units":[unit.id]})
			events_log.append("Enemy phase — turn %d" % turn)
			_reset_faction("enemy")
			_run_events("turn")
			_turn_sequence.stage = "enemy"
			_turn_sequence.ids = units.filter(func(u): return u.faction == "enemy" and _on_map(u)).map(func(u): return str(u.id))
			_turn_sequence.index = 0
		"enemy":
			phase_actions.append({"type":"enemy_phase_end"})
			if not outcome.is_empty():
				_commit_support_gains(_turn_sequence.support, turn)
				_turn_sequence.clear()
			else:
				phase = "npc"
				_reset_faction("neutral")
				_run_events("turn")
				_turn_sequence.stage = "npc"
				_turn_sequence.ids = units.filter(func(u): return u.faction == "neutral").map(func(u): return str(u.id))
				_turn_sequence.index = 0
		"npc":
			# FE6 advances timed traps after green phase, before the next turn.
			if str(chapter.get("id", "")).begins_with("fe6_"):
				_apply_map_hazards()
				_check_objective()
				if not outcome.is_empty():
					_commit_support_gains(_turn_sequence.support, turn)
					_turn_sequence.clear()
					return phase_actions.slice(start)
			for unit in units:
				if unit.faction == "enemy": unit.acted = false
			turn += 1
			phase = "player"
			_reset_faction("player")
			_run_events("turn")
			events_log.append("Player phase — turn %d" % turn)
			_check_objective()
			_commit_support_gains(_turn_sequence.support, turn - 1)
			_turn_sequence.clear()
	return phase_actions.slice(start)

func auto_player_turn() -> Array:
	phase_actions = []
	pending_skill_effects.clear()
	phase_combat = []
	if phase != "player" or not outcome.is_empty(): return []
	for id in pending_moves.keys(): commit_move(str(id))
	auto_playing = true
	for unit in units.duplicate():
		if not outcome.is_empty(): break
		if unit.faction != "player" or not _can_act(unit): continue
		if unit.get("canto_active", false): wait_unit(str(unit.id))
		else: _enemy_action(unit)
	auto_playing = false
	return phase_actions.duplicate(true)

func steal_options(id: String) -> Array:
	var thief := get_unit(id)
	if thief.get("rogue_fury", false): return []
	if not _can_command(thief) or thief.faction != "player": return []
	var fast_fingers := Rogue.active(self) and Rogue.count(thief, "fast_fingers") > 0
	# Assassin access is an explicit engine rule requested alongside Thief.
	if not fast_fingers and not thief.get("can_steal", false) and int(thief.get("rom_class_id", -1)) not in [60, 61, 62, 63]: return []
	if thief.inventory.size() >= int(rules.inventory_capacity): return []
	var options: Array = []
	for enemy in units:
		if enemy.faction != "enemy" or not _on_map(enemy) or not visible_to_player(enemy): continue
		if _distance(position(thief), position(enemy)) != 1 or (not fast_fingers and effective_stat(thief, "speed") < effective_stat(enemy, "speed")): continue
		for index in range(enemy.inventory.size()):
			var item: Dictionary = enemy.inventory[index]
			if int(item.get("uses", 0)) <= 0 or (not fast_fingers and not item.get("stealable", not item.has("might") and item.get("type", "item") != "staff")): continue
			options.append({"target_id": str(enemy.id), "index": index, "item": item.duplicate(true), "name": str(enemy.name)})
	return options

func steal_item(id: String, target_id: String, index: int) -> Dictionary:
	var options := steal_options(id)
	if not options.any(func(option): return option.target_id == target_id and int(option.index) == index): return {"ok": false}
	commit_move(id)
	var thief := get_unit(id)
	if thief.acted: return {"ok": false}
	var enemy := get_unit(target_id)
	var item: Dictionary = enemy.inventory[index]
	enemy.inventory.remove_at(index)
	if item.get("droppable", false) or _same_item(item, enemy.get("drop_item", {})):
		enemy.erase("drop_item")
		enemy.drop_item_removed = true
	var delivery := _give_item(id, item)
	_finish_noncombat(thief)
	if Rogue.active(self): Rogue.Personal.FE6.action_movement(self, thief)
	events_log.append("%s stole %s from %s." % [thief.name, item.name, enemy.name])
	return {"ok": true, "item_delivery": delivery}

func _same_item(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and int(a.get("rom_item_id", -1)) == int(b.get("rom_item_id", -2)) and str(a.get("name", "")) == str(b.get("name", ""))

func item_drops(unit: Dictionary, item: Dictionary) -> bool:
	return unit.get("faction", "") == "enemy" and not unit.get("drop_claimed", false) and (item.get("droppable", false) or _same_item(item, unit.get("drop_item", {})))

func all_players_acted() -> bool:
	if phase != "player" or not outcome.is_empty(): return false
	var found := false
	for unit in units:
		if unit.faction == "player" and _on_map(unit):
			found = true
			if not unit.acted: return false
	return found

func can_interact(id: String) -> bool:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.faction != "player": return false
	if _can_seize(unit): return true
	return not interaction_at_unit(id).is_empty()

func _site_in_reach(unit: Dictionary, site: Dictionary) -> bool:
	var cell := Vector2i(int(site.get("x", -1)), int(site.get("y", -1)))
	var distance := _distance(position(unit), cell)
	if site.get("type", "") == "door" and distance == 2:
		var slot := _site_key_slot(unit, site, true)
		return slot >= 0
	return distance == (1 if site.get("type", "") == "door" or (site.get("type", "") == "chest" and movement_cost(unit, cell) <= 0) else 0)

func interaction_approach(id: String, cell: Vector2i) -> Dictionary:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.get("canto_active", false): return {"ok": false}
	for index in range(interactions.size()):
		var site: Dictionary = interactions[index]
		if site.get("used", false) or cell != Vector2i(site.x, site.y): continue
		if site.has("unit_id") and str(site.unit_id) != id: continue
		if not _can_unlock(unit, site): return {"ok": false}
		var cells := reachable(_planning_unit(unit))
		var best: Dictionary = {}
		for destination in cells:
			var candidate := unit.duplicate(true)
			candidate.x = destination.x
			candidate.y = destination.y
			if not _site_in_reach(candidate, site): continue
			if site.get("type", "") == "seize" and not _can_seize(candidate): continue
			if best.is_empty() or int(cells[destination]) < int(best.cost):
				best = {"ok": true, "cell": destination, "cost": cells[destination], "index": index}
		return best if not best.is_empty() else {"ok": false}
	return {"ok": false}

func _site_key_slot(unit: Dictionary, site: Dictionary, staff_only: bool = false) -> int:
	for index in range(unit.inventory.size()):
		var item: Dictionary = unit.inventory[index]
		if not _key_matches_site(item, site): continue
		if staff_only and not item.get("requires_staves", false): continue
		if item.get("requires_staves", false) and not can_use_staff(unit, item): continue
		if item.get("requires_lockpick_skill", false) and not unit.get("can_lockpick", false): continue
		return index
	return -1

func _key_matches_site(item: Dictionary, site: Dictionary) -> bool:
	if int(item.get("uses", 0)) <= 0 or not item.get("opens", []).has(str(site.get("type", ""))): return false
	var required: int = int(site.get("required_key_id", site.get("required_item_id", -1)))
	return required < 0 or int(item.get("rom_item_id", -2)) == required

func _ordinary_chest(site: Dictionary) -> bool:
	# Convenience options must never bypass mission gates or special locks.
	return site.get("type", "") == "chest" and _ordinary_lock(site)

func _ordinary_lock(site: Dictionary) -> bool:
	return site.get("type", "") in ["chest", "door"] and not site.get("mission_lock", false) and not site.has("required_key_id") and not site.has("required_item_id") and not site.has("required_event")

func _lock_mode(site: Dictionary) -> String:
	return str(rules.get("door_unlock_mode" if site.get("type", "") == "door" else "chest_unlock_mode", "normal"))

func _supply_key_slot(site: Dictionary) -> int:
	if not _ordinary_lock(site) or _lock_mode(site) != "supply_keys": return -1
	for index in range(inventory.size()):
		var item: Dictionary = inventory[index]
		if _key_matches_site(item, site) and not item.get("requires_lockpick_skill", false) and not item.get("requires_staves", false): return index
	return -1

func _can_unlock(unit: Dictionary, site: Dictionary) -> bool:
	if site.get("member_card_required", false) and not unit.get("inventory", []).any(func(item): return item.get("member_card",false) or int(item.get("rom_item_id", -1)) == (109 if NativeFlags.game(chapter) == "fe6" else 113)): return false
	if site.has("required_event") and not fired_events.has(str(site.required_event)): return false
	if not site.get("requires_key", false): return true
	if _ordinary_lock(site) and (_lock_mode(site) == "free" or Rogue.count(unit, "multitool") > 0): return true
	if _site_key_slot(unit, site) >= 0: return true
	if _supply_key_slot(site) >= 0: return true
	return _ordinary_chest(site) and (unit.get("can_open_chests", false) or int(unit.get("chest_keys", 0)) > 0)

func interaction_at_unit(id: String) -> Dictionary:
	var unit := get_unit(id)
	if not _can_command(unit) or unit.faction != "player": return {}
	for item in interactions:
		if item.get("used", false) or not _site_in_reach(unit, item): continue
		if item.has("unit_id") and item.unit_id != id: continue
		if item.get("type", "") == "seize" and not _can_seize(unit): continue
		if not _can_unlock(unit, item): continue
		return item
	return {}

func can_support(id: String, other_id: String) -> bool:
	if not bool(rules.get("supports_enabled", true)): return false
	var a := get_unit(id)
	var b := get_unit(other_id)
	if a.get("rogue_fury", false): return false
	if not _can_command(a) or not _on_map(b) or a.faction != "player" or b.faction != "player" or _distance(position(a), position(b)) != 1: return false
	var key := _pair_key(id, other_id)
	var rank := int(support_ranks.get(key, 0))
	return (rules.get("unlimited_supports", false) or not rules.get("support_once_per_map", true) or not support_used_pairs.has(key)) and support_points.has(key) and rank < rules.support_thresholds.size() and int(support_points[key]) >= int(rules.support_thresholds[rank]) and (rules.get("unlimited_supports", false) or (_total_support_rank(id) < int(rules.support_total_cap) and _total_support_rank(other_id) < int(rules.support_total_cap)))

func play_targets(id: String) -> Array:
	var actor := get_unit(id)
	if actor.get("rogue_fury", false): return []
	if not _can_command(actor) or actor.faction != "player" or not bool(actor.get("can_play", false)) or (not pending_moves.is_empty() and not pending_moves.has(id)): return []
	var targets: Array = []
	for other in units:
		if not _can_play_for(actor, other) or _distance(position(actor), position(other)) != 1: continue
		targets.append(other)
	return targets

func _can_play_for(actor: Dictionary, target: Dictionary) -> bool:
	return bool(actor.get("can_play", false)) and _on_map(target) and target.id != actor.id and target.faction == "player" and bool(target.acted) and not bool(target.get("can_play", false))

func play(id: String, target_id: String) -> Dictionary:
	var target: Dictionary = {}
	for candidate in play_targets(id):
		if str(candidate.id) == target_id: target = candidate; break
	if target.is_empty(): return {"ok": false, "reason": "Choose an adjacent ally who has finished acting."}
	var actor := get_unit(id)
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	# Refresh only action/movement state: terrain healing and temporary-stat
	# decay happen at phase boundaries, never when music grants another action.
	target.acted = false
	target.erase("manual_weapon_turn")
	target.erase("rogue_fury")
	target.moved = false
	target.move_spent = 0
	target.traded = false
	target.canto_active = false
	target.canto_remaining = 0
	pending_moves.erase(target_id)
	_finish_noncombat(actor)
	if Rogue.active(self):
		actor.rogue_tiles_moved = 0
		target.rogue_tiles_moved = 0
		if Rogue.Personal.has(actor, "fe7_unit_38"): Rogue.effect(self, target, "fe7_unit_38_play", Rogue.Personal.configured_stats(actor), Rogue.Personal.title(actor))
		if Rogue.Personal.has(actor, "fe7_unit_37"): Rogue.effect(self, target, "fe7_unit_37_dance", Rogue.Personal.configured_stats(actor), Rogue.Personal.title(actor))
		if Rogue.Personal.has(actor, "fe7_unit_39"): Rogue.Personal.reset_fe7_unit_39(self, actor)
		Rogue.canto(actor)
		flush_skill_notifications()
	var reward := _award_experience(actor, int(actor.get("play_experience", 10)))
	events_log.append("%s refreshed %s." % [actor.name, target.name])
	_run_events("play", {"unit_id": id, "target_id": target_id})
	return {"ok": true, "target_id": target_id, "experience": [reward], "levels": reward.levels}

func _apply_map_hazards() -> void:
	if int(chapter.get("hazards_last_turn", 0)) >= turn: return
	chapter.hazards_last_turn = turn
	MapCycles.advance(self)
	for hazard in chapter.get("hazards", []):
		if hazard.get("type", "") not in ["poison_gas", "fire", "light_arrow"]: continue
		var first := int(hazard.get("first_turn", 1))
		if turn < first or (turn-first) % maxi(1,int(hazard.get("period", 1))) != 0: continue
		if hazard.type in ["fire","light_arrow"]:
			var victims: Array = []
			for y in (range(terrain.size()) if hazard.type == "light_arrow" else [int(hazard.y)]):
				var victim := unit_at(Vector2i(int(hazard.x),y))
				if not victim.is_empty(): victims.append(victim)
			for victim in victims:
				var previous := int(victim.hp)
				victim.hp = maxi(0,previous-int(hazard.get("damage",10)))
				if Rogue.active(self): Rogue.Personal.injured(victim, previous - int(victim.hp))
				var name := "Light arrow" if hazard.type == "light_arrow" else "Fire"
				phase_actions.append({"type":"trap","result":{"unit_id":victim.id,"target_id":victim.id,"previous_hp":previous,"remaining_hp":victim.hp,"damage":previous-int(victim.hp),"recovered":false,"trap_name":name}})
				events_log.append("%s was struck by a %s trap." % [victim.name,name.to_lower()])
				if int(victim.hp) <= 0:
					if victim.faction == "player": victim.casualty_mode = "permanent" if bool(rules.get("permadeath",true)) else "injured"
					_release_on_death(victim)
					_run_events("unit_defeated",{"unit_id":victim.id})
			continue
		var direction: Vector2i = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.UP][clampi(int(hazard.direction),0,3)]
		for distance in range(1,int(hazard.get("length", 3))+1):
			var unit := unit_at(Vector2i(int(hazard.x),int(hazard.y))+direction*distance)
			if unit.is_empty(): continue
			var before := int(unit.hp)
			unit.hp = maxi(1,int(unit.hp)-int(hazard.get("damage",3)))
			if Rogue.active(self): Rogue.Personal.injured(unit, before - int(unit.hp))
			unit.status = "poison";unit.status_turns = 5
			events_log.append("%s was struck by poison gas." % unit.name)

func _reset_faction(faction: String) -> void:
	if faction == "player": Traps.decay(self)
	if faction == "player" and chapter.has("torch_lights"):
		for light in chapter.torch_lights: light.radius = maxi(0, int(light.radius) - 1)
		chapter.torch_lights = chapter.torch_lights.filter(func(light): return int(light.radius) > 0)
	for unit in units:
		if unit["faction"] == faction:
			unit.ring_bonuses = {}
			if unit.has("vision_bonus"): unit.vision_bonus = maxi(0, int(unit.vision_bonus) - 1)
			for key in unit.temporary_bonuses.keys():
				unit.temporary_bonuses[key] = maxi(0, int(unit.temporary_bonuses[key]) - 1)
				if int(unit.temporary_bonuses[key]) == 0: unit.temporary_bonuses.erase(key)
		if unit["faction"] != faction or not _on_map(unit):
			continue
		if int(unit.get("status_turns", 0)) > 0:
			if unit.get("status", "") == "poison":
				var before := int(unit.hp)
				unit.hp = maxi(1,int(unit.hp)-rng.randi_range(1,3))
				if Rogue.active(self): Rogue.Personal.injured(unit, before - int(unit.hp))
			unit.status_turns = int(unit.status_turns) - 1
			if unit.status_turns == 0: unit.status = ""
		unit.erase("manual_weapon_turn")
		unit["acted"] = false
		unit["moved"] = false
		unit.move_spent = 0
		unit.traded = false
		unit.canto_active = false
		unit.canto_remaining = 0
		if int(unit.get("reinforcement_ready_turn", 0)) > turn:
			unit.acted = true
			unit.moved = true
		else: unit.erase("reinforcement_ready_turn")
		if Rogue.active(self): Rogue.start_phase(self, unit)
		var heal := int(ceil(float(unit["max_hp"]) * float(terrain_at(position(unit)).get("heal", 0))))
		Rogue.heal(unit, heal)

func _wake_stationary_defender(unit: Dictionary) -> void:
	if unit.get("faction", "") == "enemy" and unit.get("ai_mode", "") == "raid" and unit.get("raid_alert_on_attack", false):
		unit.ai_mode = "pursue"
		unit.alerted_by_attack = true
	if unit.get("faction", "") != "enemy" or str(unit.get("ai_mode", unit.get("ai", ""))) != "stationary": return
	if float(terrain_at(position(unit)).get("heal", 0)) > 0: return
	var armed := false
	for item in [unit.weapon] + unit.inventory:
		if not can_equip_weapon(unit, item): continue
		armed = true
	if armed:
		unit.ai_mode = "pursue"
		unit.alerted_by_attack = true
		events_log.append("%s leaves their post to pursue the attackers." % unit.name)

func _enemy_action(enemy: Dictionary) -> void:
	if enemy.get("ai_waypoint_region",[]) is Array and enemy.get("ai_waypoint_region",[]).size() == 4 and not enemy.get("ai_waypoint_reached",false):
		var area: Array = enemy.ai_waypoint_region
		if int(enemy.x) >= area[0] and int(enemy.y) >= area[1] and int(enemy.x) <= area[2] and int(enemy.y) <= area[3]:
			enemy.ai_waypoint_reached = true; enemy.ai_mode = str(enemy.get("ai_after_waypoint","pursue"))
	if not _can_act(enemy):
		return
	if int(enemy.get("ai_wait_actions",0)) > 0:
		enemy.ai_wait_actions -= 1
		wait_unit(str(enemy.id))
		return
	if enemy.get("ai_open_doors_first",false):
		if interactions.any(func(site):return site.get("type","") == "door" and not site.get("used",false) and _enemy_can_unlock(enemy,site)):
			if not _loot_treasure(enemy,true): _break_wall(enemy)
			wait_unit(str(enemy.id))
			return
		enemy.erase("ai_open_doors_first")
	var missing_native_target: bool = chapter.get("dynamic_rom",false) and int(enemy.get("ai_escape_if_missing_character",0)) > 0 and not units.any(func(u):return _on_map(u) and int(u.get("rom_character_id",0)) == int(enemy.ai_escape_if_missing_character))
	if (enemy.get("ai_mode", "") == "escape" or missing_native_target) and _escape_enemy(enemy):
		wait_unit(str(enemy.id))
		return
	if Rogue.active(self) and enemy.get("canto_active", false):
		var retreat := position(enemy)
		var safety := -INF
		for cell in reachable(enemy):
			var distance := 1000
			for other in units:
				if _on_map(other) and _hostile(enemy, other): distance = mini(distance, _distance(cell, position(other)))
			var score := float(distance) + float(terrain_at(cell).get("avoid", 0)) * 0.1
			if score > safety: safety = score; retreat = cell
		move_unit(str(enemy.id), retreat)
		wait_unit(str(enemy.id))
		return
	if not _armed(enemy):
		# Exhausted siege weapons and broken equipment fall back to carried arms.
		# Keep the usual weapon while usable, preserving existing AI priorities.
		for index in range(enemy.inventory.size()):
			if can_equip_weapon(enemy, enemy.inventory[index]):
				var previous: Dictionary = enemy.weapon
				enemy.weapon = enemy.inventory[index]
				if previous.is_empty(): enemy.inventory.remove_at(index)
				else: enemy.inventory[index] = previous
				break
	var targets: Array = []
	for unit in units:
		if _hostile(enemy, unit) and _on_map(unit) and not _concealed_from(enemy, unit) and not _has_numeric_id(enemy.get("ai_excluded_character_ids", []), int(unit.get("rom_character_id", -1))):
			if not enemy.get("ai_target_character_ids", []).is_empty() and not _has_numeric_id(enemy.ai_target_character_ids, int(unit.get("rom_character_id", -1))): continue
			targets.append(unit)
	var cells := reachable(enemy)
	var mode := "pursue" if auto_playing else str(enemy.get("ai_mode", enemy.get("ai", "pursue")))
	if mode == "stationary": cells = {position(enemy): 0}
	if Rogue.active(self) and enemy.faction == "enemy" and targets.any(func(t): return Rogue.count(t, "stealth") > 0):
		var hidden := targets.filter(func(t): return Rogue.count(t, "stealth") > 0 and not units.any(func(other): return _on_map(other) and _hostile(t, other) and _distance(position(t), position(other)) == 1))
		var exposed := targets.filter(func(t): return not hidden.has(t) and cells.keys().any(func(c): return ([enemy.weapon] + enemy.inventory).any(func(w):
			var candidate := enemy.duplicate(); candidate.planned_move_cost = int(cells[c])
			return can_equip_weapon(enemy, w) and _distance(c, position(t)) >= item_range(candidate, w).x and _distance(c, position(t)) <= item_range(candidate, w).y)))
		if not exposed.is_empty(): targets = targets.filter(func(t): return not hidden.has(t))
	var attack_targets_nearby: Array = []
	var maximum_range := 0
	for weapon in [enemy.weapon] + enemy.inventory + chapter.get("emplacements", []).map(func(site): return site.weapon):
		if can_equip_weapon(enemy, weapon): maximum_range = maxi(maximum_range, item_range(enemy, weapon).y)
	for target in targets:
		if cells.keys().any(func(cell): return _distance(cell, position(target)) <= maximum_range): attack_targets_nearby.append(target)
	var staff_plan := Staff.best_plan(self, enemy, cells)
	var original := position(enemy)
	var best_cell := original
	var best_target: Dictionary = {}
	var best_weapon := -1
	var best_score := -1000000.0
	for cell in ([] if attack_targets_nearby.is_empty() else cells.keys()):
		var moved_tiles := 0
		if Rogue.active(self) and Rogue.Personal.effect_id(enemy) in ["fe7_unit_24", "fe7_unit_23", "fe7_unit_29", "fe7_unit_25", "fe7_unit_30", "fe7_unit_52", "fe7_unit_32", "fe7_unit_31"]:
			moved_tiles = maxi(0, movement_path(str(enemy.id), cell).size() - 1)
		var at_cell := enemy.duplicate()
		at_cell.x = cell.x; at_cell.y = cell.y
		var siege := emplacement_weapon(at_cell)
		for weapon_index in range(-2 if not siege.is_empty() else -1, enemy.inventory.size()):
			var weapon: Dictionary = siege if weapon_index == -2 else enemy.weapon if weapon_index == -1 else enemy.inventory[weapon_index]
			if not can_equip_weapon(enemy, weapon): continue
			var planning := enemy.duplicate()
			planning.x = cell.x
			planning.y = cell.y
			planning.weapon = weapon
			planning.planned_move_cost = int(cells[cell])
			planning.planned_move_tiles = moved_tiles
			for target in ([] if bool(enemy.get("ai_no_attack", false)) else attack_targets_nearby):
				var distance := _distance(cell, position(target))
				var limits := item_range(planning, weapon)
				if distance < limits.x or distance > limits.y: continue
				if not _in_range(planning, target): continue
				var prior_initiator := combat_initiator
				if Rogue.active(self): combat_initiator = str(enemy.id)
				var stats := _combat_stats(planning, target)
				var counter := _combat_stats(target, planning)
				combat_initiator = prior_initiator
				if weapon.get("cannot_counter", false) or target.weapon.get("cannot_counter", false): counter.can_attack = false; counter.strikes = 0
				var outgoing := float(stats.damage * stats.strikes * stats.hit) / 100.0
				var incoming := float(counter.damage * counter.strikes * counter.hit) / 100.0
				# Approximate the ROM's damage, lethal, retaliation and safety
				# preferences. No rolls are consumed while choosing a plan.
				var score := 2.0 * outgoing - incoming + (10.0 if not counter.can_attack else 0.0)
				if int(stats.damage) * int(stats.strikes) >= int(target.hp): score += 50.0 * float(stats.hit) / 100.0
				if incoming >= int(enemy.hp): score -= 40.0
				if enemy.faction == "enemy" and rules.get("hard_mode", false):
					# Hard-mode opponents favor reliable kills and vulnerable units,
					# while retaining their native movement/objective restrictions.
					score += 35.0 * minf(1.0, outgoing / maxf(1.0, float(target.hp)))
					score += 10.0 * (1.0 - float(target.hp) / maxf(1.0, float(target.max_hp)))
					if int(stats.damage) >= int(target.hp): score += 30.0 * float(stats.hit) / 100.0
				score += _terrain_combat_bonus(planning, "avoid") * 0.05
				score -= float(cells[cell]) * 0.01
				var preferred: bool = int(enemy.get("ai_preferred_character",0)) == int(target.get("rom_character_id",-1))
				var previous_preferred: bool = not best_target.is_empty() and int(enemy.get("ai_preferred_character",0)) == int(best_target.get("rom_character_id",-1))
				if (preferred and not previous_preferred) or (preferred == previous_preferred and score > best_score):
					best_score = score
					best_cell = cell
					best_target = target
					best_weapon = weapon_index
	if not staff_plan.is_empty() and float(staff_plan.score) > best_score:
		move_unit(str(enemy.id), staff_plan.cell)
		var staff_item: Dictionary = enemy.inventory[int(staff_plan.index)].duplicate(true)
		var staff_result := use_item(str(enemy.id), int(staff_plan.index), str(staff_plan.target_id))
		if staff_result.get("ok", false):
			phase_actions.append({"type": "staff", "unit_id": str(enemy.id), "item":staff_item, "result": staff_result.duplicate(true)})
			return
	if not best_target.is_empty():
		if best_weapon >= 0:
			var previous: Dictionary = enemy.weapon
			enemy.weapon = enemy.inventory[best_weapon]
			if previous.is_empty(): enemy.inventory.remove_at(best_weapon)
			else: enemy.inventory[best_weapon] = previous
		move_unit(str(enemy["id"]), best_cell)
		if best_weapon == -2:
			var carried: Dictionary = enemy.weapon
			enemy.weapon = emplacement_weapon(enemy)
			attack(str(enemy.id), str(best_target.id))
			enemy.weapon = carried
		else: attack(str(enemy["id"]), str(best_target["id"]))
		return
	# ROM AI1 decides attacks; AI2 decides what to do when none is available.
	# In-range defenders must not chase a target that is still out of reach.
	var approach: Array = targets.filter(func(t):return int(t.get("rom_character_id",-1)) == int(enemy.get("ai_approach_character",0))) if not enemy.get("ai_approach_complete",false) else []
	if not approach.is_empty():
		var route := _route_toward(enemy,position(approach[0]),1,1)
		if route.get("ok",false): move_unit(str(enemy.id),route.cell)
		if _distance(position(enemy),position(approach[0])) == 1: enemy.ai_approach_complete = true
	elif enemy.get("ai_waypoint", []) is Array and enemy.get("ai_waypoint", []).size() == 2 and not enemy.get("ai_waypoint_reached", false):
		var waypoint := Vector2i(enemy.ai_waypoint[0], enemy.ai_waypoint[1])
		var route := _route_toward(enemy, waypoint, 0, 0)
		if route.get("ok", false): move_unit(str(enemy.id), route.cell)
		if position(enemy) == waypoint and not enemy.get("ai_waypoint_repeats",false):
			enemy.ai_waypoint_reached = true
			enemy.ai_mode = str(enemy.get("ai_after_waypoint", "attack_in_range"))
	elif mode == "raid" and _raid_village(enemy):
		pass
	elif mode == "loot" and _loot_treasure(enemy):
		pass
	elif mode == "break_walls" and _break_wall(enemy):
		pass
	elif chapter.get("dynamic_rom",false) and enemy.get("ai_random_move",false):
		var destinations: Array = cells.keys().filter(func(cell):return unit_at(cell).is_empty() or cell == position(enemy))
		if not destinations.is_empty(): move_unit(str(enemy.id),destinations[rng.randi_range(0,destinations.size()-1)])
	elif mode not in ["stationary", "attack_in_range"] and (mode != "raid" or not enemy.get("raid_alert_on_attack", false)):
		var route: Dictionary = {}
		var pursuit_search := _movement_search(enemy, position(enemy))
		pursuit_search.available = cells
		var pursuit_targets: Array = targets.duplicate()
		var pursuit_character := int(enemy.get("ai_pursuit_character",0))
		if pursuit_character > 0:
			for named in units:
				if int(named.get("rom_character_id",0)) == pursuit_character and _on_map(named) and named.id != enemy.id and not pursuit_targets.has(named): pursuit_targets.append(named)
		if pursuit_character > 0: pursuit_targets.sort_custom(func(a,z):return int(a.get("rom_character_id",-1)) == pursuit_character and int(z.get("rom_character_id",-1)) != pursuit_character)
		for target in pursuit_targets:
			if not enemy.get("ai_pursuit_character_ids", []).is_empty() and not _has_numeric_id(enemy.ai_pursuit_character_ids, int(target.get("rom_character_id", -1))): continue
			var friendly := not _hostile(enemy,target)
			var candidate := _route_toward(enemy, position(target), 1 if friendly else int(enemy.weapon.get("min_range", 1)), 1 if friendly else int(enemy.weapon.get("max_range", 1)), pursuit_search)
			if not auto_playing and enemy.has("ai_pursuit_turns") and int(candidate.get("cost", 2147483647)) > int(enemy.mov) * int(enemy.ai_pursuit_turns): continue
			if candidate.get("ok", false) and (route.is_empty() or int(candidate.cost) < int(route.cost)):
				route = candidate
			if candidate.get("ok",false) and int(target.get("rom_character_id",-1)) == pursuit_character: break
		if not route.is_empty(): move_unit(str(enemy.id), route.cell)
	wait_unit(str(enemy["id"]))

func _break_wall(enemy: Dictionary) -> bool:
	if not _armed(enemy): return false
	var cells := reachable(enemy)
	var best: Dictionary = {}
	for wall in destructibles:
		if int(wall.hp) <= 0: continue
		for cell in cells:
			var distance := _distance(cell, position(wall))
			if distance < int(enemy.weapon.min_range) or distance > int(enemy.weapon.max_range): continue
			if best.is_empty() or int(cells[cell]) < int(best.cost): best = {"cell": cell, "cost": int(cells[cell]), "wall": wall}
	if not best.is_empty():
		move_unit(str(enemy.id), best.cell)
		attack(str(enemy.id), str(best.wall.id))
		return true
	for wall in destructibles:
		if int(wall.hp) <= 0: continue
		var route := _route_toward(enemy, position(wall), int(enemy.weapon.min_range), int(enemy.weapon.max_range))
		if route.get("ok", false) and (best.is_empty() or int(route.cost) < int(best.cost)): best = route
	if best.is_empty(): return false
	move_unit(str(enemy.id), best.cell)
	return true

func _route_toward(unit: Dictionary, destination: Vector2i, minimum: int, maximum: int, search: Dictionary = {}, allow_partial: bool = false, allow_allied_goal: bool = false) -> Dictionary:
	if search.is_empty(): search = _movement_search(unit, position(unit))
	var best := Vector2i(-1, -1)
	var best_cost := 2147483647
	for cell in search.costs:
		var distance := _distance(cell, destination)
		if distance < minimum or distance > maximum: continue
		var occupant := unit_at(cell)
		if not occupant.is_empty() and occupant.id != unit.id and (not allow_allied_goal or _hostile(occupant, unit)): continue
		var cost := int(search.costs[cell])
		if cost < best_cost or (cost == best_cost and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))):
			best = cell
			best_cost = cost
	if best.x < 0:
		if not allow_partial: return {"ok": false}
		# A blocked final route must not freeze an objective-driven unit. Choose
		# the nearest legal frontier and follow the actual path to that tile.
		var nearest := 2147483647
		for cell in search.costs:
			var occupant := unit_at(cell)
			if not occupant.is_empty() and occupant.id != unit.id: continue
			var distance := _distance(cell, destination)
			var cost := int(search.costs[cell])
			if distance < nearest or (distance == nearest and cost < best_cost):
				best = cell
				best_cost = cost
				nearest = distance
		if best.x < 0: return {"ok": false}
	var path: Array = [best]
	while path.front() != position(unit): path.push_front(search.previous[path.front()])
	if not search.has("available"): search.available = reachable(unit)
	var available: Dictionary = search.available
	var next := position(unit)
	for cell in path:
		if available.has(cell): next = cell
	return {"ok": true, "cell": next, "cost": best_cost}

func _raid_village(enemy: Dictionary) -> bool:
	var best: Dictionary = {}
	var target: Dictionary = {}
	for site in interactions:
		if site.get("used", false) or site.get("type", "") != "village": continue
		var route := _route_toward(enemy, Vector2i(site.x, site.y), 0, 0, {}, true)
		if route.get("ok", false) and (best.is_empty() or int(route.cost) < int(best.cost)):
			best = route
			target = site
	if best.is_empty():
		if not enemy.get("raid_alert_on_attack", false) or not interactions.any(func(site): return site.get("type", "") == "village" and not site.get("used", false)):
			enemy.ai_mode = "pursue"
		return false
	move_unit(str(enemy.id), best.cell)
	if position(enemy) == Vector2i(target.x, target.y):
		if enemy.acted: return true
		target.used = true
		target["destroyed"] = true
		if target.has("destroy_map_change"):
			var destroyed := target.duplicate(true)
			destroyed.map_change = target.destroy_map_change
			_apply_map_change(destroyed)
			phase_actions.append({"type": "map_change", "id": str(destroyed.id)})
		enemy.ai_mode = "pursue"
		events_log.append("%s destroyed a village." % enemy.name)
		_run_events("village_destroyed", {"unit_id": enemy.id, "x": target.x, "y": target.y})
	return true

func _enemy_can_unlock(enemy: Dictionary, site: Dictionary) -> bool:
	# Player convenience settings and convoy keys never apply to enemy AI.
	if site.has("required_event") and not fired_events.has(str(site.required_event)): return false
	if not bool(site.get("requires_key", false)): return true
	return _site_key_slot(enemy, site) >= 0

func _loot_treasure(enemy: Dictionary, doors_only: bool = false) -> bool:
	if not doors_only and bool(enemy.get("ai_looted", false)): return _escape_enemy(enemy)
	var best: Dictionary = {}
	var target: Dictionary = {}
	# Prefer reachable treasure; when doors block every route, open the closest
	# reachable generic door and reconsider the treasure on the next turn.
	# A friendly unit may temporarily occupy the only interaction tile. Keep
	# that goal if no free one is available, moving only onto legal free tiles.
	# The looter retries next turn instead of mistaking congestion for no loot.
	for allow_allied_goal in [false, true]:
		for kind in (["door"] if doors_only else ["chest", "door"]):
			for site in interactions:
				if bool(site.get("used", false)) or site.get("type", "") != kind or not _enemy_can_unlock(enemy, site): continue
				var range_to_site := 1 if kind == "door" or movement_cost(enemy, position(site)) <= 0 else 0
				var route := _route_toward(enemy, position(site), range_to_site, range_to_site, {}, false, allow_allied_goal)
				if route.get("ok", false) and (best.is_empty() or int(route.cost) < int(best.cost)):
					best = route
					target = site
			if not best.is_empty(): break
		if not best.is_empty(): break
	if best.is_empty(): return false if doors_only else _escape_enemy(enemy)
	move_unit(str(enemy.id), best.cell)
	if enemy.acted: return true
	if not _site_in_reach(enemy, target): return true
	var key_slot := _site_key_slot(enemy, target)
	if target.get("requires_key", false) and key_slot >= 0:
		enemy.inventory[key_slot].uses = maxi(0, int(enemy.inventory[key_slot].uses) - 1)
		if int(enemy.inventory[key_slot].uses) == 0: enemy.inventory.remove_at(key_slot)
	target.used = true
	target["looted_by"] = str(enemy.id)
	if target.has("map_change"): _apply_map_change(target)
	if target.get("type", "") == "chest":
		var loot: Array = []
		if target.get("give_item", {}) is Dictionary and not target.get("give_item", {}).is_empty(): loot.append(_normalize_item(target.give_item))
		var reward: Dictionary = target.get("reward", {}) if target.get("reward", {}) is Dictionary else {}
		if reward.get("item", {}) is Dictionary and not reward.get("item", {}).is_empty(): loot.append(_normalize_item(reward.item))
		if not enemy.has("stolen_items"): enemy.stolen_items = []
		for item in loot:
			item.droppable = true
			enemy.stolen_items.append(item.duplicate(true))
			enemy.inventory.append(item)
		enemy.stolen_gold = int(enemy.get("stolen_gold", 0)) + maxi(0, int(reward.get("gold", 0)))
		enemy.ai_looted = true
		events_log.append("%s took the treasure." % enemy.name)
	else:
		events_log.append("%s unlocked a door." % enemy.name)
	phase_actions.append({"type": "loot", "unit_id": str(enemy.id), "site_id": str(target.get("id", "")), "site_type": str(target.get("type", ""))})
	if target.get("native_visit_event",false):
		_run_events("visit", {"unit_id": str(enemy.id), "x": int(target.x), "y": int(target.y)})
	_run_events("enemy_loot", {"unit_id": str(enemy.id), "x": int(target.x), "y": int(target.y)})
	return true

func _escape_enemy(enemy: Dictionary) -> bool:
	var points: Array = enemy.get("ai_escape_points", [])
	if points.is_empty() and enemy.get("ai_escape", []) is Array and enemy.get("ai_escape", []).size() == 2: points = [enemy.ai_escape]
	var best: Dictionary = {}
	var destination := Vector2i(-1, -1)
	for point in points:
		if not point is Array or point.size() != 2: continue
		var cell := Vector2i(int(point[0]), int(point[1]))
		# Some escape adapters name the first tile beyond the map edge. Route
		# to the adjacent boundary tile and leave from there; pathfinding cannot
		# reach an off-map cell. Reject distant or diagonal off-map destinations.
		if not in_bounds(cell):
			if cell.x in [-1,width] and cell.y >= 0 and cell.y < height:
				cell.x = clampi(cell.x,0,width-1)
			elif cell.y in [-1,height] and cell.x >= 0 and cell.x < width:
				cell.y = clampi(cell.y,0,height-1)
			else: continue
		var route := _route_toward(enemy, cell, 0, 0)
		if route.get("ok", false) and (best.is_empty() or int(route.cost) < int(best.cost)):
			best = route
			destination = cell
	if best.is_empty(): return false
	move_unit(str(enemy.id), best.cell)
	if position(enemy) == destination:
		if enemy.acted: return true
		enemy.escaped = true
		enemy.acted = true
		phase_actions.append({"type": "escape", "unit_id": str(enemy.id)})
		events_log.append("%s escaped%s." % [enemy.name, " with the treasure" if bool(enemy.get("ai_looted", false)) else ""])
		_run_events("unit_escaped", {"unit_id": str(enemy.id)})
		_check_objective()
	return true

func shop_at(id: String) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or unit.faction != "player" or (unit.canto_active and (unit.moved or pending_moves.has(id))): return {}
	for site in interactions:
		if site.get("type", "") in ["armory", "shop"] and position(unit) == Vector2i(site.x, site.y):
			if site.get("hidden", false): continue
			if not _can_unlock(unit, site): continue
			return site
	return {}

func shop_price(id: String, base_price: int) -> int:
	var discount := 1.0
	for entry in inventory_slots(id): discount = minf(discount, float(entry.item.get("shop_discount", 1.0)))
	return Rogue.price(self, int(base_price * discount), get_unit(id))

func buy_item(id: String, stock_index: int, to_supply: bool = false) -> Dictionary:
	var shop := shop_at(id)
	if shop.is_empty(): return {"ok": false, "reason": "Move onto a shop to buy items."}
	var stock: Array = shop.get("stock", [])
	if stock_index < 0 or stock_index >= stock.size(): return {"ok": false, "reason": "Choose an available item."}
	var entry: Dictionary = stock[stock_index]
	var price := shop_price(id, int(entry.get("price", 0)))
	var unit := get_unit(id)
	if price < 0 or gold < price: return {"ok": false, "reason": "Not enough gold."}
	if not to_supply and unit.inventory.size() >= int(rules.inventory_capacity): return {"ok": false, "reason": "This unit's inventory is full."}
	var item := _normalize_item(entry.get("item", {}))
	if item.is_empty(): return {"ok": false, "reason": "This item is unavailable."}
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	gold -= price
	if to_supply: inventory.append(item)
	else: unit.inventory.append(item)
	if not unit.canto_active: _finish_noncombat(unit, false)
	events_log.append("%s bought %s for %d gold." % [unit.name, item.name, price])
	return {"ok": true, "item": item.duplicate(true), "price": price}

func sell_item(id: String, slot: int, from_supply: bool = false) -> Dictionary:
	if shop_at(id).is_empty(): return {"ok": false, "reason": "Move onto a shop to sell items."}
	var unit := get_unit(id)
	if (from_supply and (slot < 0 or slot >= inventory.size())) or (not from_supply and not _valid_slot(unit, slot)): return {"ok": false, "reason": "Choose an item."}
	var item: Dictionary = inventory[slot] if from_supply else _slot_item(unit, slot)
	if item.is_empty() or item.get("unsellable", false) or item.get("untradeable", false): return {"ok": false, "reason": "This item cannot be sold."}
	var price := sell_price(item)
	if price <= 0: return {"ok": false, "reason": "This item has no sale value."}
	commit_move(id)
	if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
	if from_supply: inventory.remove_at(slot)
	else: _put_slot(unit, slot, {})
	gold += price
	if not unit.canto_active: _finish_noncombat(unit, false)
	events_log.append("%s sold %s for %d gold." % [unit.name, item.name, price])
	return {"ok": true, "item": item.duplicate(true), "price": price}

func sell_price(item: Dictionary) -> int:
	if item.is_empty() or item.get("unsellable", false) or item.get("untradeable", false): return 0
	return maxi(0, floori(float(int(item.get("uses", 0)) * int(item.get("cost_per_use", 0))) / 2.0))

func interact(id: String, site_index: int = -1) -> Dictionary:
	var unit := get_unit(id)
	if unit.get("rogue_fury", false): return {"ok": false}
	if not _can_command(unit) or unit["faction"] != "player":
		return {"ok": false}
	for item in interactions:
		if site_index >= 0 and interactions.find(item) != site_index: continue
		if bool(item.get("used", false)) or not _site_in_reach(unit, item):
			continue
		if item.has("unit_id") and str(item["unit_id"]) != id:
			continue
		var kind: String = str(item.get("type", "village"))
		if kind == "seize" and not _can_seize(unit):
			return {"ok": false, "reason": "Only the designated unit can seize the objective."}
		if not _can_unlock(unit, item): return {"ok": false, "reason": "A suitable key or thief's Lockpick is required."}
		commit_move(id)
		if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		if item.get("requires_key", false) and not (_ordinary_lock(item) and (_lock_mode(item) == "free" or Rogue.count(unit, "multitool") > 0)):
			var key_slot := _site_key_slot(unit, item, _distance(position(unit), Vector2i(item.x, item.y)) == 2)
			var supply_key := _supply_key_slot(item)
			if key_slot >= 0:
				var key: Dictionary = unit.inventory[key_slot]
				if key.get("requires_staves", false):
					var rewards := _staff_rewards(unit, key)
					experience_queue.append_array(rewards.experience)
				_consume_use(key)
				if int(key.uses) <= 0: unit.inventory.remove_at(key_slot)
			elif supply_key >= 0:
				_consume_use(inventory[supply_key])
				if int(inventory[supply_key].uses) <= 0: inventory.remove_at(supply_key)
			elif not unit.get("can_open_chests", false): unit.chest_keys = int(unit.get("chest_keys", 0)) - 1
		item["used"] = true
		NativeFlags.site(self,item)
		if item.has("map_change"): _apply_map_change(item)
		_finish_noncombat(unit)
		Rogue.after_action(self, unit, "busy")
		if Rogue.active(self) and kind in ["door", "chest"]: Rogue.Personal.FE6.action_movement(self, unit)
		var reward: Variant = item.get("reward_by_unit", {}).get(id, item.get("reward", {}))
		var item_delivery := _award_reward(reward, id)
		if item.has("give_item"): item_delivery = _give_item(id, item.give_item)
		var dialogue: Array = item.get("dialogue_by_unit", {}).get(id, item.get("dialogue", [])).duplicate(true)
		_resolve_visit_dialogue(dialogue, unit)
		dialogue_queue.append_array(dialogue)
		events_log.append("%s: %s" % [unit["name"], str(item.get("message", "Opened chest" if kind == "chest" else "Visited " + kind))])
		var before_patches := map_patches.size()
		_run_events("visit", {"unit_id": id, "x": int(item.x), "y": int(item.y)})
		if item.get("native_revisitable",false) and before_patches == map_patches.size(): item.used = false
		if kind == "seize":
			_check_objective(true)
		else:
			_check_objective()
		return {"ok": true, "type": kind, "reward": reward, "give_item": item.get("give_item", {}).duplicate(true), "item_delivery": item_delivery, "dialogue": dialogue}
	if _can_seize(unit):
		commit_move(id)
		if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
		unit["acted"] = true
		_check_objective(true)
		return {"ok": true, "type": "seize", "reward": {}, "dialogue": []}
	return {"ok": false, "reason": "Nothing to interact with here."}

func _resolve_visit_dialogue(dialogue: Array, visitor: Dictionary) -> void:
	# Content may name the visitor without knowing the campaign roster at compile
	# time. Bind the role on emitted copies, retaining reusable chapter templates.
	for page in dialogue:
		if not page is Dictionary:
			continue
		for prefix in ["", "left_", "right_"]:
			var role_key: String = prefix + "portrait_role"
			if page.get(role_key, "") == "visitor":
				page[prefix + "portrait"] = str(visitor.get("portrait", ""))
				page[prefix + "speaker"] = str(visitor.get("name", ""))
				page.erase(role_key)

func _can_seize(unit: Dictionary) -> bool:
	var objective: Dictionary = chapter.get("objective", {})
	if objective.get("type") == "native_seize":
		return str(unit.id) == str(objective.get("unit_id","")) and interactions.any(func(site):return site.get("type") == "seize" and not site.get("used",false) and position(unit) == Vector2i(int(site.x),int(site.y)))
	return objective.get("type", "") == "seize" and position(unit) == Vector2i(int(objective.get("x", -1)), int(objective.get("y", -1))) and (not objective.has("unit_id") or str(objective["unit_id"]) == str(unit["id"]))

func _talk_conditions(talk: Dictionary) -> bool:
	if talk.has("native_program") and NativeFlags.has_flag(native_event_state,int(talk.native_program.get("completion_flag",0))): return false
	return _event_conditions(talk)

func _npc_talk_action(unit: Dictionary) -> void:
	var target := get_unit(str(unit.get("npc_talk_target", "")))
	if not _on_map(target) or target.faction != "player": return
	var route := _route_toward(unit, position(target), 1, 1, {}, true)
	if route.get("ok", false): move_unit(str(unit.id), route.cell)
	if _distance(position(unit), position(target)) == 1:
		for talk in chapter.get("talks", []):
			if talk.get("from", "") != unit.id or talk.get("to", "") != target.id: continue
			if fired_events.has(str(talk.id)) or not _talk_conditions(talk): continue
			if talk.has("native_program"):
				talk = talk.duplicate(true); talk.trigger = "talk"
				if not _apply_event_effects(talk,{"unit_id":str(unit.id),"target_id":str(target.id)}): return
				fired_events.append(str(talk.id))
			else:
				fired_events.append(str(talk.id))
				_apply_event_effects(talk)
			unit.acted = true
			phase_actions.append({"type":"recruit", "unit_id":str(unit.id)})
			return
	unit.acted = true

func talk_targets(id: String) -> Array:
	var actor := get_unit(id)
	if not _can_command(actor) or actor.faction != "player": return []
	var result: Array = []
	for talk in chapter.get("talks", []):
		var target := get_unit(str(talk.get("to", "")))
		if talk.get("from", "") not in [id, "*"] or fired_events.has(str(talk.get("id", "talk_" + id + "_" + str(talk.get("to", ""))))): continue
		if _on_map(target) and _distance(position(actor), position(target)) == 1 and _talk_conditions(talk): result.append(target)
	return result

func talk_unit(id: String, target_id: String, offer_index: int = -1) -> Dictionary:
	var actor := get_unit(id)
	var target := get_unit(target_id)
	if actor.get("rogue_fury", false): return {"ok": false, "reason": "Deathmatch allows only another attack or Wait."}
	if not talk_targets(id).has(target): return {"ok": false, "reason": "No conversation is available with this adjacent unit."}
	for talk in chapter.get("talks", []):
		var event_id := str(talk.get("id", "talk_" + id + "_" + target_id))
		if talk.get("from", "") in [id, "*"] and talk.get("to", "") == target_id and not fired_events.has(event_id) and _talk_conditions(talk):
			if talk.has("recruitment_offers"):
				talk = preload("res://engine/recruitment_offers.gd").select(talk,offer_index,gold)
				if talk.is_empty(): return {"ok":false,"reason":"Choose an affordable recruitment offer or decline."}
			var cost := int(talk.get("cost", 0))
			if gold < cost: return {"ok": false, "reason": "Recruiting %s costs %d G." % [target.name, cost]}
			if talk.get("duel_recruit", false) and not _armed(actor): return {"ok": false, "reason": "Equip a usable weapon before challenging fe7_unit_55."}
			commit_move(id)
			if get_unit(id).acted: return {"ok": false, "reason": "A hidden enemy blocked the movement."}
			if talk.has("native_program"):
				talk = talk.duplicate(true); talk.trigger = "talk"
				if not _apply_event_effects(talk,{"unit_id":id,"target_id":target_id}): return {"ok":false,"reason":"The native conversation could not run. Export diagnostics for details."}
				gold -= cost
				fired_events.append(event_id)
				_run_events("native_flag",{"unit_id":id,"target_id":target_id},true)
			else:
				gold -= cost
				fired_events.append(event_id)
				if talk.get("duel_recruit", false):
					return _recruitment_duel(actor, target, talk)
				_apply_event_effects(talk)
			if int(talk.get("stat_penalty",0)) > 0: preload("res://engine/recruitment_offers.gd").weaken(target,int(talk.stat_penalty))
			_finish_noncombat(actor)
			Rogue.after_action(self, actor, "busy")
			events_log.append("%s spoke with %s." % [actor.name, target.name])
			_check_objective()
			return {"ok": true, "target_id": target_id}
	return {"ok": false, "reason": "This conversation has already happened."}

func _recruitment_duel(actor: Dictionary, target: Dictionary, talk: Dictionary) -> Dictionary:
	# One ordinary combat exchange, without making a neutral recruit hostile
	# to the rest of the army. Both participants must survive to recruit her.
	var a := _combat_stats(actor, target)
	var b := _combat_stats(target, actor)
	var order: Array = [[actor, target]] if a.can_attack else []
	if b.can_attack: order.append([target, actor])
	if a.strikes == 2: order.append([actor, target])
	if b.strikes == 2: order.append([target, actor])
	var strikes: Array = []
	for pair in order:
		if int(actor.hp) <= 0 or int(target.hp) <= 0: break
		if _armed(pair[0]): strikes.append(_strike(pair[0], pair[1]))
	actor.acted = true
	var recruited: bool = int(actor.hp) > 0 and int(target.hp) > 0
	if recruited: _apply_event_effects(talk)
	else: dialogue_queue.append_array(talk.get("dialogue", []).duplicate(true))
	Traps.trigger(self, actor, true)
	_run_events("unit_defeated")
	_check_objective()
	events_log.append("fe7_unit_55 joined after the duel." if recruited else "The recruitment duel ended in a casualty.")
	return {"ok": true, "strikes": strikes, "recruited": recruited, "target_id": target.id}

func _roster_levels(ids: Array) -> int:
	var total := 0
	for unit in Army.all_units(self):
		if ids.has(str(unit.id)) and unit.faction == "player": total += int(unit.level) + (20 if unit.get("promoted", false) else 0)
	return total

func _event_conditions(event: Dictionary) -> bool:
	if event.has("native_program") and NativeFlags.has_flag(native_event_state,int(event.native_program.get("completion_flag",0))): return false
	var conditions: Dictionary = event.get("conditions", {})
	for test in conditions.get("native_unit_presence",[]):
		if not NativeRunner.valid_test(test,NativeFlags.game(chapter)): return false
	if conditions.has("difficulty") and not preload("res://engine/campaign_difficulty.gd").matches(chapter.get("difficulty","normal"), conditions.difficulty): return false
	if conditions.has("native_experience_compare"):
		var comparison: Dictionary = conditions.native_experience_compare
		var totals: Dictionary = chapter.get("fe6_experience",{})
		var difference := 0
		for character in comparison.left: difference += int(totals.get(str(int(character)),0))
		for character in comparison.right: difference -= int(totals.get(str(int(character)),0))
		if difference <= 0: return false
	for flag in conditions.get("story_flags_not", []):
		if chapter.get("story_flags", {}).get(flag, false): return false
	for id in conditions.get("recruits_available", []):
		if chapter.get("unavailable_recruits", []).has(id): return false
	for id in conditions.get("player_alive", []):
		var unit := get_unit(str(id))
		if unit.is_empty() or unit.faction != "player" or int(unit.hp) <= 0: return false
	for id in conditions.get("player_not_alive", []):
		var unit := get_unit(str(id))
		if not unit.is_empty() and unit.faction == "player" and int(unit.hp) > 0: return false
	for id in conditions.get("sites_used", []):
		if not interactions.any(func(site): return site.get("id", "") == id and site.get("used", false)): return false
	for id in conditions.get("sites_visited", []):
		if not interactions.any(func(site): return site.get("id", "") == id and site.get("used", false) and not site.get("destroyed", false)): return false
	if conditions.has("occupied_player_regions"):
		var occupied := false
		for area in conditions.occupied_player_regions:
			for unit in units:
				if _on_map(unit) and unit.faction == "player" and int(unit.x) >= int(area[0]) and int(unit.y) >= int(area[1]) and int(unit.x) <= int(area[2]) and int(unit.y) <= int(area[3]): occupied = true
		if not occupied: return false
	for area in conditions.get("empty_player_regions", []):
		for unit in units:
			if _on_map(unit) and unit.faction == "player" and int(unit.x) >= int(area[0]) and int(unit.y) >= int(area[1]) and int(unit.x) <= int(area[2]) and int(unit.y) <= int(area[3]): return false
	for flag in conditions.get("story_flags", []):
		var flags: Dictionary = chapter.get("story_flags", {})
		if not flags.get(flag, false): return false
	for id in conditions.get("prior_levels", {}):
		if int(chapter.get("campaign_roster", {}).get(id, {}).get("level", 0)) < int(conditions.prior_levels[id]): return false
	for id in conditions.get("deployed_class_level", {}):
		var unit := get_unit(str(id))
		var requirement: Dictionary = conditions.deployed_class_level[id]
		if not _on_map(unit) or unit.faction != "player" or int(unit.get("rom_class_id", -1)) != int(requirement.class_id) or int(unit.level) < int(requirement.level): return false
	for query in conditions.get("native_unit_presence",[]):
		if not NativeRunner.test_value(self,native_event_state,query,{}): return false
	if conditions.has("native_flag_count") and not NativeFlags.matches(native_event_state,conditions.native_flag_count): return false
	for flag in conditions.get("native_flags_all",[]):
		if not NativeFlags.has_flag(native_event_state,int(flag)): return false
	for flag in conditions.get("native_flags_not",[]):
		if NativeFlags.has_flag(native_event_state,int(flag)): return false
	if conditions.has("defeated_characters"):
		var count := 0
		for unit in units:
			if int(unit.hp) <= 0 and _has_numeric_id(conditions.defeated_characters.get("ids",[]),int(unit.get("rom_character_id",-1))): count += 1
		if count < int(conditions.defeated_characters.get("min",0)) or count > int(conditions.defeated_characters.get("max",999)): return false
	if conditions.has("opened_doors"):
		var count := 0
		for site in interactions:
			if site.get("type","") == "door" and site.get("used",false): count += 1
		if count < int(conditions.opened_doors.get("min",0)) or count > int(conditions.opened_doors.get("max",999)): return false
	if int(chapter.get("earned_experience", 0)) < int(conditions.get("chapter_exp_min", 0)): return false
	if conditions.has("levels_sum"):
		if _roster_levels(conditions.levels_sum.get("units", [])) < int(conditions.levels_sum.get("min", 0)): return false
	if conditions.has("native_levels_sum"):
		# Native lord-route callbacks sum living player levels, including reserves,
		# without the promotion bonus used by the older level-group adapter.
		var query: Variant = conditions.native_levels_sum
		if not query is Dictionary or not NativeRunner.keys(query,["characters","min"]) or not query.characters is Array or query.characters.is_empty() or not NativeFlags.integer(query.min,1,256) or not query.characters.all(func(id):return NativeFlags.integer(id,1,255)): return false
		var total := 0
		for unit in Army.all_units(self):
			if unit.faction == "player" and int(unit.hp) > 0 and _has_numeric_id(query.characters,int(unit.get("rom_character_id",0))): total += int(unit.level)
		if total < int(query.min): return false
	if conditions.has("level_group_compare"):
		if _roster_levels(conditions.level_group_compare.a) <= _roster_levels(conditions.level_group_compare.b): return false
	if conditions.has("survivors"):
		var count := 0
		for id in conditions.survivors.get("units", []):
			if int(get_unit(str(id)).get("hp", 0)) > 0: count += 1
		if count < int(conditions.survivors.get("min", 0)) or count > int(conditions.survivors.get("max", 999)): return false
	if turn < int(conditions.get("turn_min", 1)) or turn > int(conditions.get("turn_max", 2147483647)): return false
	if conditions.has("enemy_count"):
		var count := 0
		for unit in units:
			if unit.faction == "enemy" and int(unit.hp) > 0 and not unit.get("escaped", false) and not conditions.enemy_count.get("exclude", []).has(str(unit.id)): count += 1
		if count < int(conditions.enemy_count.get("min", 0)) or count > int(conditions.enemy_count.get("max", units.size())): return false
	for id in conditions.get("unit_position", {}):
		var unit := get_unit(str(id))
		var cell: Array = conditions.unit_position[id]
		if not _on_map(unit) or position(unit) != Vector2i(int(cell[0]), int(cell[1])): return false
	for id in conditions.get("unit_faction", {}):
		var unit := get_unit(str(id))
		if unit.is_empty() or unit.faction != conditions.unit_faction[id]: return false
	for id in conditions.get("unit_not_faction", {}):
		var unit := get_unit(str(id))
		if unit.is_empty() or unit.faction == conditions.unit_not_faction[id]: return false
	for id in conditions.get("unit_alive", []):
		var unit := get_unit(str(id))
		if unit.is_empty() or int(unit.hp) <= 0: return false
	for id in conditions.get("unit_dead", []):
		var unit := get_unit(str(id))
		if unit.is_empty() or int(unit.hp) > 0: return false
	for id in conditions.get("events_fired", []):
		if not fired_events.has(str(id)): return false
	for id in conditions.get("events_not_fired", []):
		if fired_events.has(str(id)): return false
	return true

func _apply_event_effects(event: Dictionary, context: Dictionary = {}) -> bool:
	if event.has("native_program"):
		return native_events_ready and NativeRunner.execute(self,event,context)
	NativeFlags.effects(native_event_state,event)
	for flag in event.get("set_story_flags", {}):
		chapter.get_or_add("story_flags", {})[flag] = event.set_story_flags[flag]
	for relocation in event.get("relocate_units", []):
		var unit := get_unit(str(relocation.unit_id))
		if not _on_map(unit): continue
		var destination := Vector2i(int(relocation.x), int(relocation.y))
		var cells: Array[Vector2i] = []
		for y in range(height):
			for x in range(width):
				var cell := Vector2i(x, y)
				if movement_cost(unit, cell) > 0 and unit_at(cell).is_empty(): cells.append(cell)
		cells.sort_custom(func(a,b): return _distance(a,destination) < _distance(b,destination))
		if not cells.is_empty():
			unit.x = cells[0].x; unit.y = cells[0].y
			_sync_carried(unit)
	for id in event.get("promote_units", []):
		var unit := get_unit(str(id))
		if unit.is_empty() or unit.get("promoted",false): continue
		if rules.promotion_catalog.get("promotions",[]).is_empty(): rules.promotion_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://content/fe7/promotion_manifest.json"))
		for route in rules.promotion_catalog.promotions:
			if int(route.from_class) == int(unit.get("rom_class_id",-1)):
				_apply_class_change(unit,_class_definition(int(route.to_class)))
				break
	for change in event.get("map_changes", []):
		_apply_map_change({"id": str(event.get("id", "event")), "map_change": change})
		phase_actions.append({"type": "map_change", "id": str(event.get("id", "event"))})
	for id in event.get("remove_units", []):
		var unit := get_unit(str(id))
		if _on_map(unit):
			unit.escaped = true
			phase_actions.append({"type": "escape", "unit_id": unit.id})
	if event.has("schedule_departure"):
		var unit := get_unit(str(event.schedule_departure))
		if not unit.is_empty(): unit.departure_turn = turn + 1
	for scheduled in event.get("activate_events", []):
		for definition in chapter.get("events", []):
			if definition.get("id", "") == scheduled:
				definition.turn = turn + int(definition.get("activation_delay", 1))
	if event.get("result", "") in ["victory", "defeat"]: outcome = event.result
	for change in event.get("ai_changes", []):
		var unit := get_unit(str(change.unit_id)) if change.has("unit_id") else unit_at(Vector2i(int(change.x), int(change.y)))
		if not unit.is_empty() and unit.faction in ["enemy", "neutral"]:
			if change.has("npc_escape"): unit.npc_escape = change.npc_escape.duplicate(true)
			if change.has("ai_no_attack"): unit.ai_no_attack = change.ai_no_attack
			unit.ai_mode = str(change.ai_mode)
			if change.has("ai_escape_points"): unit.ai_escape_points = change.ai_escape_points.duplicate(true)
	if event.has("fog_radius") and not rules.get("clear_fog", false): rules.fog_radius = int(event.fog_radius)
	if event.has("rom_sound"): native_sound_queue.append(int(event.rom_sound))
	if event.has("weather"):
		rules.weather = int(event.weather)
		if NativeFlags.game(chapter) == "fe6": rules.weather_effect = "snow" if int(event.weather) == 2 else ""
		elif chapter.get("dynamic_rom",false): rules.weather_effect = "sandstorm" if int(event.weather) == 6 else ("snow" if int(event.weather) in [1,2] else "")
	if event.has("weather_effect"): rules.weather_effect = str(event.weather_effect)
	for spawn in event.get("spawns", []):
		var existed := not get_unit(str(spawn.get("id", ""))).is_empty()
		_spawn_unit(spawn,context.get("initial_deployment",false))
		if not existed and not get_unit(str(spawn.get("id", ""))).is_empty() and spawn.get("faction", "") == "player":
			chapter.get_or_add("reward_notices", []).append({"recruit": str(spawn.get("name", "Ally"))})
	for change in event.get("change_faction", []):
		var unit := get_unit(str(change.get("unit_id", "")))
		if unit.is_empty() or int(unit.hp) <= 0: continue
		if unit.faction != "player" and change.get("faction", "") == "player":
			chapter.get_or_add("reward_notices", []).append({"recruit": str(unit.name)})
		unit.faction = str(change.get("faction", unit.faction))
		if unit.faction == "player": unit.erase("reinforcement_ready_turn")
		Rogue.initialize_unit(self, unit)
		unit.acted = not str(unit.rescued_by).is_empty()
		unit.moved = unit.acted
		unit.move_spent = 0
		unit.traded = false
		unit.canto_active = false
		unit.canto_remaining = 0
	var dialogue: Array = event.get("dialogue_by_unit", {}).get(str(context.get("unit_id", "")), event.get("dialogue", [])).duplicate(true)
	if event.get("trigger") == "unit_defeated":
		var fallen := get_unit(str(event.get("unit_id", "")))
		for page in dialogue:
			if not fallen.is_empty() and (str(page.get("portrait", "")).is_empty() or page.get("portrait") == fallen.get("portrait") or page.get("speaker") == fallen.get("name")):
				page.portrait = fallen.get("portrait", "")
				page.left_portrait = page.portrait
				page.right_portrait = ""
				page.speaker = fallen.get("name", page.get("speaker", ""))
				page.speaker_side = "left"
				page.rom_portrait_slots = true
	var actor := get_unit(str(context.get("unit_id", "")))
	if not actor.is_empty(): _resolve_visit_dialogue(dialogue, actor)
	dialogue_queue.append_array(dialogue)
	if event.has("map_change"): _apply_map_change(event)
	_award_reward(event.get("reward", {}), str(context.get("unit_id", "")))
	for gift in event.get("give_items", []): _give_item(str(gift.get("unit_id", "")), gift.get("item", {}))
	if event.has("give_item_to_actor") and not actor.is_empty(): _give_item(str(actor.id), event.give_item_to_actor)
	for id in event.get("complete_level", []):
		var unit := get_unit(str(id))
		if unit.is_empty() or int(unit.hp) <= 0 or int(unit.level) >= int(rules.max_level): continue
		if str(unit.id) == "fe7_unit_3" and str(chapter.get("id", "")) == "fe7_tutorial_prologue" and int(unit.level) >= 2: continue
		var reward := _award_experience(unit, int(rules.experience_per_level) - int(unit.exp))
		if int(reward.amount) > 0: experience_queue.append(reward)
	if event.has("message"): events_log.append(str(event.message))
	return true

func _award_reward(reward: Variant, unit_id: String = "") -> Dictionary:
	var delivery := {}
	if reward is Dictionary:
		gold += int(reward.get("gold", 0))
		if reward.get("item") is Dictionary:
			delivery = _give_item(unit_id, reward.item)
		elif reward.has("item"):
			delivery = _give_item(unit_id, {"name":str(reward.item)})
		if int(reward.get("gold", 0)) > 0:
			chapter.get_or_add("reward_notices", []).append({"reward": {"gold": reward.gold}})
	elif reward is String and not reward.is_empty():
		inventory.append(reward)
	return delivery

func _support_identity(id: String) -> String:
	var unit := get_unit(id)
	return str(unit.get("support_id", id)) if not unit.is_empty() else id

func _support_unit(id: String) -> Dictionary:
	var direct := get_unit(id)
	if not direct.is_empty(): return direct
	for unit in units:
		if str(unit.get("support_id", unit.id)) == id: return unit
	return {}

func _pair_key(a: String, b: String) -> String:
	a = _support_identity(a)
	b = _support_identity(b)
	return a + "|" + b if a < b else b + "|" + a

func _pending_support_gains() -> Dictionary:
	var gains := {}
	if not bool(rules.get("supports_enabled", true)): return gains
	if int(rules.get("support_chapter_gain_limit", 0)) > 0 and support_chapter_gain >= int(rules.support_chapter_gain_limit): return gains
	for pair in chapter.get("support_pairs", []):
		var a := _support_unit(str(pair.get("a", "")))
		var b := _support_unit(str(pair.get("b", "")))
		if a.is_empty() or b.is_empty() or int(a.hp) <= 0 or int(b.hp) <= 0: continue
		if a.faction != "player" or b.faction != "player": continue
		var rescued: bool = str(a.get("carrying_id", "")) == str(b.id) or str(b.get("carrying_id", "")) == str(a.id)
		if not rescued and (not _on_map(a) or not _on_map(b) or (not rules.get("support_any_distance", false) and _distance(position(a), position(b)) != 1)): continue
		var key := _pair_key(str(a.id), str(b.id))
		var rank := int(support_ranks.get(key, 0))
		if rank >= rules.support_thresholds.size() or (not rules.get("unlimited_supports", false) and (_total_support_rank(str(a.id)) >= int(rules.support_total_cap) or _total_support_rank(str(b.id)) >= int(rules.support_total_cap))): continue
		gains[key] = mini(maxi(0, int(pair.get("growth", 1))), maxi(0, int(rules.support_thresholds[rank]) - int(support_points.get(key, 0))))
	return gains

func _commit_support_gains(gains: Dictionary, completed_turn: int) -> void:
	if completed_turn <= support_last_gain_turn or not bool(rules.get("supports_enabled", true)): return
	support_last_gain_turn = completed_turn
	if not outcome.is_empty() and (outcome != "victory" or chapter.get("objective", {}).get("type", "") != "survive"): return
	for key in gains:
		var amount := int(gains[key])
		if Rogue.army(self, "tea_time") > 0:
			var fractions: Dictionary = chapter.rogue.get_or_add("support_fractions", {})
			var scaled := amount * Rogue.army(self, "tea_time") + int(fractions.get(key, 0))
			@warning_ignore("integer_division") # Intentional integer truncation.
			amount += scaled / 10
			fractions[key] = scaled % 10
		support_points[key] = int(support_points.get(key, 0)) + amount
		support_chapter_gain += amount * int(rules.get("support_gain_counter_multiplier", 1))

func _gain_support_points() -> void:
	# Retained for data-driven engine clients; guards against duplicate accrual.
	_commit_support_gains(_pending_support_gains(), turn)

func _total_support_rank(id: String) -> int:
	id = _support_identity(id)
	var total := 0
	for key in support_ranks:
		if str(key).split("|").has(id): total += int(support_ranks[key])
	return total

func support_partners(id: String) -> Array:
	var result: Array = []
	for other in units:
		if can_support(id, str(other.id)): result.append(other)
	return result

func support_records(id: String = "") -> Array:
	var result: Array = []
	var identity := _support_identity(id)
	for pair in chapter.get("support_pairs", []):
		var a_id := str(pair.get("a", ""))
		var b_id := str(pair.get("b", ""))
		if not identity.is_empty() and identity not in [_support_identity(a_id), _support_identity(b_id)]: continue
		var a := _support_unit(a_id)
		var b := _support_unit(b_id)
		var key := _pair_key(a_id, b_id)
		var rank := clampi(int(support_ranks.get(key, 0)), 0, rules.support_thresholds.size())
		var points := int(support_points.get(key, pair.get("points", 0)))
		var threshold := int(rules.support_thresholds[rank]) if rank < rules.support_thresholds.size() else 0
		var a_used := _total_support_rank(a_id)
		var b_used := _total_support_rank(b_id)
		var reason := ""
		if not bool(rules.get("supports_enabled", true)): reason = str(rules.get("supports_disabled_reason", "Supports are disabled for this chapter."))
		elif threshold == 0: reason = "Maximum support rank reached."
		elif not rules.get("unlimited_supports", false) and (a_used >= int(rules.support_total_cap) or b_used >= int(rules.support_total_cap)): reason = "A character has used all five support ranks."
		elif rules.get("support_once_per_map", true) and not rules.get("unlimited_supports", false) and support_used_pairs.has(key): reason = "This pair has already supported on this map."
		var active: bool = bool(rules.get("supports_enabled", true)) and rank > 0 and _on_map(a) and _on_map(b) and a.faction == "player" and b.faction == "player" and _distance(position(a), position(b)) <= int(rules.support_range)
		result.append({"key": key, "a": a_id, "b": b_id, "a_name": str(a.get("name", pair.get("a_name", a_id.capitalize()))), "b_name": str(b.get("name", pair.get("b_name", b_id.capitalize()))), "a_unit_id": str(a.get("id", "")), "b_unit_id": str(b.get("id", "")), "rank": rank, "rank_label": ["—", "C", "B", "A"][mini(rank, 3)], "points": points, "next_threshold": threshold, "remaining": maxi(0, threshold - points), "growth": int(pair.get("growth", 1)), "ready": reason.is_empty() and threshold > 0 and points >= threshold, "can_converse": (not a.is_empty() and not b.is_empty()) and (can_support(str(a.id), str(b.id)) or can_support(str(b.id), str(a.id))), "used_this_map": support_used_pairs.has(key), "disabled_reason": reason, "a_ranks_used": a_used, "b_ranks_used": b_used, "rank_cap": int(rules.support_total_cap), "active": active})
	return result

func support(id: String, other_id: String) -> bool:
	if not can_support(id, other_id): return false
	var a := get_unit(id)
	var b := get_unit(other_id)
	if a.get("rogue_fury", false): return false
	var key := _pair_key(id, other_id)
	var rank := int(support_ranks.get(key, 0))
	commit_move(id)
	if get_unit(id).acted: return false
	support_ranks[key] = rank + 1
	var point_bonus := int(rules.get("support_rank_point_bonus", 0))
	support_points[key] = int(support_points[key]) + point_bonus
	support_chapter_gain += point_bonus * int(rules.get("support_gain_counter_multiplier", 1))
	if not support_used_pairs.has(key): support_used_pairs.append(key)
	_finish_noncombat(a)
	events_log.append("%s and %s reached support rank %s." % [a.name, b.name, ["C", "B", "A"][mini(rank, 2)]])
	for pair in chapter.get("support_pairs", []):
		if _pair_key(str(pair.get("a", "")), str(pair.get("b", ""))) == key:
			if pair.get("dialogue_reference", false):
				dialogue_queue.append({"support_conversation": {"pair": key, "rank": rank + 1}})
			else:
				dialogue_queue.append_array(pair.get("dialogue", {}).get(str(rank + 1), []).duplicate(true))
			break
	return true

func _run_events(trigger: String, context: Dictionary = {}, native_only: bool = false) -> void:
	if chapter.has("native_pending_choice"): return
	var first_start := trigger == "chapter_start" and not native_events_ready
	if first_start: native_events_ready = true
	NativeFlags.synchronize(self)
	var definitions: Array = chapter.get("events", [])
	for index in range(definitions.size()):
		var event: Dictionary = definitions[index]
		if native_only and not event.has("native_program"): continue
		if event.has("native_program") and not native_events_ready: continue
		if event.has("native_program") and not NativeRunner.validate_event(event,NativeFlags.game(chapter)).is_empty():
			NativeRunner.execute(self,event,context)
			continue
		var event_id := str(event.get("id", "event_%d" % index))
		var region_event: bool = (event.get("trigger", "") == "enter_region" and trigger == "position") or (event.get("trigger", "") == "wait_region" and trigger == "wait")
		if event.get("search_on_wait", false) and trigger == "wait": region_event = true
		if event.get("native_action_search",false):
			if trigger not in ["wait","action_complete"]: continue
			if context.get("phase_end",false) and get_unit(str(context.get("unit_id",""))).get("acted",false): continue
			region_event = true
		var native_repeat: bool = event.has("native_program") and event.get("native_repeat",false)
		var native_stamp: Dictionary = native_event_turns.get(event_id,{})
		if native_repeat and event.get("trigger") == "turn" and int(native_stamp.get("turn",0)) == turn and native_stamp.get("phase","") == phase: continue
		if event.has("native_program") and NativeFlags.has_flag(native_event_state,int(event.native_program.get("completion_flag",0))): continue
		if (fired_events.has(event_id) and not native_repeat) or (str(event.get("trigger", "turn")) != trigger and not region_event):
			continue
		if region_event:
			var area: Array = event.get("region", [])
			if area.size() != 4: continue
			if event.get("actor_faction","player") != "any" and get_unit(str(context.get("unit_id", ""))).get("faction", "") != event.get("actor_faction","player"): continue
			if int(context.get("x", -1)) < int(area[0]) or int(context.get("x", -1)) > int(area[2]) or int(context.get("y", -1)) < int(area[1]) or int(context.get("y", -1)) > int(area[3]): continue
			if event.has("unit_id") and str(event.unit_id) != str(context.get("unit_id", "")): continue
		if not _event_conditions(event): continue
		if trigger == "turn" and ((not event.get("each_turn", false) and int(event.get("turn", 1)) != turn) or str(event.get("phase", "player")) not in [phase,"any"]):
			continue
		if event.has("delay_phases"):
			if int(event.get("last_checked_turn", -1)) == turn: continue
			event.last_checked_turn = turn
			event.delay_phases = int(event.delay_phases) - 1
			if int(event.delay_phases) > 0: continue
		if trigger == "unit_defeated" and event.has("unit_id"):
			var target := get_unit(str(event.get("unit_id", "")))
			if target.is_empty() or int(target["hp"]) > 0 or target.get("benched", false):
				continue
		if trigger == "battle":
			if event.has("unit_id") and str(event.unit_id) not in [str(context.get("attacker_id", "")), str(context.get("defender_id", ""))]:
				continue
			if event.has("attacker_id") and str(event.attacker_id) != str(context.get("attacker_id", "")):
				continue
			if event.has("defender_id") and str(event.defender_id) != str(context.get("defender_id", "")):
				continue
		if trigger in ["visit", "position", "village_destroyed", "rescue", "drop", "wait", "play"]:
			if event.has("actor_faction") and event.actor_faction != "any" and get_unit(str(context.get("unit_id", ""))).get("faction", "") != event.actor_faction: continue
			if event.has("unit_id") and str(event["unit_id"]) != str(context.get("unit_id", "")):
				continue
			if event.has("x") and int(event["x"]) != int(context.get("x", -1)):
				continue
			if event.has("y") and int(event["y"]) != int(context.get("y", -1)):
				continue
			if event.has("target_id") and str(event.target_id) != str(context.get("target_id", "")): continue
		if event.get("desert_find", false):
			var actor := get_unit(str(context.get("unit_id", "")))
			if actor.is_empty() or int(event.get("search_attempts", {}).get(str(actor.id), -1)) == turn: continue
			event.get_or_add("search_attempts", {})[str(actor.id)] = turn
			if int(actor.get("rom_class_id", -1)) not in [52,53] and rng.randi_range(0,10) != 0: continue
		if event.has("native_program"):
			if _apply_event_effects(event,context):
				# Native conditions set their flag before dispatch. A script can clear
				# it to decline activation (e.g. a switch checked on another phase).
				var completion := int(event.native_program.get("completion_flag",0))
				if not native_repeat and completion > 0 and not NativeFlags.has_flag(native_event_state,completion): continue
				if not fired_events.has(event_id): fired_events.append(event_id)
				if native_repeat: native_event_turns[event_id] = {"turn":turn,"phase":phase}
		else:
			fired_events.append(event_id)
			_apply_event_effects(event,context)
	if first_start: _run_events("turn",{},true)
	if trigger != "native_flag" and native_events_ready and (NativeFlags.game(chapter) == "fe6" or chapter.get("native_flag_dispatch",false)): _run_events("native_flag",context,true)

func _spawn_unit(definition: Dictionary, initial_deployment: bool = false) -> void:
	if definition.get("native_skip_dead",false):
		var history: Array = units+chapter.get("reserve_units",[])+chapter.get("campaign_roster",{}).values()
		if history.any(func(u):return int(u.get("rom_character_id",0)) == int(definition.get("rom_character_id",-1)) and (int(u.get("hp",0)) <= 0 or u.get("casualty_mode","") == "permanent")): return
	var unit := _normalize_unit(definition)
	Army.restore_campaign_unit(self, unit)
	if chapter.get("dynamic_rom",false) and unit.faction == "player":
		# Dynamic LOADs choose the actual party after campaign transfer. Preserve
		# inventory, progress and casualties when activating a carried reserve.
		for reserved in chapter.get("reserve_units",[]):
			if reserved.id != unit.id: continue
			if not Army.eligible(reserved): return
			chapter.reserve_units.erase(reserved)
			reserved.x = unit.x; reserved.y = unit.y; reserved.erase("benched")
			unit = reserved
			break
	if not get_unit(str(unit["id"])).is_empty():
		return
	if definition.has("spawn_near_unit"):
		var anchor := get_unit(str(definition.spawn_near_unit))
		if _on_map(anchor): unit.x = anchor.x; unit.y = anchor.y
	var destination := position(unit)
	if (bool(definition.get("blockable_spawn", false)) or terrain_id_at(destination) == Terrain.FORT) and not unit_at(destination).is_empty():
		events_log.append("%s's arrival was blocked." % unit.name)
		return
	# Roofed rooms contain dormant units at their native positions. A roof is
	# impassable to movement, but does not displace its concealed deployment.
	# Native starting formations can occupy otherwise impassable terrain;
	# movement costs constrain later movement, not their authored placement.
	if not unit_at(destination).is_empty() or (not initial_deployment and _move_cost(unit, destination) <= 0 and not _under_roof(unit)):
		var found := false
		for radius in range(1, width + height):
			for y in range(height):
				for x in range(width):
					var cell := Vector2i(x, y)
					if _distance(cell, destination) == radius and unit_at(cell).is_empty() and _move_cost(unit, cell) > 0:
						unit["x"] = x
						unit["y"] = y
						found = true
						break
				if found:
					break
			if found:
				break
		if not found:
			events_log.append("No free tile for reinforcement %s." % unit["name"])
			return
	# Dynamic opening LOADs build the starting army, not a reinforcement wave.
	if not initial_deployment and unit.faction == "enemy" and rules.get("wait_enemy_reinforcements", false):
		unit.reinforcement_ready_turn = turn + 1
		unit.acted = true
		unit.moved = true
	units.append(unit)
	events_log.append("%s arrived." % unit["name"])

func _check_objective(seized: bool = false) -> void:
	if chapter.get("dynamic_rom",false) and not native_events_ready: return
	if not outcome.is_empty():
		return
	var players := 0
	var enemies := 0
	for unit in units:
		if unit.get("escaped", false): continue
		if int(unit["hp"]) > 0:
			if unit["faction"] == "player":
				players += 1
			elif unit["faction"] == "enemy":
				enemies += 1
		elif bool(unit.get("essential", false)):
			outcome = "defeat"
	if players == 0:
		outcome = "defeat"
	var objective: Dictionary = chapter.get("objective", {"type": "rout"})
	for cell in objective.get("defend_positions", []):
		var occupier := unit_at(Vector2i(int(cell[0]), int(cell[1])))
		if not occupier.is_empty() and occupier.faction == "enemy": outcome = "defeat"
	if outcome.is_empty():
		match str(objective.get("type", "rout")):
			"rout":
				if enemies == 0 or Rogue.morale_broken(self):
					outcome = "victory"
			"defeat_boss":
				var boss := get_unit(str(objective.get("unit_id", "")))
				if not boss.is_empty() and int(boss["hp"]) <= 0:
					outcome = "victory"
			"native_seize","native_flag":
				if NativeFlags.has_flag(native_event_state,int(objective.get("flag",0))): outcome = "victory"
			"native_event":
				if chapter.get("native_event_victory",false): outcome = "victory"
			"seize":
				if seized:
					outcome = "victory"
			"survive":
				var boss := get_unit(str(objective.get("alternative_boss", "")))
				if turn > int(objective.get("turns", 5)) or (not boss.is_empty() and int(boss.hp) <= 0) or (objective.has("alternative_native_flag") and NativeFlags.has_flag(native_event_state,int(objective.alternative_native_flag))) or Rogue.morale_broken(self):
					outcome = "victory"
			"event":
				if fired_events.has(str(objective.get("event_id", ""))): outcome = "victory"
			"activate":
				var complete: bool = not objective.get("event_ids", []).is_empty()
				for event_id in objective.get("event_ids", []):
					if not fired_events.has(str(event_id)): complete = false
				if complete: outcome = "victory"
	if not outcome.is_empty():
		events_log.append("Victory!" if outcome == "victory" else "Defeat.")
		if outcome == "victory":
			preload("res://engine/fe7_campaign_rank.gd").record(self)
			Rogue.chapter_clear(self)
		_run_events(outcome)

func take_native_sounds() -> Array:
	var sounds := native_sound_queue.duplicate()
	native_sound_queue.clear()
	return sounds

func serialize(include_catalog: bool = true) -> Dictionary:
	var saved_rules := rules.duplicate(false)
	if not include_catalog: saved_rules.erase("promotion_catalog")
	return {"version": 2, "chapter": chapter.duplicate(true), "rules": saved_rules.duplicate(true), "units": units.duplicate(true), "terrain": terrain.duplicate(true), "phase": phase, "turn": turn, "outcome": outcome, "pending_moves": pending_moves.duplicate(true), "events_log": events_log.duplicate(true), "interactions": interactions.duplicate(true), "fired_events": fired_events.duplicate(true), "native_event_state": native_event_state.duplicate(true), "native_sound_queue": native_sound_queue.duplicate(), "native_events_ready": native_events_ready, "native_event_turns": native_event_turns.duplicate(true), "support_points": support_points.duplicate(true), "support_ranks": support_ranks.duplicate(true), "support_used_pairs": support_used_pairs.duplicate(true), "support_last_gain_turn": support_last_gain_turn, "support_chapter_gain": support_chapter_gain, "inventory": inventory.duplicate(true), "gold": gold, "chapter_repairs_applied": chapter_repairs_applied, "dialogue_queue": dialogue_queue.duplicate(true), "experience_queue": experience_queue.duplicate(true), "destructibles": destructibles.duplicate(true), "map_patches": map_patches.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}

func _valid_event_definition(event: Dictionary, flag_game: String = "fe7") -> bool:
	if not event.get("conditions", {}) is Dictionary: return false
	if not NativeFlags.valid_event(event,flag_game): return false
	if not preload("res://engine/recruitment_offers.gd").valid(event,flag_game): return false
	var presence: Variant = event.get("conditions",{}).get("native_unit_presence",[])
	if not presence is Array or presence.size() > 32: return false
	for query in presence:
		if not NativeRunner.valid_test(query,flag_game) or query.kind not in (["presence","fe6"] if flag_game == "fe6" else ["presence","route","phase","constant","affiliation","flag_pair","support_rank","phase_terrain","occupied_tiles","enemy_count_at_most","route_support_flag"]): return false
	if event.has("native_program") and not NativeRunner.validate_event(event,flag_game).is_empty(): return false
	for key in ["turn_min", "turn_max"]:
		var value: Variant = event.get("conditions", {}).get(key, 1)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 1 or float(value) != floor(float(value)): return false
	for key in ["unit_alive", "unit_dead", "events_fired", "events_not_fired", "story_flags", "story_flags_not", "recruits_available", "player_alive", "player_not_alive", "sites_used", "sites_visited", "occupied_player_regions", "empty_player_regions"]:
		if not event.get("conditions", {}).get(key, []) is Array: return false
	for area in event.get("conditions", {}).get("empty_player_regions", []) + event.get("conditions", {}).get("occupied_player_regions", []):
		if not area is Array or area.size() != 4: return false
		for coordinate in area:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate) != floor(float(coordinate)): return false
	if not event.get("set_story_flags", {}) is Dictionary or not event.get("each_turn", false) is bool: return false
	for value in event.get("set_story_flags", {}).values():
		if not value is bool: return false
	for key in ["delay_phases", "last_checked_turn"]:
		var value: Variant = event.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) != floor(float(value)): return false
	for key in ["unit_faction", "unit_not_faction", "unit_position", "enemy_count"]:
		if not event.get("conditions", {}).get(key, {}) is Dictionary: return false
	for cell in event.get("conditions", {}).get("unit_position", {}).values():
		if not cell is Array or cell.size() != 2: return false
		for value in cell:
			if not value is int and not value is float: return false
	for key in ["complete_level", "change_faction"]:
		if not event.get(key, []) is Array: return false
	for id in event.get("complete_level", []):
		if not id is String: return false
	for change in event.get("change_faction", []):
		if not change is Dictionary or not change.get("unit_id", "") is String or change.get("faction", "") not in ["player", "enemy", "neutral"]: return false
	return true

func _valid_experience_reward(reward: Variant) -> bool:
	if not reward is Dictionary or not reward.get("unit_id", "") is String or not reward.get("levels", []) is Array: return false
	for key in ["amount", "before_level", "before_exp", "after_level", "after_exp", "threshold"]:
		if not reward.get(key) is int and not reward.get(key) is float: return false
		if not is_finite(float(reward[key])) or float(reward[key]) < 0: return false
	if int(reward.threshold) <= 0: return false
	for key in ["before_stats", "after_stats"]:
		if not reward.get(key, {}) is Dictionary: return false
	for level in reward.levels:
		if not level is Dictionary or not level.get("gains", {}) is Dictionary or not level.get("before_stats", {}) is Dictionary or not level.get("after_stats", {}) is Dictionary: return false
	return true

func restore(data: Dictionary) -> bool:
	# Reject malformed suspend files before mutating live state.
	if int(data.get("version", -1)) != 2 or not data.get("chapter") is Dictionary or not data.get("units") is Array or not data.get("terrain") is Array:
		return false
	if not data.get("chapter_repairs_applied", true) is bool: return false
	if not data.get("pending_moves", {}) is Dictionary: return false
	for id in data.get("pending_moves", {}):
		var planned = data.pending_moves[id]
		if not id is String or not planned is Dictionary: return false
		for axis in ["x", "y"]:
			var coordinate = planned.get(axis)
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate) != floor(float(coordinate)): return false
	if not data.get("native_events_ready",true) is bool or not NativeRunner.valid_dispatch_state(data.get("native_event_turns",{})): return false
	if not NativeRunner.valid_sound_queue(data.get("native_sound_queue",[])): return false
	var saved_chapter: Dictionary = data.chapter
	if saved_chapter.has("native_pending_choice") and (NativeFlags.game(saved_chapter) != "fe7" or not NativeRunner.valid_pending_choice(saved_chapter.native_pending_choice)): return false
	if saved_chapter.has("fe6_step_traps"):
		if not preload("res://engine/fe6_event_actions.gd").valid_traps(saved_chapter.fe6_step_traps): return false
		if data.terrain.is_empty() or saved_chapter.fe6_step_traps.any(func(t):return int(t.y) >= data.terrain.size() or not data.terrain[int(t.y)] is String or int(t.x) >= data.terrain[int(t.y)].length()): return false
	if saved_chapter.has("fe6_ending") and not NativeFlags.integer(saved_chapter.fe6_ending,0,2): return false
	if saved_chapter.has("campaign_end") and not saved_chapter.campaign_end is bool: return false
	if saved_chapter.has("fe6_last_battle_items") and (not saved_chapter.fe6_last_battle_items is Array or saved_chapter.fe6_last_battle_items.size() != 2 or not saved_chapter.fe6_last_battle_items.all(func(v):return NativeFlags.integer(v,0,255))): return false
	if saved_chapter.has("native_next_chapter"):
		var destination: Variant = saved_chapter.native_next_chapter
		var destination_root := "res://content/fe7/dynamic/"+str(saved_chapter.get("rom_sha256",""))+"/chapters/" if NativeFlags.game(saved_chapter) == "fe7" else "res://content/fe6/chapters/"
		if not destination is String or (not destination.is_empty() and (not destination.begins_with(destination_root) or destination.contains("..") or not destination.ends_with(".json"))): return false
	if saved_chapter.has("fe7_tutorials") and not preload("res://engine/fe7_tutorial.gd").valid(saved_chapter.fe7_tutorials): return false
	if not NativeFlags.integer(saved_chapter.get("fe7_lesson_selection_turn",0),0,2147483647): return false
	if not preload("res://engine/fe7_campaign_rank.gd").valid(saved_chapter): return false
	for key in ["fe7_earned_experience","fe7_exp_baseline"]:
		if not NativeFlags.integer(saved_chapter.get(key,0),0,2147483647): return false
	if not saved_chapter.get("fe7_experience",{}) is Dictionary or saved_chapter.get("fe7_experience",{}).size() > 255: return false
	for character in saved_chapter.get("fe7_experience",{}):
		if not character is String or not character.is_valid_int() or not NativeFlags.integer(int(character),1,255) or not NativeFlags.integer(saved_chapter.fe7_experience[character],0,4000): return false
	if not saved_chapter.get("fe6_experience",{}) is Dictionary or saved_chapter.get("fe6_experience",{}).size()>255: return false
	for character in saved_chapter.get("fe6_experience",{}):
		if not character is String or not character.is_valid_int() or not NativeFlags.integer(int(character),1,255) or not NativeFlags.integer(saved_chapter.fe6_experience[character],0,4000): return false
	if not NativeFlags.integer(saved_chapter.get("fe6_ambush_count",0),0,255): return false
	if saved_chapter.has("native_route") and not NativeFlags.integer(saved_chapter.native_route,1,3): return false
	if not NativeFlags.valid_bindings(saved_chapter.get("native_flag_bindings",{}),NativeFlags.game(saved_chapter)) or not NativeFlags.valid_state(data.get("native_event_state"),NativeFlags.game(saved_chapter)): return false
	var saved_rogue: bool = preload("res://engine/campaign_difficulty.gd").is_rogue(saved_chapter.get("difficulty", ""))
	if not saved_chapter.get("torch_lights", []) is Array: return false
	for light in saved_chapter.get("torch_lights", []):
		if not light is Dictionary: return false
		for field in ["x", "y", "radius"]:
			if not (light.get(field) is int or light.get(field) is float) or not is_finite(float(light[field])) or float(light[field]) != floor(float(light[field])): return false
		if int(light.x) < 0 or int(light.y) < 0 or int(light.radius) < 1 or int(light.radius) > 8: return false
	for field in ["units", "events", "talks", "support_pairs", "interactions"]:
		if not saved_chapter.get(field, []) is Array:
			return false
		for entry in saved_chapter.get(field, []):
			if not entry is Dictionary:
				return false
	if not saved_chapter.get("objective", {}) is Dictionary or not saved_chapter.get("rules", {}) is Dictionary:
		return false
	for event in saved_chapter.get("events", []) + saved_chapter.get("talks", []):
		if not _valid_event_definition(event,NativeFlags.game(saved_chapter)): return false
		if not event.get("spawns", []) is Array or not event.get("dialogue", []) is Array or not event.get("give_items", []) is Array:
			return false
		for gift in event.get("give_items", []):
			if not gift is Dictionary or not gift.get("item", {}) is Dictionary:
				return false
		for spawn in event.get("spawns", []):
			if not spawn is Dictionary:
				return false
	var rows: Array = data["terrain"]
	if rows.is_empty() or not rows[0] is String or rows[0].is_empty():
		return false
	for row in rows:
		if not row is String or row.length() != rows[0].length():
			return false
	if not Traps.valid(saved_chapter.get("placed_traps", []), rows): return false
	if not MapCycles.valid(saved_chapter.get("map_cycles", []), rows): return false
	if not saved_chapter.get("hazards",[]) is Array: return false
	for hazard in saved_chapter.get("hazards",[]):
		if not hazard is Dictionary: return false
		if hazard.get("type") != "light_arrow": continue
		if not NativeFlags.integer(hazard.get("x"),0,rows[0].length()-1) or not NativeFlags.integer(hazard.get("y"),0,rows.size()-1): return false
		for field in ["first_turn","period","damage"]:
			if not NativeFlags.integer(hazard.get(field),1,255): return false
	var ids: Array = []
	var occupied: Array = []
	var saved_by_id: Dictionary = {}
	var reserves: Variant = saved_chapter.get("reserve_units", [])
	if not reserves is Array: return false
	for reserve in reserves:
		if not reserve is Dictionary or not reserve.get("benched", false) or reserve.get("faction", "") != "player": return false
	for unit in data["units"] + reserves:
		if not unit is Dictionary or not unit.has("id") or not unit.has("x") or not unit.has("y") or not unit.has("hp") or not unit.get("weapon", {}) is Dictionary:
			return false
		if not unit.get("carrying_id", "") is String or not unit.get("rescued_by", "") is String: return false
		if not unit.get("traded", false) is bool: return false
		if not unit.get("temporary_bonuses", {}) is Dictionary: return false
		if not unit.get("ring_bonuses", {}) is Dictionary: return false
		for key in unit.get("ring_bonuses", {}):
			if key not in ["def", "res", "attack", "crit", "avoid"] or unit.ring_bonuses[key] != 10: return false
		if not unit.get("weapon_exp", {}) is Dictionary: return false
		for key in unit.get("weapon_exp", {}):
			var value: Variant = unit.weapon_exp[key]
			if not key is String or not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or float(value) < 0 or float(value) > 255: return false
		for key in ["promoted", "multiple_s_ranks"]:
			if not unit.get(key, false) is bool: return false
		if not unit.get("escaped", false) is bool or not unit.get("stolen_items", []) is Array: return false
		for item in unit.get("stolen_items", []):
			if not item is Dictionary: return false
		if unit.get("escaped", false) and (not str(unit.get("carrying_id", "")).is_empty() or not str(unit.get("rescued_by", "")).is_empty()): return false
		for key in unit.get("temporary_bonuses", {}):
			var bonus: Variant = unit.temporary_bonuses[key]
			if key not in ["str", "skill", "speed", "def", "res", "luck"] or not (bonus is int or bonus is float): return false
			if not is_finite(float(bonus)) or float(bonus) < 0 or float(bonus) > 255 or float(bonus) != floor(float(bonus)): return false
		if not str(unit.get("carrying_id", "")).is_empty() and not str(unit.get("rescued_by", "")).is_empty(): return false
		if not unit.get("drop_item", {}) is Dictionary:
			return false
		var saved_move := int(unit.get("mov", 5))
		if saved_rogue: saved_move = maxi(0, saved_move + Rogue.permanent(unit, "mov") + Rogue.temporary(unit, "mov"))
		var rogue_canto: bool = saved_rogue and Rogue.count(unit, "canto") > 0
		for field in ["move_spent", "canto_remaining"]:
			var value: Variant = unit.get(field, 0)
			if not (value is int or value is float) or not is_finite(float(value)) or int(value) < 0 or int(value) > (maxi(255, saved_move) if field == "move_spent" else saved_move + (3 * Rogue.count(unit, "canto") if rogue_canto else 0)):
				return false
		if not rogue_canto and bool(unit.get("canto_active", false)) and (not bool(unit.get("canto", false)) or unit.get("faction", "") != "player" or data.get("phase", "") != "player" or int(unit.hp) <= 0 or bool(unit.get("acted", false)) or int(unit.get("canto_remaining", 0)) <= 0 or int(unit.get("move_spent", 0)) + int(unit.get("canto_remaining", 0)) != saved_move):
			return false
		if not unit.get("inventory", []) is Array or not unit.get("growths", {}) is Dictionary or not unit.get("stat_caps", {}) is Dictionary or not unit.get("weapon_types", []) is Array:
			return false
		for item in unit.get("inventory", []):
			if not item is Dictionary:
				return false
		if ids.has(str(unit["id"])) or int(unit["x"]) < 0 or int(unit["y"]) < 0 or int(unit["x"]) >= rows[0].length() or int(unit["y"]) >= rows.size():
			return false
		ids.append(str(unit["id"]))
		saved_by_id[str(unit.id)] = unit
		if _on_map(unit):
			var cell := Vector2i(int(unit["x"]), int(unit["y"]))
			if saved_chapter.get("placed_traps", []).any(func(trap): return trap.kind == "light_rune" and Vector2i(trap.x, trap.y) == cell): return false
			# Tentative movement may visually overlap a concealed enemy.
			# Occupancy is reserved at the player's committed origin until
			# the path is committed and the hidden blocker is resolved.
			if data.get("pending_moves", {}).has(str(unit.id)):
				var planned: Dictionary = data.pending_moves[str(unit.id)]
				cell = Vector2i(int(planned.x), int(planned.y))
			if occupied.has(cell):
				return false
			occupied.append(cell)
	for id in saved_by_id:
		var unit: Dictionary = saved_by_id[id]
		var carrying := str(unit.get("carrying_id", ""))
		var rescued := str(unit.get("rescued_by", ""))
		if not carrying.is_empty():
			if carrying == id or not saved_by_id.has(carrying) or int(unit.hp) <= 0: return false
			var passenger: Dictionary = saved_by_id[carrying]
			if passenger.get("rescued_by", "") != id or int(passenger.hp) <= 0 or position(unit) != position(passenger): return false
		if not rescued.is_empty():
			if rescued == id or not saved_by_id.has(rescued) or int(unit.hp) <= 0: return false
			var carrier: Dictionary = saved_by_id[rescued]
			if carrier.get("carrying_id", "") != id or not bool(unit.get("acted", false)) or bool(unit.get("canto_active", false)): return false
	if not ["player", "enemy"].has(str(data.get("phase", ""))) or int(data.get("turn", 0)) < 1 or not ["", "victory", "defeat"].has(str(data.get("outcome", ""))):
		return false
	if not data.get("pending_moves", {}) is Dictionary:
		return false
	var pending: Dictionary = data.get("pending_moves", {})
	if pending.size() > 1 or (not pending.is_empty() and (data.phase != "player" or not str(data.get("outcome", "")).is_empty())):
		return false
	for id in pending:
		var origin = pending[id]
		var free_move: bool = data.get("phase", "") == "player" and int(data.get("rules", {}).get("cheat_move_turn", -1)) == int(data.get("turn", 0))
		var savior_jump: bool = saved_rogue and Rogue.count(saved_by_id.get(str(id), {}), "savior") > 0
		if not origin is Dictionary or not origin.has("x") or not origin.has("y") or (bool(origin.get("moved", false)) and not free_move) or not ids.has(str(id)):
			return false
		var cell := Vector2i(int(origin.x), int(origin.y))
		if cell.x < 0 or cell.y < 0 or cell.x >= rows[0].length() or cell.y >= rows.size():
			return false
		if origin.has("path"):
			if not origin.path is Array or origin.path.is_empty() or origin.path.size() > rows.size() * rows[0].length() + 1: return false
			var last := cell
			for index in range(origin.path.size()):
				var coordinates = origin.path[index]
				if not coordinates is Array or coordinates.size() != 2: return false
				for coordinate in coordinates:
					if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate) != floor(float(coordinate)): return false
				var step := Vector2i(int(coordinates[0]), int(coordinates[1]))
				if step.x < 0 or step.y < 0 or step.x >= rows[0].length() or step.y >= rows.size(): return false
				if (index == 0 and step != cell) or (index > 0 and _distance(last, step) != 1 and not free_move and not savior_jump): return false
				last = step
			if last != position(saved_by_id[str(id)]): return false
		for unit in data.units:
			if str(unit.id) == str(id):
				if unit.get("faction", "") != "player" or not str(unit.get("rescued_by", "")).is_empty() or int(unit.hp) <= 0 or bool(unit.get("acted", false)) or not bool(unit.get("moved", false)):
					return false
				var cost: Variant = origin.get("cost", 0)
				var budget := _movement_budget(unit)
				if saved_rogue: budget = int(unit.get("canto_remaining", 0)) if unit.get("canto_active", false) else maxi(0, int(unit.get("mov", 5)) + Rogue.permanent(unit, "mov") + Rogue.temporary(unit, "mov"))
				if not (cost is int or cost is float) or not is_finite(float(cost)) or int(cost) < 0 or int(cost) > budget:
					return false
			elif _on_map(unit) and position(unit) == cell:
				return false
	for key in ["rules", "support_points", "support_ranks"]:
		if not data.get(key, {}) is Dictionary:
			return false
	if not DURABILITY_MODES.has(str(data.get("rules", {}).get("durability_mode", "normal"))): return false
	if not ["lords", "anywhere"].has(str(data.get("rules", {}).get("supply_access", "lords"))): return false
	if not ["normal", "supply_keys", "free"].has(str(data.get("rules", {}).get("chest_unlock_mode", "normal"))): return false
	if not ["normal", "supply_keys", "free"].has(str(data.get("rules", {}).get("door_unlock_mode", "normal"))): return false
	for key in ["events_log", "interactions", "fired_events", "inventory", "dialogue_queue", "experience_queue", "map_patches", "support_used_pairs"]:
		if not data.get(key, []) is Array:
			return false
	for item in data.get("inventory", []):
		if not item is Dictionary or item.is_empty(): return false
	for field in ["support_points", "support_ranks"]:
		for key in data.get(field, {}):
			var value: Variant = data[field][key]
			if not key is String or key.split("|").size() != 2 or not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) != floor(float(value)): return false
			if field == "support_ranks" and int(value) > 3: return false
	var used_supports: Array = []
	for key in data.get("support_used_pairs", []):
		if not key is String or not data.get("support_ranks", {}).has(key) or int(data.support_ranks[key]) <= 0 or used_supports.has(key): return false
		used_supports.append(key)
	var chapter_gain: Variant = data.get("support_chapter_gain", 0)
	if not (chapter_gain is int or chapter_gain is float) or not is_finite(float(chapter_gain)) or float(chapter_gain) != int(chapter_gain) or int(chapter_gain) < 0: return false
	var last_support_turn: Variant = data.get("support_last_gain_turn", 0)
	if not (last_support_turn is int or last_support_turn is float) or not is_finite(float(last_support_turn)) or int(last_support_turn) < 0 or int(last_support_turn) > int(data.turn): return false
	for reward in data.get("experience_queue", []):
		if not _valid_experience_reward(reward): return false
	var saved_structures: Variant = data.get("destructibles", saved_chapter.get("destructibles", []))
	if not saved_structures is Array: return false
	for structure in saved_structures:
		if not structure is Dictionary or not structure.has("id") or ids.has(str(structure.id)) or not structure.get("map_change", {}) is Dictionary:
			return false
		ids.append(str(structure.id))
		var cell := Vector2i(int(structure.get("x", -1)), int(structure.get("y", -1)))
		if cell.x < 0 or cell.y < 0 or cell.x >= rows[0].length() or cell.y >= rows.size() or int(structure.get("hp", -1)) < 0: return false
		var change: Dictionary = structure.get("map_change", {})
		if not change.get("terrain", []) is Array: return false
		for row in change.get("terrain", []):
			if not row is String: return false
	for patch in data.get("map_patches", []):
		if not patch is Dictionary: return false
		for key in ["x", "y", "width", "height"]:
			if not patch.get(key, 0) is int and not patch.get(key, 0) is float: return false
	if not str(data.get("rng_seed", "")).is_valid_int() or not str(data.get("rng_state", "")).is_valid_int():
		return false
	# Restore the snapshot directly. Loading a chapter would execute its start
	# events again before replacing their state, and can consume unrelated data.
	_turn_sequence.clear()
	chapter = saved_chapter.duplicate(true)
	rules = Rules.defaults()
	_merge(rules, data.get("rules", {}))
	units = []
	for unit in data["units"]:
		units.append(_normalize_unit(unit))
	if chapter.has("reserve_units"):
		chapter.reserve_units = []
		for unit in reserves: chapter.reserve_units.append(_normalize_unit(unit))
	terrain = rows.duplicate(true)
	height = terrain.size()
	width = str(terrain[0]).length()
	phase = str(data["phase"])
	turn = int(data["turn"])
	outcome = str(data.get("outcome", ""))
	pending_moves = pending.duplicate(true)
	phase_combat = []
	phase_actions = []
	pending_skill_effects.clear()
	last_movement_effect = {}
	pending_trap_effects = []
	destructibles = []
	for structure in saved_structures: destructibles.append(_normalize_structure(structure))
	map_patches = data.get("map_patches", []).duplicate(true)
	events_log = data.get("events_log", []).duplicate(true)
	interactions = data.get("interactions", []).duplicate(true)
	fired_events = data.get("fired_events", []).duplicate(true)
	native_event_state = NativeFlags.from_save(data.get("native_event_state"),NativeFlags.game(chapter))
	native_events_ready = data.get("native_events_ready",true)
	native_sound_queue = data.get("native_sound_queue",[]).map(func(id): return int(id))
	native_event_turns = data.get("native_event_turns",{}).duplicate(true)
	native_flags_inherited = true
	native_event_errors = {}
	NativeFlags.synchronize(self)
	support_points = data.get("support_points", {}).duplicate(true)
	support_ranks = data.get("support_ranks", {}).duplicate(true)
	support_used_pairs = data.get("support_used_pairs", []).duplicate(true)
	support_last_gain_turn = int(data.get("support_last_gain_turn", maxi(0, turn - 1)))
	support_chapter_gain = int(data.get("support_chapter_gain", 0))
	inventory = data.get("inventory", []).duplicate(true)
	gold = int(data.get("gold", 0))
	chapter_repairs_applied = bool(data.get("chapter_repairs_applied", true))
	dialogue_queue = data.get("dialogue_queue", []).duplicate(true)
	experience_queue = data.get("experience_queue", []).duplicate(true)
	rng.seed = int(str(data["rng_seed"]))
	rng.state = int(str(data["rng_state"]))
	return true

func queue_skill_effect(unit: Dictionary, skill: String, previous_hp: int = -1) -> void:
	var effect := {"type": "skill", "unit_id": str(unit.id), "skill": skill, "previous_hp": previous_hp, "remaining_hp": int(unit.hp)}
	if phase != "player" or auto_playing: phase_actions.append(effect)
	else: pending_skill_effects.append(effect)

func flush_skill_notifications() -> void:
	for unit in units:
		for skill in unit.get("skill_notifications", []): queue_skill_effect(unit, str(skill))
		unit.erase("skill_notifications")
