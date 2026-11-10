extends VBoxContainer
const Dialogue = preload("res://ui/dialogue_view.gd")
const Conversations = preload("res://runtime/support_conversations.gd")
var characters
var scenes: ItemList
var viewer: Control
var dialogue_layer: CanvasLayer
var screen_shade: ColorRect
var next_button: Button
var pairs: Array = []
var pages: Array = []
var index := 0
func _ready() -> void:
	characters = preload("res://ui/portrait_entry_dropdown.gd").new()
	characters.custom_minimum_size.y = 46
	characters.item_selected.connect(func(_i): _filter())
	add_child(characters)
	scenes = preload("res://ui/swipe_item_list.gd").new()
	scenes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scenes.add_theme_font_size_override("font_size", 22)
	scenes.item_activated.connect(_play)
	add_child(scenes)
	dialogue_layer = CanvasLayer.new()
	dialogue_layer.layer = 20
	add_child(dialogue_layer)
	screen_shade = ColorRect.new()
	screen_shade.color = Color(0.01, 0.02, 0.04, 0.72)
	screen_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_layer.add_child(screen_shade)
	screen_shade.hide()
	viewer = Dialogue.new()
	dialogue_layer.add_child(viewer)
	viewer.visibility_changed.connect(func(): screen_shade.visible = viewer.visible)
	viewer.hide()
	visibility_changed.connect(func():
		if not is_visible_in_tree(): viewer.hide())
	next_button = Button.new()
	next_button.text = "Play support conversation"
	next_button.custom_minimum_size.y = 48
	next_button.pressed.connect(func():
		if viewer.visible: _next()
		elif not scenes.get_selected_items().is_empty(): _play(scenes.get_selected_items()[0]))
	add_child(next_button)
func configure(manifest: Dictionary) -> void:
	if not pairs.is_empty(): return
	pairs = manifest.get("pairs", [])
	for character in manifest.get("characters", []):
		characters.add_item(str(character.name))
		characters.set_item_metadata(characters.item_count - 1, str(character.id))
	if characters.item_count > 0: characters.select(0)
	_filter()
func _filter() -> void:
	viewer.hide(); scenes.show(); next_button.text = "Play support conversation"
	scenes.clear()
	if characters.selected < 0: return
	var id := str(characters.get_item_metadata(characters.selected))
	for pair in pairs:
		if id not in [str(pair.a), str(pair.b)]: continue
		for rank in ["1", "2", "3"]:
			if not Conversations.available(pair,rank): continue
			scenes.add_item("%s & %s · Rank %s" % [pair.get("a_name", pair.a), pair.get("b_name", pair.b), ["C","B","A"][int(rank)-1]])
			scenes.set_item_metadata(scenes.item_count - 1, {"pair":pair,"rank":rank})
	if scenes.item_count > 0: scenes.select(0)
func _play(selected: int) -> void:
	var request: Dictionary = scenes.get_item_metadata(selected)
	pages = Conversations.pages(request.pair,request.rank)
	if pages.is_empty(): return
	index = 0
	viewer.reset(); viewer.prepare(pages); viewer.show()
	viewer.present(pages[0], pages.slice(1))
func _next() -> void:
	if viewer.is_typing(): viewer.reveal(); return
	index += 1
	if index >= pages.size(): _filter(); return
	viewer.present(pages[index], pages.slice(index + 1))

func _input(event: InputEvent) -> void:
	if not viewer or not viewer.visible or not is_visible_in_tree(): return
	# Touch already advances directly; ignore its emulated mouse event.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed) or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_next()
