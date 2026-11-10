extends RefCounted
## Per-cartridge content provider. Lightweight directory first, chapters on demand.
const Profile = preload("res://runtime/fe6/fe6_dynamic_profile.gd")
const Data = preload("res://runtime/rom_data.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Events = preload("res://runtime/fe6/fe6_dynamic_events.gd")
const Definitions = preload("res://runtime/fe6/fe6_dynamic_data.gd")
const Difficulty = preload("res://runtime/fe6/rom_fe6_difficulty.gd")
const Supports = preload("res://runtime/fe6/fe6_dynamic_supports.gd")
# Native FE6 engine policy; class powers, ranks, growths and caps remain ROM data.
const PROGRESSION_RULES := {"experience_model":"fe6","weapon_rank_thresholds":{"E":1,"D":51,"C":101,"B":151,"A":201,"S":251},
	"weapon_exp_unpromoted_cap":201,"weapon_exp_cap":251,"weapon_exp_kill_multiplier":1}
var rom := PackedByteArray()
var digest := ""
var prefix := ""
var directory := ""
var names := {}
var paths := {}
var destinations := {}
var compiled := {}
var assets := {}
var items := {}
var promotions := {}
var supports := {}
var support_paths := {}
var battles := {"game_id":"fe6","animations":{},"fps":60}
var movement := {"schema_version":1,"movement":{}}
var manifest := {}
var error := ""
var revision := 0
var battle_units := {}
var library: RefCounted
var package := preload("res://runtime/rom_dynamic_package.gd").new()
var mutex := Mutex.new()

func initialize(bytes: PackedByteArray, rom_hash: String, root: String) -> bool:
	rom = bytes; digest = rom_hash; directory = root
	prefix = "res://content/fe6/dynamic/"+digest+"/"
	var d := Profile.decoder(rom)
	var definitions := Definitions.new(); definitions.d = d; definitions.prefix = prefix
	var character_table: int = d.ptr(0x17680)
	for id in range(1,256):
		d.set_meta("dynamic_context","Character %d" % id)
		var at := character_table+id*48
		if at+48 > rom.size() or d.u8(at+4) != id: break
		var name: String = d.text(d.u16(at)) if d.u16(at) else ""
		if not d.error.is_empty(): return failed(d)
		var face: int = d.u16(at+6)
		if face and not names.has(face): names[face] = name
	var table: int = d.ptr(0x16410)
	for id in range(1,256):
		d.set_meta("dynamic_context","Item %d" % id)
		var at := table+id*32
		if at+32 > rom.size() or d.u8(at+6) != id: break
		if d.u16(at) == 0: continue
		definitions.item(id,false)
		if not d.error.is_empty(): return failed(d)
	d.set_meta("dynamic_context","Promotion catalog")
	promotions = definitions.promotion_catalog()
	if not d.error.is_empty(): return failed(d)
	d.set_meta("dynamic_context","Battle backgrounds")
	for family in ["plains","castle","water"]:
		var background_id := 4 if family == "castle" else 3
		var at: int = d.ptr(0x5f090)+(background_id-1)*12
		definitions.assets[prefix+"battle/"+family+".png"] = {"kind":"scene","graphics":[[d.ptr(at)]],"tsa":d.ptr(at+4),"tsa_lz":true,"palette":d.ptr(at+8),"palette_lz":true,"width":240,"height":160,"header":false}
		definitions.assets[prefix+"battle/platform_"+family+".png"] = {"kind":"platform","id":2 if family == "castle" else 1}
	battles.background = prefix+"battle/plains.png"; battles.platform = prefix+"battle/platform_plains.png"
	items = definitions.items; assets = definitions.assets
	d.set_meta("dynamic_context","Support catalog")
	supports = Supports.catalog(d,prefix,assets)
	if not d.error.is_empty(): return failed(d)
	supports.rom_sha256 = digest
	for pair in supports.pairs: support_paths[pair.dialogue_path] = pair
	var resources := {}
	var chapters: Array = []
	table = d.ptr(0x2bb20)
	# Follow every ending branch, without evaluating its gameplay predicates.
	# Table bounds cannot be inferred by scanning bytes beyond the last record.
	var pending: Array = [1]
	var seen := {}
	while not pending.is_empty():
		var id := int(pending.pop_front())
		d.set_meta("dynamic_context","Chapter directory slot %d" % id)
		if seen.has(id): continue
		seen[id] = true
		if id < 0 or id >= Profile.MAX_CHAPTERS: d.fail("FE6 compatibility","Chapter index exceeds the compatible map format."); return failed(d)
		var at := table+id*68
		if not d.require_range(at,68,"FE6 chapter directory"): return failed(d)
		if d.u8(at+8) == 0 or d.u8(at+58) == 0: d.fail("FE6 compatibility","Referenced chapter has no map or event group."); return failed(d)
		var title: String = d.text(d.u16(at+56)) if d.u16(at+56) else ""
		if title.is_empty(): title = "Chapter slot %d" % id
		var path := "res://content/fe6/chapters/dynamic/"+digest+"/%d.json" % id
		var entry := {"id":"fe6_dynamic_%d" % id,"title":title,"path":path,"rom_chapter_index":id}
		chapters.append(entry); paths[path] = id; destinations[id] = path
		resources[path] = {"dynamic_pending":true,"id":entry.id}
		var header := Groups.chapter_events(d,"fe6",id)
		var script_queue: Array = [Groups.pointer(d,header+24)]
		var visited := {}
		while not script_queue.is_empty():
			var script := int(script_queue.pop_front())
			if visited.has(script): continue
			if visited.size() >= 64: d.fail("FE6 compatibility","Too many ending subroutines."); return failed(d)
			visited[script] = true
			for command in Events.Reader.commands(d,script):
				if command.opcode == 0x3d: pending.append(d.u32(int(command.offset)+4))
				elif command.opcode == 0x25: script_queue.append(Groups.pointer(d,int(command.offset)+4))
			if not d.error.is_empty(): return failed(d)
	if not d.error.is_empty(): return failed(d)
	if not destinations.has(1): error = "FE6 compatibility: the starting chapter (slot 1) is missing."; return false
	manifest = {"id":"fe6","title":"FE6","schema_version":1,"dynamic_rom":true,"rom_sha256":digest,"compatibility_profile":Profile.VERSION,
		"start_chapter":destinations[1],"campaign_starts":{"fe6_unit_1":destinations[1]},"chapters":chapters,
		"item_manifest":prefix+"items.json","promotion_manifest":prefix+"promotions.json","title_manifest":prefix+"title.json","map_catalog":prefix+"maps.json",
		"support_manifest":prefix+"supports.json",
		"battle_animation_manifest":prefix+"battles.json","map_animation_manifest":prefix+"movement.json","audio_manifest":prefix+"audio.json"}
	resources["res://content/fe6/manifest.json"] = manifest
	resources[prefix+"items.json"] = {"game_id":"fe6","items":items.values()}
	resources[prefix+"promotions.json"] = promotions
	resources[prefix+"supports.json"] = supports
	resources[prefix+"title.json"] = preload("res://runtime/fe6/fe6_dynamic_title.gd").manifest(rom,prefix,assets)
	resources[prefix+"maps.json"] = {"maps":[]}
	resources[prefix+"battles.json"] = battles
	resources[prefix+"movement.json"] = movement
	d.set_meta("dynamic_context","Audio catalog")
	resources[prefix+"audio.json"] = preload("res://runtime/fe6/fe6_dynamic_audio.gd").manifest(d)
	if not d.error.is_empty(): return failed(d)
	if not mount(resources): return false
	# Validate the playable entry before accepting this cartridge into the library.
	return ensure(destinations[1])

func failed(d: RefCounted) -> bool:
	error = "FE6 compatibility (%s): %s" % [d.get_meta("dynamic_context","decode"),d.error.get("reason","Unknown decoding error.")]
	return false

func ensure(path: String) -> bool:
	mutex.lock()
	var ok := true
	if paths.has(path) and not compiled.has(path): ok = compile_chapter(path,int(paths[path]))
	elif support_paths.has(path) and not compiled.has(path): ok = compile_support(path)
	elif compiled.has(path): error = ""
	mutex.unlock()
	return ok

func compile_support(path: String) -> bool:
	error = ""
	var d := Profile.decoder(rom)
	d.set_meta("dynamic_context","Support "+path.get_file().get_basename())
	var reader := Supports.Reader.new()
	if not reader.configure(d,"fe6",true): return failed(d)
	var pair: Dictionary = support_paths[path]
	var fields: Variant = reader.read({"game":"fe6","characters":pair.rom_character_ids},pair)
	if fields == null: return failed(d)
	var definitions := Definitions.new(); definitions.d = d; definitions.prefix = prefix
	var events := Events.new(); events.data = definitions
	events.register_art(fields.dialogue)
	# Every portrait and other ROM asset remains scoped to this cartridge.
	var dialogue: Variant = rebase_support(fields.dialogue)
	if not mount({path:{"dialogue":dialogue}}): return false
	assets.merge(definitions.assets,true)
	revision += 1
	compiled[path] = true
	return true

func rebase_support(value: Variant) -> Variant:
	if value is String: return value if value.begins_with(prefix) else value.replace("res://content/fe6/",prefix)
	if value is Array: return value.map(rebase_support)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = rebase_support(value[key])
		return result
	return value

func prepare_battle_art(units: Array) -> bool:
	mutex.lock()
	var ok := compile_battle_art(units)
	mutex.unlock()
	return ok

func library_catalog(kind: String) -> Array:
	mutex.lock()
	if library == null:
		library = preload("res://runtime/fe6/fe6_dynamic_library.gd").new()
		library.rom = rom; library.prefix = prefix+"library/"
	var existing: bool = library.catalogs.has(kind)
	var result: Array = library.catalog(kind,manifest.chapters,names,assets)
	if not existing:
		assets.merge(library.assets,true); revision += 1
	mutex.unlock()
	return result.duplicate(true)

func compile_battle_art(units: Array) -> bool:
	error = ""
	var d := Profile.decoder(rom)
	d.set_meta("dynamic_context","Arena animation")
	var definitions := Definitions.new(); definitions.d = d; definitions.prefix = prefix
	var requested := {}
	for unit in units:
		var u: Dictionary = unit.duplicate()
		u.rom_character_id = int(u.get("rom_character_id",0))
		var key := "%d_%d_%s_%s" % [int(u.rom_class_id),u.rom_character_id,str(u.get("promoted",false)),str(u.faction)]
		if battle_units.has(key): continue
		requested[key] = true; definitions.unit_offsets[key] = u
	if requested.is_empty(): return true
	definitions.art()
	if not d.error.is_empty(): return failed(d)
	var next_battles := battles.duplicate(true)
	for key in definitions.battles.animations:
		var profile: Dictionary = definitions.battles.animations[key]
		for character in next_battles.animations.get(key,{}).get("characters",[]):
			if not profile.characters.has(character): profile.characters.append(character)
		next_battles.animations[key] = profile
	if not mount({prefix+"battles.json":next_battles}): return false
	assets.merge(definitions.assets,true)
	battles = next_battles; battle_units.merge(requested); revision += 1
	return true

func prepare_story_art(pages: Array) -> bool:
	mutex.lock()
	error = ""
	var d := Profile.decoder(rom)
	d.set_meta("dynamic_context","Ending presentation")
	var definitions := Definitions.new(); definitions.d = d; definitions.prefix = prefix
	var events := Events.new(); events.data = definitions
	events.register_art(pages)
	for page in pages:
		var path := str(page.get("background",""))
		if not path.begins_with("res://content/fe6/rom/backgrounds/"): continue
		var recipe: Variant = Events.Scene.asset(d,path)
		if recipe != null: definitions.assets[rebase_support(path)] = recipe
	var ok: bool = d.error.is_empty()
	if ok:
		assets.merge(definitions.assets,true); revision += 1
	else: failed(d)
	mutex.unlock()
	return ok

func compile_chapter(path: String, id: int) -> bool:
	error = ""
	# An unsupported chapter cannot poison the active cartridge decoder or assets.
	var d := Profile.decoder(rom)
	d.set_meta("dynamic_context","Chapter %d" % id)
	var definitions := Definitions.new(); definitions.d = d; definitions.prefix = prefix; definitions.items = items.duplicate(true)
	definitions.chapter_index = id
	var events := Events.new(); events.d = d; events.data = definitions; events.chapter = id; events.names = names; events.destinations = destinations
	var at: int = d.ptr(0x2bb20)+id*68
	var header := Groups.chapter_events(d,"fe6",id)
	var map: Variant = Data.map_fields(d,{"chapter":id,"fields":["width","height","terrain","terrain_ids"]},"fe6")
	if map == null or not d.error.is_empty(): return failed(d)
	definitions.terrain = map.terrain
	map.image = prefix+"maps/%d.png" % id
	map.tile_size = 16
	definitions.assets[map.image] = {"kind":"map","chapter":id}
	var title: String = d.text(d.u16(at+56)) if d.u16(at+56) else "Chapter slot %d" % id
	var result := {"id":"fe6_dynamic_%d" % id,"dynamic_rom":true,"rom_sha256":digest,"rom_chapter_index":id,"title":title,"subtitle":"FE6 compatibility mode",
		"map":prefix+"maps/%d.json" % id,"terrain":map.terrain,"seed":6000+id,"gold":0,"units":[],"events":[],"interactions":[],"talks":[],"intro":[],
		"battle_cutscenes_supported":true,"rules":{"terrain":{},"triangle_hit":10,"effectiveness_multiplier":3,"fog_radius":d.u8(at+12)},"music":{},"deployment":{"slots":[],"forced":["fe6_unit_1"]},"explicit_forced_deployment":true}
	result.support_profile = "fe6"; result.support_pairs = supports.pairs.duplicate(true)
	result.rules.merge(supports.rules.duplicate(true)); result.rules.merge(PROGRESSION_RULES.duplicate(true))
	definitions.support_characters = supports.characters
	# Native default terrain identity/labels; class records provide costs/bonuses.
	var default_class: int = d.ptr(0x176e0)+72
	for tid in range(Data.SYMBOLS.length()):
		d.set_meta("dynamic_context","Chapter %d terrain %d" % [id,tid])
		var cost: int = d.u8(d.ptr(default_class+52)+tid)
		result.rules.terrain[Data.SYMBOLS[tid]] = {"id":tid,"name":"Terrain %d" % tid,"cost":cost-256 if cost>=128 else cost,"avoid":d.u8(d.ptr(default_class+56)+tid),"defense":d.u8(d.ptr(default_class+60)+tid),"resistance":d.u8(d.ptr(default_class+64)+tid),"heal":d.u8(d.ptr(0x192d0)+tid)/100.0}
	for entry in [["player_phase",20],["enemy_phase",21]]:
		var song: int = d.u8(at+int(entry[1]))
		if preload("res://runtime/rom_audio.gd").has_song(d,song): result.music[entry[0]] = "song_%03x" % song
	# Map-change entries supply both tiles and their coordinate selectors.
	if not d.error.is_empty(): return failed(d)
	d.set_meta("dynamic_context","Chapter %d events" % id)
	var change_pointer: int = d.ptr(0x2bb9c)+d.u8(at+11)*4
	var changes: int = d.ptr(change_pointer) if d.u32(change_pointer) else -1
	var ended := changes < 0
	for index in range(64):
		if changes < 0: break
		if not d.require_range(changes+index*12,12,"FE6 map changes"): return failed(d)
		var change: int = d.u8(changes+index*12)
		if change == 255: ended = true; break
		events.patches.append(definitions.patch(id,change))
	if not ended: d.fail("FE6 compatibility","Unterminated map changes.")
	if not d.error.is_empty(): return failed(d)
	var terrain_rows: Array = map.terrain.duplicate()
	for patch in events.patches: terrain_rows.append_array(patch.terrain)
	var used := {}
	for row in terrain_rows:
		for symbol in row:
			if used.has(symbol): continue
			used[symbol] = true
			result.rules.terrain[symbol].name = d.terrain_name(Data.SYMBOLS.find(symbol))
	if not d.error.is_empty(): return failed(d)
	# Header formations exist before opening scripts. LOAD commands add other units.
	for offset in [16,20]:
		if d.u32(header+offset):
			for unit in definitions.group(Groups.pointer(d,header+offset)):
				if not result.units.any(func(u):return u.id == unit.id): result.units.append(unit)
	if not events.prepare(result,header): return failed(d)
	if not events.quotes(result): return failed(d)
	# Native terrain initialization creates siege weapons and breakable walls.
	result.emplacements = []; result.destructibles = []
	for y in range(map.height):
		for x in range(map.width):
			var tid := int(map.terrain_ids[y][x])
			if Data.SYMBOLS[tid] == "a" and not result.interactions.any(func(s):return s.x == x and s.y == y):
				result.interactions.append({"id":"fe6_dynamic_arena_%d_%d" % [x,y],"type":"arena","x":x,"y":y})
			if tid in [39,40,41]:
				result.emplacements.append({"x":x,"y":y,"weapon":definitions.item(48+tid-39)})
			elif tid == 27 and (y == 0 or int(map.terrain_ids[y-1][x]) != 27):
				var matches: Array = events.patches.filter(func(p):return x >= p.x and x < p.x+p.width and y >= p.y and y < p.y+p.height and p.mask[y-int(p.y)][x-int(p.x)])
				if matches.size() != 1: d.fail("FE6 compatibility","Breakable wall has no unique map change."); return failed(d)
				var hp: int = d.u8(at+25)
				result.destructibles.append({"id":"fe6_dynamic_wall_%d_%d" % [x,y],"x":x,"y":y,"hp":hp,"max_hp":hp,"map_change":matches[0]})
	# Door terrain can be present without a location-event row.
	for y in range(map.height):
		for x in range(map.width):
			if int(map.terrain_ids[y][x]) != 30 or result.interactions.any(func(s):return s.x == x and s.y == y): continue
			var matches: Array = events.patches.filter(func(p):return x >= p.x and x < p.x+p.width and y >= p.y and y < p.y+p.height and p.mask[y-int(p.y)][x-int(p.x)])
			if matches.size() != 1: d.fail("FE6 compatibility","Door has no unique map change."); return failed(d)
			result.interactions.append({"id":"fe6_dynamic_door_%d_%d" % [x,y],"type":"door","x":x,"y":y,"requires_key":true,"map_change":matches[0]})
	for site in result.interactions:
		if site.type != "door" or not site.has("map_change"): continue
		var patch: Dictionary = site.map_change
		site.linked_sites = result.interactions.filter(func(s):return s.type == "door" and s.x >= patch.x and s.x < patch.x+patch.width and s.y >= patch.y and s.y < patch.y+patch.height).map(func(s):return s.id)
	# Keep objective labels tied to cartridge terrain, including covered rooms.
	if result.objective.type == "defeat_boss": result.objective_text = "Defeat the boss."
	elif result.objective.type in ["seize","native_seize"]:
		var x := int(result.objective.x); var y := int(result.objective.y)
		if x < 0 or y < 0 or x >= int(map.width) or y >= int(map.height):
			d.fail("FE6 compatibility","Seize objective lies outside the chapter map."); return failed(d)
		var symbol: String = map.terrain[y][x]
		# A roof may cover the objective before its room opens. The replacement
		# terrain supplies the actual throne/gate name, still decoded from ROM.
		if symbol == "H":
			for patch in events.patches:
				if x < patch.x or y < patch.y or x >= patch.x+patch.width or y >= patch.y+patch.height: continue
				var tile: String = patch.terrain[y-int(patch.y)][x-int(patch.x)]
				if patch.mask[y-int(patch.y)][x-int(patch.x)] and tile in ["T","E"]: symbol = tile; break
		result.objective.terrain_name = result.rules.terrain[symbol].name
	if not preload("res://runtime/fe6/rom_fe6_autolevel.gd").prepare(d,result): return failed(d)
	var params: Variant = Difficulty.parameters(d,id)
	if params == null: return failed(d)
	for unit in result.units:
		if not Difficulty.bonus(d,unit,params,true,int(params.opening_passes)): return failed(d)
	for event in result.events+result.talks:
		for unit in Events.Runner.spawn_templates(event):
			if not Difficulty.bonus(d,unit,params,false,int(params.opening_passes) if event.get("trigger") == "chapter_start" else 0): return failed(d)
	for unit in result.units:
		if unit.faction == "player": result.deployment.slots.append({"unit_id":unit.id,"x":unit.x,"y":unit.y})
	definitions.prepare_art(promotions)
	if not d.error.is_empty(): return failed(d)
	var next_battles := battles.duplicate(true); next_battles.animations.merge(definitions.battles.animations,true)
	var next_movement := movement.duplicate(true); next_movement.movement.merge(definitions.movement.movement,true)
	if not mount({path:result,result.map:map,prefix+"battles.json":next_battles,prefix+"movement.json":next_movement}): return false
	assets.merge(definitions.assets,true); items.merge(definitions.items,true)
	battles = next_battles; movement = next_movement
	revision += 1
	compiled[path] = true
	return true

func mount(resources: Dictionary) -> bool:
	package.directory = directory; package.digest = digest
	var ok: bool = package.mount(resources)
	if not ok: error = package.error
	return ok
