extends ItemList

# ItemList does not inherit ScrollContainer's touch dragging. Scroll its own
# bar so taps, keyboard selection, the wheel and preview selection still work.
var drag_pointer := -2
var drag_origin := Vector2.ZERO
var drag_scroll := 0.0
var dragging := false
var flick_velocity := 0.0
var last_motion_ms := 0
var last_scroll_value := 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree(): flick_velocity = 0.0
	if drag_pointer == -2 and absf(flick_velocity) > 8.0:
		get_v_scroll_bar().value += flick_velocity * delta
		flick_velocity *= exp(-6.0 * delta)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		drag_pointer = -2
		return
	if event is InputEventMouse and event.device == -1: return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pointer: int = event.index if event is InputEventScreenTouch else -1
		if event.pressed and get_v_scroll_bar().get_global_rect().grow(8).has_point(event.position): return
		if event.pressed and get_global_rect().has_point(event.position):
			drag_pointer = pointer
			drag_origin = event.position
			drag_scroll = get_v_scroll_bar().value
			last_scroll_value = drag_scroll
			flick_velocity = 0.0
			last_motion_ms = Time.get_ticks_msec()
			dragging = false
		elif not event.pressed and pointer == drag_pointer:
			if Time.get_ticks_msec() - last_motion_ms > 100: flick_velocity = 0.0
			drag_pointer = -2
			if dragging: get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		var pointer: int = event.index if event is InputEventScreenDrag else -1
		if pointer != drag_pointer: return
		var delta: Vector2 = event.position - drag_origin
		if absf(delta.y) >= 8: dragging = true
		if dragging:
			var now := Time.get_ticks_msec()
			var value := drag_scroll - delta.y
			flick_velocity = clampf((value - last_scroll_value) / maxf(0.016, (now - last_motion_ms) / 1000.0), -2400, 2400)
			last_scroll_value = value
			last_motion_ms = now
			get_v_scroll_bar().value = value
			get_viewport().set_input_as_handled()
