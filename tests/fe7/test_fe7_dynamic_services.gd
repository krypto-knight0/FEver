extends "fe7_test_base.gd"
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Arena = preload("res://engine/arena.gd")
const Conversations = preload("res://runtime/support_conversations.gd")
const Gallery = preload("res://runtime/fe7/fe7_dynamic_library.gd")

func read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func files(path: String = "user://") -> Dictionary:
	var result := {}
	for name in DirAccess.get_files_at(path): result[path.path_join(name)] = FileAccess.get_sha256(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		if name not in ["logs","diagnostics"]: result.merge(files(path.path_join(name)))
	return result

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("English FE7 or Flux Echo 7 ROM path required"); quit(2); return
	var source := args[0]
	var digest := FileAccess.get_sha256(source)
	var error := Assets.load_rom(source,false)
	check(error.is_empty(),"Dynamic import: "+error)
	if not error.is_empty(): quit(1); return
	check(Assets.decoder.layout.get("event_variant") == "fe7u","English FE7 service ABI")
	if failures: quit(1); return
	Assets.install_loader()
	var content: RefCounted = Assets.dynamic_content
	check(content.library == null and content.compiled_supports.is_empty(),"Import does not decode galleries or support conversations")
	check(content.supports.characters.size() == 48 and content.supports.pairs.size() == 115,"Native support directory")
	check(read(content.manifest.support_manifest) == JSON.parse_string(JSON.stringify(content.supports)),"Support manifest published for shared UI")
	library_checks()
	support_checks()
	await arena_checks()
	mutation_checks()
	check(FileAccess.get_sha256(source) == digest,"Source ROM unchanged")
	check(Assets.decoder.error.is_empty(),"Campaign decoder healthy")
	print("Dynamic FE7 services: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func library_checks() -> void:
	var content: RefCounted = Assets.dynamic_content
	var before := files()
	var viewer := preload("res://ui/backdrop_viewer.gd").new(); root.add_child(viewer)
	for kind in ["portraits","backgrounds","maps"]:
		var entries := Assets.library_catalog(kind)
		check(entries.size() == {"portraits":228,"backgrounds":162 if Policy.us(Assets.decoder) else 163,"maps":48}[kind],"Native gallery count: "+kind)
		var revision: int = content.revision
		check(Assets.library_catalog(kind) == entries and content.revision == revision,"Repeated index reuses memory: "+kind)
		viewer.configure_dynamic(kind)
		check(viewer.entries.size() == entries.size() and viewer.picture.texture != null,"Browser opens: "+kind)
		viewer.select_image(entries.size()-1)
		check(viewer.picture.texture != null,"Browser final entry: "+kind)
		for entry in entries:
			check(entry.path.begins_with(content.prefix+"library/"),"Gallery path scoped to ROM")
			check(Assets.image(entry.path) != null,"Decode "+kind+" "+str(entry.id))
		print("Gallery ",kind,": ",entries.size()," entries, index ",content.library.timings[kind]," ms")
	check(files() == before,"Gallery indexing and decoding writes no disk cache or packages")
	var gallery: RefCounted = content.library
	var original: PackedByteArray = gallery.rom
	var damaged := original.duplicate()
	var portrait: Dictionary = gallery.catalogs.portraits[0]
	var at: int = gallery.portrait_table()+int(portrait.rom_portrait_id)*28
	damaged.encode_u32(at,0xffffffff)
	gallery.rom = damaged
	check(gallery.image(portrait.path) == null and Assets.decoder.error.is_empty(),"Corrupt optional art is isolated from campaign")
	gallery.rom = original
	check(gallery.image(portrait.path) != null,"Gallery recovers after isolated failure")
	viewer.queue_free()

func support_checks() -> void:
	var content: RefCounted = Assets.dynamic_content
	var first := port_battle(12,2)
	var second := port_battle(13,3)
	var route_two: Dictionary = first.get_unit("fe7_unit_1").duplicate(true)
	var route_three: Dictionary = second.get_unit("fe7_unit_2").duplicate(true)
	route_two.x = 0; route_two.y = 0; route_two.benched = false; route_two.acted = false
	route_three.x = 1; route_three.y = 0; route_three.benched = false; route_three.acted = false
	var fixture := {"id":"fe7_support_test","game_id":"fe7","dynamic_rom":true,"terrain":["......"],"units":[route_two,route_three],"rules":first.rules.duplicate(true),"support_pairs":content.supports.pairs.duplicate(true)}
	var b := Battle.new(); b.load_chapter(fixture)
	var key: String = b._pair_key(route_two.id,route_three.id)
	var pair: Dictionary = content.supports.pairs.filter(func(p):return p.a == route_two.id and p.b == route_three.id)[0]
	check(route_two.support_id == route_two.id and route_three.support_id == route_three.id and not route_two.affinity.is_empty(),"Native deployment carries support identity and affinity")
	check(b.support_ranks["fe7_unit_15|fe7_unit_21"] == 3,"Native pair 15/21 begins at A rank")
	check(not read(content.chapter_path(0,1)).rules.supports_enabled,"Tutorial campaign disables support growth")
	var initial: int = b.support_points[key]
	b._gain_support_points()
	check(b.support_points[key] == mini(80,initial+int(pair.growth)),"Adjacent turn grants native growth")
	b._gain_support_points()
	check(b.support_points[key] == mini(80,initial+int(pair.growth)),"No duplicate gain for same turn")
	for rank in range(1,4):
		b.support_points[key] = [80,160,240][rank-1]
		b.get_unit(route_two.id).acted = false; b.phase = "player"
		check(b.can_support(route_two.id,route_three.id),"Support rank is available: "+str(rank))
		check(b.support(route_two.id,route_three.id) and b.support_ranks[key] == rank,"Support conversation earns rank")
		check(b.support_points[key] == [81,161,241][rank-1],"Native rank increment point")
		check(b.dialogue_queue.any(func(p):return p.has("support_conversation")),"Gameplay queues lazy support dialogue")
		b.get_unit(route_two.id).acted = false
		if rank < 3:
			b.support_points[key] = [160,240][rank-1]
			check(not b.can_support(route_two.id,route_three.id),"Only one rank per pair per map")
		var restored := Battle.new()
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(b.serialize()))
		var restored_ok := restored.restore(snapshot)
		check(restored_ok,"Support suspend restores")
		check(restored.support_ranks.get(key) == rank and restored.support_used_pairs == b.support_used_pairs,"Support ranks and chapter locks survive suspend")
		b.support_used_pairs.clear()
	check(b.support_bonuses(route_two.id).values().any(func(v):return v > 0),"Earned support grants combat bonuses")
	var next = preload("res://engine/chapter_preparation.gd").handoff(fixture,b,1,{})
	check(next.support_ranks.get(key) == 3 and next.support_points.get(key) == 241 and next.support_used_pairs.is_empty(),"Earned A support carries between chapters while map lock resets")
	b.get_unit(route_three.id).x = 5
	check(b.support_bonuses(route_two.id).values().all(func(v):return v == 0),"Support bonuses respect native range")
	var portrait_paths := {}
	for entry in content.supports.pairs:
		for rank in range(1,4):
			var pages: Array = Conversations.pages(entry,str(rank))
			# US leaves unavailable A conversations for the married pair blank.
			var text_id: int = entry.source_text_ids[["C","B","A"][rank-1]]
			check(pages.is_empty() == Assets.decoder.symbols(text_id).is_empty(),"Read support %s/%s" % [entry.dialogue_path.get_file(),rank])
			collect_portraits(pages,portrait_paths)
		var revision: int = content.revision
		Conversations.pages(entry,"1")
		check(content.revision == revision,"Support pair compiles once")
	for path in portrait_paths:
		check(str(path).begins_with(content.prefix) and Assets.image(path) != null,"Lazy support portrait is available")
	check(content.compiled_supports.size() == 115,"All support pairs decoded on demand")
	var library := preload("res://ui/support_library.gd").new(); root.add_child(library)
	library.configure(content.supports)
	check(library.characters.item_count == 48 and library.scenes.item_count > 0,"Shared support library lists native partners and ranks")
	library._play(0)
	check(library.viewer.visible and not library.pages.is_empty(),"Support library presents native dialogue")
	library.queue_free()
	print("Support pairs: ",content.compiled_supports.size(),"; portraits: ",portrait_paths.size())

func collect_portraits(value: Variant, paths: Dictionary) -> void:
	if value is String and value.contains("/portraits/") and value.ends_with(".png"): paths[value] = true
	elif value is Array:
		for child in value: collect_portraits(child,paths)
	elif value is Dictionary:
		for child in value.values(): collect_portraits(child,paths)

func arena_checks() -> void:
	var content: RefCounted = Assets.dynamic_content
	var source := port_battle(12,2)
	var b := port_battle(21,2)
	var hero: Dictionary = source.get_unit("fe7_unit_1").duplicate(true)
	var site: Dictionary = b.interactions.filter(func(s):return s.type == "arena")[0]
	hero.x = site.x; hero.y = site.y; hero.acted = false
	b.units = [hero]; b.phase = "player"; b.outcome = ""; b.gold = 10000
	var cutscene := preload("res://ui/battle_cutscene.gd").new(); root.add_child(cutscene)
	cutscene.configure(content.manifest.battle_animation_manifest)
	var catalog := Arena.new().catalog
	check(catalog.classes.size() == 29,"Native arena opponent classes")
	for cid in catalog.classes:
		var cls: Dictionary = catalog.classes[cid]
		var opponent := {"id":"arena_opponent","game_id":"fe7","faction":"enemy","rom_class_id":int(cid),"rom_character_id":0,"promoted":bool(str(cls.attributes).hex_to_int()&0x100),"weapon_exp":cls.weapon_ranks}
		var kind := Arena.best_type(opponent)
		opponent.weapon = catalog.weapons[str(int(catalog.basic[Arena.TYPES.find(kind)]))].duplicate(true)
		var duel := Battle.new(); duel.load_chapter({"units":[hero.duplicate(true),opponent],"terrain":[".."],"rules":{"arena":true}})
		check(cutscene.prepare_arena(duel,content.manifest.battle_animation_manifest),"Native arena class art: "+str(cid))
		check(cutscene.can_present(duel,[{"attacker_id":hero.id,"defender_id":"arena_opponent"}]),"Both arena fighters can animate")
	for outcome in ["yield","victory","defeat","exhausted"]:
		hero.acted = false; hero.hp = hero.max_hp; hero.casualty_mode = ""; hero.weapon.uses = 30; b.outcome = ""
		var arena := Arena.new()
		check(arena.offer(b,hero.id).get("ok",false),"Arena offer: "+outcome)
		check(cutscene.prepare_arena(arena.duel,content.manifest.battle_animation_manifest),"Generated opponent prepares before wager")
		var gold: int = b.gold; var hp: int = hero.hp
		check(arena.begin() and not arena.begin() and hero.hp == hp,"Wager starts once without instant damage")
		if outcome == "yield":
			var strike := arena.next_strike()
			cutscene.animation_time_scale = 12
			await cutscene.play(arena.duel,[strike],true)
			check(not cutscene.last_scene.is_empty(),"Arena strike plays battle cutscene")
			if "ui" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("user://fe7-services-arena.png"))
			arena.finish("yield"); cutscene.cancel()
		elif outcome == "victory":
			var fighter: Dictionary = arena.duel.get_unit(hero.id)
			fighter.str = 99; fighter.skill = 99; fighter.weapon.hit = 255; fighter.speed = 99
			arena.duel.get_unit("arena_opponent").hp = 1; arena.duel.get_unit("arena_opponent").speed = 0
			arena.next_strike()
		elif outcome == "defeat": arena.duel.get_unit(hero.id).hp = 0; arena.next_strike()
		else: arena.duel.get_unit(hero.id).weapon.uses = 0; arena.next_strike()
		check(arena.result == outcome,"Arena settlement: "+outcome)
		check(b.gold == gold+(arena.wager if outcome == "victory" else -arena.wager),"Wager paid correctly")
		arena.finish("yield")
		check(b.gold == gold+(arena.wager if outcome == "victory" else -arena.wager),"No duplicate settlement")
		if outcome == "defeat": check(hero.hp == 0 and hero.casualty_mode == "permanent","Arena defeat is permanent")
		if outcome == "victory": check(not arena.rewards.is_empty(),"Arena victory grants experience")
	cutscene.queue_free()

func mutation_checks() -> void:
	# Repoint the portrait table and append a valid extra face without importing
	# another whole campaign. The browsing catalog must discover it at runtime.
	var gallery := Gallery.new(); gallery.rom = Assets.decoder.rom
	var table := gallery.portrait_table(); var count := 1
	while gallery.portrait_valid(table,count): count += 1
	var bytes: PackedByteArray = gallery.rom.duplicate()
	var relocated := bytes.size()
	bytes.append_array(bytes.slice(table,table+count*28))
	bytes.append_array(bytes.slice(table+28,table+56)); bytes.resize(bytes.size()+28)
	bytes.encode_u32(int(Profile.layout_for(bytes).portraits),0x08000000+relocated)
	gallery.rom = bytes; gallery.prefix = "res://test/"
	check(gallery.catalog("portraits",[],{},{}).size() == count,"Gallery follows relocated and expanded portrait table")
	# Support and arena literal operands also follow relocated tables.
	bytes = Assets.decoder.rom.duplicate()
	var support_at := bytes.decode_u32(Policy.address(Assets.decoder,0x79264))-0x08000000
	relocated = bytes.size(); bytes.append_array(bytes.slice(support_at,support_at+116*20)); bytes.encode_u32(Policy.address(Assets.decoder,0x79264),0x08000000+relocated)
	var d: RefCounted = Profile.decoder(bytes)
	var catalog: Dictionary = preload("res://runtime/fe7/fe7_dynamic_supports.gd").catalog(d,"res://test/",{})
	check(d.error.is_empty() and catalog.pairs.size() == 115,"Supports follow relocated conversation table")
	var reader := preload("res://runtime/rom_support_data.gd").new(); reader.configure(d,"fe7",true)
	for ids in [[1,2],[2,1]]:
		var at: int = reader.character_addresses[ids[0]]
		var growth := bytes.decode_u32(at+44)-0x08000000
		for index in range(bytes[growth+21]):
			if bytes[growth+index] == ids[1]: bytes[growth+7+index] = 55; bytes[growth+14+index] = 7
	var affinity := bytes.decode_u32(Policy.address(Assets.decoder,0x26e24))-0x08000000
	bytes[affinity+1] = 8
	d = Profile.decoder(bytes)
	catalog = preload("res://runtime/fe7/fe7_dynamic_supports.gd").catalog(d,"res://test/",{})
	check(catalog.pairs[0].points == 55 and catalog.pairs[0].growth == 7 and catalog.rules.support_affinities.fire.atk == 4.0,"Edited native growth and affinity coefficients drive supports")
	var melee := bytes.decode_u32(Policy.address(Assets.decoder,0x2f024))-0x08000000
	relocated = bytes.size(); bytes.append_array(bytes.slice(melee,melee+128)); bytes.encode_u32(Policy.address(Assets.decoder,0x2f024),0x08000000+relocated)
	d = Profile.decoder(bytes)
	var arena: Dictionary = preload("res://runtime/rom_arena.gd").read(d,Assets.item_catalog,"fe7")
	check(d.error.is_empty() and arena.classes.size() == 29,"Arena follows relocated opponent list")
	bytes = Assets.decoder.rom.duplicate(); bytes[Policy.address(Assets.decoder,0x26bd0)+10] ^= 1
	d = Profile.decoder(bytes)
	check(preload("res://runtime/fe7/fe7_dynamic_supports.gd").catalog(d,"res://test/",{}).is_empty() and not d.error.is_empty(),"Changed support rank policy is rejected")

