extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Arena = preload("res://engine/arena.gd")
const Cutscene = preload("res://ui/battle_cutscene.gd")
const Epilogue = preload("res://engine/fe6_epilogue.gd")
var checks := 0
var failures := 0
var images := {}
var bytes := PackedByteArray()
var strikes_shown := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func pointer(at: int) -> int: return bytes.decode_u32(at)-0x08000000
func append(block: PackedByteArray) -> int:
	bytes.resize((bytes.size()+3)&~3)
	var at := bytes.size(); bytes.append_array(block); return at
func check_images(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): check_images(child)
	elif value is Array:
		for child in value: check_images(child)
	elif value is String and value.begins_with("res://content/fe6/") and value.ends_with(".png") and not images.has(value):
		images[value] = true
		check(value.begins_with(Assets.dynamic_content.prefix) and Assets.image(value) != null,"Ending asset is available in cartridge namespace: "+value.get_file())
func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var digest := FileAccess.get_sha256(source)
	bytes = FileAccess.get_file_as_bytes(source)
	# Relocate both audio tables, edit a sound-room label, and replace the title
	# song with a different native sequence. No production ROM is modified.
	var songs := pointer(0x3748)
	var relocated := append(bytes.slice(songs,songs+0x200*8))
	bytes.encode_u32(0x3748,0x08000000+relocated)
	bytes.encode_u32(relocated+8,bytes.decode_u32(songs+0x48*8))
	var room := pointer(0x8b9c4); var count := 0
	while count < 256 and bytes.decode_u32(room+count*12) != 0xffffffff: count += 1
	relocated = append(bytes.slice(room,room+(count+1)*12))
	bytes.encode_u32(0x8b9c4,0x08000000+relocated)
	var tid := bytes.decode_u32(relocated+4)
	var text := "Edited song title".to_utf8_buffer(); text.append(0)
	var text_at := append(text)
	bytes.encode_u32(pointer(0x13b10)+tid*4,0x88000000+text_at)
	var file := FileAccess.open("user://presentation.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	Assets.install_loader()
	var error := Assets.load_rom("user://presentation.gba",false)
	check(error.is_empty(),"Dynamic import: "+error)
	if not error.is_empty(): quit(1); return
	var pack := read("res://content/fe6/manifest.json")
	var audio := preload("res://audio/audio_manager.gd").new(); root.add_child(audio)
	check(audio.configure(pack.audio_manifest,false),"Dynamic audio manifest configures")
	check(audio.manifest.sound_room_catalog.size() == count and audio.manifest.sound_room_catalog[0].title == "Edited song title","Relocated sound room supplies edited labels")
	for cue in ["title","player_battle","enemy_battle","boss_battle","victory","dialogue"]:
		check(audio.play_music(cue),"Logical music starts: "+cue)
		var sequence := preload("res://runtime/m4a_sequence.gd").new(); sequence.decoder = Assets.decoder
		var song: Dictionary = sequence.song(audio.manifest.music[cue].song_id)
		check(not song.notes.is_empty() and song.duration > 0,"Music parses native sequence: "+cue)
		if cue == "title":
			var expected: Dictionary = sequence.song(0x48)
			check(song.notes == expected.notes and song.duration == expected.duration,"Title uses the replaced song through relocated table")
	for cue in ["select","confirm","cancel","hit","miss","critical","heal","level_up","item","phase_change"]:
		check(audio.play_sfx(cue),"Native effect starts: "+cue)
	check(audio.play_music("song_048"),"Event song IDs remain playable")
	check(Assets.dynamic_content.compiled.size() == 1,"Audio does not load additional chapters")
	var path: String = Assets.dynamic_content.destinations[7]
	check(Assets.ensure_resource(path),"Arena chapter compiles")
	var b := Battle.new(); b.load_chapter(read(path)); b._run_events("chapter_start"); b._run_events("preparations")
	var site: Dictionary = b.interactions.filter(func(s):return s.type == "arena")[0]
	var hero := b.get_unit("fe6_unit_1")
	for unit in b.units:
		if unit.id != hero.id and b.position(unit) == Vector2i(site.x,site.y): unit.benched = true
	hero.x = site.x; hero.y = site.y; hero.acted = false
	b.phase = "player"; b.outcome = ""; b.gold = 10000
	var cutscene := Cutscene.new(); root.add_child(cutscene); cutscene.configure(pack.battle_animation_manifest)
	cutscene.strike_presented.connect(func(_strike): strikes_shown += 1)
	for seed_value in range(10):
		b.rng.seed = seed_value
		var arena := Arena.new()
		check(arena.offer(b,hero.id).get("ok",false),"Arena offer")
		var preview := [{"attacker_id":hero.id,"defender_id":"arena_opponent"}]
		check(cutscene.prepare_arena(arena.duel,pack.battle_animation_manifest),"Arena art prepares before wagering")
		check(cutscene.can_present(arena.duel,preview),"Arena cutscene can present both fighters")
		check(arena.duel.rules.weapon_rank_thresholds.D == 51 and arena.duel.rules.weapon_exp_kill_multiplier == 1,"Arena retains FE6 progression")
		if seed_value == 1:
			var original_hp: int = hero.hp; var original_gold: int = b.gold
			check(arena.begin() and not arena.begin() and hero.hp == original_hp,"Wager starts once and does not inflict damage")
			var strike := arena.next_strike()
			cutscene.animation_time_scale = 12
			await cutscene.play(arena.duel,[strike],true)
			check(strikes_shown == 1 and cutscene.visible and not cutscene.last_scene.is_empty(),"Previously missing opponent plays a complete animated strike")
			arena.finish("yield")
			check(arena.result == "yield" and hero.hp > 0 and b.gold == original_gold-arena.wager,"Yield preserves living fighter and loses only wager")
			arena.finish("yield"); check(b.gold == original_gold-arena.wager,"Settlement cannot charge twice")
			hero.acted = false; cutscene.cancel()
	# Every native arena class/tier must have renderable art, including classes
	# outside this chapter and promoted/magic/bow opponents.
	var catalog := Arena.new().catalog
	for cid in catalog.classes:
		var cls: Dictionary = catalog.classes[cid]
		var opponent := {"id":"arena_opponent","faction":"enemy","rom_class_id":int(cid),"rom_character_id":0xe1,"promoted":bool(str(cls.attributes).hex_to_int()&0x100),"weapon_exp":cls.weapon_ranks}
		var kind := Arena.best_type(opponent)
		opponent.weapon = catalog.weapons[str(int(catalog.basic[Arena.TYPES.find(kind)]))].duplicate(true)
		var duel := Battle.new(); duel.load_chapter({"units":[hero.duplicate(true),opponent],"terrain":[".."],"rules":{"arena":true}})
		check(cutscene.prepare_arena(duel,pack.battle_animation_manifest),"All arena classes render: "+str(cid))
	for outcome in ["victory","defeat","exhausted"]:
		hero.acted = false; hero.hp = hero.max_hp; hero.casualty_mode = ""; b.outcome = ""
		var arena := Arena.new(); check(arena.offer(b,hero.id).get("ok",false) and arena.begin(),"Arena settlement starts: "+outcome)
		if outcome == "victory":
			var fighter: Dictionary = arena.duel.get_unit(hero.id); fighter.str = 99; fighter.skill = 99; fighter.weapon.hit = 255
			arena.duel.get_unit("arena_opponent").hp = 1; arena.duel.get_unit("arena_opponent").speed = 0
		elif outcome == "defeat": arena.duel.get_unit(hero.id).hp = 0
		else: arena.duel.get_unit(hero.id).weapon.uses = 0
		arena.next_strike()
		check(arena.result == outcome,"Arena settles: "+outcome)
		if outcome == "defeat": check(hero.hp == 0 and hero.casualty_mode == "permanent","Actual arena defeat remains permanent")
	# Missing class animation is rejected before either currency or HP changes.
	hero.acted = false; hero.hp = hero.max_hp; hero.weapon.uses = 30; b.outcome = ""
	var blocked := Arena.new(); check(blocked.offer(b,hero.id).get("ok",false),"Unsupported art offer prepared")
	blocked.duel.get_unit("arena_opponent").weapon.type = "unsupported"
	var gold: int = b.gold; var hp: int = hero.hp
	check(not cutscene.prepare_arena(blocked.duel,pack.battle_animation_manifest) and b.gold == gold and hero.hp == hp and not blocked.active,"Unrenderable arena is rejected without wager or damage")
	check(cutscene._rank_name(31) == "E" and cutscene._rank_name(51) == "D","Battle rank presentation uses FE6 thresholds")
	for ending_id in [0,1,2]:
		for married in [false,true]:
			b.chapter.fe6_ending = ending_id; b.support_ranks["fe6_unit_1|fe6_unit_38"] = 3 if married else 0
			var pages: Array = Epilogue.story(b,Assets.decoder)
			check(not pages.is_empty(),"Ending dialogue reads: %d/%s" % [ending_id,str(married)])
			var prepared: Variant = Assets.prepare_story_art(pages)
			check(prepared is Array and prepared.size() == pages.size(),"Ending presentation prepares")
			if prepared is Array: check_images(prepared)
	var cards := Epilogue.pages(b,Assets.decoder)
	check(not cards.is_empty() and cards.all(func(p):return not p.text.is_empty()),"Character epilogue cards use live ROM text")
	check_images(cards)
	check(images.size() > 3,"Ending scenes exercise multiple backgrounds and portraits")
	check(Assets.dynamic_content.compiled.size() == 2,"Arena and endings do not load unrelated chapters")
	check(FileAccess.get_sha256(source) == digest,"Source cartridge unchanged")
	check(Assets.decoder.error.is_empty(),"Decoder healthy")
	cutscene.queue_free(); audio.queue_free()
	print("Dynamic FE6 presentation: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
