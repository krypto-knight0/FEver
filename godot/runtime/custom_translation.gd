extends Translation
const Replacements = preload("res://runtime/text_replacements.gd")

func _get_message(source: StringName, _context: StringName) -> StringName:
	var translated := Replacements.apply(str(source))
	return StringName("\u200b" if translated.is_empty() and not str(source).is_empty() else translated)

func _get_plural_message(source: StringName, plural: StringName, count: int, context: StringName) -> StringName:
	return _get_message(source if count == 1 else plural, context)
