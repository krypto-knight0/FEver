extends ColorRect
signal import_requested
signal defaults_saved
signal background_import_requested
signal map_import_requested
signal sprite_import_requested
signal originals_requested(kind: String)
signal delete_art_requested
var art_toggles: Dictionary = {}
var hide_platforms_toggle: CheckButton
var delete_button: Button
var delete_prompt: ConfirmationDialog
var extra_buttons: Array[Button] = []
var store = preload("res://runtime/custom_portraits.gd").store
var kind := "dialogue"
var defaults_kind: OptionButton
var entry_selector: Button
var inherit_button: Button
var heading: Label
var hint: Label
var outside_pointer := -2
var outside_start := Vector2.ZERO
var panel: PanelContainer
var scale_value: SpinBox
var x_value: SpinBox
var y_value: SpinBox
var flip_value: CheckButton
var import_button: Button
var save_button: Button
var status: Label
var import_status: Label
var importing := false

func _ready() -> void:
	color = Color(0.01, 0.02, 0.04, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 1.0))
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	heading = Label.new()
	heading.text = "Custom art"
	heading.add_theme_font_size_override("font_size", 25)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(heading)
	import_status = Label.new()
	import_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(import_status)
	var scroll := preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 18)
	scroll.add_child(gutter)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	gutter.add_child(fields)
	import_button = _button(fields, "Load character art ZIP…", func(): import_requested.emit())
	extra_buttons.append(_button(fields, "Load backgrounds / CG / battle / title art ZIP…", func(): background_import_requested.emit()))
	extra_buttons.append(_button(fields, "Load battle maps ZIP…", func(): map_import_requested.emit()))
	extra_buttons.append(_button(fields, "Load map sprites ZIP…", func(): sprite_import_requested.emit()))
	var labels := {"dialogue": "dialogue portraits", "cards": "unit-card portraits", "backgrounds": "backgrounds / CG / battle / title art", "maps": "battle maps", "sprites": "map sprites"}
	for art_kind in labels:
		var toggle := CheckButton.new()
		toggle.text = "Use original " + labels[art_kind]
		toggle.custom_minimum_size.y = 48
		toggle.toggled.connect(func(_value): if not importing: originals_requested.emit(art_kind))
		fields.add_child(toggle)
		art_toggles[art_kind] = toggle
	hide_platforms_toggle = CheckButton.new()
	hide_platforms_toggle.text = "Hide battle platforms"
	hide_platforms_toggle.custom_minimum_size.y = 48
	hide_platforms_toggle.toggled.connect(func(platforms_hidden):
		preload("res://runtime/battle_art.gd").set_platforms_hidden(platforms_hidden)
		defaults_saved.emit())
	fields.add_child(hide_platforms_toggle)
	delete_prompt = ConfirmationDialog.new()
	delete_prompt.title = "Delete all custom art?"
	delete_prompt.dialog_text = "Delete all imported custom art and restore the originals? Your source ZIP files will be kept."
	delete_prompt.ok_button_text = "Delete all custom art"
	delete_prompt.confirmed.connect(func(): if not importing: delete_art_requested.emit())
	add_child(delete_prompt)
	delete_button = _button(fields, "Delete all custom art…", func(): delete_prompt.popup_centered())
	var defaults_row := HBoxContainer.new()
	fields.add_child(defaults_row)
	var defaults_label := Label.new()
	defaults_label.text = "Art type"
	defaults_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defaults_row.add_child(defaults_label)
	defaults_kind = OptionButton.new()
	defaults_kind.add_item("Dialogue portraits")
	defaults_kind.add_item("Unit-card portraits")
	defaults_kind.add_item("Battle backgrounds")
	defaults_kind.custom_minimum_size = Vector2(240, 48)
	defaults_kind.item_selected.connect(func(index): _select_defaults(["dialogue", "cards", "battle"][index]))
	defaults_row.add_child(defaults_kind)
	entry_selector = preload("res://ui/portrait_entry_dropdown.gd").new()
	entry_selector.clip_text = true
	entry_selector.custom_minimum_size.y = 48
	entry_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	entry_selector.item_selected.connect(func(_index): _load_selected_values())
	fields.add_child(entry_selector)
	hint = Label.new()
	hint.text = "Defaults apply to every portrait unless its entry specifies a value. Offsets are percentages of the screen width and height."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(hint)
	scale_value = _percentage(fields, "Scale", 1, 400)
	x_value = _percentage(fields, "X offset", -100, 100)
	y_value = _percentage(fields, "Y offset", -100, 100)
	flip_value = CheckButton.new()
	flip_value.text = "Flip horizontally"
	fields.add_child(flip_value)
	save_button = _button(fields, "Save defaults", _save)
	inherit_button = _button(fields, "Use defaults for this portrait", _inherit)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(status)
	_button(column, "Back to Custom", hide)
	resized.connect(_layout)
	_layout()
	hide()

func _layout() -> void:
	if not panel: return
	panel.size = Vector2(minf(640, size.x - 32), minf(650, size.y - 32))
	panel.position = (size - panel.size) * 0.5

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _percentage(parent: Node, title: String, minimum: float, maximum: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := SpinBox.new()
	value.min_value = minimum
	value.max_value = maximum
	value.step = 1
	value.suffix = "%"
	value.custom_minimum_size = Vector2(180, 48)
	row.add_child(value)
	return value

func open_panel(portrait_kind: String = "dialogue") -> void:
	_select_defaults(portrait_kind)
	outside_pointer = -2
	show()
	_layout()

func _select_defaults(portrait_kind: String) -> void:
	if entry_selector.item_count > 0: entry_selector.select(0)
	kind = portrait_kind
	defaults_kind.select(["dialogue", "cards", "battle"].find(kind))
	store = preload("res://runtime/custom_backdrops.gd").store if kind == "battle" else preload("res://runtime/custom_card_portraits.gd").store if kind == "cards" else preload("res://runtime/custom_portraits.gd").store
	hint.text = "Defaults apply unless an entry specifies its own value. " + ("Offsets are percentages of the portrait frame. Positive X moves right; positive Y moves down." if kind == "cards" else "Offsets are percentages of the screen. Positive X moves away from the dialogue box on either side; positive Y moves down.")
	if kind == "battle": hint.text = "Move custom battle backgrounds up (negative) or down (positive), as a percentage of the battle scene height. 0% restores the original position. Defaults apply unless a background has its own setting."
	y_value.get_parent().get_child(0).text = "Vertical position" if kind == "battle" else "Y offset"
	refresh_values()

func refresh_values() -> void:
	hide_platforms_toggle.set_pressed_no_signal(preload("res://runtime/battle_art.gd").platforms_hidden())
	if not store.loaded: store.reload()
	var selected: int = entry_selector.selected
	entry_selector.clear()
	entry_selector.add_item("All battle backgrounds · defaults" if kind == "battle" else "All portraits · defaults")
	entry_selector.set_item_metadata(0, -1)
	for index in store.entries.size():
		var entry: Dictionary = store.entries[index]
		if kind == "battle" and not str(entry.get("character", "")).begins_with("battle_background_"): continue
		var title := str(entry.get("character", entry.get("character_id", "Portrait")))
		if kind == "battle": title = title.trim_prefix("battle_background_").replace("_", " ").capitalize()
		if entry.has("class"): title += " · " + str(entry["class"])
		elif entry.has("class_id"): title += " · Class " + str(int(entry.class_id))
		title += " · " + str(entry.get("source_image", entry.image))
		entry_selector.add_item(title)
		entry_selector.set_item_metadata(entry_selector.item_count - 1, index)
	entry_selector.select(clampi(selected, 0, entry_selector.item_count - 1))
	_load_selected_values()

func _load_selected_values() -> void:
	var values: Dictionary = store.default_values()
	if entry_selector.selected > 0: values.merge(store.entries[int(entry_selector.get_item_metadata(entry_selector.selected))], true)
	save_button.text = ("Save background" if kind == "battle" else "Save portrait") if entry_selector.selected > 0 else "Save defaults"
	inherit_button.text = "Use defaults for this background" if kind == "battle" else "Use defaults for this portrait"
	inherit_button.visible = entry_selector.selected > 0
	scale_value.value = values.scale_percent
	x_value.value = values.x_percent
	y_value.value = float(values.get("battle_y_percent", 0)) if kind == "battle" else values.y_percent
	flip_value.set_pressed_no_signal(bool(values.get("flip_h", false)))
	status.text = "" if store.editable_defaults else ("Load a portrait ZIP to edit defaults." if store.entries.is_empty() else "Reimport your portrait ZIP once to enable editable defaults. Your current portraits will stay available.")
	if kind == "battle": status.text = "Load a backgrounds ZIP to adjust battle backgrounds." if store.directory.is_empty() else ""
	set_importing(importing)

func set_importing(value: bool) -> void:
	import_status.text = "Importing art…" if value else ""
	importing = value
	import_button.disabled = value
	for button in extra_buttons: button.disabled = value
	var stores := art_stores()
	var portraits_supported := stores.has("dialogue")
	import_button.visible = portraits_supported
	for index in extra_buttons.size(): extra_buttons[index].visible = stores.has(["backgrounds", "maps", "sprites"][index])
	for control in [defaults_kind.get_parent(), entry_selector, hint, scale_value.get_parent(), x_value.get_parent(), y_value.get_parent(), flip_value, save_button]:
		control.visible = portraits_supported
	if kind == "battle":
		for control in [scale_value.get_parent(), x_value.get_parent(), flip_value]: control.hide()
	inherit_button.visible = portraits_supported and entry_selector.selected > 0
	delete_prompt.dialog_text = "Delete all imported %s custom art and restore the originals? Your source ZIP files will be kept." % str(preload("res://runtime/rom_assets.gd").game_id).to_upper()
	var stored_bytes := 0
	if not value:
		for art_store in stores.values(): stored_bytes += preload("res://runtime/import_storage.gd").pack_bytes(art_store.root)
		delete_button.text = "Delete all custom art (%s)…" % preload("res://runtime/import_storage.gd").label(stored_bytes)
	for art_kind in art_toggles:
		art_toggles[art_kind].visible = stores.has(art_kind)
		if not stores.has(art_kind): continue
		var art_store = stores[art_kind]
		if not art_store.loaded: art_store.reload()
		var available: bool = not art_store.entries.is_empty()
		if art_kind == "backgrounds": available = true
		art_toggles[art_kind].disabled = value or not available
		art_toggles[art_kind].set_pressed_no_signal(not available or not art_store.enabled)
	delete_button.disabled = value or stored_bytes == 0
	defaults_kind.disabled = value
	entry_selector.disabled = value
	var editable: bool = not store.directory.is_empty() if kind == "battle" else store.editable_defaults
	inherit_button.disabled = value or not editable
	flip_value.disabled = value or not store.editable_defaults
	save_button.disabled = value or not editable
	for field in [scale_value, x_value, y_value]: field.editable = not value and editable
	if value: status.text = ""

static func art_stores() -> Dictionary:
	if preload("res://runtime/rom_assets.gd").game_id == "fe6":
		return {"dialogue": preload("res://runtime/custom_portraits.gd").store, "cards": preload("res://runtime/custom_card_portraits.gd").store, "backgrounds": preload("res://runtime/custom_backdrops.gd").store}
	return {"dialogue": preload("res://runtime/custom_portraits.gd").store, "cards": preload("res://runtime/custom_card_portraits.gd").store, "backgrounds": preload("res://runtime/custom_backdrops.gd").store, "maps": preload("res://runtime/custom_maps.gd").store, "sprites": preload("res://runtime/custom_sprites.gd").store}

func _save() -> void:
	if importing: return
	for field in [scale_value, x_value, y_value]: field.apply()
	if kind == "battle":
		var height_error: String = store.save_battle_height(int(entry_selector.get_item_metadata(entry_selector.selected)), y_value.value)
		status.text = "Battle background position saved." if height_error.is_empty() else height_error
		if height_error.is_empty(): defaults_saved.emit()
		return
	var error: String = store.save_entry(entry_selector.selected - 1, scale_value.value, x_value.value, y_value.value, false, flip_value.button_pressed) if entry_selector.selected > 0 else store.save_defaults(scale_value.value, x_value.value, y_value.value, flip_value.button_pressed)
	status.text = "Portrait settings saved." if error.is_empty() else error
	if error.is_empty(): defaults_saved.emit()

func _inherit() -> void:
	if importing or entry_selector.selected <= 0: return
	if kind == "battle":
		var height_error: String = store.save_battle_height(int(entry_selector.get_item_metadata(entry_selector.selected)), 0, true)
		if height_error.is_empty():
			_load_selected_values()
			defaults_saved.emit()
		status.text = "This background now follows the defaults." if height_error.is_empty() else height_error
		return
	var error: String = store.save_entry(entry_selector.selected - 1, 100, 0, 0, true)
	if error.is_empty():
		_load_selected_values()
		defaults_saved.emit()
	status.text = "This portrait now follows the defaults." if error.is_empty() else error

func _gui_input(event: InputEvent) -> void:
	# The shade receives gestures outside the panel; keep the whole gesture here
	# so its release cannot activate Settings beneath it.
	var point := Vector2.ZERO
	var pointer := -1
	var pressed := false
	var canceled := false
	if event is InputEventScreenTouch:
		point = event.position; pointer = event.index; pressed = event.pressed; canceled = event.canceled
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position; pressed = event.pressed
	else: return
	if pressed:
		if not panel.get_rect().has_point(point):
			outside_pointer = pointer; outside_start = point
	elif pointer == outside_pointer:
		outside_pointer = -2
		if not canceled and not panel.get_rect().has_point(point) and point.distance_to(outside_start) < 20: hide()
	accept_event()
