extends Control
## Custom title backdrop with the original ROM prompt and copyright overlays.
const Art = preload("res://runtime/art_textures.gd")
const Backdrops = preload("res://runtime/custom_backdrops.gd")
signal start_requested
signal continue_requested
signal back_requested
var back_button: Button

var manifest: Dictionary = {}
var picture: TextureRect
var art_frame: Control
var prompt_layer: TextureRect
var copyright_layer: TextureRect
var choice_panel: PanelContainer
var start_button: Button
var continue_button: Button
var can_continue := false
var pointer_id := -1
var pointer_start := Vector2.ZERO
var gesture_canceled := false
var requested := false
var game_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	art_frame = Control.new()
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art_frame)
	picture = _art_layer()
	prompt_layer = _art_layer()
	copyright_layer = _art_layer()
	resized.connect(_layout_art)
	_layout_art()
	choice_panel = PanelContainer.new()
	choice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	choice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	choice_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	choice_panel.offset_left = -170
	choice_panel.offset_right = 170
	choice_panel.offset_top = -20
	choice_panel.offset_bottom = 140
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.16, 0.96)
	style.border_color = Color("e7d59c")
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(6)
	choice_panel.add_theme_stylebox_override("panel", style)
	add_child(choice_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	choice_panel.add_child(column)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size.y = 52
	continue_button.pressed.connect(func(): _request(true))
	column.add_child(continue_button)
	start_button = Button.new()
	start_button.text = "New game"
	start_button.custom_minimum_size.y = 52
	start_button.pressed.connect(func(): _request(false))
	column.add_child(start_button)
	choice_panel.hide()
	game_label = Label.new()
	game_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_label.add_theme_font_size_override("font_size", 38)
	game_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	game_label.add_theme_constant_override("shadow_outline_size", 10)
	game_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_label)
	move_child(choice_panel, get_child_count()-1)
	back_button = Button.new()
	back_button.text = "Back"
	add_child(back_button)
	back_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	back_button.offset_left = -114; back_button.offset_right = -18
	back_button.offset_top = -64; back_button.offset_bottom = -18
	back_button.pressed.connect(func(): back_requested.emit())
	hide()

func configure(path: String = "res://content/fe7/title_manifest.json", has_continue: bool = false) -> bool:
	manifest.clear()
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: manifest = parsed
	game_label.text = str(manifest.get("label", "")) + "\n\n" + str(manifest.get("notice", ""))
	game_label.visible = manifest.has("label")
	can_continue = has_continue
	continue_button.visible = can_continue or manifest.get("game_id", "fe7") == "fe6"
	continue_button.disabled = not can_continue
	choice_panel.hide()
	pointer_id = -1
	requested = false
	refresh_art()
	return picture.texture != null

func refresh_art() -> void:
	if not is_instance_valid(picture): return
	var art_store = Backdrops.for_game(str(manifest.get("game_id", "fe7")))
	if not art_store.loaded: art_store.reload()
	var custom: Texture2D = null
	if art_store.enabled and not manifest.is_empty():
		custom = Backdrops.texture("title_" + str(manifest.get("game_id", "fe7")))
	picture.texture = custom if custom != null else Art.texture(str(manifest.get("image", "")))
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if manifest.get("game_id", "fe7") == "fe6" else TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if custom != null else CanvasItem.TEXTURE_FILTER_NEAREST
	prompt_layer.texture = _original_layer(str(manifest.get("prompt", ""))) if custom != null else null
	copyright_layer.texture = null
	if custom != null:
		for entry in manifest.get("entries", []):
			if entry.get("id", "") == "title_copyright": copyright_layer.texture = _original_layer(str(entry.path))

func _original_layer(path: String) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path): return load(path)
	return null

func _art_layer() -> TextureRect:
	var layer := TextureRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(layer)
	return layer

func _layout_art() -> void:
	var scale_factor := minf(size.x / 240.0, size.y / 160.0)
	art_frame.size = Vector2(240, 160) * scale_factor
	art_frame.position = (size - art_frame.size) * 0.5

func activate() -> void:
	if requested: return
	if can_continue or manifest.get("game_id", "fe7") == "fe6":
		game_label.hide()
		choice_panel.show()
		if can_continue: continue_button.grab_focus()
		else: start_button.grab_focus()
	else:
		_request(false)

func _request(resume: bool) -> void:
	if requested or (resume and not can_continue): return
	requested = true
	if resume: continue_requested.emit()
	else: start_requested.emit()

func _gui_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch:
		if event.pressed and pointer_id == -1:
			pointer_id = event.index
			pointer_start = event.position
			gesture_canceled = false
		elif not event.pressed and pointer_id == event.index:
			pointer_id = -1
			if not event.canceled and not gesture_canceled: activate()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == pointer_id and event.position.distance_to(pointer_start) > 20: gesture_canceled = true
		accept_event()
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pointer_id = -2
			pointer_start = event.position
			gesture_canceled = false
		elif pointer_id == -2:
			pointer_id = -1
			if not gesture_canceled: activate()
		accept_event()
	elif event is InputEventMouseMotion and pointer_id == -2:
		if event.position.distance_to(pointer_start) > 20: gesture_canceled = true
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		activate()
		get_viewport().set_input_as_handled()
