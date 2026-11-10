extends "res://runtime/fe6/fe6_decoder.gd"
## Text encoding is independent of a full-ROM fingerprint. Known remapped-font
## profiles are identified by font bytes; standard Japanese uses Shift-JIS.
var text_profile := "shift_jis"
var text_symbols: Dictionary = {}
# FE6's menu font repurposes these seven-glyph runs for narrow katakana names.
# They are not ordinary Shift-JIS (nor the CP932 circled/Roman numerals at
# these codes). Decode only complete native menu glyph runs.
const MENU_LIGATURES := {
	0x40:"サンダーストーム",
	0x54:"ファルコンナイト",
	0x4a:"ドラゴンマスター",
}

func menu_ligature(bytes: Array, at: int) -> String:
	if text_profile != "shift_jis" or at+14 > bytes.size() or int(bytes[at]) != 0x87: return ""
	var first := int(bytes[at+1])
	if not MENU_LIGATURES.has(first): return ""
	for i in range(7):
		if int(bytes[at+i*2]) != 0x87 or int(bytes[at+i*2+1]) != first+i: return ""
	return MENU_LIGATURES[first]

func configure_text() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/text_encodings.json"))
	glyphs = catalog.shift_jis
	for profile in catalog.profiles:
		var at := int(profile.offset)
		var length := int(profile.length)
		if at < 0 or at+length > rom.size(): continue
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256); hasher.update(rom.slice(at,at+length))
		if hasher.finish().hex_encode() == profile.sha256:
			glyphs = glyphs.duplicate(); glyphs.merge(profile.glyphs,true)
			text_profile = profile.id
			break

func symbols(id: int) -> Array:
	if text_symbols.has(id): return text_symbols[id].duplicate()
	if id < 0 or id > 0x7fff:
		fail("FE6 compatible text","Invalid text ID."); return []
	var result := pointer_symbols(u32(ptr(0x13b10)+id*4))
	if error.is_empty() and text_symbols.size() < 4096: text_symbols[id] = result
	return result

func pointer_symbols(pointer: int) -> Array:
	return preload("res://runtime/rom_japanese_text.gd").symbols(self,pointer,ptr(0x6e0),ptr(ptr(0x6dc)),glyphs,menu_ligature)
