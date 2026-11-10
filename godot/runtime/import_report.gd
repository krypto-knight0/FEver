extends RefCounted
## Per-import results, read by the UI after the worker finishes.
var accepted := 0
var warnings: Array[String] = []

func skip(reason: String) -> void:
	warnings.append(reason)

func summary(noun: String) -> String:
	var result := "Imported %d %s." % [accepted, noun]
	if not warnings.is_empty():
		result += " Skipped %d invalid entries or files.\n%s" % [warnings.size(), "\n".join(warnings.slice(0, 3))]
		if warnings.size() > 3: result += "\n…and %d more." % (warnings.size() - 3)
	return result

func no_valid(noun: String) -> String:
	return "No valid %s found. Previous selection preserved.%s" % [noun, "\n" + warnings[0] if not warnings.is_empty() else ""]
