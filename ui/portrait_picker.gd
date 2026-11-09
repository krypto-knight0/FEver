extends "res://ui/swipe_scroll.gd"
signal item_selected(index: int)
var selected := -1
var item_count: int:
	get: return entries.size()
var entries: Array = []
var row: HBoxContainer

func _ready() -> void:
	vertical_scroll_mode = SCROLL_MODE_DISABLED
	custom_minimum_size.y = 100
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

func clear() -> void:
	selected = -1
	entries.clear()
	for child in row.get_children(): row.remove_child(child); child.queue_free()

func add_unit(unit: Dictionary, label: String) -> void:
	var index := entries.size()
	entries.append(str(unit.id))
	var button := Button.new()
	button.custom_minimum_size = Vector2(82, 82)
	button.toggle_mode = true
	for state in ["pressed", "hover_pressed"]:
		var gold := StyleBoxFlat.new()
		gold.bg_color = Color("e9b936")
		gold.border_color = Color("fff0a0")
		gold.set_border_width_all(3)
		gold.set_corner_radius_all(5)
		button.add_theme_stylebox_override(state, gold)
	button.tooltip_text = "%s · Lv %d%s" % [label, int(unit.level), " · Fallen" if int(unit.hp) <= 0 else ""]
	row.add_child(button)
	var portrait := preload("res://ui/unit_portrait.gd").new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 4; portrait.offset_top = 4; portrait.offset_right = -4; portrait.offset_bottom = -4
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait)
	portrait.present(unit)
	if int(unit.hp) <= 0: portrait.modulate = Color(0.65, 0.65, 0.65)
	button.pressed.connect(func(): select(index); item_selected.emit(index))
	if selected < 0: select(0)

func select(index: int) -> void:
	selected = index
	for i in range(row.get_child_count()): row.get_child(i).set_pressed_no_signal(i == selected)

func get_item_metadata(index: int) -> Variant:
	return entries[index] if index >= 0 and index < entries.size() else ""
