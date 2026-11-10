extends ScrollContainer
## A drag can start over a button without activating it when released.
var pointer := -2
var origin := Vector2.ZERO
var start_scroll := 0
var horizontal := false
var dragging := false
var flick_velocity := 0.0
var last_motion_ms := 0
var last_scroll_value := 0.0
var buttons: Dictionary = {}

func cancel_gesture() -> void:
	for button in buttons:
		if is_instance_valid(button): button.disabled = buttons[button]
	buttons.clear()
	pointer = -2
	dragging = false

func _process(delta: float) -> void:
	if not is_visible_in_tree(): flick_velocity = 0.0
	if pointer == -2 and absf(flick_velocity) > 8.0:
		var bar: ScrollBar = get_v_scroll_bar()
		if horizontal: bar = get_h_scroll_bar()
		bar.value += flick_velocity * delta
		flick_velocity *= exp(-6.0 * delta)
	# Native/embedded popups consume releases before this viewport sees them.
	if pointer == -2: return
	if not is_visible_in_tree() or (pointer == -1 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		cancel_gesture()
	for button in find_children("*", "BaseButton", true, false):
		if (button is OptionButton or button is MenuButton) and button.get_popup().visible:
			cancel_gesture()
			return

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		for button in buttons:
			if is_instance_valid(button): button.disabled = buttons[button]
		buttons.clear()
		pointer = -2
		dragging = false
		return
	var pos := Vector2.ZERO
	var id := -1
	var down := false
	var up := false
	var motion := false
	if event is InputEventScreenTouch:
		pos = event.position
		id = event.index
		down = event.pressed
		up = not down
	elif event is InputEventScreenDrag:
		pos = event.position
		id = event.index
		motion = true
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		down = event.pressed
		up = not down
	elif event is InputEventMouseMotion and event.device != -1:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			cancel_gesture()
			return
		pos = event.position
		motion = true
	else: return
	if down and get_v_scroll_bar().get_global_rect().grow(8).has_point(pos): return
	if down:
		for button in find_children("*", "BaseButton", true, false):
			if (button is OptionButton or button is MenuButton) and button.is_visible_in_tree() and (button.get_popup().visible or button.get_global_rect().has_point(pos)):
				cancel_gesture()
				return
	if down and get_global_rect().has_point(pos) and pointer == -2:
		pointer = id
		flick_velocity = 0.0
		last_motion_ms = Time.get_ticks_msec()
		origin = pos
		horizontal = vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		start_scroll = scroll_horizontal if horizontal else scroll_vertical
		last_scroll_value = start_scroll
		dragging = false
		buttons.clear()
		for button in find_children("*", "BaseButton", true, false):
			buttons[button] = button.disabled
	if pointer != id: return
	var distance := origin.x - pos.x if horizontal else origin.y - pos.y
	if motion and (dragging or absf(distance) > 12):
		dragging = true
		var now := Time.get_ticks_msec()
		var value := float(start_scroll) + distance
		if last_motion_ms > 0: flick_velocity = clampf((value - last_scroll_value) / maxf(0.016, (now - last_motion_ms) / 1000.0), -2400, 2400)
		last_motion_ms = now
		last_scroll_value = value
		if horizontal: scroll_horizontal = start_scroll + roundi(distance)
		else: scroll_vertical = start_scroll + roundi(distance)
		for button in buttons:
			if is_instance_valid(button): button.disabled = true
		get_viewport().set_input_as_handled()
	if up:
		if Time.get_ticks_msec() - last_motion_ms > 100: flick_velocity = 0.0
		if dragging: get_viewport().set_input_as_handled()
		for button in buttons:
			if is_instance_valid(button): button.set_deferred("disabled", buttons[button])
		buttons.clear()
		pointer = -2
		dragging = false
