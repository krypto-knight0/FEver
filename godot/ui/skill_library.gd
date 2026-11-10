extends VBoxContainer
const Rogue = preload("res://engine/rogue_mode.gd")
const Config = preload("res://engine/personal_skill_config.gd")
const Icons = preload("res://ui/skill_icons.gd")
var search: LineEdit
var scroll: ScrollContainer
var rows: VBoxContainer
var records: Array = []

func _ready() -> void:
	search = LineEdit.new(); search.placeholder_text = "Search personal, character, and army skills"
	search.custom_minimum_size.y = 48; add_child(search)
	search.text_changed.connect(func(_text): _filter())
	scroll = preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL; add_child(scroll)
	rows = VBoxContainer.new(); rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 20); scroll.add_child(rows)

func configure() -> void:
	records.clear()
	Config.ensure_loaded()
	var rom = preload("res://runtime/rom_assets.gd")
	var fe6: bool = rom.game_id == "fe6"
	var seen := {}
	for id in Config.defaults:
		if str(id).begins_with("fe6_unit_") != fe6: continue
		var skill_name := Config.display_name(id)
		var description := Config.description(id)
		var key := skill_name + description
		if fe6 and seen.has(key): continue
		seen[key] = true
		records.append({"id":"personal_" + str(id), "name":skill_name, "description":description, "category":"Personal"})
	if fe6 or rom.dynamic_content != null:
		records.append({"id":str(rom.game_id)+"_potential", "name":"Potential", "description":"Characters without an assigned personal skill retain a fixed +2 stat placeholder, shown in their skill panel.", "category":"Personal"})
	for group in [["Character",Rogue.UNIT_TEXT],["Army",Rogue.ARMY_TEXT]]:
		for id in group[1]:
			if not Rogue.skill_available(id,rom.dynamic_content != null): continue
			records.append({"id":id,"name":Rogue.title(id),"description":group[1][id],"category":group[0]})
	records.sort_custom(func(a,b): return (a.category + a.name).naturalnocasecmp_to(b.category + b.name) < 0)
	search.clear()
	_filter()

func _filter() -> void:
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	var query := search.text.strip_edges().to_lower()
	for record in records:
		if not preload("res://runtime/text_replacements.gd").matches_search(record.name + " " + record.description + " " + record.category, query): continue
		var row := VBoxContainer.new(); row.set_meta("skill_id",record.id); rows.add_child(row)
		var header := HBoxContainer.new(); row.add_child(header)
		var icon := TextureRect.new(); icon.texture = Icons.texture(record.id)
		icon.custom_minimum_size = Vector2(36,36); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; header.add_child(icon)
		var title := Label.new(); title.text = "%s · %s" % [record.name,record.category]
		title.add_theme_font_size_override("font_size",22); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = SIZE_EXPAND_FILL; header.add_child(title)
		var description := Label.new(); description.text = record.description
		description.add_theme_font_size_override("font_size",19); description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)
	if rows.get_child_count() == 0:
		var empty := Label.new(); empty.text = "No matching skills."; rows.add_child(empty)
	scroll.scroll_vertical = 0
