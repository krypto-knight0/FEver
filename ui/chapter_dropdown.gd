extends Button
## A themed dropdown with a touch-scrollable list, instead of PopupMenu's
## desktop-only scrolling. The popup has its own input viewport.
signal item_selected(index: int)
var entries: Array = []
var popup: PopupPanel
var scroll: ScrollContainer
var list: VBoxContainer

func _ready() -> void:
	theme_type_variation = "OptionButton"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = 48
	text = "Chapters"
	popup = PopupPanel.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("272e68")
	panel.border_color = Color("d9c88b")
	panel.set_border_width_all(2)
	panel.set_content_margin_all(6)
	popup.add_theme_stylebox_override("panel", panel)
	add_child(popup)
	scroll = preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	popup.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	list = VBoxContainer.new()
	margin.add_child(list)
	pressed.connect(open)
	popup.popup_hide.connect(scroll.cancel_gesture)

func _draw() -> void:
	var center := Vector2(size.x - 9, size.y * 0.5)
	draw_polyline(PackedVector2Array([center + Vector2(-4, -2), center + Vector2(0, 2), center + Vector2(4, -2)]), Color("a8b4d4"), 2, true)

func open() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for index in entry_order():
		var choice := Button.new()
		choice.text = str(entries[index].get("title", "Chapter"))
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.clip_text = true
		choice.custom_minimum_size.y = 48
		choice.pressed.connect(func(): popup.hide(); _select_entry(index))
		list.add_child(choice)
	var bounds := get_viewport_rect().size
	var extent := Vector2(minf(maxf(size.x, 580), bounds.x - 24), minf(500, bounds.y - 48))
	var at := global_position + Vector2(0, size.y)
	if at.y + extent.y > bounds.y - 12: at.y = maxf(12, global_position.y - extent.y)
	at.x = clampf(at.x, 12, bounds.x - extent.x - 12)
	at.y = clampf(at.y, 12, bounds.y - extent.y - 12)
	scroll.custom_minimum_size = extent
	popup.popup(Rect2i(Vector2i(at), Vector2i(extent)))
	scroll.scroll_vertical = 0

func _select_entry(index: int) -> void:
	item_selected.emit(index)

func entry_order() -> Array:
	return range(entries.size())
