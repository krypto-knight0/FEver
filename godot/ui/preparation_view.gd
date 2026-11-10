extends ColorRect
## Preparation owns a clone. Only Begin battle commits the roster/formation.
signal confirmed
signal info_requested
var pointer_exclusion: Callable
var last_empty_tap := -1000
var last_empty_position := Vector2.ZERO
signal inspect_requested(unit_id: String)
signal unit_selected(unit: Dictionary)
var inspection_blocked: Callable
const Army = preload("res://engine/army_roster.gd")
const Art = preload("res://runtime/art_textures.gd")
var source: RefCounted
var selection: Array = []
var placements: Dictionary = {}
var map: Control
var sidebar: PanelContainer
var scroll: ScrollContainer
var roster: VBoxContainer
var message: Label
var start: Button
var cards: Dictionary = {}
var drag_id := ""
var pointer := -2
var origin := Vector2.ZERO
var dragging := false
var scrolling := false
var list_origin := false
var scroll_start := 0
var flick_velocity := 0.0
var last_motion_ms := 0
var last_scroll_value := 0.0
var ghost: TextureRect
var status_card: PanelContainer
var selected_id := ""
var camera_touches: Dictionary = {}
var camera_pointer := -2
var camera_last := Vector2.ZERO
var pinching := false

func _ready() -> void:
	color = Color.TRANSPARENT
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map = preload("res://ui/deployment_map.gd").new()
	map.focus_formation = false
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map)
	sidebar = PanelContainer.new()
	sidebar.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.91))
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_top = 230
	sidebar.offset_bottom = -16
	sidebar.offset_left = 10
	sidebar.offset_right = 250
	add_child(sidebar)
	var column := VBoxContainer.new()
	sidebar.add_child(column)
	var title := Label.new()
	title.text = "DEPLOY ARMY"
	column.add_child(title)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 16)
	column.add_child(message)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list_margin := MarginContainer.new()
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(list_margin)
	roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_child(roster)
	start = Button.new()
	start.text = "Begin battle"
	start.custom_minimum_size.y = 48
	start.pressed.connect(func(): confirmed.emit())
	column.add_child(start)
	ghost = preload("res://ui/unit_portrait.gd").new()
	ghost.size = Vector2(72, 72)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	ghost.hide()
	status_card = preload("res://ui/unit_status_panel.gd").new()
	add_child(status_card)
	status_card.mouse_filter = Control.MOUSE_FILTER_STOP
	status_card.unit_pressed.connect(func(id): inspect_requested.emit(id))
	status_card.hide()
	status_card.minimum_size_changed.connect(_place_status_card)
	resized.connect(_place_status_card)
	visibility_changed.connect(func():
		if not visible:
			pointer = -2; drag_id = ""; dragging = false; ghost.hide(); status_card.hide()
			camera_touches.clear(); camera_pointer = -2; pinching = false)

func present(state: RefCounted, data: Dictionary) -> void:
	source = state
	selected_id = ""
	status_card.hide()
	selection = Army.default_selection(state)
	placements.clear()
	map.placements.clear()
	map.configure(source, selection, data)
	placements = map.placements.duplicate()
	var center := 0.0
	for cell in placements.values(): center += cell.x
	center /= maxf(1, placements.size())
	var right_side: bool = center < source.width * 0.5
	sidebar.anchor_left = 1.0 if right_side else 0.0
	sidebar.anchor_right = sidebar.anchor_left
	sidebar.offset_left = -250 if right_side else 10
	sidebar.offset_right = -10 if right_side else 250
	_refresh()
	_place_status_card()
	show()

func _refresh() -> void:
	var camera_zoom: float = map.zoom
	var camera_pan: Vector2 = map.pan
	map.placements = placements.duplicate()
	map.configure(source, selection, map.map_data)
	map.zoom = camera_zoom
	map.pan = camera_pan
	map._view_updated()
	placements = map.placements.duplicate()
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	cards.clear()
	for unit in Army.all_units(source):
		if not Army.eligible(unit) or selection.has(str(unit.id)): continue
		var card := HBoxContainer.new()
		card.custom_minimum_size.y = 76
		roster.add_child(card)
		var face := preload("res://ui/unit_portrait.gd").new()
		face.custom_minimum_size = Vector2(65, 72)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(face)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.present(unit)
		var name_label := Label.new()
		name_label.text = "%s\nLv %d" % [unit.name, unit.level]
		name_label.add_theme_font_size_override("font_size", 16)
		card.add_child(name_label)
		cards[str(unit.id)] = card
	message.text = "%d / %d deployed" % [selection.size(), source.chapter.deployment.slots.size()]
	start.disabled = selection.is_empty()
	map.queue_redraw()
	if not selected_id.is_empty(): _select_unit(selected_id)

func _select_unit(id: String) -> void:
	if selected_id != id: unit_selected.emit(source.get_unit(id))
	selected_id = id
	map.selected_id = id
	var overlay: Dictionary = map.battle.range_overlay(id) if not id.is_empty() else {"movement": {}, "attack": []}
	map.reachable_cells = overlay.movement
	map.target_cells = overlay.attack
	status_card.present(source.get_unit(id))
	_place_status_card()
	map.queue_redraw()
	if has_node("/root/Diagnostics"): get_node("/root/Diagnostics").record("deploy_select", {"unit": id})

func _place_status_card() -> void:
	if not status_card: return
	status_card.size = status_card.get_combined_minimum_size()
	# Stack both panels along the same edge, leaving the spawn side clear.
	status_card.position = Vector2(size.x - status_card.size.x - 16 if sidebar.anchor_left == 1.0 else 16.0, 16)
	sidebar.offset_top = maxf(170, status_card.position.y + status_card.size.y + 10)
	sidebar.offset_bottom = -80

func apply_drop(id: String, cell: Vector2i, reserve_id: String = "") -> bool:
	if has_node("/root/Diagnostics"): get_node("/root/Diagnostics").record("deploy_drop", {"unit": id, "cell": [cell.x, cell.y], "reserve": reserve_id})
	if Army.forced_ids(source).has(id) or not Army.eligible(source.get_unit(id)): return false
	var selected := selection.has(id)
	# A reserve dropped anywhere on the map fills the nearest suitable free
	# deployment tile. Dropping on a deployment tile still explicitly swaps.
	if not selected and source.in_bounds(cell) and not source.chapter.deployment.slots.any(func(slot): return cell == Vector2i(slot.x, slot.y)):
		var free: Array = source.chapter.deployment.slots.filter(func(slot):
			var at := Vector2i(slot.x, slot.y)
			return not placements.values().has(at) and map.battle.unit_at(at).is_empty() and source.movement_cost(source.get_unit(id), at) > 0)
		free.sort_custom(func(a, b): return Vector2i(a.x,a.y).distance_squared_to(cell) < Vector2i(b.x,b.y).distance_squared_to(cell))
		if free.is_empty(): return false
		cell = Vector2i(free[0].x, free[0].y)
	if not reserve_id.is_empty() and selected and cards.has(reserve_id):
		var at: Vector2i = placements[id]
		if source.movement_cost(source.get_unit(reserve_id), at) <= 0: return false
		selection.erase(id); placements.erase(id)
		selection.append(reserve_id); placements[reserve_id] = at
	elif source.chapter.deployment.slots.any(func(slot): return cell == Vector2i(slot.x, slot.y)):
		if source.movement_cost(source.get_unit(id), cell) <= 0: return false
		var occupant := ""
		for other in placements:
			if placements[other] == cell: occupant = str(other); break
		if occupant == id: return false
		if Army.forced_ids(source).has(occupant): return false
		if not occupant.is_empty():
			if selected:
				if source.movement_cost(source.get_unit(occupant), placements[id]) <= 0: return false
				placements[occupant] = placements[id]
			else:
				selection.erase(occupant); placements.erase(occupant)
		if not selected: selection.append(id)
		placements[id] = cell
	elif selected:
		selection.erase(id); placements.erase(id)
	else: return false
	_refresh()
	return true

func _process(delta: float) -> void:
	if not is_visible_in_tree() or (inspection_blocked.is_valid() and inspection_blocked.call()):
		flick_velocity = 0.0
		return
	if pointer == -2 and absf(flick_velocity) > 8:
		scroll.get_v_scroll_bar().value += flick_velocity * delta
		flick_velocity *= exp(-6.0 * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == -1: return
	if not is_visible_in_tree() or not source: return
	if inspection_blocked.is_valid() and inspection_blocked.call(): return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and pointer_exclusion.is_valid() and pointer_exclusion.call(event.position): return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and _over_map(event.position) and map.battle.unit_at(map.cell_at(event.position - map.global_position)).is_empty():
		var now := Time.get_ticks_msec()
		if now - last_empty_tap < 350 and event.position.distance_to(last_empty_position) < 24:
			last_empty_tap = -1000
			camera_pointer = -2
			info_requested.emit()
			get_viewport().set_input_as_handled()
			return
		last_empty_tap = now
		last_empty_position = event.position
	if _camera_input(event):
		get_viewport().set_input_as_handled()
		return
	var point := Vector2.ZERO
	var id := -1
	var down := false
	var up := false
	var motion := false
	if event is InputEventScreenTouch:
		point = event.position; id = event.index; down = event.pressed; up = not down
	elif event is InputEventScreenDrag:
		point = event.position; id = event.index; motion = true
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position; down = event.pressed; up = not down
	elif event is InputEventMouseMotion and event.device != -1:
		point = event.position; motion = true
	else: return
	if down and pointer == -2:
		if start.get_global_rect().has_point(point) or (status_card.visible and status_card.get_global_rect().has_point(point)): return
		scrolling = false
		list_origin = scroll.get_global_rect().has_point(point)
		scroll_start = scroll.scroll_vertical
		last_scroll_value = scroll_start
		flick_velocity = 0.0
		last_motion_ms = Time.get_ticks_msec()
		drag_id = ""
		for unit_id in cards:
			if scroll.get_global_rect().has_point(point) and cards[unit_id].get_global_rect().has_point(point): drag_id = unit_id; break
		if drag_id.is_empty() and not sidebar.get_global_rect().has_point(point):
			drag_id = str(map.battle.unit_at(map.cell_at(point - map.global_position)).get("id", ""))
		_select_unit(drag_id)
		if Army.forced_ids(source).has(drag_id) or not Army.eligible(source.get_unit(drag_id)): drag_id = ""
		if drag_id.is_empty() and not list_origin: return
		pointer = id; origin = point; dragging = false
		var unit: Dictionary = source.get_unit(drag_id)
		ghost.present(unit)
	if pointer != id: return
	if motion:
		# A vertical swipe inside the reserve list scrolls; a horizontal drag
		# leaving it carries the portrait to the map.
		if scrolling or (list_origin and not dragging and absf(point.y - origin.y) > 10 and absf(point.y - origin.y) >= absf(point.x - origin.x)):
			scrolling = true
			var now := Time.get_ticks_msec()
			var value := float(scroll_start) + origin.y - point.y
			flick_velocity = clampf((value - last_scroll_value) / maxf(0.016, (now - last_motion_ms) / 1000.0), -2400, 2400)
			last_motion_ms = now
			last_scroll_value = value
			scroll.scroll_vertical = roundi(value)
		elif not drag_id.is_empty() and (dragging or (point.distance_to(origin) > 16 and (not list_origin or absf(point.x - origin.x) > absf(point.y - origin.y)))):
			dragging = true
			ghost.position = point - Vector2(36, 54); ghost.show()
	if up:
		if Time.get_ticks_msec() - last_motion_ms > 100 or (event is InputEventScreenTouch and event.canceled): flick_velocity = 0.0
		if dragging and not (event is InputEventScreenTouch and event.canceled):
			var reserve := ""
			for unit_id in cards:
				if scroll.get_global_rect().has_point(point) and cards[unit_id].get_global_rect().has_point(point): reserve = unit_id; break
			apply_drop(drag_id, map.cell_at(point - map.global_position) if not sidebar.get_global_rect().has_point(point) else Vector2i(-1,-1), reserve)
		ghost.hide(); drag_id = ""; pointer = -2; dragging = false; scrolling = false
	get_viewport().set_input_as_handled()

func _over_map(point: Vector2) -> bool:
	return get_global_rect().has_point(point) and not sidebar.get_global_rect().has_point(point) and not (status_card.visible and status_card.get_global_rect().has_point(point))

func _camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.device != -1 and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _over_map(event.position):
		map.change_zoom(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, event.position - map.global_position)
		return true
	var id := -1
	var point := Vector2.ZERO
	var down := false
	var up := false
	var motion := false
	if event is InputEventScreenTouch:
		id = event.index; point = event.position; down = event.pressed; up = not down
		if down and _over_map(point): camera_touches[id] = point
		if down and camera_touches.size() >= 2:
			pinching = true; camera_pointer = -2
			pointer = -2; drag_id = ""; dragging = false; ghost.hide()
		if pinching:
			if up: camera_touches.erase(id)
			if camera_touches.is_empty(): pinching = false
			return true
		if up: camera_touches.erase(id)
	elif event is InputEventScreenDrag:
		id = event.index; point = event.position; motion = true
		if camera_touches.has(id):
			var before := camera_touches.values()
			camera_touches[id] = point
			if pinching:
				var after := camera_touches.values()
				if before.size() >= 2:
					var old_center: Vector2 = (before[0] + before[1]) * 0.5
					var center: Vector2 = (after[0] + after[1]) * 0.5
					map.change_zoom(after[0].distance_to(after[1]) / maxf(1, before[0].distance_to(before[1])), old_center - map.global_position)
					map.pan += center - old_center
					map._view_updated()
				return true
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position; down = event.pressed; up = not down
	elif event is InputEventMouseMotion and event.device != -1:
		point = event.position; motion = true
	else: return false
	if down and _over_map(point):
		var unit: Dictionary = map.battle.unit_at(map.cell_at(point - map.global_position))
		if unit.is_empty() or not Army.eligible(unit) or Army.forced_ids(source).has(str(unit.get("id", ""))):
			camera_pointer = id; camera_last = point
			_select_unit(str(unit.get("id", "")))
			return true
	if camera_pointer != id: return false
	if motion:
		map.pan += point - camera_last
		camera_last = point
		map._view_updated()
	if up: camera_pointer = -2
	return true
