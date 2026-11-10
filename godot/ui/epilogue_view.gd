extends ColorRect
signal advanced(index: int)
signal finished
const Labels = preload("res://ui/unit_stat_labels.gd")
const Skills = preload("res://ui/skill_icons.gd")
const Rogue = preload("res://engine/rogue_mode.gd")
var pages: Array = []
var game_title := "FE7"
var completion_page := true
var background_texture: Texture2D
var index := 0
var heading: Label
var body: Label
var portraits: Array = []
var summaries: Array = []
var next: Button
var previous: Button
var skip: Button
var count: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("0c1427")
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = background_texture if background_texture != null else load("res://art/branding/start.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	heading = Label.new(); heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("efce86")); column.add_child(heading)
	var row := HBoxContainer.new(); row.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(row)
	row.add_theme_constant_override("separation", 20)
	var faces := VBoxContainer.new(); faces.size_flags_horizontal = Control.SIZE_EXPAND_FILL; faces.size_flags_stretch_ratio = 0.8; row.add_child(faces)
	for side in range(2):
		var portrait := preload("res://ui/dialogue_unit_portrait.gd").new()
		portrait.fit_to_frame = true
		portrait.left_side = side == 0
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		faces.add_child(portrait); portraits.append(portrait)
	var center := VBoxContainer.new(); center.size_flags_horizontal = Control.SIZE_EXPAND_FILL; center.size_flags_stretch_ratio = 1.3; row.add_child(center)
	var top := Control.new(); top.size_flags_vertical = Control.SIZE_EXPAND_FILL; center.add_child(top)
	var story := PanelContainer.new(); story.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.92)); center.add_child(story)
	body = Label.new(); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_theme_font_size_override("font_size", 21); story.add_child(body)
	var bottom := Control.new(); bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL; center.add_child(bottom)
	var scroll := preload("res://ui/swipe_scroll.gd").new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var stats := VBoxContainer.new(); stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(stats)
	for side in range(2):
		var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.92)); stats.add_child(panel)
		var fields := VBoxContainer.new(); panel.add_child(fields); summaries.append(fields)
	var buttons := HBoxContainer.new(); column.add_child(buttons)
	previous = _button(buttons, "Previous", func(): navigate(index - 1))
	count = Label.new(); count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; buttons.add_child(count)
	skip = _button(buttons, "Skip all", func():
		if completion_page: navigate(pages.size())
		finished.emit())
	next = _button(buttons, "Continue", func():
		if index >= pages.size(): finished.emit()
		else: navigate(index + 1))

func _stats(fields: VBoxContainer, unit: Dictionary) -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	var title := Label.new(); title.text = "%s · Lv %d\n%s" % [unit.get("name", "Unit"), int(unit.get("level", 1)), unit.get("class_name", "")]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; title.add_theme_font_size_override("font_size", 20); fields.add_child(title)
	for entry in [["max_hp", "HP"], [Labels.power_key(unit), Labels.power(unit)], ["skill", "Skill"], ["speed", "Speed"], ["luck", "Luck"], ["def", "Defense"], ["res", "Resistance"], ["mov", "Movement"], ["con", "Constitution"]]:
		var amount := int(unit.get(entry[0], 0)) + Rogue.permanent(unit, entry[0])
		var line := HBoxContainer.new(); fields.add_child(line)
		var label := Label.new(); label.text = str(entry[1]); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size", 16); line.add_child(label)
		var value := Label.new(); value.text = str(amount); value.add_theme_font_size_override("font_size", 16); line.add_child(value)
		var bar := ProgressBar.new(); bar.show_percentage = false; bar.max_value = maxi(amount, int(unit.get("stat_caps", {}).get(entry[0], 60 if entry[0] == "max_hp" else 30))); bar.value = amount; bar.custom_minimum_size.y = 6
		var fill := StyleBoxFlat.new(); fill.bg_color = Color("68c785"); bar.add_theme_stylebox_override("fill", fill)
		var track := StyleBoxFlat.new(); track.bg_color = Color("17223b"); bar.add_theme_stylebox_override("background", track); fields.add_child(bar)
	var skills := Skills.records(unit)
	if not skills.is_empty():
		var names: Array[String] = []
		for record in skills: names.append(str(record.name) + (" ×%d" % int(record.count) if int(record.count) > 1 else ""))
		var label := Label.new(); label.text = "Skills\n" + " · ".join(names); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_size_override("font_size", 16); fields.add_child(label)

func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new(); button.text = title
	button.custom_minimum_size = Vector2(130, 52)
	button.pressed.connect(action); parent.add_child(button)
	return button

func navigate(target: int) -> void:
	index = clampi(target, 0, pages.size())
	advanced.emit(index)
	if index == pages.size() and not completion_page:
		finished.emit(); return
	present()

static func unit_summary(unit: Dictionary) -> String:
	var text := "%s\n%s · Lv %d" % [unit.get("name", "Unit"), unit.get("class_name", ""), int(unit.get("level", 1))]
	var stats := [["max_hp", "HP"], [Labels.power_key(unit), Labels.power(unit, true)], ["skill", "Skill"], ["speed", "Spd"], ["luck", "Luck"], ["def", "Def"], ["res", "Res"]]
	var values: Array[String] = []
	for entry in stats: values.append("%s %d" % [entry[1], int(unit.get(entry[0], 0)) + Rogue.permanent(unit, entry[0])])
	for i in range(0, values.size(), 2): text += "\n" + " · ".join(values.slice(i,i+2))
	text += "\nMov %d · Con %d" % [int(unit.get("mov", 0)) + Rogue.permanent(unit, "mov"), int(unit.get("con", 0)) + Rogue.permanent(unit, "con")]
	var skills := Skills.records(unit)
	if not skills.is_empty():
		var names: Array[String] = []
		for record in skills: names.append(str(record.name) + (" ×%d" % int(record.count) if int(record.count) > 1 else ""))
		text += "\n\nSkills\n" + " · ".join(names)
	return text

func present() -> void:
	if not summaries.is_empty(): summaries[0].get_parent().get_parent().get_parent().scroll_vertical = 0
	var ending := index >= pages.size()
	var page: Dictionary = {} if ending else pages[index]
	heading.text = "The End" if ending else str(page.title)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if ending else HORIZONTAL_ALIGNMENT_LEFT
	body.text = str(ProjectSettings.get_setting("application/config/name")) + "\n" + game_title + "\n\nYour journey is complete." if ending else str(page.text)
	count.text = "" if ending else "%d / %d" % [index + 1, pages.size()]
	next.text = "Return to title" if ending else "Continue"
	previous.disabled = index <= 0
	var members: Array = page.get("units", [])
	portraits[0].get_parent().visible = not members.is_empty()
	summaries[0].get_parent().get_parent().get_parent().visible = not members.is_empty()
	body.add_theme_font_size_override("font_size",18 if page.has("ranking") else 21)
	for side in range(2):
		portraits[side].visible = side < members.size()
		summaries[side].get_parent().visible = side < members.size()
		if side >= members.size(): continue
		portraits[side].present(members[side])
		_stats(summaries[side], members[side])
