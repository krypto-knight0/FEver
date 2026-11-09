extends PanelContainer
## A content-independent preview; no combat rules or unit mutation live here.
var attacker: Dictionary = {}
var defender: Dictionary = {}
var forecast: Dictionary = {}
var forecast_label: RichTextLabel
var triangle_label: Label
var name_labels: Array[Label] = []
var weapon_labels: Array[Label] = []
var portraits: Array[TextureRect] = []
var stat_labels: Array = []
var stat_titles: Array[Label] = []

func _ready() -> void:
	custom_minimum_size = Vector2(320, 350)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("e8dda7")
	frame.border_color = Color("fff2bd")
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(5)
	frame.shadow_size = 3
	frame.shadow_color = Color(0.03, 0.02, 0.09, 0.65)
	frame.content_margin_left = 8
	frame.content_margin_right = 8
	frame.content_margin_top = 8
	frame.content_margin_bottom = 10
	add_theme_stylebox_override("panel", frame)
	var content := VBoxContainer.new()
	add_child(content)
	triangle_label = _label("Triangle Attack", 18, Color("66592c"))
	triangle_label.hide()
	content.add_child(triangle_label)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 5)
	content.add_child(columns)
	for side in range(3):
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		if side == 1:
			column.custom_minimum_size.x = 48
			columns.add_child(column)
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 197
			column.add_child(spacer)
			for title in ["HP", "Mt", "Hit", "Crit"]:
				var label := _label(title, 20, Color("66592c"))
				label.custom_minimum_size.y = 32
				stat_titles.append(label)
				column.add_child(label)
			continue
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tint := StyleBoxFlat.new()
		tint.bg_color = Color("355da9") if side == 0 else Color("a83d48")
		tint.content_margin_left = 5
		tint.content_margin_right = 5
		tint.content_margin_top = 5
		tint.content_margin_bottom = 5
		panel.add_theme_stylebox_override("panel", tint)
		columns.add_child(panel)
		panel.add_child(column)
		var name_label := _label("", 23)
		name_label.custom_minimum_size.y = 32
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_labels.append(name_label)
		column.add_child(name_label)
		var portrait := preload("res://ui/unit_portrait.gd").new()
		portrait.custom_minimum_size = Vector2(84, 110)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.flip_h = side == 0
		portraits.append(portrait)
		column.add_child(portrait)
		var weapon := _label("", 17)
		weapon.custom_minimum_size.y = 42
		weapon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		weapon_labels.append(weapon)
		column.add_child(weapon)
		var labels: Array[Label] = []
		for _stat in range(4):
			var label := _label("", 23)
			label.custom_minimum_size.y = 32
			labels.append(label)
			column.add_child(label)
		stat_labels.append(labels)
	forecast_label = RichTextLabel.new()
	forecast_label.hide()
	add_child(forecast_label)
	_ignore_children(self)

func _label(value: String, font_size: int, color: Color = Color("fff4d7")) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _ignore_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control: child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_children(child)

func present(first: Dictionary, second: Dictionary, preview: Dictionary) -> void:
	attacker = first.duplicate(true)
	defender = second.duplicate(true)
	forecast = preview.duplicate(true)
	if attacker.is_empty() or defender.is_empty() or forecast.is_empty():
		hide()
		return
	var summaries: Array[String] = []
	triangle_label.visible = bool(forecast.get("attacker", {}).get("triangle_attack", false))
	for side in range(2):
		var unit: Dictionary = attacker if side == 0 else defender
		var stats: Dictionary = forecast.get("attacker" if side == 0 else "defender", {})
		name_labels[side].text = str(unit.get("name", "Unit"))
		weapon_labels[side].text = str(unit.get("weapon", {}).get("name", "Unarmed"))
		portraits[side].present(unit)
		var can_attack: bool = stats.get("can_attack", false)
		stat_labels[side][0].text = "%d/%d" % [int(unit.get("hp", 0)), int(unit.get("max_hp", 0))]
		stat_labels[side][1].text = (str(stats.get("damage", 0)) + (" ×%d" % int(stats.get("strikes", 1)) if int(stats.get("strikes", 1)) > 1 else "")) if can_attack else "--"
		stat_labels[side][2].text = str(stats.get("hit", 0)) + "%" if can_attack else "--"
		stat_labels[side][3].text = str(stats.get("crit", 0)) + "%" if can_attack else "--"
		summaries.append("%s  HP %s  DMG %s  HIT %s  CRIT %s" % [name_labels[side].text, stat_labels[side][0].text, stat_labels[side][1].text, stat_labels[side][2].text, stat_labels[side][3].text])
	forecast_label.text = "\n".join(summaries)
	show()
