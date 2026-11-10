extends PanelContainer
## Compact, clickable unit card; all values are supplied by the game controller.
signal unit_pressed(unit_id: String)

var unit: Dictionary = {}
var portrait: TextureRect
var unit_label: RichTextLabel
var name_label: Label
var level_label: Label
var hp_label: Label
var hp_bar: ProgressBar
var touch_id := -1
var texture_cache: Dictionary = {}
var loot_icons: HBoxContainer
var skill_icons: HFlowContainer

func _ready() -> void:
	custom_minimum_size = Vector2(400, 164)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "View unit details"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d7ddf1")
	style.border_color = Color("f6ecc5")
	style.set_border_width_all(3)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.05, 0.04, 0.12, 0.6)
	style.shadow_size = 3
	style.content_margin_left = 8
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.87))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	portrait = preload("res://ui/unit_portrait.gd").new()
	portrait.custom_minimum_size = Vector2(110, 138)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	column.add_child(identity)
	name_label = _label(27, Color("fff4d7"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_label)
	level_label = _label(17, Color("dbe7fa"))
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(level_label)
	hp_label = _label(24, Color("fff4d7"))
	column.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 12
	hp_bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color("77798b")
	track.border_color = Color("faf3c7")
	track.set_border_width_all(2)
	hp_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e9c65c")
	fill.set_border_width_all(2)
	fill.border_color = Color("fff3a5")
	hp_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(hp_bar)
	skill_icons = HFlowContainer.new()
	column.add_child(skill_icons)
	loot_icons = HBoxContainer.new()
	loot_icons.add_theme_constant_override("separation", 12)
	column.add_child(loot_icons)
	for icon_name in ["steal", "drop"]:
		var icon := TextureRect.new()
		icon.texture = load("res://ui/icons/" + icon_name + ".svg")
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		loot_icons.add_child(icon)
	unit_label = RichTextLabel.new()
	unit_label.hide()
	add_child(unit_label)
	_ignore_children(self)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _ignore_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control: child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_children(child)

func present(value: Dictionary) -> void:
	unit = value.duplicate(true)
	if unit.is_empty():
		hide()
		return
	name_label.text = str(unit.get("name", "Unit"))
	level_label.text = "Lv %d" % int(unit.get("level", 1))
	if unit.get("faction", "") == "player": level_label.text += " · XP %d" % int(unit.get("exp", 0))
	hp_label.text = "HP %d / %d" % [int(unit.get("hp", 0)), int(unit.get("max_hp", 1))]
	if str(unit.get("status", "")) not in ["", "none"]: hp_label.text += " · " + str(unit.status).capitalize()
	hp_bar.max_value = maxi(1, int(unit.get("max_hp", 1)))
	hp_bar.value = maxi(0, int(unit.get("hp", 0)))
	var stealable := false
	var droppable := false
	for item in unit.get("inventory", []) + [unit.get("weapon", {})]:
		if item.is_empty(): continue
		if not item.has("might") and item.get("stealable", item.get("type", "item") != "staff") and int(item.get("uses", 0)) > 0: stealable = true
		var drop: Dictionary = unit.get("drop_item", {})
		if item.get("droppable", false) or (not drop.is_empty() and int(item.get("rom_item_id", -1)) == int(drop.get("rom_item_id", -2))): droppable = true
	loot_icons.visible = unit.get("faction", "") == "enemy" and (stealable or droppable)
	loot_icons.get_child(0).visible = stealable
	loot_icons.get_child(1).visible = droppable and not unit.get("drop_claimed", false)
	tooltip_text = "View unit details" + (" · Stealable item" if loot_icons.visible and stealable else "") + (" · Droppable item" if loot_icons.visible and droppable else "")
	for child in skill_icons.get_children(): skill_icons.remove_child(child); child.queue_free()
	for record in preload("res://ui/skill_icons.gd").records(unit):
		var icon := TextureRect.new()
		icon.texture = preload("res://ui/skill_icons.gd").texture(record.id)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_icons.add_child(icon)
	skill_icons.visible = skill_icons.get_child_count() > 0
	portrait.present(unit)
	portrait.visible = portrait.has_portrait()
	unit_label.text = "%s  %s  %s" % [name_label.text, level_label.text, hp_label.text]
	show()

func _gui_input(event: InputEvent) -> void:
	var activate := false
	if event is InputEventScreenTouch:
		if event.pressed and touch_id < 0: touch_id = event.index
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			activate = not event.canceled
	elif event is InputEventMouseButton:
		activate = event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	elif event is InputEventKey:
		activate = event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]
	if activate and not unit.is_empty():
		unit_pressed.emit(str(unit.get("id", "")))
	accept_event()
