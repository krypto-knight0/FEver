extends VBoxContainer
## Read-only support progress. Conversations are initiated on the battlefield.
var battle: RefCounted
var catalog: Dictionary = {}
var characters: Dictionary = {}
var records: Array = []
var character_ids: Array[String] = []
var selected_character := ""
var selector: Button
var summary: Label
var pair_list: ItemList
var detail: RichTextLabel
var portraits: Array[TextureRect] = []
var portrait_units: Array = [{}, {}]
var portrait_paths: Array[String] = ["", ""]

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	selector = preload("res://ui/portrait_entry_dropdown.gd").new()
	selector.custom_minimum_size.y = 48
	selector.item_selected.connect(func(index): selected_character = character_ids[index]; _populate_pairs())
	add_child(selector)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size", 17)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	pair_list = preload("res://ui/swipe_item_list.gd").new()
	pair_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pair_list.custom_minimum_size.y = 100
	pair_list.add_theme_font_size_override("font_size", 19)
	pair_list.add_theme_constant_override("line_separation", 14)
	pair_list.item_selected.connect(_select_pair)
	add_child(pair_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for side in range(2):
		var portrait := preload("res://ui/unit_portrait.gd").new()
		portrait.custom_minimum_size = Vector2(80, 92)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.flip_h = side == 0
		row.add_child(portrait)
		portraits.append(portrait)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.add_theme_font_size_override("normal_font_size", 17)
	detail.custom_minimum_size.y = 156
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)

func present(state: RefCounted, manifest: Dictionary, character_id: String = "") -> void:
	battle = state
	catalog = manifest
	characters.clear()
	for character in manifest.get("characters", []): characters[str(character.id)] = character
	selected_character = character_id
	selector.clear()
	character_ids.assign([""])
	selector.add_item("All army pairs")
	for unit in preload("res://engine/army_roster.gd").all_units(battle):
		if unit.faction != "player": continue
		character_ids.append(str(unit.id))
		selector.add_item(str(unit.name))
	var index := character_ids.find(selected_character)
	if index < 0 and not character_id.is_empty():
		for unit in preload("res://engine/army_roster.gd").all_units(battle):
			if str(unit.get("support_id", unit.id)) == character_id:
				selected_character = str(unit.id)
				index = character_ids.find(selected_character)
				break
	if index < 0: selected_character = ""; index = 0
	selector.select(index)
	_populate_pairs()

func _populate_pairs() -> void:
	pair_list.clear()
	records = battle.support_records(selected_character) if battle.has_method("support_records") else []
	if selected_character.is_empty():
		var army: Array[String] = []
		for unit in preload("res://engine/army_roster.gd").all_units(battle):
			if unit.faction == "player": army.append(str(unit.get("support_id", unit.id)))
		records = records.filter(func(pair): return army.has(str(pair.a)) or army.has(str(pair.b)))
	var enabled: bool = bool(battle.rules.get("supports_enabled", true))
	summary.text = "Adjacent allies and rescue partners earn points each completed turn. Each pair can gain one rank per map."
	if battle.rules.get("unlimited_supports", false): summary.text = "Unlimited conversations. Nearby bonuses use at most five ranks, highest ranks first (ties by character)."
	if not enabled: summary.text = "Supports are inactive in this chapter: no points, conversations, or combat bonuses. Pair values are shown for reference."
	if not selected_character.is_empty():
		var unit: Dictionary = battle.get_unit(selected_character)
		var ranks := 0
		for record in records: ranks += int(record.rank)
		summary.text = "%s · %s affinity · %d / %d support ranks\n%s" % [unit.get("name", "Unit"), str(unit.get("affinity", "none")).capitalize(), ranks, int(battle.rules.get("support_total_cap", 5)), summary.text]
	if battle.rules.get("unlimited_supports", false): summary.text = summary.text.replace(" / %d support ranks" % int(battle.rules.get("support_total_cap", 5)), " unlocked support ranks")
	for record in records:
		var progress := "%d points to %s" % [int(record.remaining), ["C", "B", "A"][mini(2, int(record.rank))]] if int(record.rank) < 3 else "Maximum rank"
		if record.get("ready", false): progress = "Ready for " + ["C", "B", "A"][mini(2, int(record.rank))]
		if record.get("used_this_map", false): progress += " · spoke this map"
		pair_list.add_item("%s / %s   ·   %s   ·   %s" % [record.a_name, record.b_name, record.rank_label, progress])
		if record.get("can_converse", false): pair_list.set_item_custom_fg_color(pair_list.item_count - 1, Color("f8df8f"))
	if records.is_empty():
		detail.text = "No support partners are defined for this character."
		portrait_paths.assign(["", ""])
		portrait_units = [{}, {}]
		refresh_art()
	else:
		pair_list.select(0)
		_select_pair(0)

func _select_pair(index: int) -> void:
	if index < 0 or index >= records.size(): return
	var record: Dictionary = records[index]
	var left: Dictionary = characters.get(str(record.a), {})
	var right: Dictionary = characters.get(str(record.b), {})
	for side in range(2):
		var character: Dictionary = left if side == 0 else right
		var id := str(record.get("a_unit_id" if side == 0 else "b_unit_id", ""))
		var unit: Dictionary = battle.get_unit(id)
		portrait_units[side] = character.duplicate(true)
		portrait_units[side].merge(unit, true)
		portrait_paths[side] = str(unit.get("portrait", character.get("portrait", "")))
	refresh_art()
	var points := "%d / %d points · %d needed for next rank" % [int(record.points), int(record.next_threshold), int(record.remaining)] if int(record.rank) < 3 else "%d points · A rank complete" % int(record.points)
	var status := str(record.get("disabled_reason", ""))
	if status.is_empty():
		if record.get("used_this_map", false) and not battle.rules.get("unlimited_supports", false): status = "This pair has already spoken on this map. Points can build toward the next rank."
		elif record.get("can_converse", false): status = "Ready now: choose Support beside this ally on the battlefield."
		elif record.get("ready", false): status = "Ready: bring both allies next to each other to choose Support."
		else: status = "+%d points per completed turn together, stopping at the next conversation." % int(record.growth)
	var affinity_a := str(left.get("affinity", "none")).capitalize()
	var affinity_b := str(right.get("affinity", "none")).capitalize()
	detail.text = "[b]%s & %s · %s[/b]\n%s\n%s + %s · ranks used %d/%d and %d/%d\n%s" % [record.a_name, record.b_name, record.rank_label, points, affinity_a, affinity_b, int(record.a_ranks_used), int(record.rank_cap), int(record.b_ranks_used), int(record.rank_cap), status]
	if battle.rules.get("unlimited_supports", false):
		detail.text = "[b]%s & %s · %s[/b]\n%s\n%s + %s · %d and %d ranks unlocked\n%s" % [record.a_name, record.b_name, record.rank_label, points, affinity_a, affinity_b, int(record.a_ranks_used), int(record.b_ranks_used), status]
	if int(record.rank) > 0:
		var affinity_rules: Dictionary = battle.rules.get("support_affinities", {})
		var first: Dictionary = affinity_rules.get(affinity_a.to_lower(), {})
		var second: Dictionary = affinity_rules.get(affinity_b.to_lower(), {})
		var parts: Array[String] = []
		for stat in ["atk", "def", "hit", "avo", "crit", "ddg"]:
			var value := floori((float(first.get(stat, 0)) + float(second.get(stat, 0))) * int(record.rank))
			if value > 0: parts.append("%s +%d" % [stat.capitalize(), value])
		detail.text += "\nPair contribution within %d tiles: %s" % [int(battle.rules.get("support_range", 3)), ", ".join(parts) if not parts.is_empty() else "None"]
		if battle.rules.get("unlimited_supports", false): detail.text += " (before the five-rank total bonus limit)"

func refresh_art() -> void:
	for side in range(portraits.size()): portraits[side].present(portrait_units[side])
