extends "fe7_test_base.gd"
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Ending = preload("res://runtime/fe7/fe7_dynamic_ending.gd")
const Rank = preload("res://engine/fe7_campaign_rank.gd")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("ERROR: Supply an English FE7 or Flux Echo 7 cartridge"); quit(2); return
	var source := args[0]
	var digest := FileAccess.get_sha256(source)
	var bytes := FileAccess.get_file_as_bytes(source)
	check(Profile.detect(bytes).get("region") in ["AE7E","FX7E"],"Supported English FE7 profile detected")
	var failure := Assets.load_rom(source,false)
	check(failure.is_empty(),"US dynamic import: "+failure)
	if not failure.is_empty(): quit(1); return
	Assets.install_loader()
	check(Assets.dynamic_content != null and Policy.us(Assets.decoder),"English dynamic runtime selected")
	var character_record: int = Assets.decoder.ptr(int(Assets.decoder.layout.characters))+2*int(Assets.decoder.layout.character_stride)
	var native_name: String = Assets.decoder.text(Assets.decoder.u16(character_record))
	check(not native_name.is_empty() and Names.character(Assets.decoder,"fe7",3) == native_name,"Character name resolves from the selected cartridge")
	check(Assets.dynamic_content.manifest.chapters.size() == 76,"All route/chapter variants compiled")
	if "focused" not in OS.get_cmdline_user_args():
		for mode in (["normal"] if "normal" in args else ["hard"] if "hard" in args else ["normal","hard"]):
			active_mode = mode
			for entry in Assets.dynamic_content.manifest.chapters:
				var b := port_battle(int(entry.rom_chapter_index),int(entry.native_route))
				check(b.outcome.is_empty(),"Playable "+str(entry.id)+" "+mode)
				var restored := Battle.new()
				check(restored.restore(JSON.parse_string(JSON.stringify(b.serialize(false)))),"English opening suspend restores")
				check(b.rules.effectiveness_multiplier == 2,"US effectiveness multiplier retained")
			print("US Classic openings: ",mode)
	active_mode = "normal"
	regional_checks()
	ending_checks_us()
	media_checks(port_battle(0,1),port_battle(1,1))
	for asset_path in Assets.dynamic_content.assets:
		if Assets.dynamic_content.assets[asset_path].kind in ["scene","worldmap","portrait","platform"]:
			check(Assets.image(asset_path) != null,"US story/world-map artwork: "+str(asset_path))
	gameplay_checks_us()
	check(Assets.decoder.error.is_empty(),"US campaign decoder healthy: "+str(Assets.decoder.error))
	var error := Assets.load_rom(source,false)
	check(error.is_empty() and Assets.dynamic_content != null and Assets.rom_digest == digest,"Selected cartridge reloads dynamically: "+error)
	check(FileAccess.get_sha256(source) == digest,"Supplied ROM unchanged")
	print("Dynamic FE7 US: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func regional_checks() -> void:
	var d: RefCounted = Assets.decoder
	var bytes: PackedByteArray = d.rom.duplicate()
	var at := bytes.size()
	bytes.append_array(PackedByteArray([16,3,0,65,128,0,66,0]))
	var altered := Profile.decoder(bytes)
	check(altered.pointer_symbols(0x88000000+at) == [16,3,65,128,0,66],"Raw English controls retain zero argument bytes")
	bytes = d.rom.duplicate(); bytes[Policy.address(d,0x17f3c)] ^= 1
	altered = Profile.decoder(bytes)
	check(not NativeDifficulty.validate(altered),"Modified US difficulty instructions rejected")
	bytes = d.rom.duplicate(); bytes[0x7cfa8] ^= 1
	altered = Profile.decoder(bytes)
	check(preload("res://runtime/fe7/fe7_dynamic_native.gd").predicate(altered,0x0807cfa9,12).is_empty() and not altered.error.is_empty(),"Actual changed callback bytes are checked")
	var b := port_battle(35,2)
	for flag in [false,true]:
		preload("res://engine/native_event_flags.gd").set_flag(b.native_event_state,0x65,flag)
		var ending: Dictionary = b.chapter.events.filter(func(e):return e.trigger == "victory")[0]
		var result := preload("res://engine/native_event_runner.gd").plan(b,ending.native_program,{})
		check(result.error.is_empty(),"Continued conditional English dialogue plans on both branches")

func ending_checks_us() -> void:
	var d: RefCounted = Assets.decoder
	var roll := Ending.credits(d)
	check(not roll.is_empty() and d.error.is_empty(),"US credits decode: "+str(d.error))
	if not roll.is_empty():
		check(roll.image.get_size() == Vector2i(256,2048) and roll.distance == 1823,"US seven-block credits layout and scroll distance")
		roll.image.save_png("user://us-credits.png")
	check(Ending.ranking_background(d) != null and d.error.is_empty(),"US ranking background decodes")
	for route in [2,3]:
		var b := port_battle(47,route)
		for key in ["farewell","teaser"]:
			var pages := Ending.story(b,key,d)
			check(pages.any(func(page):return not str(page.get("text","")).is_empty()),"English "+key)
			for page in pages:
				if not str(page.get("background","")).is_empty(): check(Assets.image(page.background) != null,"English ending artwork")
		b.chapter.fe7_rank_records = {"47":{"turns":12,"experience":900,"battles":40,"wins":30}}
		var rank := Rank.page(b,d)
		check(not rank.title.is_empty() and not rank.text.is_empty(),"English ranking text")
		var pages := preload("res://engine/epilogue.gd").pages(b,"fe7_unit_2" if route == 3 else "fe7_unit_1",d)
		check(pages.any(func(page):return page.has("ranking")),"English epilogue contains tactician ranking")

func gameplay_checks_us() -> void:
	var b := port_battle(0,1)
	var lyn: Dictionary = b.get_unit("fe7_unit_3")
	var gate: Dictionary = b.interactions.filter(func(i):return i.type == "seize")[0]
	lyn.x = gate.x; lyn.y = gate.y; lyn.acted = false
	check(b.interact(lyn.id).get("ok",false) and b.outcome == "victory","US prologue seizure completes")
	var next := Prep.handoff(Prep.read(b.chapter.next_chapter,"normal").chapter,b,1,{})
	next._run_events("chapter_start")
	check(next.native_event_errors.is_empty() and next.get_unit(lyn.id).hp > 0,"US prologue progresses with carried Lyn")
	var runner = preload("res://engine/native_event_runner.gd")
	var flags = preload("res://engine/native_event_flags.gd")
	var returning := port_battle(19,2)
	var bonus := {}
	for event in returning.chapter.events:
		for script in event.get("native_program",{}).get("scripts",[]):
			for command in script:
				if command.op == "fe7_bonus": bonus = command
	check(bonus.has("default_without_lyn"),"US Lyn bonus helper supplies fallback gem")
	if not bonus.is_empty():
		var actor: Dictionary = returning.units.filter(func(u):return u.rom_character_id == bonus.character)[0]
		actor.inventory = []; actor.weapon = {}
		for flag in bonus.flags: flags.set_flag(returning.native_event_state,int(flag),false)
		for completed in [false,true]:
			returning.chapter.get_or_add("story_flags",{}).fe7_lyn_completed = completed
			var result := runner.plan(returning,{"version":1,"scripts":[[bonus,{"op":"end"}]]},{})
			check(result.error.is_empty(),"US bonus plans with/without Lyn completion")
			check(result.commands.any(func(c):return c.op == "fe7_inventory_result") == not completed,"Default gem only for skipped Lyn campaign")
	var crazed := port_battle(33,3)
	var sites: Array = crazed.chapter.events.filter(func(e):return e.trigger == "enter_region" and e.region[0] == e.region[2] and e.region[1] == e.region[3])
	var captor: Dictionary = crazed.units.filter(func(u):return u.faction == "player" and u.rom_character_id != 2)[0]
	for site in sites:
		place_test_unit(crazed,captor,Vector2i(site.region[0],site.region[1]))
		crazed.phase = "player"; captor.acted = false
		crazed._run_events("position",{"unit_id":captor.id,"x":captor.x,"y":captor.y})
		crazed.wait_unit(captor.id)
	check(sites.size() == 3 and crazed.outcome == "victory" and crazed.native_event_errors.is_empty(),"US three-fort objective completes")
	# This AI is assigned by conditional event branches; test its actual native
	# record directly, independently of which soldiers remain after a capture.
	var native_ai := {"source_deployment":{"ai":[0,20,0,0],"offset":"0x0"},"faction":"enemy"}
	check(preload("res://runtime/rom_unit_factory.gd")._ai(Assets.decoder,"fe7",native_ai),"US region approach AI decodes")
	check(native_ai.get("ai_waypoint_repeats",false) and native_ai.ai_waypoint == [18,13] and native_ai.ai_waypoint_region.is_empty(),"US invalid region keeps its live waypoint without a pursuit transition")
