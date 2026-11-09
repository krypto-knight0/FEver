extends ColorRect
const Art = preload("res://runtime/art_textures.gd")
## Inventory presentation only; the controller applies validated engine swaps.
signal slot_pressed(side: int, slot: int)
signal partner_changed(unit_id: String)
signal closed
const PanelMotion = preload("res://ui/panel_motion.gd")
const PanelStyle = preload("res://ui/panel_style.gd")
var animations_enabled := true
var transition_speed := 1.0
var motion = PanelMotion.new()

var panel: PanelContainer
var partner_menu: OptionButton
var message: Label
var names: Array[Label] = []
var portraits: Array[TextureRect] = []
var lists: Array[VBoxContainer] = []
var partner_ids: Array[String] = []
var slots: Array = [[], []]
var selected_side := -1
var selected_slot := -2
var outside_pointer := -1
var outside_origin := Vector2.ZERO
var outside_canceled := false
var item_drag: Node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.01, 0.02, 0.06, 0.30)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_outside_input)
	panel = PanelContainer.new()
	var style := PanelStyle.create(false, 0.88)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.minimum_size_changed.connect(func(): call_deferred("_layout"))
	var column := VBoxContainer.new()
	panel.add_child(column)
	partner_menu = OptionButton.new()
	partner_menu.custom_minimum_size.y = 48
	partner_menu.item_selected.connect(func(index): partner_changed.emit(partner_ids[index]))
	column.add_child(partner_menu)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 18)
	column.add_child(sides)
	for side in range(2):
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sides.add_child(box)
		var heading := HBoxContainer.new()
		box.add_child(heading)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(86, 90)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.flip_h = side == 0
		heading.add_child(portrait)
		portraits.append(portrait)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 28)
		heading.add_child(name_label)
		names.append(name_label)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		box.add_child(list)
		lists.append(list)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size.y = 48
	close.pressed.connect(dismiss)
	column.add_child(close)
	resized.connect(_layout)
	item_drag = preload("res://ui/item_drag.gd").new()
	add_child(item_drag)
	item_drag.configure(self, _drag_hit)
	item_drag.tapped.connect(func(record): slot_pressed.emit(int(record.side), int(record.slot)))
	item_drag.dropped.connect(_drop_item)
	hide()

func present(left: Dictionary, right: Dictionary, left_slots: Array, right_slots: Array, partners: Array) -> void:
	item_drag.cancel()
	outside_pointer = -1
	partner_ids.clear()
	partner_menu.clear()
	var ordered := partners.duplicate()
	ordered.sort_custom(func(a,b): return str(TranslationServer.translate(str(a.name))).naturalnocasecmp_to(str(TranslationServer.translate(str(b.name)))) < 0)
	for partner in ordered:
		partner_ids.append(str(partner.id))
		partner_menu.add_item("Trade with %s" % partner.name)
		if partner.id == right.id: partner_menu.selected = partner_ids.size() - 1
	slots = [left_slots, right_slots]
	for side in range(2):
		var unit: Dictionary = left if side == 0 else right
		names[side].text = str(unit.get("name", ""))
		var path := str(unit.get("portrait", ""))
		portraits[side].set_meta("art_path", path)
		portraits[side].texture = Art.texture(path) if ResourceLoader.exists(path) else null
		for child in lists[side].get_children():
			lists[side].remove_child(child)
			child.queue_free()
		for entry in slots[side]:
			var item: Dictionary = entry.get("item", {})
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(310, 44)
			button.toggle_mode = true
			button.button_pressed = selected_side == side and selected_slot == int(entry.slot)
			button.text = "— Empty —" if item.is_empty() else "%s%s    %d" % ["◆ " if entry.get("equipped", false) else "", item.get("name", "Item"), int(item.get("uses", 0))]
			button.icon = Art.texture(str(item.get("icon", ""))) if not item.is_empty() else null
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 26)
			button.tooltip_text = "Drag to the other inventory, or choose an item and then its destination."
			button.pressed.connect(func(): slot_pressed.emit(side, int(entry.slot)))
			lists[side].add_child(button)
	message.text = "Drag an item to the other inventory, or tap two slots to exchange them."
	_layout()
	call_deferred("_layout")
	motion.configure(animations_enabled, transition_speed)
	motion.present(self, true)

func dismiss() -> void:
	item_drag.cancel()
	outside_pointer = -1
	motion.configure(animations_enabled, transition_speed)
	motion.present(self, false)
	closed.emit()

func _drag_hit(point: Vector2) -> Dictionary:
	for side in range(lists.size()):
		for index in range(lists[side].get_child_count()):
			var button: Button = lists[side].get_child(index)
			if button.get_global_rect().has_point(point):
				var entry: Dictionary = slots[side][index]
				return {"side": side, "slot": int(entry.slot), "label": str(entry.get("item", {}).get("name", "Item")), "draggable": not entry.get("item", {}).is_empty()}
	return {}

func _drop_item(source: Dictionary, destination: Dictionary) -> void:
	# One validated controller transaction; an earlier tap selection cannot cause
	# a different swap when the drag starts on another item.
	selected_side = int(source.side)
	selected_slot = int(source.slot)
	slot_pressed.emit(int(destination.side), int(destination.slot))

func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device == -1:
		accept_event()
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		if outside_pointer != -1 and (event.position.distance_to(outside_origin) >= 18.0 or panel.get_rect().has_point(event.position)):
			outside_canceled = true
		return
	var pointer := -1
	if event is InputEventScreenTouch: pointer = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: pointer = -2
	else: return
	if event.pressed:
		if outside_pointer == -1 and not panel.get_rect().has_point(event.position):
			outside_pointer = pointer
			outside_origin = event.position
			outside_canceled = false
	elif pointer == outside_pointer:
		var close: bool = not outside_canceled and not panel.get_rect().has_point(event.position) and event.position.distance_to(outside_origin) < 18.0
		if event is InputEventScreenTouch and event.canceled: close = false
		outside_pointer = -1
		if close: dismiss()
	accept_event()

func _layout() -> void:
	if not panel: return
	panel.size = Vector2(minf(860, size.x - 40), 0)
	panel.position = (size - panel.size) * 0.5
