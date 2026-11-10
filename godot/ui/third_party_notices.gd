extends RefCounted
## Offline notices, available even before a cartridge has been imported.
const DOCUMENTS := [
	"res://notices/GODOT_LICENSE.txt",
	"res://notices/GODOT_COPYRIGHT.txt",
]

static func show_notices(parent: Node) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.name = "ThirdPartyNotices"
	dialog.title = "Third-party notices"
	dialog.ok_button_text = "Close"
	dialog.min_size = Vector2i(280, 240)
	dialog.theme = preload("res://ui/app_theme.gd").create()
	# Legal text must remain verbatim, including when custom translations are enabled.
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.get_ok_button().custom_minimum_size.y = 48
	# A plain Control prevents wrapped text's initial minimum height from
	# enlarging the dialog beyond the screen before containers have laid out.
	var content := Control.new()
	dialog.add_child(content)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	content.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scope := Label.new()
	scope.text = "Godot Engine and its third-party components. These notices do not license FEver's own code or artwork."
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(scope)
	var choice := OptionButton.new()
	choice.name = "NoticeDocument"
	choice.add_item("Godot Engine license")
	choice.add_item("Godot third-party copyrights and licenses")
	choice.fit_to_longest_item = false
	choice.custom_minimum_size.y = 48
	column.add_child(choice)
	var scroll := preload("res://ui/swipe_scroll.gd").new()
	scroll.name = "NoticeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := Label.new()
	body.name = "NoticeText"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 17)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)
	var select_document := func(index: int):
		scroll.cancel_gesture()
		scroll.flick_velocity = 0.0
		body.text = FileAccess.get_file_as_string(DOCUMENTS[index])
		scroll.scroll_vertical = 0
	choice.item_selected.connect(select_document)
	select_document.call(0)
	dialog.popup_centered_clamped(Vector2i(1000, 700), 0.9)
	return dialog
