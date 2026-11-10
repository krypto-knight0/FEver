extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const Title = preload("res://runtime/fe6/fe6_dynamic_title.gd")
const Codec = preload("res://engine/save_codec.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)

func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func _initialize() -> void: run.call_deferred()

func fresh(wait_reinforcements: bool = false):
	var b := Battle.new(); b.load_chapter(read(Assets.dynamic_content.destinations[1]))
	b.rules.wait_enemy_reinforcements = wait_reinforcements
	b._run_events("chapter_start"); b.dialogue_queue.clear()
	return b

func visit(b, site: Dictionary, actor_id: String = "fe6_unit_1") -> Dictionary:
	var lead_unit: Dictionary = b.get_unit(actor_id)
	lead_unit.x = site.x; lead_unit.y = site.y; lead_unit.acted = false; lead_unit.moved = false
	b.dialogue_queue.clear()
	return b.interact(lead_unit.id,b.interactions.find(site))

func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var digest := FileAccess.get_sha256(source)
	# Exercise either supplied base via compatibility mode without touching it.
	var bytes := FileAccess.get_file_as_bytes(source); bytes[-1] ^= 1
	var file := FileAccess.open("user://chapter1-fixture.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	Assets.install_loader()
	var error := Assets.load_rom("user://chapter1-fixture.gba",false)
	check(error.is_empty(),"Import: "+error)
	if not error.is_empty(): finish(); return
	var pack := read("res://content/fe6/manifest.json")
	var title := read(pack.title_manifest)
	check(title.has("image") and title.has("card"),"Native title screen and card recipes")
	if title.has("image"):
		var art: Texture2D = load(title.image)
		check(art != null and art.get_size() == Vector2(240,160),"Native title renders at GBA resolution")
		if art: art.get_image().save_png("user://chapter1-title.png")
		var screen = preload("res://ui/title_screen.gd").new(); root.add_child(screen)
		check(screen.configure(pack.title_manifest) and not screen.game_label.visible,"Title UI uses cartridge artwork without placeholder label")
		screen.free()
	var card = preload("res://runtime/rom_card_art.gd")
	var library_entry := {"dynamic_rom":true,"path":"user://chapter1-fixture.gba","rom_sha256":Assets.rom_digest}
	check(card.texture(library_entry) != null,"Library card renders dynamic cartridge artwork")
	library_entry.rom_sha256 = "stale"
	check(card.texture(library_entry) == null,"Library card rejects a replaced cartridge")
	var decoder := Title.Decoder.new(); decoder.rom = bytes.duplicate()
	var original := Title.layers(decoder)
	var palette := decoder.rom.size()
	decoder.rom.append_array(decoder.raw(int(original.background.palette),32))
	decoder.rom.encode_u32(0x9b498,0x08000000+palette)
	for i in range(1,16): decoder.rom.encode_u16(palette+i*2,0x7fff)
	var relocated := Title.layers(decoder)
	check(relocated.background.palette == palette and decoder.image(original.background).get_data() != decoder.image(relocated.background).get_data(),"Title follows relocated and edited palette data")
	var missing_title := bytes.duplicate(); missing_title.encode_u32(0x9b494,0)
	var missing_assets := {}
	check(Title.manifest(missing_title,"res://missing/",missing_assets).has("label") and missing_assets.is_empty(),"Unsupported title pointers retain a text fallback")
	var b = fresh()
	check(b.gold == 5000,"ROM opening awards 5,000G")
	var village: Dictionary = b.interactions.filter(func(s):return s.x == 12 and s.y == 19)[0]
	check(visit(b,village).get("ok",false),"Bottom-right village visit succeeds")
	check(b.dialogue_queue.any(func(p):return not str(p.get("text","")).is_empty()),"Bottom-right village emits dialogue")
	check(b.gold == 10000 and Flags.has_flag(b.native_event_state,6),"Village adds 5,000G and sets its native flag")
	check(not visit(b,village).get("ok",false) and b.gold == 10000,"Village cannot pay twice")
	for site in b.interactions.filter(func(s):return s.type == "house"):
		check(visit(b,site).get("ok",false) and b.dialogue_queue.any(func(p):return not str(p.get("text","")).is_empty()),"House dialogue "+site.id)
		check(site.used and not visit(b,site).get("ok",false),"House is single-use "+site.id)
	check(b.native_event_errors.is_empty(),"Visits execute without native errors")
	var codec := Codec.new(); codec.configure(pack)
	var encoded := codec.encode({"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)})
	var decoded := codec.decode(encoded)
	var restored := Battle.new()
	check(not decoded.is_empty() and restored.restore(decoded.get("state",{})),"Visited chapter survives save/load")
	if not decoded.is_empty():
		for site in restored.interactions.filter(func(s):return s.type == "house" or (s.x == 12 and s.y == 19)):
			check(not visit(restored,site).get("ok",false),"Visited site stays closed after reload "+site.id)
	for wait_reinforcements in [false,true]:
		b = fresh(wait_reinforcements)
		var enemies: Array = b.units.filter(func(u):return u.faction == "enemy" and not u.get("boss",false))
		var enemy: Dictionary = enemies[-1]
		# Put an armed bandit next to the lead unit, leaving normal phase/event dispatch intact.
		for u in b.units:
			if u.id not in [enemy.id,"fe6_unit_1"]: u.benched = true
		var lead_unit: Dictionary = b.get_unit("fe6_unit_1"); lead_unit.x = 11; lead_unit.y = 17; lead_unit.hp = 100; lead_unit.max_hp = 100
		enemy.x = 12; enemy.y = 17
		b.end_player_turn()
		check(not b.phase_combat.is_empty(),"Bandit attacks on turn 1; wait reinforcements="+str(wait_reinforcements))
		check(b.native_event_errors.is_empty(),"First enemy phase native event executes")
	# The opening exemption must not disable the user's setting for later LOADs.
	b = fresh(true)
	var reinforcement: Dictionary = b.units.filter(func(u):return u.faction == "enemy")[0].duplicate(true)
	reinforcement.id = "test_reinforcement"; reinforcement.x = 12; reinforcement.y = 17
	b._spawn_unit(reinforcement)
	check(b.get_unit(reinforcement.id).get("reinforcement_ready_turn") == 2 and not b._can_act(b.get_unit(reinforcement.id)),"Actual reinforcement still waits")
	# The recruitment house declines unit 1, then closes only when an eligible visitor enters.
	check(Assets.ensure_resource(Assets.dynamic_content.destinations[23]),"Conditional recruitment chapter compiles")
	b = Battle.new(); b.load_chapter(read(Assets.dynamic_content.destinations[23])); b._run_events("chapter_start")
	var house: Dictionary = b.interactions.filter(func(s):return s.type == "house")[0]
	check(visit(b,house).get("ok",false) and not house.used,"Conditional recruitment house remains available after ineligible unit 1 visits")
	var eligible_visitor: Dictionary = b.get_unit("fe6_unit_1").duplicate(true); eligible_visitor.id = "fe6_unit_22"; eligible_visitor.rom_character_id = 22
	b.units.append(eligible_visitor); b.get_unit("fe6_unit_1").x -= 1
	check(visit(b,house,eligible_visitor.id).get("ok",false) and house.used and not b.get_unit("fe6_unit_21").is_empty(),"Eligible visitor recruits unit 21 and closes the house")
	check(not visit(b,house,eligible_visitor.id).get("ok",false),"Recruitment house cannot repeat after success")
	check(FileAccess.get_sha256(source) == digest,"Source cartridge unchanged")
	finish()

func finish() -> void:
	Assets.diagnostic_sink = Callable()
	print("Dynamic FE6 chapter 1 checks: ",checks," failures: ",failures)
	quit(1 if failures else 0)
