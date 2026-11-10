extends VBoxContainer
const Store = preload("res://runtime/text_replacements.gd")
var entries: Array = []
var selected := -1
var enabled: CheckButton
var list: ItemList
var original: TextEdit
var replacement: TextEdit
var whole_word: CheckButton
var match_case: CheckButton
var status: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	enabled = CheckButton.new(); enabled.text = "Enable text replacements"; add_child(enabled)
	enabled.toggled.connect(func(_value): _save())
	var files := HBoxContainer.new(); add_child(files)
	_button(files,"Import config",func(): _pick(false))
	_button(files,"Export config",func(): _pick(true))
	list = preload("res://ui/swipe_item_list.gd").new()
	list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	list.custom_minimum_size.y = 120; list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size",18)
	list.item_selected.connect(func(index): select_entry(int(list.get_item_metadata(index))))
	add_child(list)
	_label("Original word or phrase")
	original = _editor()
	_label("Replace with (leave empty to remove text)")
	replacement = _editor()
	var options := HBoxContainer.new(); add_child(options)
	whole_word = CheckButton.new(); whole_word.text = "Whole words"; options.add_child(whole_word)
	match_case = CheckButton.new(); match_case.text = "Match case"; options.add_child(match_case)
	var actions := HBoxContainer.new(); add_child(actions)
	_button(actions,"New",func(): select_entry(-1))
	_button(actions,"Save entry",save_entry)
	_button(actions,"Remove",remove_entry)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status)
	reload()

func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new(); button.text = title; button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action); parent.add_child(button)

func _label(text: String) -> void:
	var label := Label.new(); label.text = text; add_child(label)

func _editor() -> TextEdit:
	var field := TextEdit.new(); field.custom_minimum_size.y = 60
	field.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(field); return field

func reload() -> void:
	Store.ensure_loaded()
	entries = Store.config.replacements.duplicate(true)
	enabled.set_pressed_no_signal(Store.config.enabled)
	_rebuild(); select_entry(-1)

func _rebuild() -> void:
	list.clear()
	var order := range(entries.size())
	order.sort_custom(func(a,b): return str(entries[a].from).naturalnocasecmp_to(str(entries[b].from)) < 0)
	for index in order:
		list.add_item(str(entries[index].from).replace("\n"," ") + " → " + str(entries[index].to).replace("\n"," "))
		list.set_item_metadata(list.item_count - 1,index)
		if index == selected: list.select(list.item_count - 1)

func select_entry(index: int) -> void:
	selected = index
	var entry: Dictionary = entries[index] if index >= 0 else {}
	original.text = entry.get("from", "")
	replacement.text = entry.get("to", "")
	whole_word.set_pressed_no_signal(entry.get("whole_word",true))
	match_case.set_pressed_no_signal(entry.get("case_sensitive",false))
	if index < 0: list.deselect_all()

func save_entry() -> void:
	var previous := entries.duplicate(true)
	var entry := {"from":original.text,"to":replacement.text,"whole_word":whole_word.button_pressed,"case_sensitive":match_case.button_pressed}
	if selected < 0: entries.append(entry)
	else: entries[selected] = entry
	if not _save(): entries = previous; return
	if selected < 0: selected = entries.size() - 1
	_rebuild()

func remove_entry() -> void:
	if selected < 0: return
	var previous := entries.duplicate(true)
	entries.remove_at(selected)
	if not _save(): entries = previous; return
	select_entry(-1); _rebuild()

func _save() -> bool:
	var failure := Store.save({"schema_version":1,"enabled":enabled.button_pressed,"replacements":entries})
	status.text = "Saved. Changes apply throughout the game." if failure.is_empty() else failure
	if not failure.is_empty(): enabled.set_pressed_no_signal(Store.config.enabled); return false
	get_node("/root/CustomTranslations").refresh()
	return true

func import_config(path: String) -> void:
	var failure := Store.import_file(path)
	if failure.is_empty():
		reload()
		get_node("/root/CustomTranslations").refresh()
	status.text = Store.report.summary("replacements") if failure.is_empty() else failure

func _pick(exporting: bool) -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.json ; Translation config"])
	picker.use_native_dialog = true
	if exporting: picker.current_file = "translations.json"
	add_child(picker)
	picker.file_selected.connect(func(path):
		picker.queue_free()
		if not exporting: import_config(path); return
		var file := FileAccess.open(path,FileAccess.WRITE)
		if not file: status.text = "Cannot create export."; return
		file.store_string(JSON.stringify(Store.config,"\t")); file.flush()
		status.text = "Export saved." if file.get_error() == OK else "Could not finish export."
		file.close())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)
