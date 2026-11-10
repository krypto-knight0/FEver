extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Difficulty = preload("res://engine/campaign_difficulty.gd")
const Rogue = preload("res://engine/rogue_mode.gd")
const Army = preload("res://engine/army_roster.gd")
const Config = preload("res://engine/personal_skill_config.gd")
const Preparation = preload("res://engine/chapter_preparation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func fresh(index: int = 1, mode: String = "rogue_normal") -> RefCounted:
	var path: String = Assets.dynamic_content.destinations[index]
	check(Assets.ensure_resource(path),"Compile chapter "+str(index))
	var b := Battle.new(); b.load_chapter(Difficulty.chapter(read(path),mode))
	b.set_promotion_catalog(Assets.dynamic_content.promotions); b._run_events("chapter_start")
	return b
func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var before := FileAccess.get_sha256(source)
	var bytes := FileAccess.get_file_as_bytes(source); bytes[0xbf] ^= 1
	var file := FileAccess.open("user://dynamic-rogue.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	var error := Assets.load_rom("user://dynamic-rogue.gba",false)
	check(error.is_empty(),"Dynamic import: "+error)
	if not error.is_empty(): quit(1); return
	Assets.install_loader()
	await ui_checks()
	personal_checks()
	reward_checks()
	army_checks()
	transition_checks()
	if OS.get_cmdline_user_args().has("focused"):
		finish(source,before); return
	var pack := read("res://content/fe6/manifest.json")
	var codec := preload("res://engine/save_codec.gd").new(); codec.configure(pack)
	for entry in pack.chapters:
		for mode in ["rogue_normal","rogue_hard"]:
			var b := fresh(int(entry.rom_chapter_index),mode)
			var label := "%s %s" % [entry.rom_chapter_index,mode]
			check(b.native_event_errors.is_empty() and b.outcome.is_empty(),"Playable native opening "+label)
			check(b.rules.hard_mode == (mode == "rogue_hard") and b.rules.permadeath,"Difficulty/permadeath "+label)
			check(b.chapter.deployment.slots.size() <= 6 and b.chapter.deployment.limit > 0,"Opening retains Rogue deployment limit "+label)
			for unit in b.units:
				if unit.faction == "player":
					var id := "fe6_unit_%d" % int(unit.rom_character_id)
					if not Config.definition(id).is_empty(): check(unit.get("rogue_personal",{}).get("id") == id,"Native personal "+id+" "+label)
				if unit.faction == "enemy":
					check(not unit.get("rogue_skills",{}).is_empty(),"Native enemy skills "+label)
					check(not Rogue.DYNAMIC_UNAVAILABLE.any(func(id):return unit.rogue_skills.has(id)),"Compatible enemy skills "+label)
			check(Army.deploy(b,Army.default_selection(b)).get("ok",false),"Deploy native formation "+label)
			var snapshot := {"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)}
			var encoded := codec.encode(snapshot)
			check(not encoded.is_empty() and not codec.decode(encoded).is_empty(),"Rogue cartridge-bound save "+label+" "+codec.error)
		print("ROGUE CHAPTER ",entry.rom_chapter_index," checked")
	finish(source,before)

func finish(source: String, before: String) -> void:
	check(FileAccess.get_sha256(source) == before,"Source cartridge unchanged")
	check(Assets.decoder.error.is_empty(),"Main ROM decoder stays healthy")
	print("Dynamic FE6 Rogue: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func ui_checks() -> void:
	var route := preload("res://ui/route_select.gd").new(); root.add_child(route); route.present(false,"fe6")
	for index in [2,3]: check(not route.difficulty_picker.is_item_disabled(index),"Dynamic Rogue difficulty selectable")
	route.queue_free()
	var library := preload("res://ui/skill_library.gd").new(); root.add_child(library); library.configure()
	for id in Rogue.DYNAMIC_UNAVAILABLE: check(not library.records.any(func(r):return r.id == id),"Unsupported skill hidden: "+id)
	for id in Rogue.ARMY_TEXT: check(library.records.any(func(r):return r.id == id),"Army skill listed: "+id)
	library.queue_free(); await process_frame

func personal_checks() -> void:
	var b := fresh()
	var lead_unit: Dictionary = b.get_unit("fe6_unit_1")
	for id in Config.defaults:
		if not str(id).begins_with("fe6_unit_"): continue
		var u := lead_unit.duplicate(true); u.id = "custom_spawn"; u.name = "Renamed character"; u.rom_character_id = str(id).trim_prefix("fe6_unit_").to_int()
		u.erase("rogue_personal"); Rogue.initialize_unit(b,u)
		check(u.rogue_personal.id == id,"Renamed native character maps to "+id)
	var unknown := lead_unit.duplicate(true); unknown.id = "fe6_unit_200"; unknown.rom_character_id = 200; unknown.erase("rogue_personal")
	Rogue.initialize_unit(b,unknown)
	check(unknown.rogue_personal.get("amount") == 2 and unknown.rogue_personal.id == unknown.id,"Additional characters receive Potential")
	check(Rogue.Personal.is_lord(lead_unit),"Lead unit recognized from native flags")
	var rider := lead_unit.duplicate(true); rider.rogue_skills = {"granis_shield":1}; rider.mounted = true; rider.canto = false
	check(Rogue.shield(rider),"Cavalry shield uses native mounted flag without Canto")
	rider.mounted = false; rider.canto = true
	check(not Rogue.shield(rider),"Foot units with Canto do not count as cavalry")
	var partner: Dictionary = b.get_unit("fe6_unit_13"); partner.x = lead_unit.x+1; partner.y = lead_unit.y
	var enemy: Dictionary = b.units.filter(func(u):return u.faction == "enemy")[0]
	enemy.weapon = {"type":"axe"}; partner.gender = "male"
	b.support_ranks[b._pair_key(lead_unit.id,partner.id)] = 1
	check(Rogue.Personal.FE6.can_guard(b,lead_unit,partner,enemy),"Physical guard accepts same-gender support partner")
	b.chapter.dynamic_rom = false
	check(not Rogue.Personal.FE6.can_guard(b,lead_unit,partner,enemy),"Native physical guard keeps gender condition")
	b.chapter.dynamic_rom = true
	Rogue.Personal.FE6.use_guard(b,lead_unit,partner)
	check(not Rogue.Personal.FE6.can_guard(b,lead_unit,partner,enemy),"Dynamic guard retains per-partner rank limit")
	lead_unit.rogue_personal = {"id":"fe6_unit_38"}; lead_unit.erase("rogue_personal_state")
	partner.gender = "female"; enemy.weapon = {"type":"anima"}
	check(Rogue.Personal.FE6.can_guard(b,lead_unit,partner,enemy),"Magical guard accepts any support partner")
	enemy.weapon.type = "axe"
	check(not Rogue.Personal.FE6.can_guard(b,lead_unit,partner,enemy),"Magical guard still requires magic")
	for id in ["fe6_unit_1","fe6_unit_38"]:
		check(not Config.description(id).contains("male support"),"Guard description matches dynamic behavior")

func reward_checks() -> void:
	var b := fresh()
	b.rng.seed = 98765
	var seen := {}
	for i in range(250):
		b.chapter.rogue.erase("offer")
		for skill in Rogue.offer(b): seen[skill] = true
	check(seen.size() == Rogue.UNIT_TEXT.size()-Rogue.DYNAMIC_UNAVAILABLE.size()-1,"Character pool includes all eligible skills except resurrection without casualties")
	for skill in Rogue.DYNAMIC_UNAVAILABLE:
		check(not seen.has(skill),"Unsupported skill never offered: "+skill)
		b.chapter.rogue.offer = [skill]
		check(not Rogue.choose(b,skill,"fe6_unit_1"),"Unsupported saved card cannot be granted")
	for completed in [5,20]:
		b.chapter.rogue.completed = completed; seen.clear()
		for i in range(150):
			b.chapter.rogue.erase("offer")
			for skill in Rogue.offer(b): seen[skill] = true
		check(seen.has("alternate_reality") == (completed == 20) and seen.has("welcome_to_the_team") == (completed == 20),"Late army cards follow actual campaign progress")
		if completed == 20: check(seen.size() == Rogue.ARMY_TEXT.size(),"Every army skill can be offered")
	for id in Rogue.ARMY_TEXT:
		b = fresh(); b.chapter.rogue.completed = 20; b.chapter.rogue.offer = [id,"darkvision","study_sessions"]
		var lead_unit: Dictionary = b.get_unit("fe6_unit_1"); var ranged_unit: Dictionary = b.get_unit("fe6_unit_13")
		lead_unit.rogue_skills = {"haste":2}; ranged_unit.rogue_skills = {"str_up":1}; ranged_unit.level = 10
		if id == "alternate_reality":
			lead_unit.level = 3; lead_unit.str = 10; lead_unit.rogue_growth_gains = {"str":2}; lead_unit.rogue_level_count = 2
			for stat in Rogue.STATS: lead_unit.growths[stat] = 0
		check(Rogue.choose(b,id,"fe6_unit_1","fe6_unit_13"),"Army card applies: "+id)
		if id != "reroll": check(Rogue.army(b,id) == 1 and b.chapter.rogue.chosen,"Army card persists: "+id)
		else: check(b.chapter.rogue.rerolled and Rogue.offer(b).size() == 3,"Army reroll produces fresh choices")
		if id == "identity_theft": check(Rogue.count(lead_unit,"str_up") == 1 and Rogue.count(ranged_unit,"haste") == 2 and lead_unit.rogue_personal.id == "fe6_unit_1" and ranged_unit.rogue_personal.id == "fe6_unit_13","Identity Theft swaps acquired skills only")
		if id == "alternate_reality": check(lead_unit.str == 8 and lead_unit.level == 3,"Alternate Reality rerolls recorded growth while preserving level")
		if id == "welcome_to_the_team": check(lead_unit.level > 1,"Welcome to the Team levels native character")
		if id == "extra_training": check(b.chapter.rogue.training == 5,"Extra Training grants charges")

func army_checks() -> void:
	var b := fresh()
	var lead_unit: Dictionary = b.get_unit("fe6_unit_1")
	# Isolate army bonuses from the native Mentor personal aura.
	for unit in b.units: unit.rogue_personal = {}
	b.chapter.rogue.army = {"loyal_customer":2,"gladiators_will":1,"guidance_of_fe7_unit_39":2,"study_sessions":2,"sparring_sessions":1,"fast_learners":1,"tea_time":1}
	check(Rogue.price(b,100) == 80,"Native shop discount")
	check(Rogue.remaining(b,"arena") == 10 and Rogue.remaining(b,"undo") == 15,"Arena and Undo allowances")
	check(Rogue.growth(b,lead_unit,"str") == int(lead_unit.growths.str)+20,"Native growths receive Study Sessions")
	check(b._award_experience(lead_unit,10).amount == 11,"Native experience receives Fast Learners")
	var sword: Dictionary = lead_unit.weapon.duplicate(true); sword.weapon_exp = 10
	check(b._award_weapon_experience(lead_unit,sword).gained == 11,"Native weapon ranks receive Sparring Sessions")
	var key: String = b._pair_key(lead_unit.id,"fe6_unit_13")
	var points := int(b.support_points.get(key,0)); b._commit_support_gains({key:10},1)
	check(int(b.support_points[key]) == points+11,"Native supports receive Tea Time")
	b.rules.fog_radius = 1; var visible: int = b.visible_cells().size(); b.chapter.rogue.army.darkvision = 1
	check(b.visible_cells().size() > visible,"Darkvision extends native map visibility")
	b.rules.weather = 4; var cell: Vector2i = b.position(lead_unit)
	var terrain: String = b.terrain[cell.y][cell.x]
	lead_unit.movement_costs = {terrain:1}; lead_unit.movement_costs_rain = {terrain:3}
	check(b.movement_cost(lead_unit,cell) == 3,"Fixture has rain penalty")
	b.chapter.rogue.army.commandos = 1
	check(b.movement_cost(lead_unit,cell) == 1,"Commandos ignores rain")
	b.chapter.rogue.training = 5; b._award_experience(lead_unit,100)
	check(Rogue.reroll_level(b,lead_unit) and b.chapter.rogue.training == 4,"Extra Training rerolls native stat growths")
	var foe: Dictionary = b.units.filter(func(u):return u.faction == "enemy")[0]
	foe.drop_item = foe.weapon.duplicate(true); var items: int = b.inventory.size()
	b.chapter.rogue.army.spoils_of_war = 1; Rogue.chapter_clear(b)
	check(b.inventory.size() > items and foe.drop_claimed,"Spoils collects native enemy drops")
	items = b.inventory.size(); Rogue.chapter_clear(b)
	check(b.inventory.size() == items,"Spoils awarded only once")

func transition_checks() -> void:
	var b := fresh(); var lead_unit: Dictionary = b.get_unit("fe6_unit_1")
	lead_unit.rogue_skills = {"haste":2}; b.chapter.rogue.army = {"darkvision":2}; b.chapter.rogue.undo_used = 4
	b.get_unit("fe6_unit_13").hp = 0; b.get_unit("fe6_unit_13").casualty_mode = "permanent"
	Assets.ensure_resource(Assets.dynamic_content.destinations[2])
	var next := Preparation.handoff(Difficulty.chapter(read(Assets.dynamic_content.destinations[2]),"rogue_normal"),b,5,Assets.dynamic_content.promotions)
	Preparation.start(next)
	check(Rogue.count(next.get_unit(lead_unit.id),"haste") == 2 and Rogue.army(next,"darkvision") == 2,"Native LOAD preserves unit and army upgrades")
	check(Rogue.is_army_offer(next) and Rogue.remaining(next,"undo") == 5,"Native opening preserves completed chapters and resets allowances")
	check(int(next.get_unit("fe6_unit_13").hp) == 0,"Native LOAD does not revive a fallen ally")
	check(next.chapter.deployment.slots.size() <= 6,"Native transition keeps six slots")
	next.chapter.rogue.completed = 6; next.chapter.rogue.offer = ["resurrect"]
	check(Rogue.choose(next,"resurrect","fe6_unit_13") and int(next.get_unit("fe6_unit_13").hp) > 0,"Resurrection works with native casualties")
	var copy := Battle.new()
	check(copy.restore(JSON.parse_string(JSON.stringify(next.serialize(false)))),"Dynamic Rogue suspend restores")
	check(Rogue.count(copy.get_unit(lead_unit.id),"haste") == 2 and Rogue.army(copy,"darkvision") == 2 and copy.chapter.rogue.completed == 6,"Suspend preserves upgrades and progress")
	b = fresh(7)
	for turn in [1,2,3]:
		b.turn = turn
		for phase in ["player","npc","enemy"]: b.phase = phase; b._run_events("turn")
	b.phase = "player"
	var recruit: Dictionary = b.get_unit("fe6_unit_60")
	lead_unit = b.get_unit("fe6_unit_1"); lead_unit.x = recruit.x+1; lead_unit.y = recruit.y
	check(b.talk_unit(lead_unit.id,recruit.id).get("ok",false),"Native talk recruits neutral ally")
	check(recruit.faction == "player" and recruit.get("rogue_personal",{}).get("id") == "fe6_unit_60","Native recruit receives ID personal")
	b = fresh(8)
	var prison_unit: Dictionary = b.get_unit("fe6_unit_38"); var prison: Vector2i = b.position(prison_unit)
	check(Army.deploy(b,Army.default_selection(b)).get("ok",false) and b.position(prison_unit) == prison and b.chapter.deployment.forced.has(prison_unit.id),"Rogue preserves scripted forced prison deployment")
