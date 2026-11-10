extends Control
signal selected(route: String)
signal cancelled
var heading: Label
var description: Label
var buttons: Dictionary = {}
var cancel_button: Button
var choosing := false
var difficulty_picker: OptionButton
var difficulty_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.06, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 460
	panel.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.98))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	heading = Label.new()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	description = Label.new()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(description)
	difficulty_label = Label.new()
	difficulty_label.text = "Difficulty"
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(difficulty_label)
	difficulty_picker = OptionButton.new()
	for label in preload("res://engine/campaign_difficulty.gd").LABELS: difficulty_picker.add_item(label)
	difficulty_picker.custom_minimum_size.y = 48
	column.add_child(difficulty_picker)
	for route in ["fe7_unit_3", "fe7_unit_1", "fe7_unit_2", "fe6_unit_1"]:
		var button := Button.new()
		button.text = "Story"
		button.custom_minimum_size.y = 58
		button.pressed.connect(func():
			if not choosing: return
			choosing = false
			hide()
			selected.emit(route))
		buttons[route] = button
		column.add_child(button)
	cancel_button = Button.new()
	cancel_button.text = "Back"
	cancel_button.custom_minimum_size.y = 48
	cancel_button.pressed.connect(func(): choosing = false; hide(); cancelled.emit())
	column.add_child(cancel_button)
	hide()

func present(after_tutorial: bool, game: String = "fe7") -> void:
	var fe6 := game == "fe6"
	heading.text = "Choose difficulty" if fe6 else ("Choose the next story" if after_tutorial else "Choose a starting story")
	description.text = "Begin the campaign." if fe6 else ("Returning allies keep their progress." if after_tutorial else "Start from the beginning of any campaign.")
	var assets = preload("res://runtime/rom_assets.gd")
	var dynamic_manifest: Dictionary = assets.dynamic_content.manifest if assets.dynamic_content != null and assets.game_id == game else {}
	for index in range(difficulty_picker.item_count):
		var supported: Array = dynamic_manifest.get("supported_difficulties",preload("res://engine/campaign_difficulty.gd").MODES)
		difficulty_picker.set_item_disabled(index,preload("res://engine/campaign_difficulty.gd").MODES[index] not in supported)
	for route in buttons:
		buttons[route].text = "Story"
		if assets.initialized() and assets.game_id == game and (route == "fe6_unit_1") == fe6:
			buttons[route].text = preload("res://runtime/rom_names.gd").character(assets.decoder,game,{"fe7_unit_3":3,"fe7_unit_1":1,"fe7_unit_2":2,"fe6_unit_1":1}[route]) + "’s story"
		buttons[route].visible = (route == "fe6_unit_1") if fe6 else (route != "fe6_unit_1" and (route != "fe7_unit_3" or not after_tutorial))
		if dynamic_manifest.has("campaign_starts"):
			buttons[route].visible = buttons[route].visible and dynamic_manifest.campaign_starts.has(route)
	cancel_button.visible = not after_tutorial
	difficulty_picker.visible = not after_tutorial
	difficulty_label.visible = not after_tutorial
	difficulty_picker.select(0)
	choosing = true
	show()
	buttons["fe6_unit_1" if fe6 else ("fe7_unit_1" if after_tutorial else "fe7_unit_3")].grab_focus()
