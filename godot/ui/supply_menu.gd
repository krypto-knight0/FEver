extends VBoxContainer
## Shared storage uses explicit transfer buttons and leaves equipment choices to Items.
const Art = preload("res://runtime/art_textures.gd")
signal transfer_requested(direction: String, index: int)
var unit_list: ItemList
var supply_list: ItemList
var store_button: Button
var take_button: Button
var message: Label
var unit_title: Label
var supply_title: Label
var slots: Array[int] = []
var item_drag: Node

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	for side in range(2):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 21)
		column.add_child(title)
		var items := ItemList.new()
		items.size_flags_vertical = Control.SIZE_EXPAND_FILL
		items.custom_minimum_size.y = 160
		items.fixed_icon_size = Vector2i(28, 28)
		items.add_theme_font_size_override("font_size", 19)
		items.add_theme_constant_override("v_separation", 12)
		column.add_child(items)
		var button := Button.new()
		button.custom_minimum_size.y = 48
		button.text = "Store →" if side == 0 else "← Take"
		button.disabled = true
		column.add_child(button)
		if side == 0:
			unit_title = title; unit_list = items; store_button = button
			items.item_selected.connect(func(index): store_button.disabled = false; _describe(unit_list, index))
			button.pressed.connect(func():
				var selected := unit_list.get_selected_items()
				if not selected.is_empty(): transfer_requested.emit("store", slots[selected[0]]))
		else:
			supply_title = title; supply_list = items; take_button = button
			items.item_selected.connect(func(index): take_button.disabled = false; _describe(supply_list, index))
			button.pressed.connect(func():
				var selected := supply_list.get_selected_items()
				if not selected.is_empty(): transfer_requested.emit("take", selected[0]))
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 50
	add_child(message)
	item_drag = preload("res://ui/item_drag.gd").new()
	add_child(item_drag)
	item_drag.configure(self, _drag_hit)
	item_drag.tapped.connect(_tap_item)
	item_drag.dropped.connect(func(source, _destination): transfer_requested.emit("store" if int(source.side) == 0 else "take", int(source.slot)))

func present(unit: Dictionary, inventory_slots: Array, supply: Array) -> void:
	item_drag.cancel()
	unit_title.text = str(unit.get("name", "Unit"))
	supply_title.text = "Supply · %d items" % supply.size()
	unit_list.clear()
	supply_list.clear()
	slots.clear()
	store_button.disabled = true
	take_button.disabled = true
	for record in inventory_slots:
		if record.item.is_empty(): continue
		slots.append(int(record.slot))
		_add_item(unit_list, record.item, "◆ " if record.equipped else "")
	for item in supply: _add_item(supply_list, item)
	message.text = ""
	var initial := unit_list if unit_list.item_count > 0 else supply_list
	if initial.item_count > 0: initial.select(0); initial.item_selected.emit(0)

func _drag_hit(point: Vector2) -> Dictionary:
	for side in range(2):
		var list: ItemList = unit_list if side == 0 else supply_list
		if not list.get_global_rect().has_point(point): continue
		var bar := list.get_v_scroll_bar()
		if bar.is_visible_in_tree() and bar.get_global_rect().has_point(point): return {}
		var index := list.get_item_at_position(point - list.global_position, true)
		return {"side": side, "slot": slots[index] if side == 0 and index >= 0 else index, "index": index, "selectable": index >= 0, "draggable": index >= 0, "scroll": bar, "label": list.get_item_text(index) if index >= 0 else ""}
	return {}

func _tap_item(record: Dictionary) -> void:
	var list: ItemList = unit_list if int(record.side) == 0 else supply_list
	list.select(int(record.index))
	list.item_selected.emit(int(record.index))

func _add_item(list: ItemList, item: Dictionary, prefix: String = "") -> void:
	list.add_item("%s%s · %d" % [prefix, item.get("name", "Item"), int(item.get("uses", 0))], Art.texture(str(item.get("icon", ""))))
	list.set_item_metadata(list.item_count - 1, item.duplicate(true))

func _describe(list: ItemList, index: int) -> void:
	message.text = preload("res://ui/item_description.gd").describe(list.get_item_metadata(index))
