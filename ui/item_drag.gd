extends Node
## Shared pointer gestures. The menus emit requests; only the battle model moves items.
signal tapped(record: Dictionary)
signal dropped(source: Dictionary, destination: Dictionary)
var host: Control
var hit_test: Callable
var pointer := -1
var origin := Vector2.ZERO
var last_position := Vector2.ZERO
var source: Dictionary = {}
var mode := ""
var held := 0.0
var preview: Label
var coast_bar: VScrollBar
var flick_velocity := 0.0
var last_motion_ms := 0

func configure(value: Control, lookup: Callable) -> void:
	host = value
	hit_test = lookup
	preview = Label.new()
	preview.top_level = true
	preview.z_index = 4096
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_font_size_override("font_size", 21)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.10, 0.25, 0.95)
	style.border_color = Color("f7df9d")
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	preview.add_theme_stylebox_override("normal", style)
	host.add_child(preview)
	preview.hide()
	host.visibility_changed.connect(func():
		if not host.is_visible_in_tree(): cancel())
	host.get_window().focus_exited.connect(cancel)

func cancel() -> void:
	flick_velocity = 0.0
	coast_bar = null
	pointer = -1
	source = {}
	mode = ""
	if is_instance_valid(preview): preview.hide()

func _process(delta: float) -> void:
	if pointer == -1 and is_instance_valid(coast_bar) and absf(flick_velocity) > 8:
		coast_bar.value += flick_velocity * delta
		flick_velocity *= exp(-6.0 * delta)
	if pointer < 0 or mode != "pending": return
	held += delta
	if held >= 0.3 and source.get("draggable", false): _begin_drag(last_position)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(host) or not host.is_visible_in_tree(): return
	if handle_event(event): get_viewport().set_input_as_handled()

func handle_event(event: InputEvent) -> bool:
	# Touch has its own complete gesture. Ignore Godot's duplicated mouse events.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		# Other controls still need their native emulated click (Done, Store,
		# Take, partner selection and scrollbars).
		return pointer != -1 or not hit_test.call(event.position).is_empty()
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		if pointer == -1: return false
		if event is InputEventScreenDrag and event.index != pointer: return false
		var offset: Vector2 = event.position - origin
		var step: Vector2 = event.position - last_position
		last_position = event.position
		if mode == "pending" and offset.length() >= 12:
			if source.get("scroll") != null and absf(offset.y) > absf(offset.x) * 1.35 and held < 0.3:
				mode = "scroll"
			elif source.get("draggable", false): _begin_drag(event.position)
			else: mode = "canceled"
		if mode == "scroll":
			var bar: VScrollBar = source.scroll
			var now := Time.get_ticks_msec()
			flick_velocity = clampf(-step.y / maxf(0.016, (now - last_motion_ms) / 1000.0), -2400, 2400)
			last_motion_ms = now
			bar.value -= step.y
		elif mode == "drag": _move_preview(event.position)
		return true
	var event_pointer := -1
	if event is InputEventScreenTouch: event_pointer = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: event_pointer = -2
	else: return false
	if event.pressed:
		if pointer != -1:
			if event_pointer != pointer: mode = "canceled"; preview.hide()
			return true
		var record: Dictionary = hit_test.call(event.position)
		if record.is_empty() or not record.get("selectable", true): return false
		flick_velocity = 0.0
		coast_bar = null
		last_motion_ms = Time.get_ticks_msec()
		pointer = event_pointer
		origin = event.position
		last_position = event.position
		source = record
		mode = "pending"
		held = 0.0
		return true
	if pointer != event_pointer: return pointer != -1
	var destination: Dictionary = hit_test.call(event.position)
	var original := source
	var ended_mode := mode
	var canceled: bool = event is InputEventScreenTouch and event.canceled
	var velocity := flick_velocity if Time.get_ticks_msec() - last_motion_ms <= 100 else 0.0
	cancel()
	if ended_mode == "scroll" and not canceled:
		coast_bar = original.get("scroll")
		flick_velocity = velocity
	if canceled or destination.is_empty(): return true
	if ended_mode == "drag":
		if int(destination.get("side", -1)) != int(original.get("side", -1)):
			dropped.emit(original, destination)
	elif ended_mode == "pending" and original.get("side") == destination.get("side") and original.get("slot") == destination.get("slot") and event.position.distance_to(origin) < 12:
		tapped.emit(original)
	return true

func _begin_drag(point: Vector2) -> void:
	mode = "drag"
	preview.text = str(source.get("label", "Item"))
	preview.reset_size()
	preview.show()
	_move_preview(point)

func _move_preview(point: Vector2) -> void:
	var viewport_size := host.get_viewport_rect().size
	preview.global_position = Vector2(clampf(point.x + 16, 4, maxf(4, viewport_size.x - preview.size.x - 4)), clampf(point.y - preview.size.y - 8, 4, maxf(4, viewport_size.y - preview.size.y - 4)))
	var destination: Dictionary = hit_test.call(point)
	preview.modulate = Color("bbffd4") if not destination.is_empty() and destination.get("side") != source.get("side") else Color.WHITE
