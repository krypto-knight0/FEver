extends Node
var translation: Translation

func _ready() -> void:
	preload("res://runtime/text_replacements.gd").ensure_loaded()
	translation = preload("res://runtime/custom_translation.gd").new()
	translation.locale = TranslationServer.get_locale()
	TranslationServer.add_translation(translation)
	refresh()

func refresh() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	_redraw(get_tree().root)

func _redraw(node: Node) -> void:
	if node is CanvasItem: node.queue_redraw()
	for child in node.get_children(): _redraw(child)

func _exit_tree() -> void:
	if translation: TranslationServer.remove_translation(translation)
