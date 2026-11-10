extends VBoxContainer
var player: Node
var sets: Button
var clips: ItemList
var hint: Label
var entry_indices: Array[int] = []

func _ready() -> void:
	sets = preload("res://ui/portrait_entry_dropdown.gd").new(); sets.custom_minimum_size.y = 48; add_child(sets)
	sets.item_selected.connect(_select)
	hint = Label.new(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(hint)
	clips = preload("res://ui/swipe_item_list.gd").new()
	clips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clips.add_theme_font_size_override("font_size",22)
	clips.add_theme_constant_override("line_separation",16)
	add_child(clips)
	clips.item_selected.connect(func(index): player.play_clip(str(clips.get_item_metadata(index))))
	var stop_button := Button.new(); stop_button.text = "Stop"; stop_button.custom_minimum_size.y = 48
	stop_button.pressed.connect(func(): player.stop())
	add_child(stop_button)
	visibility_changed.connect(func():
		if not visible:
			sets.popup.hide()
			if player: player.stop())

func configure(voice_player: Node) -> void:
	player = voice_player
	sets.clear(); clips.clear()
	entry_indices.clear()
	sets.text = "Select character"
	var seen := {}
	for index in range(player.store.entries.size()):
		var entry: Dictionary = player.store.entries[index]
		var title := str(entry.get("label", entry.get("character", entry.get("character_id", "Unit")))) + (" · Class %d" % int(entry.class_id) if entry.has("class_id") else " · Default")
		# Route duplicates share recordings; list each actual recording set once.
		var key := title + JSON.stringify(entry.actions)
		if seen.has(key): continue
		seen[key] = true
		entry_indices.append(index)
		sets.add_item(title)
	sets.disabled = sets.item_count == 0
	hint.text = "Select a clip to listen." if sets.item_count else "Import a voice ZIP through Settings → Custom voices."
	if sets.item_count: sets.select(0); _select(0)

func _select(index: int) -> void:
	player.stop(); clips.clear()
	var entry: Dictionary = player.store.entries[entry_indices[index]]
	var titles := {"select":"Selection", "attack":"Attack", "crit":"Critical", "damage":"Damage", "defeat":"Defeat", "status":"Full stats"}
	for action in preload("res://runtime/voice_store.gd").ACTIONS:
		var paths: Array = entry.actions.get(action, [])
		for i in range(paths.size()):
			clips.add_item("%s · %d" % [titles[action], i+1])
			clips.set_item_metadata(clips.item_count-1,paths[i])
