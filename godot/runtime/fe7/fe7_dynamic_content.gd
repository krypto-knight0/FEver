extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## Live FE7 chapters with reviewed regional event coverage. No stock templates.
const Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")
const Data = preload("res://runtime/rom_data.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Events = preload("res://runtime/fe7/fe7_dynamic_events.gd")
const SUPPORTED_CHAPTERS := [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47]
var rom := PackedByteArray()
var digest := ""
var prefix := ""
var directory := ""
var assets := {}
var items := {}
var promotions := {}
var supports := {}
var support_paths := {}
var compiled_supports := {}
var battles := {"game_id":"fe7","animations":{},"fps":60,"supported":true}
var movement := {"schema_version":1,"movement":{}}
var manifest := {}
var native_chapters: Array = []
var event_report := {}
var names := {}
var error := ""
var compiling_chapter := -1
var revision := 0
var library: RefCounted
var work_mutex := Mutex.new()
var package := preload("res://runtime/rom_dynamic_package.gd").new()

func failed(d: RefCounted) -> bool:
	error = "FE7 compatibility (%s): %s" % [str(d.error.get("operation","native data")),str(d.error.get("reason","Invalid native data."))]
	if compiling_chapter >= 0: error += " Chapter %d." % compiling_chapter
	if int(d.error.get("offset",-1)) >= 0: error += " At 0x%x." % int(d.error.offset)
	return false

func initialize(bytes: PackedByteArray, rom_hash: String, root: String) -> bool:
	rom = bytes; digest = rom_hash; directory = root
	prefix = "res://content/fe7/dynamic/"+digest+"/"
	var d := Profile.decoder(bytes)
	if not preload("res://runtime/fe7/fe7_dynamic_difficulty.gd").validate(d): return failed(d)
	var definitions := preload("res://runtime/fe7/fe7_dynamic_data.gd").new()
	definitions.d = d; definitions.prefix = prefix
	# Discover the native directory; compile only supported chapters. Images remain lazy.
	var table: int = d.ptr(int(d.layout.chapters))
	for id in range(Profile.MAX_CHAPTERS):
		var at := table+id*int(d.layout.chapter_stride)
		if not d.require_range(at,int(d.layout.chapter_stride),"FE7 chapter directory"): return failed(d)
		if d.u8(at+8) == 0 or d.u16(at+int(d.layout.get("chapter_title",112))) == 0: continue
		native_chapters.append({"id":str(id),"rom_chapter_index":id,"title":d.text(d.u16(at+int(d.layout.get("chapter_title",112)))),"native_objective":d.text(d.u16(at+int(d.layout.get("chapter_objective",138)))) if d.u16(at+int(d.layout.get("chapter_objective",138))) else ""})
		if not d.error.is_empty(): return failed(d)
	table = d.ptr(int(d.layout.record_layout[0]))
	for index in range(253):
		var at := table+index*52
		if not d.require_range(at,52,"FE7 character directory"): return failed(d)
		if d.u8(at+4) != index+1 or d.u16(at) == 0: continue
		var face: int = d.u16(at+6)
		if face and not names.has(face): names[face] = d.text(d.u16(at))
		if not d.error.is_empty(): return failed(d)
	table = d.ptr(int(d.layout.items))
	for id in range(1,256):
		var at := table+id*36
		if at+36 > rom.size() or d.u8(at+6) != id: break
		if d.u16(at): definitions.item(id,false)
		if not d.error.is_empty(): return failed(d)
	supports = preload("res://runtime/fe7/fe7_dynamic_supports.gd").catalog(d,prefix,assets)
	if not d.error.is_empty(): return failed(d)
	supports.rom_sha256 = digest
	for pair in supports.pairs: support_paths[pair.dialogue_path] = pair
	definitions.support_characters = supports.characters
	var resources := {}
	promotions = preload("res://runtime/fe7/fe7_dynamic_promotions.gd").catalog(d,prefix,definitions.assets)
	if not d.error.is_empty(): return failed(d)
	for chapter_index in SUPPORTED_CHAPTERS:
		for route in chapter_routes(chapter_index):
			if not compile_chapter(d,definitions,resources,chapter_index,route): return false
	definitions.prepare_art(promotions)
	if not d.error.is_empty(): return failed(d)
	battles = definitions.battles; movement = definitions.movement
	items = definitions.items; assets.merge(definitions.assets,true)
	var path := prefix+"chapters/0.json"
	manifest = {"id":"fe7","title":"FE7 · Experimental","dynamic_rom":true,"rom_sha256":digest,"compatibility_profile":Profile.US.VERSION if Policy.us(d) else Profile.VERSION,
		"supported_difficulties":["normal","hard","rogue_normal","rogue_hard"],"battle_cutscenes_supported":true,
		"start_chapter":path,"campaign_starts":{"fe7_unit_3":path,"fe7_unit_1":chapter_path(12,2),"fe7_unit_2":chapter_path(13,3)},"chapters":[],
		"support_manifest":prefix+"supports.json","title_manifest":prefix+"title.json","item_manifest":prefix+"items.json","promotion_manifest":prefix+"promotions.json",
		"battle_animation_manifest":prefix+"battles.json","map_animation_manifest":prefix+"movement.json","audio_manifest":prefix+"audio.json","map_catalog":prefix+"maps.json"}
	for chapter_index in SUPPORTED_CHAPTERS:
		for route in chapter_routes(chapter_index):
			var path_for_route := chapter_path(chapter_index,route)
			var label: String = resources[path_for_route].title
			if chapter_index >= 14: label += " · "+preload("res://runtime/rom_names.gd").character(d,"fe7",route-1)
			manifest.chapters.append({"id":resources[path_for_route].id,"title":label,"path":path_for_route,"rom_chapter_index":chapter_index,"native_route":route})
	resources["res://content/fe7/manifest.json"] = manifest
	resources[prefix+"title.json"] = preload("res://runtime/fe7/fe7_dynamic_title.gd").manifest(d,prefix,assets)
	resources[prefix+"supports.json"] = supports
	resources[prefix+"items.json"] = {"game_id":"fe7","items":items.values()}
	resources[prefix+"promotions.json"] = promotions
	resources[prefix+"battles.json"] = battles; resources[prefix+"movement.json"] = movement
	resources[prefix+"audio.json"] = preload("res://runtime/fe7/fe7_dynamic_audio.gd").manifest(d)
	if not d.error.is_empty(): return failed(d)
	resources[prefix+"maps.json"] = {"maps":[]}
	package.directory = directory; package.digest = digest
	if not package.mount(resources): error = package.error; return false
	revision += 1
	return true

static func chapter_routes(index: int) -> Array:
	if index <= 11: return [1]
	if index in [12,40]: return [2]
	if index in [13,18,25,33,41,45]: return [3]
	return [2,3]

func chapter_path(index: int, route: int) -> String:
	return prefix+("chapters/%d.json" % index if index < 14 else "chapters/%d_%d.json" % [index,route])

func compile_chapter(d: RefCounted, definitions: RefCounted, resources: Dictionary, chapter_index: int, route: int = 1) -> bool:
	compiling_chapter = chapter_index
	definitions.chapter_index = chapter_index; definitions.native_route = route; definitions.enemy_records.clear()
	var header := Groups.chapter_events(d,"fe7",chapter_index)
	var map: Variant = Data.map_fields(d,{"chapter":chapter_index,"fields":["width","height","terrain"]},"fe7")
	if map == null or not d.error.is_empty(): return failed(d)
	var units: Array = definitions.group(Groups.pointer(d,header+(48 if route == 3 else 40)))
	units.append_array(definitions.group(Groups.pointer(d,header+(32 if route == 3 else 24))))
	if not d.error.is_empty(): return failed(d)
	for unit in units:
		if int(unit.x) >= int(map.width) or int(unit.y) >= int(map.height): d.fail("FE7 deployment","Deployment lies outside the map."); return failed(d)
	# Some chapters populate their army entirely through the opening script.
	# Reuse the tutorial live terrain policy for the map's default info-panel records.
	var terrain_unit: Dictionary = definitions.unit_offsets.values()[0] if units.is_empty() else units[0]
	var report := Events.inspect(d,chapter_index)
	if chapter_index == 0: event_report = report
	if not d.error.is_empty(): return failed(d)
	var terrain := {}
	for row in map.terrain:
		for symbol in row:
			if terrain.has(symbol): continue
			var id := Data.SYMBOLS.find(symbol)
			var base: Dictionary = terrain_unit.terrain_bonuses[symbol].duplicate()
			base.merge({"id":id,"name":d.terrain_name(id),"cost":terrain_unit.movement_costs[symbol],"heal":d.u8(d.ptr(int(d.layout.terrain_heal))+id)/100.0})
			terrain[symbol] = base
	if not d.error.is_empty(): return failed(d)
	map.image = prefix+"maps/%d.png" % chapter_index; map.tile_size = 16
	assets[map.image] = {"kind":"map","chapter":chapter_index}
	resources[prefix+"maps/%d.json" % chapter_index] = map
	var at: int = d.ptr(int(d.layout.chapters))+chapter_index*int(d.layout.chapter_stride)
	var result := {"id":("fe7_dynamic_%d" % chapter_index if chapter_index < 14 else "fe7_dynamic_%d_%d" % [chapter_index,route]),"game_id":"fe7","dynamic_rom":true,"rom_sha256":digest,"rom_chapter_index":chapter_index,
		"title":d.text(d.u16(at+int(d.layout.get("chapter_title",112)))),"subtitle":"FE7","map":prefix+"maps/%d.json" % chapter_index,"terrain":map.terrain,
		"gold":0,"seed":7000+chapter_index,"units":[],"events":[],"interactions":[],"talks":[],"music":{},"intro":[],
		"native_route":route,"route":"fe7_unit_%d" % {1:3,2:1,3:2}[route],"native_opening_scene":true,"objective":{"type":"rout"},
		"rules":{"terrain":terrain,"effectiveness_multiplier":2 if Policy.us(d) else 3,"experience_model":"fe7"},"deployment":{"slots":[],"forced":["fe7_unit_%d" % {1:3,2:1,3:2}[route]]},"explicit_forced_deployment":true}
	result.support_profile = "fe7"
	result.support_pairs = supports.get("pairs",[]).duplicate(true)
	result.rules.merge(supports.get("rules",{}).duplicate(true))
	result.rules.supports_enabled = route != 1
	for y in range(int(map.height)):
		for x in range(int(map.width)):
			if map.terrain[y][x] == "a":
				result.interactions.append({"id":"fe7_arena_%d_%d" % [x,y],"type":"arena","x":x,"y":y})
	if chapter_index == 47: result.merge({"native_continue_formation":true,"deployment_complete":true})
	if chapter_index in [12,13]:
		result.campaign_reset = true
		result.lyn_handoff = definitions.campaign.duplicate(true)
	if chapter_index == 11: result.route_choices = {"fe7_unit_1":chapter_path(12,2),"fe7_unit_2":chapter_path(13,3)}
	result.native_battle_terrain = definitions.terrain_art(chapter_index,terrain)
	# FE7's trap initializer reads six-byte records from the route's header bank.
	# Type 1 is a siege engine: x, y, item ID. Other constructors stay explicit.
	result.emplacements = []
	var traps: int = d.ptr(header+(20 if route == 3 else 16))
	var traps_ended := false
	for index in range(65):
		var trap := traps+index*6
		if not d.require_range(trap,1,"FE7 traps"): return failed(d)
		if d.u8(trap) == 0: traps_ended = true; break
		if index == 64:
			d.fail("FE7 traps","Trap list has no terminator.",trap); return failed(d)
		if not d.require_range(trap,6,"FE7 traps"): return failed(d)
		if d.u8(trap) in [4,5]:
			var Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
			if not (Pure.signature(d,0x34ac4,172,[],"eacf10ae1d222864f9ff6037d473325f844bdeee746648c5a716823c670114f7") and Pure.signature(d,0x2bfe4,28,[],"80c2a4e8f69c3263f5ee0993d8c6ceece04da7d9fbe99e058ca7abf98d66f864") and Pure.signature(d,0x2c000,32,[],"2e10484be4fa2ceadac1cb0f948d8b22b2b2dcdbc0ab455fd91ac664320f109b") and Pure.signature(d,0x2c3c4,128,[],"7abffb01e3611e7f84b4e485ebe82e70c2cc171ac826e6cf268dfc46dcfe3fdb") and Pure.signature(d,0x2c618,76,[],"4b646c21d363185358f4f1a9bc6d9b2d20f4622c298023442dceaa1fc3ed0a43")):
				d.fail("FE7 traps","Changed native fire/gas trap policy."); return failed(d)
			if d.u8(trap+1) >= map.width or d.u8(trap+2) >= map.height or d.u8(trap+4) < 1 or d.u8(trap+5) < 1 or d.u8(trap+3) > (3 if d.u8(trap) == 5 else 0):
				d.fail("FE7 traps","Invalid fire/gas placement or timing.",trap); return failed(d)
			result.get_or_add("hazards",[]).append({"type":"fire" if d.u8(trap) == 4 else "poison_gas","x":d.u8(trap+1),"y":d.u8(trap+2),"direction":d.u8(trap+3),"first_turn":d.u8(trap+4),"period":d.u8(trap+5),"damage":d.u8(Policy.address(d,0x2bfec if d.u8(trap) == 4 else 0x2c00c)),"length":d.u8(Policy.address(d,0x2c40a))+1})
			continue
		if d.u8(trap) != 1 or d.u8(trap+1) >= map.width or d.u8(trap+2) >= map.height:
			d.fail("FE7 traps","Unsupported trap or siege placement.",trap); return failed(d)
		var weapon: Dictionary = definitions.item(d.u8(trap+3))
		if weapon.get("type","") != "bow" or int(weapon.get("min_range",0)) < 3:
			d.fail("FE7 traps","Unsupported siege weapon.",trap); return failed(d)
		result.emplacements.append({"x":d.u8(trap+1),"y":d.u8(trap+2),"weapon":weapon})
	if not traps_ended or not d.error.is_empty(): return failed(d)
	var compiler := Events.new(); compiler.d = d; compiler.data = definitions; compiler.names = names
	compiler.chapter_index = chapter_index; compiler.native_route = route
	compiler.ending_offset = int(report.roots.ending)
	for index in SUPPORTED_CHAPTERS:
		compiler.destinations[index] = chapter_path(index,route if route in chapter_routes(index) else chapter_routes(index)[0])
	result.events.append(compiler.event(int(report.roots.opening),"chapter_start"))
	var worldmap := preload("res://runtime/fe7/fe7_dynamic_worldmap.gd").new()
	worldmap.compiler = compiler
	worldmap.attach(result.events[-1])
	if not d.error.is_empty(): return failed(d)
	result.events.append(compiler.event(int(report.roots.ending),"victory"))
	if chapter_index == 47:
		result.fe7_ending = preload("res://runtime/fe7/fe7_dynamic_ending.gd").compile(compiler)
		if not d.error.is_empty(): return failed(d)
	var progression := preload("res://runtime/fe7/fe7_dynamic_progression.gd").new()
	progression.compiler = compiler
	if not progression.conditions(result,report): return failed(d)
	result.fe7_tutorials = compiler.tutorials(chapter_index,result.events)
	if not d.error.is_empty(): return failed(d)
	if not preload("res://engine/fe7_tutorial.gd").valid(result.fe7_tutorials): d.fail("FE7 tutorials","Invalid tutorial flag bindings."); return failed(d)
	result.native_flag_dispatch = true
	result.native_flag_bindings = {"sites":[]}
	var locations := preload("res://runtime/fe7/fe7_dynamic_locations.gd").new()
	locations.compiler = compiler
	if not locations.read_patches() or not locations.structures(result,map) or not locations.objects(result,report.conditions.objects,map) or not locations.talks(result,report.conditions.talk): return failed(d)
	# Location and scheduled scripts can introduce characters absent from the
	# opening army. Collect their quotes only after every deployment is decoded.
	compiler.quotes(chapter_index,definitions.unit_offsets.values(),result.events)
	if not d.error.is_empty(): return failed(d)
	if result.objective.get("event_id","") == "unbound_native_objective":
		d.fail("FE7 progression","No supported native victory condition."); return failed(d)
	if chapter_index == 0 and result.interactions.size() != 1: d.fail("FE7 chapter","Expected one native seize objective."); return failed(d)
	event_report.execution_supported = true
	for cue in [["player_phase",22],["enemy_phase",24],["npc_phase",26]]:
		var song: int = d.u16(at+cue[1])
		if preload("res://runtime/rom_audio.gd").has_song(d,song): result.music[cue[0]] = "song_%03x" % song
	resources[chapter_path(chapter_index,route)] = result
	return d.error.is_empty() or failed(d)

func ensure(path: String) -> bool:
	if support_paths.has(path):
		work_mutex.lock()
		var ok: bool = true if compiled_supports.has(path) else compile_support(path)
		work_mutex.unlock()
		return ok
	if path.begins_with(prefix+"chapters/") and not manifest.chapters.any(func(ch):return ch.path == path):
		error = "This chapter is outside the supported FE7 campaign directory."
		return false
	error = ""
	return true

func prepare_battle_art(units: Array) -> bool:
	work_mutex.lock()
	var ok := _prepare_battle_art(units)
	work_mutex.unlock()
	return ok

func _prepare_battle_art(units: Array) -> bool:
	var d := Profile.decoder(rom)
	var definitions := preload("res://runtime/fe7/fe7_dynamic_data.gd").new()
	definitions.d = d; definitions.prefix = prefix
	definitions.battles = battles.duplicate(true); definitions.movement = movement.duplicate(true)
	for unit in units: definitions.unit_offsets[str(unit.id)] = unit
	definitions.art()
	if not d.error.is_empty(): return failed(d)
	if not package.mount({prefix+"battles.json":definitions.battles,prefix+"movement.json":definitions.movement}): error = package.error; return false
	battles = definitions.battles; movement = definitions.movement; assets.merge(definitions.assets,true)
	revision += 1; error = ""
	return true

func prepare_story_art(_pages: Array) -> bool:
	# The compiler registers every native scene/portrait before publishing.
	error = ""
	return true

func compile_support(path: String) -> bool:
	error = ""
	var d := Profile.decoder(rom)
	var reader := preload("res://runtime/fe7/fe7_dynamic_supports.gd").Reader.new()
	if not reader.configure(d,"fe7",true): return failed(d)
	var pair: Dictionary = support_paths[path]
	var fields: Variant = reader.read({"game":"fe7","characters":pair.rom_character_ids},pair)
	if fields == null: return failed(d)
	var dialogue: Variant = rebase_support(fields.dialogue)
	if not package.mount({path:{"dialogue":dialogue}}): error = package.error; return false
	register_support_art(dialogue)
	compiled_supports[path] = true; revision += 1
	return true

func register_support_art(value: Variant) -> void:
	if value is String and value.begins_with(prefix+"rom/portraits/") and value.ends_with(".png"):
		assets[value] = {"kind":"portrait","id":value.get_file().get_basename().to_int()}
	elif value is Array:
		for child in value: register_support_art(child)
	elif value is Dictionary:
		for child in value.values(): register_support_art(child)

func rebase_support(value: Variant) -> Variant:
	if value is String: return value if value.begins_with(prefix) else value.replace("res://content/fe7/",prefix)
	if value is Array: return value.map(rebase_support)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = rebase_support(value[key])
		return result
	return value

func library_catalog(kind: String) -> Array:
	work_mutex.lock()
	if library == null:
		library = preload("res://runtime/fe7/fe7_dynamic_library.gd").new()
		library.rom = rom; library.prefix = prefix+"library/"
	var existing: bool = library.catalogs.has(kind)
	var result: Array = library.catalog(kind,native_chapters,names,assets)
	if not existing: assets.merge(library.assets,true); revision += 1
	work_mutex.unlock()
	return result.duplicate(true)

