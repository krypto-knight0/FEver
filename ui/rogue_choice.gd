extends Control
signal chosen
const Rogue = preload("res://engine/rogue_mode.gd")
var state
var heading: Label
var cards: HBoxContainer
var targets: ScrollContainer
var second: ScrollContainer
var weapons: OptionButton
var confirm: Button
var selected := ""
var description: Label
var remembered_target := ""
var remembered_second := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color.WHITE
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://ui/soft_blur.gdshader")
	shade.material = blur
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var outer := VBoxContainer.new()
	margin.add_child(outer)
	var scroll := preload("res://ui/swipe_scroll.gd").new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	scroll.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	description = Label.new()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	cards.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(cards)
	targets = preload("res://ui/portrait_picker.gd").new(); second = preload("res://ui/portrait_picker.gd").new(); weapons = OptionButton.new()
	for picker in [targets, second, weapons]:
		picker.custom_minimum_size.y = 100 if picker != weapons else 48
		column.add_child(picker)
		picker.item_selected.connect(func(_index): _refresh_target())
	confirm = Button.new()
	confirm.text = "Select Upgrade"
	confirm.custom_minimum_size.y = 54
	confirm.pressed.connect(_confirm)
	outer.add_child(confirm)
	hide()

func present(battle) -> void:
	state = battle
	selected = ""
	remembered_target = ""
	remembered_second = ""
	heading.text = "Select Upgrade"
	description.hide()
	for child in cards.get_children(): cards.remove_child(child); child.queue_free()
	for skill in Rogue.offer(state):
		var card := Button.new()
		card.custom_minimum_size = Vector2(210, 290)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.text = ""
		card.set_meta("skill", skill)
		card.add_theme_stylebox_override("normal", preload("res://ui/panel_style.gd").create(false, 0.95))
		var gold := StyleBoxFlat.new()
		gold.bg_color = Color("e9b936")
		gold.border_color = Color("fff0a0")
		gold.set_border_width_all(3)
		gold.set_corner_radius_all(5)
		for style in ["pressed", "hover_pressed"]: card.add_theme_stylebox_override(style, gold)
		# Focus is painted over the pressed style. Keep its center transparent
		# so a tap/focused selection cannot cover the gold with the app's blue.
		var focus := gold.duplicate()
		focus.draw_center = false
		card.add_theme_stylebox_override("focus", focus)
		cards.add_child(card)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		content.offset_left = 18; content.offset_right = -18; content.offset_top = 24; content.offset_bottom = -24
		content.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(content)
		var name_label := Label.new()
		name_label.text = Rogue.title(skill)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 24)
		name_label.add_theme_color_override("font_color", Color("f2d28a"))
		content.add_child(name_label)
		var body := Label.new()
		body.text = (Rogue.ARMY_TEXT if Rogue.is_army_offer(state) else Rogue.UNIT_TEXT)[skill]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_vertical = SIZE_EXPAND_FILL
		body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_theme_font_size_override("font_size", 19)
		content.add_child(body)
		card.toggled.connect(func(pressed):
			name_label.add_theme_color_override("font_color", Color("172a59") if pressed else Color("f2d28a"))
			body.add_theme_color_override("font_color", Color("172a59") if pressed else Color("fff4d7")))
		for label in [name_label, body]: label.mouse_filter = MOUSE_FILTER_IGNORE
		card.pressed.connect(func(): _select(skill))
	targets.hide(); second.hide(); weapons.hide(); confirm.disabled = true
	show()
	cards.get_child(0).grab_focus()

func _select(skill: String) -> void:
	if targets.visible and targets.selected >= 0: remembered_target = str(targets.get_item_metadata(targets.selected))
	if second.visible and second.selected >= 0: remembered_second = str(second.get_item_metadata(second.selected))
	selected = skill
	for card in cards.get_children():
		var active: bool = card.get_meta("skill") == skill
		card.set_pressed_no_signal(active)
		card.toggled.emit(active)
	var targeted := skill != "reroll" and (not Rogue.is_army_offer(state) or skill in ["alternate_reality", "welcome_to_the_team", "identity_theft"])
	targets.visible = targeted; second.visible = skill == "identity_theft"; weapons.visible = skill == "cross_training"
	for picker in [targets, second]:
		picker.clear()
		var units: Array = Rogue.candidates(state, skill)
		units.sort_custom(func(a, b):
			var recent_a := int(a.get("last_deployed", int(state.chapter.rogue.get("completed", 0)) - 1 if not a.get("benched", false) else -1))
			var recent_b := int(b.get("last_deployed", int(state.chapter.rogue.get("completed", 0)) - 1 if not b.get("benched", false) else -1))
			if recent_a != recent_b: return recent_a > recent_b
			if Rogue.effective_level(a) != Rogue.effective_level(b): return Rogue.effective_level(a) > Rogue.effective_level(b)
			return str(a.id) < str(b.id))
		for unit in units:
			var stacks := Rogue.count(unit, skill)
			picker.add_unit(unit, str(unit.name) + (" · %d owned" % stacks if stacks > 0 else ""))
		var previous := remembered_target if picker == targets else remembered_second
		var retained: int = picker.entries.find(previous)
		if retained >= 0: picker.select(retained)
	if second.item_count > 1 and second.selected == targets.selected: second.select(1 if targets.selected == 0 else 0)
	_refresh_target()

func _refresh_target() -> void:
	if selected == "cross_training":
		var selected_type := str(weapons.get_item_metadata(weapons.selected)) if weapons.selected >= 0 else ""
		weapons.clear()
		var unit: Dictionary = state.get_unit(str(targets.get_item_metadata(targets.selected)))
		for kind in Rogue.TYPES:
			if int(unit.get("weapon_exp", {}).get(kind, 0)) > 0: continue
			weapons.add_item(kind.capitalize()); weapons.set_item_metadata(weapons.item_count-1, kind)
			if kind == selected_type: weapons.select(weapons.item_count-1)
	confirm.disabled = selected.is_empty() or (targets.visible and targets.selected < 0) or (second.visible and second.selected == targets.selected)
	confirm.text = "Reroll these cards" if selected == "reroll" else "Select Upgrade"

func _confirm() -> void:
	if confirm.disabled: return
	var id := str(targets.get_item_metadata(targets.selected)) if targets.visible and targets.selected >= 0 else ""
	var other := str(second.get_item_metadata(second.selected)) if second.visible and second.selected >= 0 else ""
	var kind := str(weapons.get_item_metadata(weapons.selected)) if weapons.visible and weapons.selected >= 0 else ""
	if not Rogue.choose(state, selected, id, other, kind): return
	if selected == "reroll": present(state)
	else: hide()
	chosen.emit()
