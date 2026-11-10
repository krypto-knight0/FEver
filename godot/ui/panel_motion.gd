extends RefCounted
## Short, cancelable presentation tweens. Repeated refreshes keep their target.
var enabled := true
var speed := 1.0
var active: Dictionary = {}

func configure(value: bool, multiplier: float = 1.0) -> void:
	enabled = value
	speed = maxf(0.1, multiplier)

func present(control: Control, showing: bool, edge: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(control): return
	var id := control.get_instance_id()
	var previous: Dictionary = active.get(id, {})
	if not showing and not control.visible:
		if previous.has("tween") and previous.tween.is_valid(): previous.tween.kill()
		control.modulate.a = 1.0
		control.scale = Vector2.ONE
		active[id] = {"showing": false, "origin": control.position}
		return
	if not enabled or not control.is_inside_tree():
		if previous.has("tween") and previous.tween.is_valid(): previous.tween.kill()
		control.modulate.a = 1.0
		control.scale = Vector2.ONE
		control.visible = showing
		active[id] = {"showing": showing, "origin": control.position}
		return
	if previous.get("showing", not showing) == showing and control.visible == showing: return
	if previous.get("showing", not showing) == showing and control.visible and previous.has("tween") and previous.tween.is_valid(): return
	if previous.has("tween") and previous.tween.is_valid(): previous.tween.kill()
	var origin: Vector2 = previous.get("origin", control.position)
	if previous.is_empty() or not previous.get("tween", null) or not previous.tween.is_valid(): origin = control.position
	control.position = origin
	control.scale = Vector2.ONE
	control.modulate.a = 1.0
	if showing and control.visible and previous.is_empty():
		active[id] = {"showing": true, "origin": origin}
		return
	control.pivot_offset = control.size * 0.5
	control.show()
	var tween := control.create_tween().set_parallel(true)
	active[id] = {"showing": showing, "origin": origin, "tween": tween}
	var duration := (0.15 if showing else 0.11) / speed
	if showing:
		control.modulate.a = 0.0
		control.position = origin + edge * 30.0
		control.scale = Vector2.ONE * (0.96 if edge == Vector2.ZERO else 1.0)
		tween.tween_property(control, "modulate:a", 1.0, duration)
		tween.tween_property(control, "position", origin, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(control, "modulate:a", 0.0, duration)
		tween.tween_property(control, "position", origin + edge * 24.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(control, "scale", Vector2.ONE * (0.97 if edge == Vector2.ZERO else 1.0), duration)
		tween.chain().tween_callback(func():
			control.hide()
			control.position = origin
			control.scale = Vector2.ONE
			control.modulate.a = 1.0)

func forget(control: Control) -> void:
	var entry: Dictionary = active.get(control.get_instance_id(), {})
	if entry.has("tween") and entry.tween.is_valid(): entry.tween.kill()
	if entry.has("origin"): control.position = entry.origin
	control.modulate.a = 1.0
	control.scale = Vector2.ONE
	active.erase(control.get_instance_id())

func relocate(control: Control, destination: Vector2) -> void:
	# A layout update must not be overwritten by an older positional tween.
	var id := control.get_instance_id()
	var entry: Dictionary = active.get(id, {})
	if entry.has("origin") and Vector2(entry.origin).distance_to(destination) < 0.1:
		if entry.has("tween") and entry.tween.is_running(): return
	if entry.has("tween") and entry.tween.is_valid():
		entry.tween.kill()
		control.scale = Vector2.ONE
		control.modulate.a = 1.0
		if not entry.get("showing", true): control.hide()
	control.position = destination
	if not entry.is_empty(): active[id] = {"showing": entry.get("showing", control.visible), "origin": destination}

func cancel() -> void:
	for id in active.keys():
		var control = instance_from_id(id)
		if is_instance_valid(control) and control is Control: forget(control)
	active.clear()
