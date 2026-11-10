extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Difficulty = preload("res://engine/campaign_difficulty.gd")
const Codec = preload("res://engine/save_codec.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const Runner = preload("res://engine/native_event_runner.gd")
const Actions = preload("res://engine/fe6_event_actions.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var bytes := FileAccess.get_file_as_bytes(args[0]); bytes[-1] ^= 1
	var file := FileAccess.open("user://dynamic-campaign.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	var error := Assets.load_rom("user://dynamic-campaign.gba",false)
	check(error.is_empty(),"Dynamic import: "+error)
	if not error.is_empty(): finish(); return
	var pack := read("res://content/fe6/manifest.json")
	var codec := Codec.new(); codec.configure(pack)
	for entry in pack.chapters:
		var ok := Assets.ensure_resource(entry.path)
		check(ok,"Chapter %d compile: %s" % [entry.rom_chapter_index,Assets.progress if not ok else ""])
		if not ok: continue
		for mode in ["normal","hard"]:
			var b := Battle.new(); b.load_chapter(Difficulty.chapter(read(entry.path),mode)); b.set_promotion_catalog(read(pack.promotion_manifest)); b._run_events("chapter_start")
			check(b.native_event_errors.is_empty(),"Chapter %d %s opening: %s" % [entry.rom_chapter_index,mode,str(b.native_event_errors)])
			check(b.outcome.is_empty(),"Chapter %d %s starts playable: %s" % [entry.rom_chapter_index,mode,b.outcome])
			var snapshot := {"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)}
			var encoded := codec.encode(snapshot)
			check(not encoded.is_empty(),"Chapter %d %s save: %s" % [entry.rom_chapter_index,mode,codec.error])
			if not encoded.is_empty(): check(not codec.decode(encoded).is_empty(),"Chapter %d %s restore: %s" % [entry.rom_chapter_index,mode,codec.error])
			if mode == "normal": exercise(b,entry,codec)
		print("CHAPTER ",entry.rom_chapter_index," checked")
	mechanics()
	finish()

func fresh(index: int):
	var b := Battle.new(); b.load_chapter(read(Assets.dynamic_content.destinations[index]))
	b.set_promotion_catalog(Assets.dynamic_content.promotions); b._run_events("chapter_start")
	return b

func actor(b, id: int, x: int, y: int) -> Dictionary:
	var u: Dictionary = b.get_unit("fe6_unit_%d" % id)
	if u.is_empty():
		u = b.get_unit("fe6_unit_1").duplicate(true); u.id = "fe6_unit_%d" % id; u.rom_character_id = id; b.units.append(u)
	u.x = x; u.y = y; u.acted = false; u.moved = false; u.hp = u.max_hp; u.erase("benched")
	return u

func site_action(b, site: Dictionary, id: int = 1) -> bool:
	for u in b.units:
		if int(u.rom_character_id) != id and u.x == site.x and u.y == site.y: u.x = -1; u.y = -1; u.benched = true
	actor(b,id,int(site.x),int(site.y))
	return b.interact("fe6_unit_%d" % id,b.interactions.find(site)).get("ok",false)

func mechanics() -> void:
	var b = fresh(8)
	check(b.destructibles.any(func(w):return w.x == 6 and w.y == 1 and w.hp == 10),"The prison wall uses the opening callback HP")
	check(b.chapter.deployment.forced.has("fe6_unit_38"),"The predeployed prison unit (38) cannot be replaced")
	b = fresh(31); b.turn = 2; b.phase = "npc"; b._run_events("turn")
	check(not b.get_unit("fe6_unit_6").is_empty() and b.get_unit("fe6_unit_7").is_empty(),"Route recruit uses canonical unit 6 instead of alias 7")
	actor(b,6,8,20); actor(b,1,9,20); b.phase = "player"
	check(b.talk_unit("fe6_unit_1","fe6_unit_6").get("ok",false) and b.get_unit("fe6_unit_6").faction == "player","Canonical unit 6 recruits through native talk")
	for choice in range(4):
		b = fresh(16); b.gold = 12345
		actor(b,39,8,20); actor(b,1,9,20)
		var before: Dictionary = b.get_unit("fe6_unit_39").duplicate(true)
		check(b.talk_unit("fe6_unit_1","fe6_unit_39",choice).get("ok",false),"Unit 39 bargaining choice %d" % choice)
		var bargaining_unit: Dictionary = b.get_unit("fe6_unit_39")
		check(bargaining_unit.faction == "player" and b.gold == 12345-[10000,8000,6000,5000][choice] and bargaining_unit.str == before.str-choice,"Bargaining cost, recruitment and stat penalty %d" % choice)
		check(Flags.has_flag(b.native_event_state,5) and Flags.has_flag(b.native_event_state,15+choice),"Bargaining completion flags")
	# Experience-based route fork, with the shrine sidequest disabled.
	for totals in [{},{"5":1}]:
		b = fresh(16); b.chapter.fe6_experience = totals
		for binding in b.chapter.native_flag_bindings.defeats:
			if int(binding.character) == 11: Flags.set_flag(b.native_event_state,int(binding.flag))
		b._run_events("victory")
		check(b.chapter.get("native_next_chapter") == Assets.dynamic_content.destinations[17 if totals.is_empty() else 28],"Earned experience chooses native routes 17/28, including ties")
	# Exercise the actual delayed-reinforcement scripts, not a synthetic query.
	b = fresh(6); Flags.set_flag(b.native_event_state,4)
	for t in range(1,4):
		b.turn = t; b.phase = "enemy"; b._run_events("turn")
		check(Flags.has_flag(b.native_event_state,5) and (t == 1 or Flags.has_flag(b.native_event_state,6)),"Delayed reinforcement pipeline turn %d" % t)
	check(b.native_event_errors.is_empty(),"Delayed reinforcement script executes")
	# Thieves always find the ROM-defined desert treasures, once per region.
	b = fresh(14)
	for event in b.chapter.events.filter(func(e):return e.get("search_on_wait",false)):
		var lead_unit := actor(b,54 if int(event.native_program.completion_flag) == 16 else 1,int(event.region[0]),int(event.region[1])); lead_unit.rom_class_id = 52; lead_unit.faction = "player"
		b._run_events("wait",{"unit_id":lead_unit.id,"x":lead_unit.x,"y":lead_unit.y})
		check(Flags.has_flag(b.native_event_state,int(event.native_program.completion_flag)),"Thief finds desert treasure "+event.id)
	check(b.native_event_errors.is_empty(),"Desert treasure scripts execute")
	b = fresh(22)
	for cell in [[1,0],[30,0],[15,20]]:
		actor(b,1,cell[0],cell[1]); b._run_events("position",{"unit_id":"fe6_unit_1","x":cell[0],"y":cell[1]})
	check([5,6,7,8].all(func(f):return Flags.has_flag(b.native_event_state,f)) and not b.map_patches.is_empty(),"Both throne switches open the boss chamber")
	b = fresh(37)
	var gates: Array = b.interactions.filter(func(s):return s.type == "seize")
	check(b.native_event_state.flags.filter(func(f):return f in range(10,16)).size() == 1 and not b.chapter.objective.multiple,"One randomized true gate, not a sequential-seize objective")
	for f in range(10,16): Flags.set_flag(b.native_event_state,f,false)
	Flags.set_flag(b.native_event_state,11)
	var count: int = b.units.size()
	check(site_action(b,gates[0]) and b.outcome.is_empty() and b.units.size() > count,"False gate deploys ambush without victory")
	check(site_action(b,gates[1]) and b.outcome == "victory","True gate wins")
	b = fresh(24)
	var thrones: Array = b.interactions.filter(func(s):return s.type == "seize")
	check(thrones.size() == 7,"Seven final-map seals")
	check(site_action(b,thrones[0]) and b.outcome.is_empty() and Flags.has_flag(b.native_event_state,4),"First seal does not finish chapter")
	check(site_action(b,thrones[-1]) and b.outcome == "victory","Terminal throne finishes chapter")
	for weapon in [15,1]:
		b = fresh(25); actor(b,3,1,1).faction = "player"; b.chapter.fe6_last_battle_items = [weapon,0]
		b.get_unit(b.chapter.objective.unit_id).hp = 0; b._check_objective()
		check(b.outcome == "victory" and b.chapter.get("campaign_end",false) and b.chapter.get("fe6_ending") == (0 if weapon == 15 else 1),"Final-boss ending follows final weapon")
	check(not Actions.valid({"action":"ai","character":1,"settings":{"ai_mode":"pursue","id":"injected"}}),"AI command rejects unrelated unit fields")
	var d = preload("res://runtime/fe6/fe6_dynamic_profile.gd").decoder(Assets.dynamic_content.rom.duplicate())
	var definitions = preload("res://runtime/fe6/fe6_dynamic_data.gd").new(); definitions.d = d; definitions.chapter_index = 8
	for selectors in [[9,9],[0,19],[0,20],[0,21],[0,22],[0,23],[0,15],[6,12]]:
		var unit := {"faction":"enemy","source_deployment":{"ai":selectors}}
		check(definitions.base_ai(unit),"Dynamic AI selectors "+str(selectors))
		var settings := unit.duplicate(true); settings.erase("faction"); settings.erase("source_deployment")
		check(Actions.valid_ai(settings),"AI settings survive native command validation")
		if selectors[1] == 9: check(unit.ai_random_move and not unit.ai_excluded_character_ids.is_empty(),"Random movement and selective attack are independent")
		if selectors[1] == 19: check(unit.ai_waypoint.size() == 2,"Castle AI reads its waypoint")
		if selectors[1] == 15: check(unit.ai_escape_if_missing_character == 38 and not unit.ai_escape_points.is_empty(),"Prison guard approaches unit 38 then escapes")
	var native = preload("res://runtime/fe6/fe6_dynamic_native.gd")
	d.rom[0x6bbd6] = 7
	check(native.query(d,0x0806bbd1).after == 7,"Native callback imports edited turn operand")
	d.rom[0x6bbd0] ^= 1
	check(native.query(d,0x0806bbd1) == null and not d.error.is_empty(),"Changed native instructions are rejected")

func exercise(b, entry: Dictionary, codec) -> void:
	var label := "Chapter %d" % entry.rom_chapter_index
	for turn in [1,2,3,4,5,6,8,10,12,15,20,25]:
		b.turn = turn
		for phase in ["player","npc","enemy"]:
			b.phase = phase; b._run_events("turn")
	check(b.native_event_errors.is_empty(),label+" scheduled events: "+str(b.native_event_errors))
	var lord: Dictionary = b.get_unit("fe6_unit_1")
	check(not lord.is_empty() and int(lord.hp) > 0,label+" lord survives scripted scenes")
	if lord.is_empty(): return
	b.phase = "player"
	for unit in b.units:
		if unit.faction == "enemy": unit.hp = 0; b._run_events("unit_defeated",{"unit_id":unit.id})
	if b.chapter.objective.type in ["seize","native_seize"]:
		for site in b.interactions:
			if site.type != "seize" or not b.outcome.is_empty(): continue
			lord.x = site.x; lord.y = site.y; lord.acted = false; lord.moved = false
			var result: Dictionary = b.interact(lord.id,b.interactions.find(site))
			check(result.get("ok",false),label+" seize interaction: "+str(result.get("reason","")))
	else: b._check_objective()
	check(b.outcome == "victory",label+" completes its objective")
	check(b.native_event_errors.is_empty(),label+" ending: "+str(b.native_event_errors))
	check(b.chapter.get("campaign_end",false) or Assets.dynamic_content.paths.has(b.chapter.get("native_next_chapter","")),label+" ending selects a discovered chapter or campaign end")
	var snapshot := {"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)}
	check(not codec.encode(snapshot).is_empty(),label+" post-ending save: "+codec.error)
func finish() -> void:
	Assets.diagnostic_sink = Callable()
	print("Dynamic campaign checks: ",checks," failures: ",failures)
	quit(1 if failures else 0)
