extends Control
const Assets = preload("res://runtime/rom_assets.gd")
const Header = preload("res://runtime/rom_header.gd")
const SETTINGS := "user://rom_source.cfg"
var message: Label
var choose: Button
var dialog: FileDialog
var worker: Thread
var loading := false
var cards: HBoxContainer
var games: Array = []
var info_button: Button
var info_panel: ColorRect
var remove_panel: ColorRect
var remove_label: Label
var pending_removal: Dictionary = {}

func _ready() -> void:
	get_tree().quit_on_go_back = false
	theme = preload("res://ui/app_theme.gd").create()
	Assets.diagnostic_sink = get_node("/root/Diagnostics").sink.write
	get_node("/root/Diagnostics").record("library_start")
	var background := ColorRect.new()
	background.color=Color("101c30")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var artwork := TextureRect.new()
	artwork.texture = preload("res://art/branding/start.png")
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(artwork)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.32)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x=560
	column.add_theme_constant_override("separation",24)
	center.add_child(column)
	var title := TextureRect.new()
	title.texture = preload("res://art/branding/fever-title.png")
	title.custom_minimum_size.y = 220
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	message=Label.new()
	message.text="Insert a cartridge to begin."
	message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var scroll := preload("res://ui/swipe_scroll.gd").new()
	scroll.custom_minimum_size = Vector2(560, 270)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 20)
	scroll.add_child(cards)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS) == OK:
		games = settings.get_value("library", "games", [])
	if games.is_empty():
			var old_path := str(settings.get_value("rom", "path", ""))
			if not old_path.is_empty(): games.append({"name": "FE7", "path": old_path, "image": ""})
	if games.is_empty():
		cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.alignment = BoxContainer.ALIGNMENT_CENTER
	var resize_library := func():
		var width := minf(maxf(320, size.x - 64), 940 if games.size() >= 2 else 560)
		column.custom_minimum_size.x = width
		scroll.custom_minimum_size.x = width
	resized.connect(resize_library)
	resize_library.call()
	_build_info_panel()
	_build_remove_panel()
	var names_changed := false
	for game in games:
		var name_from_rom := _card_name(game)
		if game.get("name", "") != name_from_rom:
			game.name = name_from_rom
			names_changed = true
		get_node("/root/Diagnostics").record("library_card_begin", {"game_id":game.get("id", "unknown")})
		_game_card(game)
		get_node("/root/Diagnostics").record("library_card_ready", {"game_id":game.get("id", "unknown")})
	if names_changed:
		settings.set_value("library", "games", games)
		settings.save(SETTINGS)
	choose = Button.new()
	choose.text = "+\n\nInsert Cartridge"
	choose.add_theme_font_size_override("font_size", 28)
	choose.custom_minimum_size = Vector2(260, 245)
	cards.add_child(choose)
	dialog=FileDialog.new()
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.gba ; Game Boy Advance ROM"])
	dialog.use_native_dialog=true
	add_child(dialog)
	choose.pressed.connect(func(): dialog.popup_centered_ratio(0.8))
	dialog.file_selected.connect(_load_rom)
	get_node("/root/Diagnostics").record("library_ready", {"games":games.size()})
	get_node("/root/Diagnostics").record_memory("library_ready")

func _build_info_panel() -> void:
	info_button = Button.new()
	info_button.text = "ⓘ"
	info_button.tooltip_text = "Settings and information"
	info_button.add_theme_font_size_override("font_size", 30)
	info_button.custom_minimum_size = Vector2(52, 52)
	add_child(info_button)
	info_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info_button.offset_left = -76; info_button.offset_right = -24
	info_button.offset_top = -76; info_button.offset_bottom = -24
	info_panel = ColorRect.new()
	info_panel.color = Color(0, 0, 0, 0.55)
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(info_panel)
	info_panel.hide()
	info_panel.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed):
			info_panel.hide(); info_panel.accept_event())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	info_panel.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -190; panel.offset_right = 190
	panel.offset_top = -170; panel.offset_bottom = 170
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var version := Label.new()
	version.text = str(ProjectSettings.get_setting("application/config/name")) + " · v" + str(ProjectSettings.get_setting("application/config/version"))
	version.add_theme_font_size_override("font_size", 22)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(version)
	var diagnostics := Button.new()
	diagnostics.text = "Export diagnostics"
	diagnostics.add_theme_font_size_override("font_size", 20)
	diagnostics.custom_minimum_size.y = 52
	diagnostics.pressed.connect(func(): get_node("/root/Diagnostics").show_export(self))
	column.add_child(diagnostics)
	var saves := Button.new()
	saves.text = "Export Saves"
	saves.add_theme_font_size_override("font_size", 20)
	saves.custom_minimum_size.y = 52
	saves.pressed.connect(func(): preload("res://runtime/save_archive.gd").show_export(self))
	column.add_child(saves)
	var notices := Button.new()
	notices.text = "Third-party notices"
	notices.add_theme_font_size_override("font_size", 20)
	notices.custom_minimum_size.y = 52
	notices.pressed.connect(func(): preload("res://ui/third_party_notices.gd").show_notices(self))
	column.add_child(notices)
	var power := Button.new()
	power.text = "Power Off"
	power.add_theme_font_size_override("font_size", 20)
	power.custom_minimum_size.y = 52
	power.pressed.connect(func(): get_tree().quit())
	column.add_child(power)
	info_button.pressed.connect(_show_extra_menu)

func _game_card(game: Dictionary) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(300, 245)
	cards.add_child(card)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 10
	content.offset_bottom = -44
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(280, 187)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = preload("res://runtime/rom_card_art.gd").texture(game)
	content.add_child(picture)
	var footer := HBoxContainer.new()
	card.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 10; footer.offset_right = -4
	footer.offset_top = -36; footer.offset_bottom = -4
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = _card_name(game)
	name_label.tooltip_text = name_label.text
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(name_label)
	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "Clear cartridge"
	remove.custom_minimum_size = Vector2(32,32)
	footer.add_child(remove)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style: StyleBox = remove.get_theme_stylebox(state).duplicate()
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,4)
		remove.add_theme_stylebox_override(state,style)
	remove.pressed.connect(func(): _confirm_remove(game))
	card.pressed.connect(func(): _load_rom(str(game.path)))

static func _card_name(game: Dictionary) -> String:
	var header := Header.from_file(str(game.get("path", "")))
	if not str(header.get("title", "")).is_empty() or not str(header.get("code", "")).is_empty():
		return Header.display_name(header)
	var label := str(game.get("name", "Cartridge"))
	# A temporarily unavailable cartridge keeps its last readable library title.
	label = label.trim_suffix(" · FE6 compatibility").trim_suffix(" · FE7 compatibility")
	return label if not label.is_empty() else "Cartridge"

func _build_remove_panel() -> void:
	remove_panel = ColorRect.new()
	remove_panel.color = Color(0,0,0,0.55)
	remove_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(remove_panel)
	remove_panel.hide()
	remove_panel.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed):
			remove_panel.hide(); remove_panel.accept_event())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remove_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",preload("res://ui/panel_style.gd").create())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	remove_label = Label.new()
	remove_label.custom_minimum_size.x = 260
	remove_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(remove_label)
	for caption in ["Clear cartridge", "Cancel"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size.y = 48
		column.add_child(button)
		if caption == "Cancel": button.pressed.connect(func(): remove_panel.hide())
		else: button.pressed.connect(_remove_game)

func _confirm_remove(game: Dictionary) -> void:
	if loading: return
	pending_removal = game.duplicate()
	remove_label.text = "Clear %s from the cartridge browser?\n\nYour saves and ROM file will be kept." % _card_name(game)
	move_child(remove_panel,get_child_count()-1)
	remove_panel.show()

func _remove_game() -> void:
	if loading or pending_removal.is_empty(): return
	var remaining := games.filter(func(game): return game.get("path", "") != pending_removal.get("path", ""))
	var settings := ConfigFile.new()
	settings.load(SETTINGS)
	settings.set_value("library","games",remaining)
	if settings.get_value("rom","path","") == pending_removal.get("path",""):
		settings.erase_section_key("rom","path")
	if settings.save(SETTINGS) != OK:
		message.text = "Could not clear the cartridge. Please try again."
		return
	games = remaining
	pending_removal.clear()
	remove_panel.hide()
	for child in cards.get_children():
		if child != choose: cards.remove_child(child); child.queue_free()
	for game in games: _game_card(game)
	cards.move_child(choose,cards.get_child_count()-1)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL if games.is_empty() else Control.SIZE_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER if games.is_empty() else BoxContainer.ALIGNMENT_BEGIN
	resized.emit()

func _load_rom(path: String) -> void:
	if loading: return
	Assets.diagnostic_sink = get_node("/root/Diagnostics").sink.write
	get_node("/root/Diagnostics").record("rom_load", {"private_copy": path.begins_with("user://")})
	loading=true
	choose.disabled=true
	message.text="Checking ROM…"
	Assets.progress="Checking ROM…"
	worker=Thread.new()
	var start_error := worker.start(func(): return Assets.load_rom(path))
	if start_error != OK:
		loading = false
		choose.disabled = false
		message.text = "Could not start loading the cartridge. Please try again."
		get_node("/root/Diagnostics").record("rom_load_worker_failed", {"code": start_error})

func _process(_delta: float) -> void:
	if not loading: return
	message.text=Assets.progress
	if worker.is_alive(): return
	var failure: String = worker.wait_to_finish()
	loading=false
	choose.disabled=false
	if not failure.is_empty():
		get_node("/root/Diagnostics").record("rom_load_failed", {"reason": failure})
		message.text=failure
		return
	Assets.install_loader()
	var settings := ConfigFile.new()
	settings.load(SETTINGS)
	settings.set_value("rom","path",Assets.source_path)
	DirAccess.make_dir_recursive_absolute("user://game-library")
	get_node("/root/Diagnostics").record("rom_ready")
	var game := {"id":Assets.game_id+"-"+Assets.rom_digest,"name":Assets.display_name,"path":Assets.source_path,"dynamic_rom":true,"rom_sha256":Assets.rom_digest}
	games = games.filter(func(entry): return entry.get("id", "") != game.id and entry.get("path", "") != game.path)
	games.append(game)
	settings.set_value("library", "games", games)
	settings.save(SETTINGS)
	get_tree().change_scene_to_file("res://ui/main.tscn")

func _exit_tree() -> void:
	if worker and worker.is_started(): worker.wait_to_finish()

func _show_extra_menu() -> void:
	move_child(info_panel, get_child_count() - 1)
	info_panel.show()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(info_panel):
		if is_instance_valid(remove_panel) and remove_panel.visible: remove_panel.hide()
		elif info_panel.visible: info_panel.hide()
		else: _show_extra_menu()
