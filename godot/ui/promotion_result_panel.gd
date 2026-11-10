extends Control
## Presentation only: class changes and item consumption are already resolved.
const Styles = preload("res://ui/panel_style.gd")
const StatLabels = preload("res://ui/unit_stat_labels.gd")
const STAT_TITLES = [["max_hp", "HP"], ["str", "Strength"], ["magic", "Magic"], ["skill", "Skill"], ["speed", "Speed"], ["luck", "Luck"], ["def", "Defense"], ["res", "Resistance"], ["con", "Constitution"], ["mov", "Movement"]]
signal dismissed
signal sound_requested(name: String)

var animations_enabled := true
var panel: PanelContainer
var portrait: TextureRect
var identity: Label
var level_label: Label
var item_label: Label
var done_button: Button
var stat_rows: Dictionary = {}
var stat_titles: Dictionary = {}
var _portrait_path := ""
var _tween: Tween
var _closing := false
var _sequence := 0
var _unit: Dictionary = {}
var _outside_pointer := -2

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.06, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := Styles.create(false, 0.98)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := _label("CLASS CHANGE", 20, Color("ffe293"))
	content.add_child(title)
	identity = _label("", 28, Color("fff4d7"))
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(identity)
	level_label = _label("", 19, Color("dcecff"))
	content.add_child(level_label)
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 26)
	content.add_child(body)
	portrait = preload("res://ui/dialogue_unit_portrait.gd").new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	move_child(portrait, 1)
	item_label = _label("", 16, Color("dcecff"))
	item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(item_label)
	content.move_child(item_label, body.get_index())
	var stats := GridContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.columns = 4
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 3)
	body.add_child(stats)
	for heading in ["STAT", "BEFORE", "AFTER", "GAIN"]:
		var label := _label(heading, 14, Color("b7d7ff"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if heading == "STAT" else HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(label)
	for entry in STAT_TITLES:
		var name_label := _label(entry[1], 18, Color("eef4ff"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(name_label)
		stat_titles[entry[0]] = name_label
		var cells: Array[Label] = []
		for _index in range(3):
			var value := _label("", 18, Color("fff4d7"))
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stats.add_child(value)
			cells.append(value)
		stat_rows[entry[0]] = cells
	done_button = Button.new()
	done_button.text = "Done"
	done_button.custom_minimum_size.y = 48
	done_button.add_theme_font_size_override("font_size", 20)
	done_button.pressed.connect(dismiss)
	content.add_child(done_button)
	resized.connect(_layout)
	# Wrapped text settles after the nested game containers receive their width.
	# Refit on that final minimum-size change instead of retaining the temporary
	# one-character-per-line height from the first layout frame.
	panel.minimum_size_changed.connect(func(): _layout.call_deferred())
	hide()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func present(unit: Dictionary, result: Dictionary) -> void:
	_stop_tween()
	_sequence += 1
	_closing = false
	_outside_pointer = -2
	identity.text = "%s / %s" % [str(unit.get("name", "Unit")), str(result.get("class_name", unit.get("class_name", "Promoted class")))]
	level_label.text = "Level reset to %d · EXP %d" % [int(unit.get("level", 1)), int(unit.get("exp", 0))]
	var item_name := str(result.get("item_name", ""))
	item_label.text = "Promoted with " + item_name if not item_name.is_empty() else "Class promotion"
	_unit = unit.duplicate(true)
	_portrait_path = str(unit.get("portrait", ""))
	refresh_art()
	var before: Dictionary = result.get("before_stats", {})
	var after: Dictionary = result.get("after_stats", {})
	var gains: Dictionary = result.get("stat_gains", {})
	for entry in STAT_TITLES:
		var key: String = entry[0]
		var gain := int(gains.get(key, 0))
		var current := int(after.get(key, unit.get(key, 0)))
		var cells: Array = stat_rows[key]
		var shown: bool = key not in ["str", "magic"] or key == StatLabels.power_key(unit)
		if key in ["str", "magic"]: stat_titles[key].text = StatLabels.power(unit)
		stat_titles[key].visible = shown
		for cell in cells: cell.visible = shown
		cells[0].text = str(int(before.get(key, current - gain)))
		cells[1].text = str(current)
		cells[1].modulate.a = 0.0 if animations_enabled else 1.0
		cells[2].modulate.a = 0.0 if animations_enabled else 1.0
		cells[2].text = ("+%d" % gain) if gain > 0 else (str(gain) if gain < 0 else "—")
		var color := Color("ffe37c") if gain > 0 else (Color("ffb1a3") if gain < 0 else Color("aac4e7"))
		cells[2].add_theme_color_override("font_color", color)
		cells[2].add_theme_color_override("font_shadow_color", Color(1.0, 0.62, 0.08, 0.5) if gain > 0 else Color.TRANSPARENT)
		cells[2].add_theme_constant_override("shadow_offset_x", 0)
		cells[2].add_theme_constant_override("shadow_offset_y", 0)
		cells[2].add_theme_constant_override("shadow_outline_size", 3 if gain > 0 else 0)
	show()
	_layout()
	_layout.call_deferred()
	modulate.a = 1.0
	panel.scale = Vector2.ONE
	if animations_enabled:
		modulate.a = 0.0
		panel.scale = Vector2.ONE * 0.97
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "modulate:a", 1.0, 0.15)
		_tween.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	done_button.disabled = animations_enabled
	if animations_enabled: _reveal_stats(_sequence)
	else: done_button.grab_focus()

func _reveal_stats(token: int) -> void:
	await get_tree().create_timer(0.45, true, false, true).timeout
	for entry in STAT_TITLES:
		if token != _sequence or not visible: return
		var cells: Array = stat_rows[entry[0]]
		if not cells[0].visible: continue
		cells[1].modulate.a = 1.0
		cells[2].modulate.a = 1.0
		if cells[2].text.begins_with("+"):
			sound_requested.emit("stat_up")
			await get_tree().create_timer(StatLabels.STAT_REVEAL_DELAY, true, false, true).timeout
	if token != _sequence or not visible: return
	done_button.disabled = false
	done_button.grab_focus()

func refresh_art() -> void:
	portrait.present(_unit)

func _layout() -> void:
	if not panel: return
	panel.custom_minimum_size.x = minf(700, maxf(540, size.x - 360))
	panel.size = Vector2(panel.custom_minimum_size.x, panel.get_combined_minimum_size().y)
	panel.position = Vector2(maxf(16, size.x - panel.size.x - 20), (size.y - panel.size.y) * 0.5)
	panel.pivot_offset = panel.size * 0.5

func dismiss() -> void:
	if not visible or _closing or done_button.disabled: return
	_stop_tween()
	_closing = true
	_outside_pointer = -2
	if animations_enabled:
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "modulate:a", 0.0, 0.11)
		_tween.tween_property(panel, "scale", Vector2.ONE * 0.98, 0.11)
		_tween.chain().tween_callback(_finish_dismiss)
	else:
		_finish_dismiss()

func _finish_dismiss() -> void:
	hide()
	_closing = false
	modulate.a = 1.0
	panel.scale = Vector2.ONE
	dismissed.emit()

func cancel() -> void:
	# Chapter changes can dismiss presentation without continuing an old action.
	_stop_tween()
	_sequence += 1
	_closing = false
	_outside_pointer = -2
	hide()
	modulate.a = 1.0
	if panel: panel.scale = Vector2.ONE

func _stop_tween() -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	_tween = null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == -1: return
	var pointer := -2
	var pressed := false
	var at := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = -1; pressed = event.pressed; at = event.position
	elif event is InputEventScreenTouch:
		if event.canceled:
			_outside_pointer = -2
			return
		pointer = event.index; pressed = event.pressed; at = event.position
	else: return
	if pressed: _outside_pointer = pointer if not panel.get_rect().has_point(at) else -2
	elif pointer == _outside_pointer:
		_outside_pointer = -2
		if not panel.get_rect().has_point(at): dismiss()
	accept_event()
