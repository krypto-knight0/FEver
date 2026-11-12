extends "fe7_test_base.gd"

class EndingMain extends "res://ui/main.gd":
	var captured_dialogue: Array = []
	var saved_campaign := {}
	var returned := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _input(_event: InputEvent) -> void: pass
	func _notification(_what: int) -> void: pass
	func _save_game(_background: bool = false) -> void: saved_campaign = campaign.duplicate(true)
	func _show_dialogue(lines: Array) -> void: captured_dialogue = lines
	func _open_title() -> void: returned = true

func make_main(b):
	var view = EndingMain.new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.theme = preload("res://ui/app_theme.gd").create()
	view.battle = b; view.chapter = b.chapter; view.pack = {"id":"fe7"}
	for key in ["chapter_cover","dialogue_overlay","info_overlay","settings_overlay"]:
		view.set(key,ColorRect.new()); view.add_child(view.get(key))
	for key in ["actions_panel","forecast_panel","stats_panel"]:
		view.set(key,PanelContainer.new()); view.add_child(view.get(key))
	for key in ["skip_button","info_button"]:
		view.set(key,Button.new()); view.add_child(view.get(key))
	view.status_label = Label.new(); view.add_child(view.status_label)
	view.board = Control.new(); view.add_child(view.board)
	view.scene_transition = preload("res://ui/scene_transition.gd").new(); view.add_child(view.scene_transition)
	view.audio_manager = preload("res://audio/audio_manager.gd").new(); view.add_child(view.audio_manager)
	return view

func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("English FE7 or Flux Echo 7 ROM path required"); quit(2); return
	var source := args[0]
	var rom := FileAccess.get_file_as_bytes(source)
	var d = Profile.decoder(rom)
	check(d.error.is_empty() and d.layout.get("event_variant") == "fe7u","English FE7 ending ABI")
	if failures: quit(1); return
	var content = preload("res://runtime/fe7/fe7_dynamic_content.gd").new()
	content.rom = rom; content.digest = FileAccess.get_sha256(source); content.prefix = "res://content/fe7/dynamic/"+content.digest+"/"
	var definitions = preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); definitions.d = d; definitions.prefix = content.prefix
	var resources := {}
	content.manifest = {"chapters":[]}
	for route in [2,3]:
		if not content.compile_chapter(d,definitions,resources,47,route): print(content.error); quit(1); return
		content.manifest.chapters.append({"path":content.chapter_path(47,route)})
	DirAccess.make_dir_recursive_absolute("user://ending_ui_probe")
	content.package.directory = "user://ending_ui_probe"; content.package.digest = content.digest
	if not content.package.mount(resources): print(content.package.error); quit(1); return
	content.assets.merge(definitions.assets,true); content.items = definitions.items
	Assets.dynamic_content = content; Assets.decoder = d; Assets.rom_digest = content.digest; Assets.game_id = "fe7"
	Assets.assets = content.assets.duplicate(true); Assets.install_loader()
	for route in [2,3]:
		var b := port_battle(47,route)
		b.chapter.fe7_rank_records = {"46":{"turns":12,"experience":500,"battles":40,"wins":20},"47":{"turns":5,"experience":100,"battles":10,"wins":4}}
		b.chapter.fe7_rank_assets = 50000
		var view = make_main(b)
		view._show_epilogue()
		check(view.campaign.fe7_ending_stage == 1 and not view.captured_dialogue.is_empty(),"Farewell saves next stage with its dialogue")
		check(not is_instance_valid(view.epilogue_view),"Farewell does not overlay the credits")
		view._show_epilogue()
		check(view.epilogue_view.get_script() == preload("res://ui/credits_view.gd"),"Farewell advances to native credits")
		view.epilogue_view.paused = true
		view.epilogue_view.position_in_roll = 500
		view.epilogue_view.advanced.emit(500.0)
		view._save_game()
		var snapshot: Dictionary = view.saved_campaign.duplicate(true)
		check(snapshot.fe7_credits_position == 500.0,"Credits cursor is included in campaign saves")
		await capture("user://credits-ui.png")
		view.epilogue_view.finished.emit()
		check(view.campaign.fe7_ending_stage == 2 and view.epilogue_view.pages[0].title == "Campaign record","Skipping credits shows chapter results")
		await capture("user://records-ui.png")
		view.epilogue_view.finished.emit()
		check(view.campaign.fe7_ending_stage == 3 and not view.epilogue_view.completion_page,"Character endings do not prematurely display The End")
		var ranking_index := -1
		for index in range(view.epilogue_view.pages.size()):
			if view.epilogue_view.pages[index].has("ranking"): ranking_index = index
		check(ranking_index >= 0,"Ranking card is reachable in the ending viewer")
		if ranking_index >= 0:
			view.epilogue_view.navigate(ranking_index)
			await capture("user://ranking-ui.png")
		view.epilogue_view.navigate(view.epilogue_view.pages.size())
		check(view.campaign.fe7_ending_stage == 5 and not is_instance_valid(view.epilogue_view),"Last character page advances directly to teaser dialogue")
		check(not view.captured_dialogue.is_empty() and not view.returned,"Teaser precedes return to title")
		view._show_epilogue()
		check(view.epilogue_view.completion_page and view.epilogue_view.pages.is_empty(),"The End appears after teaser completion")
		view.epilogue_view.finished.emit()
		check(view.campaign.completed and view.returned,"Finishing the ending saves completion and returns to title")
		view.queue_free(); await process_frame
		view = make_main(b); view.campaign = snapshot
		view._show_epilogue()
		check(is_equal_approx(view.epilogue_view.position_in_roll,500.0),"Resuming the staff roll restores its cursor")
		view.queue_free(); await process_frame
	check(FileAccess.get_sha256(source) == content.digest,"Source cartridge untouched")
	check(d.error.is_empty(),"Ending decoder remains healthy")
	print("ENDING UI CHECKS ",checks," failures ",failures)
	quit(1 if failures else 0)
