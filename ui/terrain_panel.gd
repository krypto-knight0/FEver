extends PanelContainer
const Styles = preload("res://ui/panel_style.gd")
signal inspect_requested(cell: Vector2i)

var title: Label
var details: Label
var cell := Vector2i(-1, -1)
var _pressed_pointer := -2
var _press_position := Vector2.ZERO
var _press_dragged := false

func _ready() -> void:
	custom_minimum_size = Vector2(190, 104)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "View movement costs"
	add_theme_stylebox_override("panel", Styles.create(false, 0.86))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("fff4d7"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	details = Label.new()
	details.add_theme_font_size_override("font_size", 18)
	details.add_theme_color_override("font_color", Color("e9eefb"))
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(details)

func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)

func _gui_input(event: InputEvent) -> void:
	# Use the native touch once; Godot's emulated mouse must not open it twice.
	if event is InputEventMouse and event.device == -1: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_button(-1, event.pressed, event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.canceled:
			if event.index == _pressed_pointer: _pressed_pointer = -2
			return
		_pointer_button(event.index, event.pressed, event.position)
		accept_event()
	elif event is InputEventMouseMotion and _pressed_pointer == -1:
		_press_dragged = _press_dragged or event.position.distance_to(_press_position) > 12
	elif event is InputEventScreenDrag and event.index == _pressed_pointer:
		_press_dragged = _press_dragged or event.position.distance_to(_press_position) > 12

func _pointer_button(index: int, pressed: bool, point: Vector2) -> void:
	if pressed:
		if _pressed_pointer != -2:
			_press_dragged = true
			return
		_pressed_pointer = index
		_press_position = point
		_press_dragged = false
	elif index == _pressed_pointer:
		_pressed_pointer = -2
		if not _press_dragged and point.distance_to(_press_position) <= 12 and _has_point(point):
			inspect_requested.emit(cell)

func present(value: Dictionary, cell_position: Vector2i) -> void:
	cell = cell_position
	title.text = str(value.get("name", "Terrain"))
	details.text = "DEF %d   AVO %d" % [int(value.get("defense", 0)), int(value.get("avoid", 0))]
	if float(value.get("heal", 0)) > 0: details.text += "\nHeals %d%% each turn" % int(float(value.heal) * 100)
