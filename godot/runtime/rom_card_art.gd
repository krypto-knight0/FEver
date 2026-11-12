extends RefCounted
## Decode every cartridge preview through its regional native title reader.
const Fe7Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")
static func texture(game: Dictionary) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(str(game.get("path","")))
	if bytes.is_empty(): return null
	var hasher := HashingContext.new(); hasher.start(HashingContext.HASH_SHA256); hasher.update(bytes)
	var expected := str(game.get("rom_sha256",""))
	if not expected.is_empty() and hasher.finish().hex_encode() != expected: return null
	if bytes.slice(0xac,0xb0).get_string_from_ascii() in Fe7Profile.GAME_CODES:
		if not Fe7Profile.detect(bytes).error.is_empty(): return null
		var preview: Image = preload("res://runtime/fe7/fe7_dynamic_title.gd").card(bytes)
		return ImageTexture.create_from_image(preview) if preview != null else null
	if not preload("res://runtime/fe6/fe6_dynamic_profile.gd").detect(bytes).get("error","").is_empty(): return null
	var native: Image = preload("res://runtime/fe6/fe6_dynamic_title.gd").card(bytes)
	return ImageTexture.create_from_image(native) if native != null else null
