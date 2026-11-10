extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Cutscene = preload("res://ui/battle_cutscene.gd")
const Gallery = preload("res://runtime/fe6/fe6_dynamic_library.gd")
class ClockScene extends Cutscene:
	var impacts := 0
	func _impact(_strike: Dictionary, _ranged: bool, _token: int, _tail: float = 0.0) -> bool:
		impacts += 1
		return true
var checks := 0
var failures := 0
var bytes := PackedByteArray()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func pointer(at: int) -> int: return bytes.decode_u32(at)-0x08000000
func append(block: PackedByteArray) -> int:
	bytes.resize((bytes.size()+3)&~3)
	var at := bytes.size(); bytes.append_array(block); return at
func files(path: String = "user://") -> Dictionary:
	var result := {}
	for name in DirAccess.get_files_at(path): result[path.path_join(name)] = FileAccess.get_sha256(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		# Existing engine and diagnostics logs are not gallery caches.
		if name not in ["logs","diagnostics"]: result.merge(files(path.path_join(name)))
	return result
func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var digest := FileAccess.get_sha256(source)
	bytes = FileAccess.get_file_as_bytes(source)
	# Repoint/expand live tables with an extra entry; edit a character label.
	var probe := Gallery.new(); probe.rom = bytes
	var portraits := pointer(0x7fd8); var portrait_count := 1
	while probe.portrait_valid(portraits,portrait_count): portrait_count += 1
	var shifted := append(bytes.slice(portraits,portraits+portrait_count*16))
	bytes.append_array(bytes.slice(portraits+2*16,portraits+3*16)); bytes.resize(bytes.size()+16)
	bytes.encode_u32(0x7fd8,0x08000000+shifted)
	var backgrounds := pointer(0xe374); var background_count := 0
	while probe.background_valid(backgrounds,background_count): background_count += 1
	shifted = append(bytes.slice(backgrounds,backgrounds+background_count*12))
	bytes.append_array(bytes.slice(backgrounds,backgrounds+12)); bytes.resize(bytes.size()+12)
	bytes.encode_u32(0xe374,0x08000000+shifted)
	var text := "Gallery Unit".to_utf8_buffer(); text.append(0)
	var text_at := append(text)
	var tid := bytes.decode_u16(pointer(0x17680)+48)
	bytes.encode_u32(pointer(0x13b10)+tid*4,0x88000000+text_at)
	var f := FileAccess.open("user://libraries.gba",FileAccess.WRITE); f.store_buffer(bytes); f.close()
	Assets.install_loader()
	var start := Time.get_ticks_msec()
	var error := Assets.load_rom("user://libraries.gba",false)
	print("Library fixture import: ",Time.get_ticks_msec()-start," ms")
	check(error.is_empty(),"Dynamic import: "+error)
	if not error.is_empty(): quit(1); return
	var pack := read("res://content/fe6/manifest.json")
	check(Assets.dynamic_content.library == null,"No gallery indexing during import")
	var before_files := files()
	var generation: int = Assets.dynamic_content.package.generation
	var viewer := preload("res://ui/backdrop_viewer.gd").new(); root.add_child(viewer)
	for kind in ["portraits","backgrounds","maps"]:
		var entries := Assets.library_catalog(kind)
		var expected: int = portrait_count if kind == "portraits" else background_count+2 if kind == "backgrounds" else pack.chapters.size()
		check(entries.size() == expected,"Live catalog count: "+kind)
		check(entries.all(func(e):return e.path.begins_with(Assets.dynamic_content.prefix+"library/")),"ROM-specific gallery paths: "+kind)
		if kind == "portraits": check(entries.any(func(e):return e.title == "Gallery Unit"),"Portrait label follows edited ROM name")
		if kind == "maps": check(entries.all(func(e):return e.width > 0 and e.height > 0),"Map dimensions indexed from native grids")
		viewer.configure_dynamic(kind)
		check(viewer.entries.size() == entries.size() and viewer.picture.texture != null,"Browser displays first entry: "+kind)
		viewer.select_image(viewer.entries.size()-1)
		check(viewer.picture.texture != null and viewer.current_index == viewer.entries.size()-1,"Browser displays final entry: "+kind)
		viewer.search.text = str(viewer.entries[-1].title); viewer._filter_catalog()
		check(not viewer.filtered.is_empty(),"Browser search: "+kind)
		var render_total := 0; var render_max := 0
		for entry in entries:
			var render_start := Time.get_ticks_usec()
			check(Assets.image(entry.path) != null,"Decode "+kind+" "+entry.id)
			var elapsed := Time.get_ticks_usec()-render_start
			render_total += elapsed; render_max = maxi(render_max,elapsed)
		print("Gallery ",kind,": ",entries.size()," entries, index ",Assets.dynamic_content.library.timings[kind]," ms")
		print("Decode ",kind,": average ",render_total/1000.0/entries.size()," ms, maximum ",render_max/1000.0," ms")
	check(Assets.dynamic_content.compiled.size() == 1,"Browsing every map does not compile chapters")
	var after_files := files()
	for path in after_files:
		if before_files.get(path,"") != after_files[path]: print("GALLERY FILE CHANGE ",path)
	check(Assets.dynamic_content.package.generation == generation and after_files == before_files,"Indexing and viewing galleries writes no files or resource packages")
	var gallery: RefCounted = Assets.dynamic_content.library
	var modified: PackedByteArray = gallery.rom.duplicate()
	var face: Dictionary = gallery.catalogs.portraits[0]
	var graphics: int = gallery.assets[face.path].id
	var address := pointer(pointer(0x7fd8)+graphics*16)
	modified[address] = 0
	gallery.rom = modified
	viewer.configure_dynamic("portraits")
	var face_index := viewer.entries.find(face)
	viewer.select_image(face_index)
	check(viewer.picture.texture == null and viewer.caption.text.contains("could not be read"),"Corrupt optional portrait is handled in browser")
	check(Assets.decoder.error.is_empty(),"Optional corrupt art does not poison campaign decoder")
	gallery.rom = bytes
	viewer.configure_dynamic("maps")
	check(viewer.picture.texture != null,"Other libraries remain usable after failed image")
	viewer.queue_free()
	check(Assets.ensure_resource(Assets.dynamic_content.destinations[2]),"Staff chapter compiles after browsing")
	var b := Battle.new(); b.load_chapter(read(Assets.dynamic_content.destinations[2])); b._run_events("chapter_start")
	var healer := b.get_unit("fe6_unit_17"); var lead_unit := b.get_unit("fe6_unit_1")
	check(healer.weapon.is_empty() and healer.inventory.any(func(i):return i.get("rom_item_id") == 67),"Elen carries Heal in staff inventory")
	# Native units/items on a clear strip, without unrelated event blockers.
	var data := {"id":"fe6_dynamic_staff_test","dynamic_rom":true,"terrain":["........"],"units":[healer.duplicate(true),lead_unit.duplicate(true)],"rules":b.rules.duplicate(true)}
	data.units[0].x = 0; data.units[0].y = 0; data.units[0].acted = false
	data.units[1].x = 4; data.units[1].y = 0; data.units[1].hp = 5
	b = Battle.new(); b.load_chapter(data)
	healer = b.get_unit("fe6_unit_17"); lead_unit = b.get_unit("fe6_unit_1")
	var options := b.assist_options(healer.id,lead_unit.id)
	check(not options.is_empty(),"Clicking wounded ally offers Heal and an approach")
	if not options.is_empty():
		var index := int(options[0].index)
		var uses := int(healer.inventory[index].uses)
		check(b.preview_move(healer.id,options[0].approach.cell),"Move to healing range")
		check(not b.staff_options(healer.id).is_empty() and b.helpful_targets(healer.id,index).has(lead_unit.id),"Staff menu remains available after moving")
		var result := b.use_item(healer.id,index,lead_unit.id)
		check(result.get("ok",false) and lead_unit.hp > 5 and healer.acted and healer.inventory[index].uses == uses-1,"Healing restores HP, consumes action and one charge")
		check(healer.exp > 0,"Healing grants experience")
	# Reconstruct the old equipped-staff layout and verify suspend migration.
	var legacy := Battle.new(); legacy.load_chapter(data)
	var old := legacy.get_unit("fe6_unit_17")
	old.weapon = old.inventory.pop_front(); old.weapon.uses = 12
	var saved: Dictionary = JSON.parse_string(JSON.stringify(legacy.serialize()))
	var restored := Battle.new()
	check(restored.restore(saved),"Old dynamic staff save restores")
	old = restored.get_unit("fe6_unit_17")
	check(old.weapon.is_empty() and old.inventory.any(func(i):return i.get("rom_item_id") == 67 and i.uses == 12) and not restored.assist_options(old.id,"fe6_unit_1").is_empty(),"Legacy staff moves to inventory with charges intact")
	await speed_checks(pack,lead_unit)
	await ui_checks(data)
	check(FileAccess.get_sha256(source) == digest,"Original ROM untouched")
	check(Assets.decoder.error.is_empty(),"Campaign decoder healthy")
	print("Dynamic FE6 libraries/staff/speed: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func speed_checks(pack: Dictionary, lead_unit: Dictionary) -> void:
	var scene := ClockScene.new(); root.add_child(scene); scene.configure(pack.battle_animation_manifest)
	var profile := scene.profile_for(lead_unit)
	scene.profiles[lead_unit.id] = profile
	var times: Array = []
	for scale in [1.0,3.0]:
		scene.animation_time_scale = scale
		var start := Time.get_ticks_msec()
		check(await scene._attack_sequence(lead_unit.id,"attack",{"defender_id":"enemy"},false,scene.generation),"Native attack timeline completes")
		times.append(Time.get_ticks_msec()-start)
	print("Native lead-unit attack poses: x1 ",times[0]," ms, x3 ",times[1]," ms")
	check(times[0] > 500 and times[1] < times[0]*0.5 and times[1] > times[0]*0.2,"Native animation poses respect x3 with frame overshoot carried forward")
	check(scene.impacts == 2,"Both playback speeds dispatch exactly one impact")
	times.clear()
	for scale in [1.0,3.0]:
		scene.animation_time_scale = scale
		var clock := {"remaining":0.0,"previous":Time.get_ticks_usec()}
		var start := Time.get_ticks_msec()
		for i in range(60): await scene._wait_frame(1.0/60.0,scene.generation,clock)
		times.append(Time.get_ticks_msec()-start)
	print("60 single-tick frames: x1 ",times[0]," ms, x3 ",times[1]," ms")
	check(times[0] >= 950 and times[0] < 1250 and times[1] >= 300 and times[1] < 500,"Single-tick sequences retain native duration at x1 and x3")
	check(not await scene._wait_frame(0.1,scene.generation-1,{"remaining":0.0,"previous":Time.get_ticks_usec()}),"Canceled animation stops promptly")
	scene.queue_free()

func ui_checks(data: Dictionary) -> void:
	var ui = load("res://ui/main.tscn").instantiate()
	ui.animations_enabled = false; ui.auto_turn_enabled = false
	root.add_child(ui)
	await process_frame
	ui._cancel_scene_presentation()
	ui.battle = Battle.new(); ui.battle.load_chapter(data)
	ui.chapter = ui.battle.chapter; ui.board.battle = ui.battle
	ui.dialogue_overlay.hide(); ui.dialogue_lines.clear(); ui.board.clear_story()
	ui.initial_phase_pending = false; ui.busy = false; ui.dialogue_transition = false
	if ui.title_screen: ui.title_screen.hide()
	ui._select_unit(ui.battle.get_unit("fe6_unit_17"))
	ui._on_cell_pressed(Vector2i(4,0))
	await process_frame
	check(ui.pending_assist.get("target") == "fe6_unit_1" and ui.assist_choices.visible,"Actual ally-click UI offers staff assist")
	ui._deselect()
	ui._select_unit(ui.battle.get_unit("fe6_unit_17"))
	ui._on_cell_pressed(Vector2i(3,0))
	await process_frame
	check(ui.staff_button.visible,"Actual post-move Actions menu exposes Staff")
	ui._open_staff()
	check(ui.choice_mode == "staff" and ui.choice_ids.has("fe6_unit_1"),"Staff menu lists wounded ally")
	ui._cancel_choice()
	ui.battle_speed = 3.0; ui._apply_speed_preferences()
	check(ui.cutscene.animation_time_scale == 3.0,"UI speed preference reaches dynamic cutscene")
	for kind in ["portraits","backgrounds","maps"]:
		ui._configure_art_library(kind)
		check(not ui.backdrop_view.entries.is_empty() and ui.backdrop_view.picture.texture != null,"Main UI routes dynamic "+kind+" library")
	ui._cancel_scene_presentation(); ui.queue_free()
	await process_frame
