extends ColorRect
## One screen-bounded list for every personal/acquired skill on a unit.
const Skills = preload("res://ui/skill_icons.gd")
var panel: PanelContainer
var scroll: ScrollContainer
var rows: VBoxContainer
var heading: Label
var switch_button: Button
var current_unit: Dictionary = {}
var current_state
var army_view := false
var generation := 0
var outside_pointer := -2
var outside_start := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	color = Color(0.01, 0.02, 0.04, 0.6)
	mouse_filter = MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 1.0))
	panel.mouse_filter = MOUSE_FILTER_STOP
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 25)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	switch_button = Button.new()
	switch_button.custom_minimum_size.y = 48
	switch_button.pressed.connect(func(): army_view = not army_view; _render())
	column.add_child(switch_button)
	scroll = preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size.y = 48
	close.pressed.connect(hide)
	column.add_child(close)
	gui_input.connect(_outside_input)
	resized.connect(_layout)
	visibility_changed.connect(func():
		outside_pointer = -2
		if not visible:
			generation += 1
			current_state = null
			current_unit = {})
	_layout()
	hide()

func _layout() -> void:
	panel.size = Vector2(minf(760, maxf(1, size.x - 32)), minf(640, maxf(1, size.y - 32)))
	panel.position = (size - panel.size) / 2

func present(unit: Dictionary, selected_id: String = "", state = null) -> void:
	current_unit = unit
	current_state = state
	army_view = false
	_render(selected_id)

func _render(selected_id: String = "") -> void:
	var unit := current_unit
	var state = current_state
	generation += 1
	var token := generation
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	heading.text = "Army · Skills" if army_view else "%s · Skills" % unit.get("name", "Unit")
	switch_button.text = "View character skills" if army_view else "View army skills"
	var selected_row: Control
	for record in (Skills.army_records(state) if army_view else Skills.records(unit)):
		var row := VBoxContainer.new()
		row.set_meta("skill_id", record.id)
		rows.add_child(row)
		var header := HBoxContainer.new()
		row.add_child(header)
		var icon := TextureRect.new()
		icon.texture = Skills.texture(str(record.id))
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.add_child(icon)
		var title := Label.new()
		title.text = str(record.name) + (" ×%d" % int(record.count) if int(record.count) > 1 else "")
		title.add_theme_font_size_override("font_size", 22)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		header.add_child(title)
		var body := Label.new()
		body.text = Skills.army_details(record, state) if army_view else Skills.details(unit, record, state)
		body.add_theme_font_size_override("font_size", 19)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(body)
		if str(record.id) == selected_id: selected_row = row
	if rows.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "No army skills acquired." if army_view else "No character skills acquired."
		rows.add_child(empty)
	scroll.scroll_vertical = 0
	show()
	_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	if token == generation and visible and is_instance_valid(selected_row): scroll.ensure_control_visible(selected_row)

func _outside_input(event: InputEvent) -> void:
	var pointer := -2
	var pressed := false
	var popup_position := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = -1; pressed = event.pressed; popup_position = event.position
	elif event is InputEventScreenTouch:
		pointer = event.index; pressed = event.pressed; popup_position = event.position
	else: return
	if pressed:
		outside_pointer = pointer if not panel.get_rect().has_point(popup_position) else -2
		outside_start = popup_position
	elif pointer == outside_pointer:
		outside_pointer = -2
		if not panel.get_rect().has_point(popup_position) and outside_start.distance_to(popup_position) < 18: hide()
	accept_event()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()
