extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Profile = preload("res://runtime/fe6/fe6_dynamic_profile.gd")
const Identity = preload("res://runtime/game_identity.gd")
const Codec = preload("res://engine/save_codec.gd")
const Battle = preload("res://engine/battle_state.gd")
const Preparation = preload("res://engine/chapter_preparation.gd")
var failures := 0
var checks := 0
var bytes := PackedByteArray()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: ",message)

func pointer(at: int) -> int: return bytes.decode_u32(at)-0x08000000

func append(data: PackedByteArray) -> int:
	while bytes.size()%4: bytes.append(0)
	var at := bytes.size(); bytes.append_array(data)
	return at

func relocate(root_pointer: int, size: int) -> int:
	var old := pointer(root_pointer)
	var at := append(bytes.slice(old,old+size))
	bytes.encode_u32(root_pointer,0x08000000+at)
	return at

func raw_text(id: int, data: PackedByteArray) -> void:
	data.append(0)
	bytes.encode_u32(pointer(0x13b10)+id*4,0x88000000+append(data))

func write_rom(path: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()

func read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var source_hash := FileAccess.get_sha256(args[0])
	Assets.install_loader()
	if args.size() > 1 and args[1] in ["routing", "stock"]:
		check(Assets.load_rom(args[0],false).is_empty(),"Known cartridge loads")
		var fe6: bool = Assets.game_id == "fe6"
		check(Assets.dynamic_content != null and Assets.rom_digest == source_hash,"Supplied cartridge uses dynamic import")
		check(read("res://content/"+Assets.game_id+"/manifest.json").get("dynamic_rom",false),"Manifest matches dynamic importer")
		if fe6:
			check(not FileAccess.file_exists("res://runtime/fe6/templates.json") and not FileAccess.file_exists("res://runtime/fe6/assets.json"),"FE6 imports without static catalogs")
			check(preload("res://runtime/rom_card_art.gd").texture({"id":"fe6","path":args[0]}) != null,"Legacy FE6 browser entry uses live title artwork")
		check(FileAccess.get_sha256(args[0]) == source_hash,"Source cartridge unchanged")
		finish(); return
	bytes = FileAccess.get_file_as_bytes(args[0])
	check(Profile.detect(bytes).error.is_empty(),"Recognize FE6 ABI")
	var wrong := bytes.duplicate(); wrong[0xac] = 0x42
	check(not Profile.detect(wrong).error.is_empty(),"Reject non-FE6 header")
	wrong = bytes.duplicate(); wrong.encode_u32(0x17680,0xffffffff)
	check(not Profile.detect(wrong).error.is_empty(),"Reject invalid table pointer")
	var character_table := relocate(0x17680,227*48)
	append(PackedByteArray([0,0,0,0,0,0,0,0]))
	var class_table := relocate(0x176e0,76*72)
	append(PackedByteArray([0,0,0,0,0,0,0,0]))
	var item_table := relocate(0x16410,128*32)
	append(PackedByteArray([0,0,0,0,0,0,0,0]))
	relocate(0x13b10,0x1000*4)
	relocate(0x7fd8,256*16)
	relocate(0x21c74,128*8)
	relocate(0x4b0f8,256*32)
	relocate(0x3748,512*8)
	relocate(0x2bb70,256*4)
	var chapter_table := relocate(0x2bb20,45*68)
	bytes.resize(bytes.size()+30*68)
	var event_table := relocate(0x2bbcc,256*4)
	var first_header := pointer(event_table+int(bytes[chapter_table+68+58])*4)
	var alternate_header := append(bytes.slice(first_header,first_header+28))
	var ending := PackedByteArray(); ending.resize(16)
	ending.encode_u32(0,0x3d); ending.encode_u32(4,46); ending.encode_u32(8,6)
	bytes.encode_u32(first_header+24,0x08000000+append(ending))
	ending.fill(0); ending.encode_u32(0,0x3e); ending.encode_u32(4,6)
	bytes.encode_u32(alternate_header+24,0x08000000+append(ending))
	for i in range(68): bytes[chapter_table+46*68+i] = bytes[chapter_table+68+i]
	bytes[chapter_table+46*68+58] = 250
	bytes.encode_u32(event_table+250*4,0x08000000+alternate_header)
	var original_strength: int = bytes[character_table+48+13]+bytes[class_table+72+12]
	bytes[character_table+48+13] += 3
	bytes[item_table+32+21] += 2
	var expected_might := int(bytes[item_table+32+21])
	raw_text(bytes.decode_u16(character_table+48),"Test Unit".to_utf8_buffer())
	var dialogue := PackedByteArray([8,16,2,0]); dialogue.append_array("A changed opening.".to_utf8_buffer())
	raw_text(6,dialogue)
	bytes.encode_u32(0x6bfcc+20,8000)
	write_rom("user://mutation.gba")
	var began := Time.get_ticks_msec()
	var failure := Assets.load_rom("user://mutation.gba",true)
	check(failure.is_empty(),"Import relocated/mutated data: "+failure)
	if not failure.is_empty(): finish(); return
	print("Dynamic import: ",Time.get_ticks_msec()-began," ms")
	var pack := read("res://content/fe6/manifest.json")
	check(pack.dynamic_rom and pack.chapters.size() == 2,"Discover changed campaign graph without stock chapter listing")
	check(Assets.dynamic_content.compiled.size() == 1,"Only entry chapter compiled")
	check(pack.rom_sha256 == Assets.rom_digest and Assets.source_path.contains(Assets.rom_digest),"Private ROM identity uses full hash")
	check(int(Assets.item_catalog[1].might) == expected_might,"Changed item table")
	var b := Battle.new(); b.load_chapter(read(pack.start_chapter)); b.set_promotion_catalog(read(pack.promotion_manifest)); b._run_events("chapter_start")
	check(b.native_event_errors.is_empty() and b.outcome.is_empty(),"Opening executes")
	var hero := b.get_unit("fe6_unit_1")
	check(hero.name == "Test Unit" and int(hero.str) == original_strength+3,"Changed name/bases")
	check(b.gold == 8000,"Changed native gold literal")
	check(b.dialogue_queue.any(func(p):return str(p.get("text","")).contains("A changed opening.")),"Raw translated dialogue including zero-valued control arguments")
	check(not hero.has("rogue_skills"),"Dynamic classic mode has no Rogue skills")
	var map := read(b.chapter.map)
	var movement := read(pack.map_animation_manifest)
	var battles := read(pack.battle_animation_manifest)
	var animation: Dictionary = battles.animations.values()[0]
	for path in [hero.portrait,hero.sprite,map.image,movement.movement["1"].paths.player,animation.atlas.left,battles.background]:
		var image: Image = Assets.image(path)
		check(image != null and not image.is_empty(),"Decode modified-ROM art: "+str(path))
	check(preload("res://runtime/rom_audio.gd").has_song(Assets.decoder,1),"Relocated sound table")
	var codec := Codec.new(); codec.configure(pack)
	var snapshot := {"schema_version":1,"pack_id":"fe6","rom_sha256":Assets.rom_digest,"chapter_id":b.chapter.id,"state":b.serialize(false)}
	var encoded := codec.encode(snapshot)
	check(not encoded.is_empty(),"Encode modified-ROM save: "+codec.error)
	var restored := codec.decode(encoded)
	check(not restored.is_empty() and restored.state.gold == 8000,"Decode modified-ROM save: "+codec.error)
	check(not Identity.accepts(encoded,"fe6") and not Identity.accepts(encoded,"fe6","a".repeat(64)),"Reject stock/other-hack saves")
	check(Identity.save_path("fe6") != Identity.save_path("fe6",Assets.rom_digest),"Separate save locations")
	var save_path: String = Identity.save_path("fe6",Assets.rom_digest)
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var save_file := FileAccess.open(save_path,FileAccess.WRITE)
	save_file.store_string(JSON.stringify(encoded)); save_file.close()
	check(preload("res://runtime/save_archive.gd").files().values().has(save_path),"Library backup includes modified-ROM saves")
	b.gold = 1234; hero.level = 8; hero.weapon.uses = 5
	var next_path: String = pack.chapters[1].path
	var prepared := Preparation.read(next_path,"normal")
	check(not prepared.is_empty() and Assets.dynamic_content.compiled.size() == 2,"Lazy loading follows relocated chapter 46")
	if not prepared.is_empty():
		var next := Preparation.handoff(prepared.chapter,b,1,read(pack.promotion_manifest))
		Preparation.start(next)
		check(next.native_event_errors.is_empty(),"Dynamic handoff executes")
		check(int(next.get_unit("fe6_unit_1").level) == 8 and int(next.get_unit("fe6_unit_1").weapon.uses) == 5,"Carryover retains levels/inventory")
		check(next.units.filter(func(u):return u.id == "fe6_unit_27").size() == 1 and not next.chapter.get("reserve_units",[]).any(func(u):return u.id == "fe6_unit_27"),"Opening LOAD activates carried reserve exactly once")
	# Unknown callback in a later chapter must fail without corrupting active data.
	var turn_table := pointer(alternate_header)
	var new_turns := append(bytes.slice(turn_table,turn_table+36))
	var unknown := PackedByteArray(); unknown.resize(12); unknown.encode_u32(0,0x17); unknown.encode_u32(4,0x08000001); unknown.encode_u32(8,6)
	bytes.encode_u32(new_turns+4,0x08000000+append(unknown)); bytes.encode_u32(alternate_header,0x08000000+new_turns)
	write_rom("user://unsupported-later.gba")
	check(Assets.load_rom("user://unsupported-later.gba",false).is_empty(),"Unsupported later chapter remains lazy")
	pack = read("res://content/fe6/manifest.json")
	check(not Assets.ensure_resource(pack.chapters[1].path),"Unknown callback rejected")
	check(Assets.initialized() and Assets.dynamic_content.compiled.size() == 1 and read(pack.chapters[1].path).get("dynamic_pending",false),"Failure preserves active decoder and leaves pending resource uncompiled")
	check(Assets.ensure_resource(pack.start_chapter),"Supported chapter remains usable")
	check(not Identity.accepts(encoded,"fe6",Assets.rom_digest),"Changed ROM cannot consume previous variant's save")
	check(FileAccess.get_sha256(args[0]) == source_hash,"Original cartridge unchanged")
	# Exercise main scene setup against generated manifests, not just parser APIs.
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(not main.chapter.is_empty() and main.battle.native_event_errors.is_empty(),"Dynamic main scene initializes")
	main._cancel_scene_presentation(); main.scene_transition.cancel()
	await process_frame
	await process_frame
	main.queue_free(); await process_frame
	finish()

func finish() -> void:
	Assets.diagnostic_sink = Callable()
	print("Dynamic FE6 checks: ",checks," failures: ",failures)
	quit(1 if failures else 0)
