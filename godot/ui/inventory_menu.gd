extends ColorRect
const Art = preload("res://runtime/art_textures.gd")
## The original inventory composition, with native readable text and touch targets.
signal action_requested(action: String)
signal selection_changed
signal sound_requested(cue: String)
const PanelMotion = preload("res://ui/panel_motion.gd")
const PanelStyle = preload("res://ui/panel_style.gd")
var animations_enabled := true
var transition_speed := 1.0
var motion = PanelMotion.new()
var item_list: ItemList
var heading: Label
var target: OptionButton
var message: Label
var details: Label
var range_label: Label
var description: Label
var weapon_stats: GridContainer
var stat_values: Array[Label] = []
var portrait: TextureRect
var equipped: Button
var use_button: Button
var equip_button: Button
var list_panel: PanelContainer
var detail_panel: PanelContainer
var read_only := false
var unit: Dictionary = {}
var battle: RefCounted
var equipped_selected := false
var last_item_tap := -1
var last_item_tap_ms := -1000
var item_pointer := -1
var pointer_item := -1
var pointer_origin := Vector2.ZERO
var pointer_canceled := false
var scroll_origin := 0.0
var scroll_last := 0.0
var flick_velocity := 0.0
var last_motion_ms := 0
var outside_pointer := -1
var outside_origin := Vector2.ZERO
var outside_canceled := false
var actor_screen := Vector2.ZERO
var top_clearance := 110.0
var bottom_clearance := 110.0
var placement_obstacles: Array = []
var placement_locked := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.01, 0.02, 0.05, 0.22)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_outside_input)
	list_panel = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	list_panel.add_child(column)
	# Kept as hidden compatibility references for the controller's art refresh.
	heading = Label.new()
	heading.hide()
	add_child(heading)
	portrait = TextureRect.new()
	portrait.hide()
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(portrait)
	equipped = Button.new()
	equipped.alignment = HORIZONTAL_ALIGNMENT_LEFT
	equipped.custom_minimum_size.y = 40
	equipped.add_theme_font_size_override("font_size", 20)
	equipped.pressed.connect(_select_equipped)
	column.add_child(equipped)
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(340, 40)
	item_list.add_theme_font_size_override("font_size", 20)
	item_list.add_theme_constant_override("v_separation", 6)
	item_list.fixed_icon_size = Vector2i(26, 26)
	item_list.texture_filter = TEXTURE_FILTER_NEAREST
	item_list.item_selected.connect(_item_selected)
	# Activation still requires two complete tap/release gestures.
	item_list.gui_input.connect(_item_pointer_input)
	column.add_child(item_list)
	detail_panel = PanelContainer.new()
	var detail_style := PanelStyle.create(false, 0.58)
	detail_style.content_margin_top = 8
	detail_style.content_margin_bottom = 8
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	column.add_child(detail_panel)
	var detail_column := VBoxContainer.new()
	detail_panel.add_child(detail_column)
	details = Label.new()
	details.add_theme_font_size_override("font_size", 19)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.y = 70
	var item_header := HBoxContainer.new()
	detail_column.add_child(item_header)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_header.add_child(details)
	range_label = Label.new()
	range_label.add_theme_font_size_override("font_size", 19)
	item_header.add_child(range_label)
	weapon_stats = GridContainer.new()
	weapon_stats.columns = 2
	weapon_stats.add_theme_constant_override("h_separation", 26)
	detail_column.add_child(weapon_stats)
	for i in range(5):
		var value := Label.new()
		value.custom_minimum_size.x = 130
		value.add_theme_font_size_override("font_size", 19)
		weapon_stats.add_child(value)
		stat_values.append(value)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 17)
	detail_column.add_child(description)
	target = OptionButton.new()
	target.custom_minimum_size.y = 40
	detail_column.add_child(target)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 17)
	detail_column.add_child(message)
	var row := HBoxContainer.new()
	column.add_child(row)
	use_button = _button(row, "Use", func(): action_requested.emit("use"))
	equip_button = _button(row, "Equip", func(): action_requested.emit("equip"))
	_button(row, "Close", dismiss)
	resized.connect(_layout)
	list_panel.minimum_size_changed.connect(func(): call_deferred("_layout"))
	hide()

func configure_placement(actor_position: Vector2, top_margin: float = 110.0, bottom_margin: float = 110.0, avoid_rects: Array = []) -> void:
	actor_screen = actor_position
	top_clearance = top_margin
	bottom_clearance = bottom_margin
	placement_obstacles = avoid_rects.duplicate()
	_layout()
	placement_locked = true

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := PanelStyle.create(false, 0.88)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 8)
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(94, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func present(value: Dictionary, state: RefCounted = null) -> void:
	if not visible or value.get("id", "") != unit.get("id", ""): placement_locked = false
	unit = value
	battle = state
	equip_button.disabled = read_only or unit.get("acted", false)
	heading.text = str(unit.get("name", "Inventory"))
	var weapon: Dictionary = unit.get("weapon", {})
	equipped.text = "◆ %s       %d" % [weapon.get("name", "Unarmed"), int(weapon.get("uses", 0))]
	equipped.icon = _icon(weapon)
	equipped.expand_icon = true
	equipped.add_theme_constant_override("icon_max_width", 32)
	equipped.visible = not weapon.is_empty()
	item_list.clear()
	for item in unit.get("inventory", []):
		item_list.add_item("%s       %d" % [item.get("name", "Item"), int(item.get("uses", 0))], _icon(item))
	item_list.custom_minimum_size.y = clampf(item_list.item_count * 34 + 10, 44, 214)
	equipped_selected = item_list.item_count == 0
	if item_list.item_count > 0: item_list.select(0)
	var path := str(unit.get("portrait", ""))
	portrait.set_meta("art_path", path)
	portrait.texture = Art.texture(path) if ResourceLoader.exists(path) else null
	message.text = ""
	_reset_gestures()
	_describe()
	_layout()
	motion.configure(animations_enabled, transition_speed)
	motion.present(self, true)

func dismiss() -> void:
	_reset_gestures()
	motion.configure(animations_enabled, transition_speed)
	motion.present(self, false)

func _reset_gestures() -> void:
	last_item_tap = -1
	item_pointer = -1
	pointer_item = -1
	outside_pointer = -1

func _select_equipped(play_sound: bool = true) -> void:
	if play_sound: sound_requested.emit("item_select")
	_reset_gestures()
	equipped_selected = true
	item_list.deselect_all()
	message.text = ""
	_describe()

func show_equipped_confirmation() -> void:
	_select_equipped(false)
	message.text = "Weapon equipped."

func _item_selected(index: int) -> void:
	sound_requested.emit("item_select")
	equipped_selected = false
	message.text = ""
	if last_item_tap != index: last_item_tap = -1
	_describe()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): flick_velocity = 0.0
	if item_pointer == -1 and absf(flick_velocity) > 8:
		item_list.get_v_scroll_bar().value += flick_velocity * delta
		flick_velocity *= exp(-6.0 * delta)

func _input(event: InputEvent) -> void:
	if not visible: return
	# Clicking a different part of the menu breaks the double-click sequence,
	# even when that child consumes its own GUI input before it reaches us.
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1):
		if event.pressed and not item_list.get_global_rect().has_point(event.position): last_item_tap = -1

func _item_pointer_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		var selected := item_list.get_selected_items()
		if not selected.is_empty(): _activate_item(selected[0])
		last_item_tap = -1
		item_list.accept_event()
		return
	if event is InputEventMouseButton and event.device == -1:
		item_list.accept_event()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		last_item_tap = -1
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		if item_pointer == -1: return
		if event is InputEventScreenDrag and event.index != item_pointer: return
		if event.position.distance_to(pointer_origin) >= 18.0 or item_list.get_item_at_position(event.position, true) != pointer_item:
			pointer_canceled = true
			last_item_tap = -1
			var now := Time.get_ticks_msec()
			var value: float = scroll_origin + pointer_origin.y - event.position.y
			flick_velocity = clampf((value - scroll_last) / maxf(0.016, (now - last_motion_ms) / 1000.0), -2400, 2400)
			scroll_last = value
			last_motion_ms = now
			item_list.get_v_scroll_bar().value = value
		item_list.accept_event()
		return
	var pointer := -1
	if event is InputEventScreenTouch: pointer = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: pointer = -2
	else: return
	var index := item_list.get_item_at_position(event.position, true)
	if event.pressed:
		if item_pointer != -1:
			pointer_canceled = true
			last_item_tap = -1
		else:
			item_pointer = pointer
			pointer_item = index
			pointer_origin = event.position
			scroll_origin = item_list.get_v_scroll_bar().value
			scroll_last = scroll_origin
			flick_velocity = 0.0
			last_motion_ms = Time.get_ticks_msec()
			pointer_canceled = index < 0
			if index >= 0:
				item_list.select(index)
				_item_selected(index)
			else: last_item_tap = -1
	elif pointer == item_pointer:
		var complete: bool = not pointer_canceled and index >= 0 and index == pointer_item and event.position.distance_to(pointer_origin) < 18.0
		if Time.get_ticks_msec() - last_motion_ms > 100: flick_velocity = 0.0
		if event is InputEventScreenTouch and event.canceled:
			complete = false
			flick_velocity = 0.0
		item_pointer = -1
		pointer_item = -1
		if complete: _item_tapped(index)
		else: last_item_tap = -1
	item_list.accept_event()

func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device == -1:
		accept_event()
		return
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		if outside_pointer != -1 and (event.position.distance_to(outside_origin) >= 18.0 or _inside_panel(event.position)):
			outside_canceled = true
		return
	var pointer := -1
	if event is InputEventScreenTouch: pointer = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: pointer = -2
	else: return
	if event.pressed:
		last_item_tap = -1
		if outside_pointer == -1 and not _inside_panel(event.position):
			outside_pointer = pointer
			outside_origin = event.position
			outside_canceled = false
	elif pointer == outside_pointer:
		var close: bool = not outside_canceled and not _inside_panel(event.position) and event.position.distance_to(outside_origin) < 18.0
		if event is InputEventScreenTouch and event.canceled: close = false
		outside_pointer = -1
		if close: dismiss()
	accept_event()

func _inside_panel(point: Vector2) -> bool:
	return list_panel.get_rect().has_point(point)

func _item_tapped(index: int) -> void:
	if index < 0 or index >= item_list.item_count: return
	var now := Time.get_ticks_msec()
	if last_item_tap == index and now - last_item_tap_ms <= 380:
		last_item_tap = -1
		_activate_item(index)
	else:
		last_item_tap = index
		last_item_tap_ms = now

func _activate_item(index: int) -> void:
	if index < 0 or index >= item_list.item_count: return
	item_list.select(index)
	equipped_selected = false
	_describe()
	if equip_button.visible and not equip_button.disabled: action_requested.emit("equip")
	elif use_button.visible and not use_button.disabled: action_requested.emit("use")

func _icon(item: Dictionary) -> Texture2D:
	var path := str(item.get("icon", ""))
	return Art.texture(path) if not path.is_empty() and ResourceLoader.exists(path) else null

func _describe() -> void:
	var item: Dictionary = unit.get("weapon", {})
	if not equipped_selected:
		var selected := item_list.get_selected_items()
		if selected.is_empty(): return
		item = unit.get("inventory", [])[selected[0]]
	var weapon := item.has("might") and str(item.get("type", "")) != "staff"
	var promotion := str(item.get("kind", "")) == "promotion" or bool(item.get("promotion", false))
	range_label.text = "Range  " + preload("res://ui/item_description.gd").range_text(item) if weapon else ""
	description.text = str(item.get("description", "")) if weapon else ""
	description.visible = not description.text.is_empty()
	weapon_stats.visible = weapon
	details.custom_minimum_size.y = 0 if weapon else 70
	if weapon:
		var speed := maxi(0, int(unit.get("speed", 0)) - maxi(0, int(item.get("weight", 0)) - int(unit.get("con", 0))))
		if battle: speed = battle.attack_speed(unit, item)
		details.text = str(item.get("name", "")) + "\n" + preload("res://ui/item_description.gd").weapon_type(item)
		stat_values[0].text = "Atk  %d" % (int(unit.get("magic", unit.get("str", 0))) + int(item.get("might", 0)) if item.get("type", "") in ["anima", "light", "dark"] or item.get("magic_damage", false) else int(unit.get("str", 0)) + int(item.get("might", 0)))
		@warning_ignore("integer_division") # Intentional integer truncation.
		stat_values[1].text = "Crit  %d" % (int(unit.get("skill", 0)) / 2 + int(item.get("crit", 0)))
		@warning_ignore("integer_division") # Intentional integer truncation.
		stat_values[2].text = "Hit  %d" % (int(item.get("hit", 0)) + int(unit.get("skill", 0)) * 2 + int(unit.get("luck", 0)) / 2)
		stat_values[3].text = "Avoid  %d" % (speed * 2 + int(unit.get("luck", 0)))
		stat_values[4].text = "AS  %d" % speed
	else: details.text = (preload("res://ui/item_description.gd").weapon_type(item) + " · Range " + preload("res://ui/item_description.gd").range_text(item) + "\n" if item.get("type", "") == "staff" else "") + str(item.get("description", "Restores HP." if item.get("healing", 0) else "Choose a recipient to use this item."))
	if item.has("temporary_bonuses"):
		var effects: Array[String] = []
		var can_restore := false
		for key in item.temporary_bonuses:
			var current := int(unit.get("temporary_bonuses", {}).get(key, 0))
			var maximum := int(item.temporary_bonuses[key])
			effects.append("%s +%d (currently +%d)" % [str(key).capitalize(), maximum, current])
			can_restore = can_restore or current < maximum
		details.text = (preload("res://ui/item_description.gd").weapon_type(item) + " · Range " + preload("res://ui/item_description.gd").range_text(item) + "\n" if item.get("type", "") == "staff" else "") + "\n".join(effects) + "\nProtection decreases by 1 each player phase."
		use_button.disabled = not can_restore or int(item.get("uses", 0)) <= 0
	else: use_button.disabled = int(item.get("uses", 0)) <= 0
	if item.has("growth_boost"):
		details.text += "\nStat growth rates +%d percentage points. Once per unit." % int(item.growth_boost)
		use_button.disabled = use_button.disabled or unit.get("growth_boost_used",false)
	use_button.text = "Promote" if promotion else "Use"
	if item.get("kind", "") == "trap":
		details.text = "Place on an empty adjacent tile. " + ("Blocks all movement for three turns." if item.get("trap", "") == "light_rune" else "Deals 10 damage and ends the moving unit's action. Can be fatal. Fliers can cross safely but trigger it when acting on it. Thieves are immune; assassins can recover it.")
	if promotion:
		var minimum := int(item.get("minimum_level", 10))
		details.text += "\nRequires level %d and a compatible class." % minimum
		use_button.disabled = use_button.disabled or int(unit.get("level", 1)) < minimum
	use_button.visible = not weapon and not equipped_selected and item.get("kind", "") != "key"
	equip_button.visible = weapon and not equipped_selected
	target.visible = str(item.get("type", "")) == "staff" or item.has("ring_bonuses")
	if item.has("ring_bonuses"):
		var effects: Array[String] = []
		for key in item.ring_bonuses: effects.append("%s +%d" % [str(key).capitalize(), int(item.ring_bonuses[key])])
		details.text += "\n" + " · ".join(effects) + " until the next player phase."
		use_button.disabled = use_button.disabled or not unit.get("can_play", false)

	use_button.disabled = use_button.disabled or read_only or unit.get("acted", false)
	equip_button.disabled = equip_button.disabled or read_only or unit.get("acted", false)
	selection_changed.emit()

func _layout() -> void:
	if not list_panel: return
	message.visible = not message.text.is_empty()
	var width := minf(410, size.x - 28)
	list_panel.size = Vector2(width, 0)
	if placement_locked:
		# Item descriptions can change height. Keep the opening position unless
		# the panel needs to be brought back inside a resized viewport.
		list_panel.position = list_panel.position.clamp(Vector2(14, 14), Vector2(maxf(14, size.x - list_panel.size.x - 14), maxf(14, size.y - list_panel.size.y - 14)))
		return
	var available_top := minf(top_clearance, maxf(14, (size.y - list_panel.size.y) * 0.5))
	var available_bottom := maxf(available_top, size.y - bottom_clearance - list_panel.size.y)
	var left_side := actor_screen.x >= size.x * 0.5
	var center_y := clampf((size.y - list_panel.size.y) * 0.5, available_top, available_bottom)
	var preferred_x := 14.0 if left_side else maxf(14, size.x - list_panel.size.x - 14)
	var opposite_x := maxf(14, size.x - list_panel.size.x - 14) if left_side else 14.0
	var best := Vector2(preferred_x, center_y)
	var best_score := INF
	for side in range(2):
		var x := preferred_x if side == 0 else opposite_x
		var candidates: Array[float] = [center_y]
		for obstacle in placement_obstacles:
			if not obstacle is Rect2 or not obstacle.has_area(): continue
			var local := Rect2(obstacle.position - global_position, obstacle.size)
			if x + list_panel.size.x <= local.position.x or x >= local.end.x: continue
			candidates.append(local.end.y + 10)
			candidates.append(local.position.y - list_panel.size.y - 10)
		for candidate_y in candidates:
			var candidate := Vector2(x, clampf(candidate_y, 14, maxf(14, size.y - list_panel.size.y - 14)))
			var bounds := Rect2(candidate + global_position, list_panel.size)
			# Preserve the middle of the screen. On a short display the other
			# column is preferable to covering the selected-unit card.
			var score := absf(candidate.y - center_y) + side * 40.0
			for obstacle in placement_obstacles:
				if obstacle is Rect2 and bounds.intersects(obstacle.grow(8)):
					score += bounds.intersection(obstacle.grow(8)).get_area() * 1000.0
			if score < best_score:
				best_score = score
				best = candidate
	list_panel.position = best
