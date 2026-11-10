extends SceneTree
const Assets = preload("res://runtime/rom_assets.gd")
const Battle = preload("res://engine/battle_state.gd")
const Flags = preload("res://engine/native_event_flags.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)
func read(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func fresh(index: int) -> RefCounted:
	var path: String = Assets.dynamic_content.destinations[index]
	check(Assets.ensure_resource(path),"Chapter available "+str(index))
	var b := Battle.new(); b.load_chapter(read(path)); b._run_events("chapter_start")
	return b
func run() -> void:
	var source := OS.get_cmdline_user_args()[0]
	var hash_before := FileAccess.get_sha256(source)
	var bytes := FileAccess.get_file_as_bytes(source); bytes[0xbf] ^= 1
	var file := FileAccess.open("user://interactions.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	var error := Assets.load_rom("user://interactions.gba",false)
	check(error.is_empty(),"Import: "+error)
	if not error.is_empty(): quit(1); return
	Assets.install_loader()
	var b := fresh(3)
	check(b.get_unit("fe6_unit_76").is_empty(),"Chapter 3 boss waits for native turn event")
	var initial_count: int = b.units.size()
	b.turn = 3; b.phase = "enemy"; b._run_events("turn")
	var boss: Dictionary = b.get_unit("fe6_unit_76")
	check(not boss.is_empty() and boss.x == 19 and boss.y == 4 and b.visible_to_player(boss),"Chapter 3 boss appears on revealed throne at enemy turn 3")
	check(b.units.size() == initial_count+5,"Chapter 3 native room guards and cavalry arrive")
	var before: int = b.units.size(); b._run_events("turn")
	check(b.units.size() == before and b.native_event_errors.is_empty(),"Chapter 3 arrival is one-time and error-free")
	for index in [6,22]: roof_checks(index)
	await ui_checks()
	await cartridge_checks(source)
	scripted_door_checks()
	check(FileAccess.get_sha256(source) == hash_before,"Original cartridge unchanged")
	print("Dynamic FE6 interactions: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func open_door(b: RefCounted, site: Dictionary) -> Dictionary:
	var lead_unit: Dictionary = b.get_unit("fe6_unit_1")
	lead_unit.x = site.x; lead_unit.y = int(site.y)+1; lead_unit.acted = false; lead_unit.moved = false
	b.phase = "player"; b.rules.door_unlock_mode = "free"
	return b.interact(lead_unit.id,b.interactions.find(site))

func roof_checks(index: int) -> void:
	var b := fresh(index)
	var hidden: Array = b.units.filter(func(u):return b._under_roof(u))
	check(not hidden.is_empty(),"Native room occupants retained chapter "+str(index))
	for unit in hidden:
		check(not b.visible_to_player(unit),"Roof hides "+unit.id)
		b.phase = "enemy"
		check(not b._can_act(unit),"Roof prevents early enemy action "+unit.id)
	if index == 22:
		b.phase = "player"
		for cell in [[1,0],[30,0],[15,20]]:
			var lead_unit: Dictionary = b.get_unit("fe6_unit_1"); lead_unit.x = cell[0]; lead_unit.y = cell[1]
			b._run_events("position",{"unit_id":lead_unit.id,"x":lead_unit.x,"y":lead_unit.y})
		check(hidden.any(func(u):return b.visible_to_player(u)),"Throne switches reveal dormant defenders")
	else:
		var revealed := 0
		for site in b.interactions:
			if site.type != "door" or site.get("used",false): continue
			var old_positions := hidden.map(func(u):return b.position(u))
			check(open_door(b,site).get("ok",false),"Door opens chapter %d at %d,%d" % [index,site.x,site.y])
			for i in range(hidden.size()):
				check(b.position(hidden[i]) == old_positions[i],"Door preserves occupant position")
				if not b._under_roof(hidden[i]): revealed += 1
		check(revealed > 0,"Doors reveal existing enemies chapter "+str(index))
	# A scripted LOAD into a still-roofed cell must also stay put.
	b = fresh(index); hidden = b.units.filter(func(u):return b._under_roof(u))
	if not hidden.is_empty():
		var original: Dictionary = hidden[0]
		var replacement := original.duplicate(true); replacement.id = "room_arrival"
		b.units.erase(original); b._spawn_unit(replacement)
		check(b.position(b.get_unit("room_arrival")) == Vector2i(replacement.x,replacement.y) and not b.visible_to_player(b.get_unit("room_arrival")),"Native LOAD stays concealed in its room")
	check(b.native_event_errors.is_empty(),"Room scripts complete chapter "+str(index))

func ui_checks() -> void:
	var ui = load("res://ui/main.tscn").instantiate()
	ui.animations_enabled = false; ui.auto_turn_enabled = false
	root.add_child(ui); await process_frame
	ui._cancel_scene_presentation(); ui.dialogue_overlay.hide(); ui.dialogue_lines.clear(); ui.board.clear_story()
	ui.initial_phase_pending = false; ui.busy = false; ui.dialogue_transition = false
	if ui.title_screen: ui.title_screen.hide()
	ui.battle = fresh(4); ui.chapter = ui.battle.chapter; ui.board.battle = ui.battle
	ui._update_terrain(Vector2i(1,1)); ui._on_cell_hovered(Vector2i(2,2))
	check(ui.terrain_cell == Vector2i(1,1),"Mouse hover preserves selected terrain")
	ui._on_cell_pressed(Vector2i(2,2))
	check(ui.terrain_cell == Vector2i(2,2),"Click/touch selects terrain")
	var recruitment: String = ui._recruitment_text()
	var talk: Dictionary = ui.chapter.talks.filter(func(t):return t.to == "fe6_unit_23")[0]
	check(preload("res://engine/native_event_runner.gd").recruitment_ids(talk).has("fe6_unit_23") and recruitment.contains("RECRUITMENT") and recruitment.contains(str(ui.battle.get_unit("fe6_unit_1").name)),"Info lists native recruitment target and recruiter")
	ui.battle = fresh(3); ui.chapter = ui.battle.chapter; ui.board.battle = ui.battle
	var objective: Dictionary = ui.chapter.objective
	var terrain_name: String = ui.battle.rules.terrain.T.name
	check(objective.terrain_name == terrain_name,"Covered objective names the throne rather than its roof")
	check(ui._objective_text().contains(terrain_name) and not ui._objective_text().contains("marked location"),"Info uses the live seize tile name, including Japanese")
	check(ui._objective_text() == "Seize the %s with %s." % [terrain_name,ui.battle.get_unit("fe6_unit_1").name],"Seize objective omits coordinates and Interact instruction")
	ui.battle = fresh(23); ui.chapter = ui.battle.chapter
	var visit: Dictionary = ui.chapter.events.filter(func(e):return e.get("trigger") == "visit" and not preload("res://engine/native_event_runner.gd").recruitment_ids(e).is_empty())[0]
	var visitors: Dictionary = preload("res://engine/native_event_runner.gd").recruitment_visitors(visit)
	check(visitors.get("fe6_unit_21",[]).size() == 2 and visitors["fe6_unit_21"].has("fe6_unit_22") and visitors["fe6_unit_21"].has("fe6_unit_35"),"Unit 21 recruitment house lists eligible visitors 22 and 35")
	ui._cancel_scene_presentation(); ui.queue_free(); await process_frame

func cartridge_checks(source: String) -> void:
	var start = load("res://runtime/rom_start.tscn").instantiate()
	root.add_child(start); await process_frame
	var game := {"id":"fixture","name":"Test cartridge - A very long translated cartridge title · native compatibility","path":source,"dynamic_rom":true,"rom_sha256":FileAccess.get_sha256(source)}
	start.games = [game]; start._game_card(game)
	await process_frame; await process_frame
	var card: Button = start.cards.get_child(start.cards.get_child_count()-1)
	var content: VBoxContainer = card.get_child(0)
	var picture: TextureRect = content.get_child(0)
	var footer: HBoxContainer = card.get_child(1)
	var title: Label = footer.get_child(0)
	var remove: Button = footer.get_child(1)
	check(is_equal_approx(picture.global_position.y-card.global_position.y,picture.global_position.x-card.global_position.x),"Card artwork top margin matches side margin")
	check(is_equal_approx(title.get_global_rect().get_center().y,remove.get_global_rect().get_center().y),"Card title shares the clear button row")
	check(is_equal_approx(picture.global_position.x+picture.size.x/2,card.global_position.x+card.size.x/2),"Dynamic card artwork is horizontally centered")
	check(content.size.x <= card.size.x and card.size.x == 300,"Long cartridge name stays within card")
	check(start._card_name(game) == preload("res://runtime/rom_header.gd").display_name(preload("res://runtime/rom_header.gd").from_file(source)),"Dynamic card uses native title instead of storage filename")
	start._confirm_remove(game)
	check(start.remove_panel.visible and not start.loading,"Clear button opens confirmation without loading ROM")
	var outside := InputEventMouseButton.new(); outside.button_index = MOUSE_BUTTON_LEFT; outside.pressed = false
	start.remove_panel.gui_input.emit(outside)
	check(not start.remove_panel.visible and start.games.size() == 1,"Outside click dismisses without clearing")
	start._confirm_remove(game)
	var settings := ConfigFile.new(); settings.set_value("rom","path",source); settings.set_value("library","games",start.games); settings.save(start.SETTINGS)
	start._remove_game()
	settings = ConfigFile.new(); settings.load(start.SETTINGS)
	check(start.games.is_empty() and settings.get_value("library","games",[]).is_empty() and str(settings.get_value("rom","path","")).is_empty(),"Clear persists and cannot resurrect the legacy card")
	check(FileAccess.file_exists(source) and start.cards.get_child_count() == 1,"Clear keeps the ROM and Insert Cartridge card")
	start.queue_free(); await process_frame

func scripted_door_checks() -> void:
	# Repoint a native location row to a new script with an actual LOAD and
	# reward. Both key and staff paths must dispatch it, once, after the patch.
	var b := fresh(6)
	var d: RefCounted = Assets.decoder
	var bytes: PackedByteArray = d.rom.duplicate()
	var header := preload("res://runtime/rom_deployments.gd").chapter_events(d,"fe6",6)
	var row: int = d.ptr(header+8)
	while d.u16(row) != 0 and d.u16(row) != 8: row += 12
	check(d.u16(row) == 8,"Fixture finds native door row")
	if d.u16(row) != 8: return
	var cell := Vector2i(d.u8(row+8),d.u8(row+9))
	var original: Dictionary = b.units.filter(func(u):return str(u.id).begins_with("fe6_dynamic_enemy_"))[0]
	var at := str(original.source_deployment.offset).hex_to_int()
	var group := bytes.slice(at,at+16)
	group[4] = cell.x; group[5] = cell.y; group[6] = cell.x; group[7] = cell.y
	group.resize(32)
	bytes.resize((bytes.size()+3)&~3)
	var group_at := bytes.size(); bytes.append_array(group)
	var script_at := bytes.size()
	for word in [0x12,0x08000000+group_at,0x28,123,6]:
		var next := bytes.size(); bytes.resize(next+4); bytes.encode_u32(next,word)
	bytes.encode_u16(row,5); bytes.encode_u16(row+2,31); bytes.encode_u32(row+4,0x08000000+script_at); bytes[row+10] = 16
	var file := FileAccess.open("user://scripted-door.gba",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	var error := Assets.load_rom("user://scripted-door.gba",false)
	check(error.is_empty(),"Modified door ROM imports: "+error)
	if not error.is_empty(): return
	for method in ["key","staff","enemy"]:
		b = fresh(6)
		var site: Dictionary = b.interactions.filter(func(s):return s.x == cell.x and s.y == cell.y)[0]
		check(site.get("native_visit_event",false),"Door has a native visit program")
		var unit: Dictionary = b.get_unit("fe6_unit_1")
		unit.x = cell.x; unit.y = cell.y+1; unit.inventory = [Assets.item_catalog[81 if method == "staff" else 101].duplicate(true)]
		unit.can_use_staves = true; unit.weapon_exp.staff = 251; unit.acted = false
		for other in b.units:
			if other.id != unit.id and other.x == unit.x and other.y == unit.y: other.benched = true
		var gold: int = b.gold
		var result: Dictionary
		if method == "staff": result = b.use_item(unit.id,0,unit.id,cell)
		elif method == "enemy":
			unit.faction = "enemy"; b.phase = "enemy"; b.interactions = [site]; result = {"ok":b._loot_treasure(unit)}
		else: result = b.interact(unit.id,b.interactions.find(site))
		check(result.get("ok",false) and site.get("used",false),"Native scripted door opens with "+method)
		check(b.gold == gold+123 and Flags.has_flag(b.native_event_state,31),"Door reward and flag dispatch with "+method)
		check(not b.get_unit("fe6_dynamic_enemy_%x" % group_at).is_empty(),"Door LOAD spawns occupant with "+method)
		var count: int = b.units.size()
		b._run_events("visit",{"unit_id":unit.id,"x":cell.x,"y":cell.y})
		check(b.gold == gold+123 and b.units.size() == count and b.native_event_errors.is_empty(),"Door script is one-use with "+method)
