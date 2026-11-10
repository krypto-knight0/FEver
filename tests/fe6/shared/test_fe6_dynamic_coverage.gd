extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Profile = preload("res://runtime/fe6/fe6_dynamic_profile.gd")
const Definitions = preload("res://runtime/fe6/fe6_dynamic_data.gd")
const Battle = preload("res://engine/battle_state.gd")
const Traits = preload("res://engine/fe6_unit_traits.gd")
const Conversations = preload("res://runtime/support_conversations.gd")
const Prep = preload("res://engine/chapter_preparation.gd")
var checks := 0
var failures := 0
var bytes := PackedByteArray()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func pointer(at: int) -> int: return bytes.decode_u32(at)-0x08000000
func append(block: PackedByteArray) -> int:
	bytes.resize((bytes.size()+3)&~3)
	var at := bytes.size(); bytes.append_array(block); return at
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var digest := FileAccess.get_sha256(source)
	bytes = FileAccess.get_file_as_bytes(source)
	var characters := pointer(0x17680)
	var table := pointer(0x6afe0)
	var count := 0
	while bytes[table+count*16] != 0: count += 1
	var relocated := append(bytes.slice(table,table+(count+1)*16))
	bytes.encode_u32(0x6afe0,0x08000000+relocated)
	var text_id := 0
	for i in range(count):
		var at := relocated+i*16
		if [bytes[at],bytes[at+1]] == [1,31]: text_id = bytes.decode_u32(at+4)
	check(text_id > 0,"Unit 1/13 support located in cartridge")
	var text := "Edited support conversation.".to_utf8_buffer(); text.append(0)
	var text_at := append(text)
	bytes.encode_u32(pointer(0x13b10)+text_id*4,0x88000000+text_at)
	for pair in [[1,31],[31,1]]:
		var at := pointer(characters+int(pair[0])*48+44)
		var shifted := append(bytes.slice(at,at+32))
		bytes.encode_u32(characters+int(pair[0])*48+44,0x08000000+shifted)
		for i in range(bytes[shifted+30]):
			if bytes[shifted+i] == pair[1]: bytes[shifted+10+i] = 50; bytes[shifted+20+i] = 4
	var affinity := pointer(0x22dbc)
	var shifted_affinity := append(bytes.slice(affinity,affinity+7*8))
	bytes.encode_u32(0x22dbc,0x08000000+shifted_affinity); bytes[shifted_affinity+1] = 8
	# A personal flag added by a hack, independently of the character's class.
	bytes.encode_u32(characters+31*48+40,bytes.decode_u32(characters+31*48+40)|0x1000000)
	var file := FileAccess.open("user://coverage.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	Assets.install_loader()
	var error := Assets.load_rom("user://coverage.gba",false)
	check(error.is_empty(),"Import modified support cartridge: "+error)
	if not error.is_empty(): finish(); return
	var pack := read("res://content/fe6/manifest.json")
	var catalog := read(pack.support_manifest)
	check(catalog.pairs.size() == count and count > 100,"All native support pairs discovered through relocated table")
	check(catalog.pairs.all(func(p):return not p.has("dialogue")) and Assets.dynamic_content.compiled.size() == 1,"Support dialogue remains lazy at import")
	check(catalog.rules.support_affinities.fire.atk == 4.0,"Relocated edited affinity coefficients")
	check(catalog.characters.any(func(c):return c.id == "fe6_unit_56" and c.rom_character_ids.has(57.0)),"Alternate unit 56/57 support identity follows native alias flag")
	var pair: Dictionary = catalog.pairs.filter(func(p):return p.a == "fe6_unit_1" and p.b == "fe6_unit_31")[0]
	check(pair.points == 50 and pair.growth == 4,"Relocated edited support growth")
	var b := Battle.new(); b.load_chapter(read(pack.start_chapter)); b.set_promotion_catalog(read(pack.promotion_manifest)); b._run_events("chapter_start")
	var lead_unit := b.get_unit("fe6_unit_1"); var partner := b.get_unit("fe6_unit_31")
	check(not partner.is_empty(),"Support partner deploys in chapter 1")
	if partner.is_empty(): finish(); return
	check(lead_unit.get("support_id") == lead_unit.id and lead_unit.has("affinity"),"Starting units receive support identities and affinities")
	check(b.rules.experience_model == "fe6" and b.rules.weapon_rank_thresholds.D == 51 and b.rules.weapon_exp_unpromoted_cap == 201,"FE6 progression rules installed")
	var test_unit: Dictionary = lead_unit.duplicate(true); test_unit.promoted = true; test_unit.level = 1; test_unit.exp = 0; test_unit.experience_bonus = 60
	var foe: Dictionary = b._normalize_unit({"id":"test_foe","faction":"enemy","level":10,"experience_power":3,"hp":0})
	var reward := b._combat_experience(test_unit,foe,[{"attacker_id":test_unit.id,"defender_id":foe.id,"damage":10,"remaining_hp":0}])
	check(reward[0].amount == 6,"Promoted FE6 combat EXP uses base-class power")
	check(partner.disable_experience and b._award_experience(partner,50).amount == 0,"ROM disable-experience flag is enforced")
	test_unit = lead_unit.duplicate(true); test_unit.weapon_exp.sword = 200
	check(b._award_weapon_experience(test_unit,test_unit.weapon,true).gained == 1 and test_unit.weapon_exp.sword == 201,"Kill gives one WEXP at FE6 unpromoted cap")
	test_unit.promoted = true; test_unit.weapon_exp.sword = 250; test_unit.weapon_exp.lance = 251
	check(b._award_weapon_experience(test_unit,test_unit.weapon,true).total == 251,"FE6 permits multiple S ranks")
	for u in b.units:
		if u.id not in [lead_unit.id,partner.id]: u.benched = true
	lead_unit.x = 11; lead_unit.y = 17; partner.x = 12; partner.y = 17
	var key := b._pair_key(lead_unit.id,partner.id)
	b._gain_support_points()
	check(b.support_points[key] == 54 and b.support_chapter_gain == 8,"Adjacent support growth uses edited ROM rate and FE6 chapter counter")
	b.support_points[key] = 60; b.dialogue_queue.clear()
	check(b.support(lead_unit.id,partner.id) and b.support_ranks[key] == 1 and b.support_points[key] == 61,"C support consumes action and applies FE6 point bonus")
	check(b.dialogue_queue.any(func(p):return p.has("support_conversation")) and not Assets.dynamic_content.compiled.has(pair.dialogue_path),"Engine queues a lazy conversation reference")
	var pages := Conversations.pages(pair,"1")
	check(pages.any(func(p):return str(p.get("text","")).contains("Edited support conversation.")),"Requested support uses changed ROM dialogue")
	check(Assets.dynamic_content.compiled.has(pair.dialogue_path) and Assets.dynamic_content.compiled.size() == 2,"Only requested pair is decoded")
	var other_pages := Conversations.pages(pair,"2")
	check(not other_pages.is_empty(),"Unchanged native B conversation decodes")
	for page in other_pages:
		for field in ["portrait","left_portrait","right_portrait"]:
			if str(page.get(field,"")).is_empty(): continue
			check(str(page[field]).begins_with(Assets.dynamic_content.prefix) and Assets.image(page[field]) != null,"Support portrait uses cartridge namespace")
	var bonus := b.support_bonuses(lead_unit.id)
	check(bonus.atk > 0,"Support affinities affect combat bonuses")
	lead_unit.acted = false; b.support_points[key] = 120
	check(b.support(lead_unit.id,partner.id) and b.support_ranks[key] == 2,"FE6 permits another rank on the same map")
	b.support_chapter_gain = 250
	check(b._pending_support_gains().is_empty(),"FE6 support chapter gain limit")
	var codec = preload("res://engine/save_codec.gd").new(); codec.configure(pack)
	var encoded: Dictionary = codec.encode({"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)})
	var saved: Dictionary = codec.decode(encoded); var restored := Battle.new()
	check(not saved.is_empty() and restored.restore(saved.get("state",{})) and restored.support_ranks.get(key) == 2,"Support rank and counters survive compact save/load")
	check(Assets.ensure_resource(Assets.dynamic_content.destinations[2]),"Chapter 2 compiles")
	var next = Prep.handoff(read(Assets.dynamic_content.destinations[2]),b,1,Assets.dynamic_content.promotions)
	next._run_events("chapter_start")
	check(next.support_ranks.get(key) == 2 and next.support_chapter_gain == 0,"Support progress carries over while chapter counter resets")
	var merchant: Dictionary = next.get_unit("fe6_unit_66")
	check(not merchant.is_empty() and merchant.get("supply_provider",false),"Convoy unit derives its role from FE6 supply flag")
	if not merchant.is_empty():
		next.chapter.deployment_complete = true; next.phase = "player"
		var ally: Dictionary = next.get_unit("fe6_unit_1"); ally.x = 11; ally.y = 17; ally.acted = false; merchant.x = 12; merchant.y = 17
		check(next.can_access_supply(ally.id),"Adjacent convoy unit enables convoy access")
	# Modified unit traits and personal weapon locks, including promotion refresh.
	var d = Profile.decoder(bytes.duplicate()); var definitions := Definitions.new(); definitions.d = d; definitions.prefix = Assets.dynamic_content.prefix
	var class_table: int = d.ptr(0x176e0)
	d.rom.encode_u32(class_table+72+36,d.u32(class_table+72+36)|0x20)
	var unit_at: int = d.rom.size(); d.rom.resize(unit_at+16); d.rom[unit_at] = 1; d.rom[unit_at+1] = 1; d.rom[unit_at+3] = 4; d.rom[unit_at+8] = 11
	var modified := definitions.unit(unit_at)
	check(modified.can_play and modified.refresh_action == "Play","Refresh ability follows edited class flags, not class ID")
	var locked_out := lead_unit.duplicate(true); locked_out.fe6_unit_flags = 0
	check(b.can_equip_weapon(lead_unit,definitions.item(11)) and not b.can_equip_weapon(locked_out,definitions.item(11)),"Personal weapon obeys ROM lock flags")
	var item_at: int = d.ptr(0x16410)+11*32
	d.rom.encode_u32(item_at+8,d.u32(item_at+8)&~0x800); definitions.items.erase(11)
	check(b.can_equip_weapon(locked_out,definitions.item(11)),"Editing the ROM weapon lock changes eligibility")
	var personal := lead_unit.duplicate(true); Traits.apply(personal,int(personal.fe6_class_flags),4|0x10000)
	b._apply_class_change(personal,b._class_definition(4))
	check(personal.can_steal and personal.fe6_unit_flags & 0x10000 and personal.promoted and personal.experience_bonus == 60,"Promotion changes class traits while preserving personal traits and EXP metadata")
	var returning := lead_unit.duplicate(true); returning.erase("campaign_restored")
	next.chapter.campaign_roster[returning.id] = personal
	preload("res://engine/army_roster.gd").restore_campaign_unit(next,returning)
	check(returning.fe6_class_flags == personal.fe6_class_flags and returning.can_steal,"Returning promoted unit restores class and personal traits together")
	var carrier := personal.duplicate(true); Traits.apply(carrier,int(carrier.fe6_class_flags)|1,0x4000)
	check(carrier.aid == 20-carrier.con,"Female mounted rescue aid uses personal flag after class change")
	var library = preload("res://ui/support_library.gd").new(); root.add_child(library); library.configure(catalog)
	check(library.scenes.item_count > 0,"Support library lists lazy conversations")
	library._play(0)
	check(not library.pages.is_empty(),"Support library loads selected dialogue on demand")
	library.queue_free(); await process_frame
	var stock_pair := {"dialogue":{"1":[{"text":"packaged"}]}}
	check(Conversations.available(stock_pair,"1") and Conversations.pages(stock_pair,"1")[0].text == "packaged","Packaged stock conversations retain existing access")
	# Exhaustive decoding is test-only; ordinary imports never do this work.
	for support_pair in catalog.pairs:
		var all_pages := Conversations.pages(support_pair,"1")
		check(not all_pages.is_empty(),"Decode native support ranks "+support_pair.a+"/"+support_pair.b+": "+Assets.dynamic_content.error)
	check(FileAccess.get_sha256(source) == digest,"Source ROM unchanged")
	finish()

func finish() -> void:
	Assets.diagnostic_sink = Callable()
	print("Dynamic FE6 coverage checks: ",checks," failures: ",failures)
	quit(1 if failures else 0)
