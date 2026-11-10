extends VBoxContainer
signal item_requested(index: int)
signal skills_requested(unit: Dictionary, record: Dictionary)
const Art = preload("res://runtime/art_textures.gd")
## Character sheet keeps the original portrait/stat grouping with scalable text.
const Styles = preload("res://ui/panel_style.gd")
var portrait: TextureRect
var summary: RichTextLabel
var identity: Label
var vitality: Label
var equipment: Label
var equipment_title: Label
var equipment_grid: GridContainer
var personal: Label
var stat_rows: Dictionary = {}
var item_rows: VBoxContainer
var rank_rows: VBoxContainer
var rank_bars: Dictionary = {}
var skill_rows: HFlowContainer
const Skills = preload("res://ui/skill_icons.gd")

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	identity = _label("", 25)
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var header := HBoxContainer.new()
	add_child(header)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	add_child(row)
	

	portrait = preload("res://ui/dialogue_unit_portrait.gd").new()
	portrait.custom_minimum_size = Vector2(170, 180)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(portrait)
	portrait.hide()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitality = _label("", 21)

	personal = _label("", 17)
	personal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 238
	stats.add_theme_constant_override("separation", 2)
	row.add_child(stats)
	for entry in [["hp", "HP"], ["str", "Strength"], ["magic", "Magic"], ["skill", "Skill"], ["speed", "Speed"], ["as", "AS"], ["luck", "Luck"], ["def", "Defense"], ["res", "Resistance"], ["con", "Constitution"], ["mov", "Movement"], ["hit", "Hit"], ["avoid", "Avoid"], ["crit", "Crit"]]:
		var line := HBoxContainer.new()
		stats.add_child(line)
		var title := _label(entry[1], 18)
		title.custom_minimum_size.x = 112
		line.add_child(title)
		var value := _label("", 20)
		value.custom_minimum_size.x = 65
		line.add_child(value)
		var bar := _bar()
		bar.custom_minimum_size.x = 70
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var delta := _label("", 18)
		delta.custom_minimum_size.x = 38
		line.add_child(delta)
		line.add_child(bar)
		stat_rows[entry[0]] = [value, bar, delta, line]
	rank_rows = VBoxContainer.new()
	rank_rows.add_theme_constant_override("separation", 5)
	var gear := VBoxContainer.new()
	gear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear.add_theme_constant_override("separation", 10)
	row.add_child(gear)
	gear.add_child(vitality)
	gear.add_child(personal)
	gear.add_child(rank_rows)
	item_rows = VBoxContainer.new()
	item_rows.custom_minimum_size.x = 198
	item_rows.add_theme_constant_override("separation", 7)
	var inventory_column := VBoxContainer.new()
	gear.add_child(inventory_column)
	inventory_column.add_child(item_rows)
	inventory_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_rows.mouse_filter = Control.MOUSE_FILTER_STOP
	item_rows.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			item_rows.accept_event()
			item_requested.emit.call_deferred(-1))
	skill_rows = HFlowContainer.new()
	skill_rows.add_theme_constant_override("h_separation", 12)
	add_child(skill_rows)
	summary = RichTextLabel.new()
	summary.hide()
	add_child(summary)

func _bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 11
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.09, 0.22, 0.65)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e6ce7d")
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _show_ranks(unit: Dictionary, battle: RefCounted) -> void:
	for child in rank_rows.get_children():
		rank_rows.remove_child(child)
		child.queue_free()
	rank_bars.clear()
	if not battle.has_method("weapon_rank_progress"): return
	var records: Array = battle.weapon_rank_progress(unit)
	if records.is_empty(): return
	rank_rows.add_child(_label("Weapon ranks", 17))
	for record in records:
		var line := HBoxContainer.new()
		rank_rows.add_child(line)
		var name_label := _label("%s  %s" % [str(record.type).capitalize(), record.rank], 17)
		name_label.custom_minimum_size.x = 78
		line.add_child(name_label)
		var bar := _bar()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = float(record.get("progress", 1.0 if record.get("maxed", false) else 0.0))
		bar.custom_minimum_size.x = 70
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var remaining := maxi(0, int(record.get("next", 0)) - int(record.get("points", 0)))
		bar.tooltip_text = "Maximum weapon rank" if record.get("maxed", false) else "%d weapon XP · %d XP to rank %s" % [int(record.get("points", 0)), remaining, str(record.get("next_rank", ""))]
		line.add_child(bar)
		var progress_label := _label("MAX" if record.get("maxed", false) else "%d to %s" % [remaining, str(record.get("next_rank", ""))], 14)
		progress_label.custom_minimum_size.x = 46
		progress_label.tooltip_text = bar.tooltip_text
		line.add_child(progress_label)
		rank_bars[str(record.type)] = bar

func _label(text_value: String, font_size: int) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color("fff4d7"))
	return result

func present(unit: Dictionary, battle: RefCounted) -> void:
	portrait.present(unit)
	identity.text = str(unit.get("name", "Unit"))
	if not str(unit.get("class_name", "")).is_empty(): identity.text += "  ·  " + str(unit.class_name)
	vitality.text = "Lv %d · EXP %d" % [unit.level, unit.exp]
	personal.text = "Mov %d · Con %d · Aid %d   %s" % [battle.effective_stat(unit, "mov"), battle.effective_stat(unit, "con"), battle.rescue_aid(unit), "Carrying " + str(battle.get_unit(str(unit.get("carrying_id", ""))).get("name", "ally")) if not str(unit.get("carrying_id", "")).is_empty() else ""]
	var power_key := preload("res://ui/unit_stat_labels.gd").power_key(unit)
	stat_rows.str[3].get_child(0).text = "Strength"
	stat_rows[power_key][3].get_child(0).text = preload("res://ui/unit_stat_labels.gd").power(unit)
	for key in stat_rows:
		stat_rows[key][3].visible = key not in ["con", "mov"] and (key not in ["str", "magic"] or key == power_key)
		var permanent: int = battle.Rogue.permanent(unit, key) if battle.Rogue.active(battle) else 0
		stat_rows[key][0].text = str(int(unit.get(key, 0)) + permanent)
		var delta: int = int(unit.get("temporary_bonuses", {}).get(key, 0)) + int(unit.get("ring_bonuses", {}).get(key, 0)) + (battle.Rogue.temporary(unit, key) if battle.Rogue.active(battle) else 0)
		if key == "as":
			stat_rows[key][0].text = str(battle.attack_speed(unit))
			stat_rows[key][3].tooltip_text = "Attack speed after weapon weight and Constitution."
			delta = 0
		if key in ["hit", "avoid"]:
			var base: int = (int(unit.get("weapon", {}).get("hit", 0)) + battle.effective_stat(unit, "skill") * 2 + battle.effective_stat(unit, "luck") / 2 + 10 * battle.Rogue.count(unit, "hit_up")) if key == "hit" else (battle._attack_speed(unit) * 2 + battle.effective_stat(unit, "luck") + 10 * battle.Rogue.count(unit, "avd_up"))
			stat_rows[key][0].text = str(base)
			stat_rows[key][1].show()
			if int(unit.hp) == int(unit.max_hp): delta += 20 * battle.Rogue.count(unit, "confidence" if key == "hit" else "energetic")
			if int(unit.hp) * 4 < int(unit.max_hp): delta += 20 * battle.Rogue.count(unit, "defiance" if key == "hit" else "gambit")
		if key == "crit":
			stat_rows[key][0].text = str(int(unit.get("weapon", {}).get("crit", 0)) + battle.effective_stat(unit, "skill") / 2 + int(unit.get("critical_bonus", 0)) + 10 * battle.Rogue.count(unit, "crit_up"))
			stat_rows[key][1].show()
		stat_rows[key][2].visible = true
		stat_rows[key][2].text = "%+d" % delta if delta != 0 else ""
		stat_rows[key][2].add_theme_color_override("font_color", Color("70ed8b") if delta > 0 else Color("ff7777"))
		stat_rows[key][1].max_value = int(battle.rules.stat_caps.get(key, 30))
		if key in ["hit", "avoid", "crit"]: stat_rows[key][1].max_value = 200 if key == "hit" else 100
		stat_rows[key][1].value = int(stat_rows[key][0].text)
		if key == "hp":
			stat_rows[key][0].text = "%d/%d" % [unit.hp, unit.max_hp]
			stat_rows[key][1].max_value = maxi(1, int(unit.max_hp))
			stat_rows[key][1].value = int(unit.hp)
			stat_rows[key][2].text = ""
	for child in skill_rows.get_children(): skill_rows.remove_child(child); child.queue_free()
	if battle.Rogue.active(battle):
		for record in Skills.records(unit):
			var button := Button.new()
			button.icon = Skills.texture(record.id)
			button.text = str(record.name) + (" ×%d" % int(record.count) if int(record.count) > 1 else "")
			button.pressed.connect(func(): _show_skill(unit, record))
			skill_rows.add_child(button)
	_show_ranks(unit, battle)
	for child in item_rows.get_children():
		item_rows.remove_child(child)
		child.queue_free()
	var weapon: Dictionary = unit.get("weapon", {})
	var items: Array = ([] if weapon.is_empty() else [weapon]) + unit.get("inventory", [])
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var line := HBoxContainer.new()
		item_rows.add_child(line)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if ResourceLoader.exists(str(item.get("icon", ""))): icon.texture = Art.texture(item.icon)
		line.add_child(icon)
		var item_name := _label("%s%s   %d" % ["◆ " if index == 0 and not weapon.is_empty() else "", item.get("name", "Item"), int(item.get("uses", 0))], 17)
		if battle.item_drops(unit, item): item_name.add_theme_color_override("font_color", Color("70ed8b"))
		line.add_child(item_name)
		var slot := index - (1 if not weapon.is_empty() else 0)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				line.accept_event()
				item_requested.emit.call_deferred(slot))
		if item.has("required_rank"):
			var kind := _label(preload("res://ui/item_description.gd").weapon_type(item), 14)
			kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(kind)
	summary.text = identity.text + "\n" + vitality.text
	summary.text += "\nSTR %d  SKL %d  SPD %d  LCK %d  DEF %d  RES %d  CON %d  MOV %d" % [unit.str, unit.skill, unit.speed, unit.luck, unit.def, unit.res, unit.con, unit.mov]

func _show_skill(unit: Dictionary, record: Dictionary) -> void:
	skills_requested.emit(unit, record)
