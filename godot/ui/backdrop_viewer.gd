extends VBoxContainer
## A read-only gallery of dialogue backgrounds and title artwork from the pack.
const Art = preload("res://runtime/art_textures.gd")
var entries: Array = []
var current_index := 0
var selector: Button
var picture: TextureRect
var caption: Label
var previous_button: Button
var next_button: Button
var fullscreen: ColorRect
var full_picture: TextureRect
var rotated := false
var fullscreen_buttons: HBoxContainer
var swipe_start := Vector2.ZERO
var swipe_pointer := -2
var catalog_overlay: ColorRect
var image_list: ItemList
var search: LineEdit
var filtered: Array = []
var library_kind := "backgrounds"
var use_custom_backgrounds := true

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	previous_button = _button(row, "‹", func(): select_image(current_index - 1))
	previous_button.tooltip_text = "Previous backdrop"
	selector = Button.new()
	selector.custom_minimum_size.y = 48
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.pressed.connect(_open_catalog)
	row.add_child(selector)
	next_button = _button(row, "›", func(): select_image(current_index + 1))
	next_button.tooltip_text = "Next backdrop"
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 17)
	add_child(caption)
	_button(self, "Full screen", _open_fullscreen)
	fullscreen = ColorRect.new()
	fullscreen.color = Color.BLACK
	fullscreen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	fullscreen.top_level = true
	add_child(fullscreen)
	full_picture = TextureRect.new()
	full_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	full_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fullscreen.add_child(full_picture)
	fullscreen_buttons = HBoxContainer.new()
	fullscreen.add_child(fullscreen_buttons)
	var rotate := _button(fullscreen_buttons, "", func(): rotated = not rotated; _layout_fullscreen())
	rotate.icon = _viewer_icon("rotate")
	rotate.tooltip_text = "Rotate image"
	var close := _button(fullscreen_buttons, "", func(): fullscreen.hide())
	close.icon = _viewer_icon("close")
	close.tooltip_text = "Close full screen"
	fullscreen.resized.connect(_layout_fullscreen)
	get_viewport().size_changed.connect(func():
		if fullscreen.visible: fullscreen.size = get_viewport_rect().size)
	fullscreen.gui_input.connect(_fullscreen_input)
	fullscreen.hide()
	catalog_overlay = ColorRect.new()
	catalog_overlay.color = Color("131e39")
	catalog_overlay.top_level = true
	add_child(catalog_overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	catalog_overlay.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	search = LineEdit.new()
	search.placeholder_text = "Search artwork"
	search.custom_minimum_size.y = 48
	search.text_changed.connect(func(_text): _filter_catalog())
	column.add_child(search)
	image_list = preload("res://ui/swipe_item_list.gd").new()
	image_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image_list.add_theme_constant_override("line_separation", 16)
	image_list.item_activated.connect(func(index): select_image(filtered[index]); catalog_overlay.hide())
	column.add_child(image_list)
	_button(column, "View selected", func():
		var selected := image_list.get_selected_items()
		if not selected.is_empty(): select_image(filtered[selected[0]]); catalog_overlay.hide())
	_button(column, "Close", func(): catalog_overlay.hide())
	catalog_overlay.hide()

func _button(row: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(64, 48)
	button.pressed.connect(callback)
	row.add_child(button)
	return button

func configure(manifest: Dictionary, imported: bool = true) -> void:
	library_kind = "backgrounds"
	use_custom_backgrounds = imported
	fullscreen.hide()
	catalog_overlay.hide()
	entries.clear()
	for entry in manifest.get("entries", []):
		if not entry is Dictionary: continue
		var is_backdrop: bool = str(entry.get("kind", "")) in ["dialogue_background", "title_screen", "cg", "cutscene"] or str(entry.get("id", "")).begins_with("cg_") or (not entry.has("kind") and str(entry.get("id", "")).begins_with("background_"))
		if not is_backdrop: continue
		entries.append(entry)
	if imported:
		var store = preload("res://runtime/custom_backdrops.gd").store
		if not store.loaded: store.reload()
		var existing := {}
		for entry in entries: existing[preload("res://runtime/custom_backdrops.gd").identifier(str(entry.get("path", entry.get("id", ""))))] = true
		for entry in store.entries:
			var id := str(entry.get("id", ""))
			if not existing.has(id) and (id.begins_with("battle_") or id.begins_with("title_")):
				entries.append({"id": id, "path": id + ".png", "title": id.replace("_", " ").capitalize(), "kind": "title_screen" if id.begins_with("title_") else "dialogue_background"})
	entries.sort_custom(func(a, b):
		if _art_order(a) != _art_order(b): return _art_order(a) < _art_order(b)
		var first := int(a.get("appearance_order", 100000))
		var second := int(b.get("appearance_order", 100000))
		if first != second: return first < second
		return str(a.get("id", "")) < str(b.get("id", "")))
	select_image(current_index)

func _art_order(entry: Dictionary) -> int:
	if str(entry.get("id", "")).begins_with("cg_") or entry.get("kind", "") in ["cg", "cutscene"]: return 0
	if entry.get("kind", "") == "title_screen": return 2
	return 1

func configure_maps(catalog: Array) -> void:
	library_kind = "maps"
	fullscreen.hide()
	catalog_overlay.hide()
	entries.clear()
	for source in catalog:
		var entry: Dictionary = source.duplicate(true)
		var path := str(entry.get("path", ""))
		if path.ends_with(".json") and FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			entry.path = data.get("image", "") if data is Dictionary else ""
		if not str(entry.get("path", "")).is_empty(): entries.append(entry)
	select_image(0)

func configure_portraits(path: String = "res://content/fe7/portrait_library.json") -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	configure_portrait_entries(data.get("entries",[]) if data is Dictionary else [])

func configure_portrait_entries(catalog: Array) -> void:
	library_kind = "portraits"
	fullscreen.hide()
	catalog_overlay.hide()
	entries.clear()
	for entry in catalog:
		entries.append(entry)
	_sort_characters()
	select_image(0)

func configure_dynamic(kind: String, imported: bool = false) -> void:
	var catalog := preload("res://runtime/rom_assets.gd").library_catalog(kind)
	match kind:
		"portraits": configure_portrait_entries(catalog)
		"backgrounds": configure({"entries":catalog},imported)
		"maps": configure_maps(catalog)

func configure_custom(cards: bool = false) -> void:
	library_kind = "custom_cards" if cards else "custom_dialogue"
	fullscreen.hide()
	catalog_overlay.hide()
	search.text = ""
	entries.clear()
	var store = preload("res://runtime/custom_card_portraits.gd").store if cards else preload("res://runtime/custom_portraits.gd").store
	if not store.loaded: store.reload()
	for source in store.entries:
		var entry: Dictionary = source.duplicate(true)
		var title := str(entry.get("character", "Character %s" % entry.get("character_id", "?")))
		if entry.has("class"): title += " · " + str(entry["class"])
		elif entry.has("class_id"): title += " · Class " + str(int(entry.class_id))
		entry.title = title + " · " + str(entry.get("source_image", entry.image)).get_file()
		entries.append(entry)
	_sort_characters()
	select_image(0)

func _sort_characters() -> void:
	entries.sort_custom(func(a,b): return str(TranslationServer.translate(str(a.get("title","")))).naturalnocasecmp_to(str(TranslationServer.translate(str(b.get("title",""))))) < 0)

func configure_custom_maps() -> void:
	library_kind = "custom_maps"
	fullscreen.hide()
	catalog_overlay.hide()
	search.text = ""
	entries.clear()
	var store = preload("res://runtime/custom_maps.gd").store
	if not store.loaded: store.reload()
	for source in store.entries:
		var entry: Dictionary = source.duplicate(true)
		var record: Dictionary = store.catalog.get(str(entry.id), {})
		entry.title = str(entry.id).replace("_", " ").capitalize()
		entry.title += " · Event patch" if record.has("change") else " · Map"
		entries.append(entry)
	select_image(0)

func _open_catalog() -> void:
	catalog_overlay.position = Vector2.ZERO
	catalog_overlay.size = get_viewport_rect().size
	_filter_catalog()
	catalog_overlay.show()

func _filter_catalog() -> void:
	filtered.clear()
	image_list.clear()
	for index in range(entries.size()):
		var title := str(entries[index].get("title", entries[index].get("id", "Artwork")))
		if not preload("res://runtime/text_replacements.gd").matches_search(title, search.text): continue
		filtered.append(index)
		image_list.add_item(title)

func _open_fullscreen() -> void:
	fullscreen.position = Vector2.ZERO
	fullscreen.size = get_viewport_rect().size
	full_picture.texture = picture.texture
	fullscreen.show()
	_layout_fullscreen()

func _fullscreen_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var id := -1
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		pos = event.position
		id = event.index
		down = event.pressed
		up = not down
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		down = event.pressed
		up = not down
	else: return
	if down:
		swipe_start = pos
		swipe_pointer = id
	elif up and swipe_pointer == id:
		if event is InputEventScreenTouch and event.canceled:
			swipe_pointer = -2
			return
		# A counterclockwise image rotation maps its visual right edge to screen top.
		var delta := swipe_start.y - pos.y if rotated else pos.x - swipe_start.x
		var direction := 0
		if absf(delta) > 45: direction = 1 if delta < 0 else -1
		elif pos.distance_to(swipe_start) < 20:
			var coordinate := fullscreen.size.y - pos.y if rotated else pos.x
			var extent := fullscreen.size.y if rotated else fullscreen.size.x
			direction = -1 if coordinate < extent * 0.5 else 1
		if direction: select_image(posmod(current_index + direction, maxi(1, entries.size())))
		swipe_pointer = -2
	fullscreen.accept_event()

func select_image(index: int) -> void:
	current_index = clampi(index, 0, maxi(0, entries.size() - 1))
	previous_button.disabled = current_index <= 0
	next_button.disabled = current_index >= entries.size() - 1
	selector.disabled = entries.is_empty()
	if not entries.is_empty(): selector.text = str(entries[current_index].get("title", entries[current_index].get("id", "Image"))) + "  ▾"
	refresh_art()

func refresh_art() -> void:
	if entries.is_empty():
		picture.texture = null
		if full_picture: full_picture.texture = null
		selector.text = "No images"
		caption.text = "No images are available in this collection."
		return
	var entry: Dictionary = entries[current_index]
	if library_kind.begins_with("custom_"):
		var store = preload("res://runtime/custom_card_portraits.gd").store if library_kind == "custom_cards" else preload("res://runtime/custom_portraits.gd").store
		if library_kind == "custom_maps": store = preload("res://runtime/custom_maps.gd").store
		picture.texture = store.texture(entry)
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		full_picture.texture = picture.texture
		full_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var portrait_dimensions := picture.texture.get_size() if picture.texture else Vector2.ZERO
		var kind := "battle map" if library_kind == "custom_maps" else "unit-card portrait" if library_kind == "custom_cards" else "dialogue portrait"
		caption.text = "%d / %d  ·  %d × %d pixels  ·  Imported %s" % [current_index + 1, entries.size(), portrait_dimensions.x, portrait_dimensions.y, kind]
		return
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	full_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.texture = preload("res://runtime/custom_backdrops.gd").texture(str(entry.get("path", ""))) if library_kind == "backgrounds" and use_custom_backgrounds else null
	var custom_background := picture.texture != null
	if picture.texture == null:
		var path := str(entry.get("path",""))
		var assets = preload("res://runtime/rom_assets.gd")
		if assets.dynamic_content != null and path.begins_with(assets.dynamic_content.prefix+"library/"):
			# Optional gallery errors are reported in the caption, without a
			# ResourceLoader error or invalidating the active campaign decoder.
			var pixels: Image = assets.image(path)
			picture.texture = ImageTexture.create_from_image(pixels) if pixels else null
		else: picture.texture = Art.texture(path)
	if custom_background:
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		full_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if full_picture: full_picture.texture = picture.texture
	var dimensions := picture.texture.get_size() if picture.texture else Vector2.ZERO
	caption.text = "%d / %d  ·  %d × %d pixels  ·  %s" % [current_index + 1, entries.size(), dimensions.x, dimensions.y, "Imported background" if custom_background else "Original artwork"]
	if picture.texture == null: caption.text = "This image could not be read from the cartridge. Other images are still available."

func _layout_fullscreen() -> void:
	if not full_picture or not fullscreen_buttons: return
	full_picture.set_anchors_preset(Control.PRESET_TOP_LEFT)
	full_picture.size = Vector2(fullscreen.size.y, fullscreen.size.x) if rotated else fullscreen.size
	full_picture.pivot_offset = full_picture.size * 0.5
	full_picture.position = (fullscreen.size - full_picture.size) * 0.5
	full_picture.rotation = -PI * 0.5 if rotated else 0.0
	fullscreen_buttons.size = fullscreen_buttons.get_combined_minimum_size()
	fullscreen_buttons.position = fullscreen.size - fullscreen_buttons.size - Vector2(16, 16)

func _viewer_icon(kind: String) -> Texture2D:
	var strokes := '<path d="M7 7L25 25M25 7L7 25"/>' if kind == "close" else '<path d="M26 13A11 11 0 1 0 25 24M26 4V13H17"/>'
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="none" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">' + strokes + '</g></svg>')
	return ImageTexture.create_from_image(image)
