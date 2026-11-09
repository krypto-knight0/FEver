extends RefCounted
## Small, shared GBA header reader. Labels never depend on mobile storage names.
const HEADER_SIZE := 0xc0

static func from_file(path: String) -> Dictionary:
	if path.is_empty(): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	return from_bytes(file.get_buffer(HEADER_SIZE))

static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE: return {}
	return {"title":_ascii_field(bytes, 0xa0, 12), "code":_ascii_field(bytes, 0xac, 4)}

static func _ascii_field(bytes: PackedByteArray, offset: int, length: int) -> String:
	var value := ""
	for index in range(offset, offset + length):
		var character := int(bytes[index])
		if character == 0: break
		if character < 32 or character > 126: return ""
		value += String.chr(character)
	return value.strip_edges()

static func display_name(header: Dictionary, fallback: String = "Cartridge") -> String:
	var title := str(header.get("title", ""))
	var code := str(header.get("code", ""))
	# The stock titles are compact header strings; custom titles stay intact.
	match title:
		"FIREEMBLEM6": title = "Fire Emblem 6"
		"FIREEMBLEM7": title = "Fire Emblem 7"
		"FIREEMBLEME": title = "Fire Emblem"
	if title.is_empty(): title = fallback
	return title if code.is_empty() else title + " · " + code
