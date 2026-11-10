extends "res://runtime/rom_decoder.gd"
## Regional FE7 text: English packed symbols or FE6's bounded Japanese reader.
const Japanese = preload("res://runtime/rom_japanese_text.gd")
var glyphs := {}
var text_symbols := {}

func configure_text() -> void:
	if layout.get("event_variant","") == "fe7u": return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://runtime/text_encodings.json"))
	if not catalog is Dictionary or not catalog.get("shift_jis") is Dictionary:
		fail("FE7 text","Missing Japanese encoding table."); return
	glyphs = catalog.shift_jis
	# FE7 uses the CP932 Roman numerals in sound-room names; FE6 reuses
	# these cells for menu ligatures and excludes them from the shared map.
	for index in range(10): glyphs[str(0x8754+index)] = 0x2160+index

func pointer_symbols(pointer: int) -> Array:
	if layout.get("event_variant","") == "fe7u":
		var at := (pointer&0x7fffffff)-0x08000000
		if pointer&0x80000000:
			# Uncompressed text uses a tagged pointer and raw bytes.
			var result: Array = []
			var index := 0
			while index < MAX_TEXT_BYTES:
				if not require_range(at+index,1,"FE7 English text"): return []
				var value := u8(at+index); index += 1
				if value == 0: return result
				result.append(value)
				if value in [16,128]:
					var count := 2 if value == 16 else 1
					if index+count > MAX_TEXT_BYTES:
						fail("FE7 English text","Oversized raw text control.",at+index); return []
					if not require_range(at+index,count,"FE7 text control"): return []
					result.append(u16(at+index) if count == 2 else u8(at+index)); index += count
			fail("FE7 English text","Unterminated raw text.",at); return []
		return huffman_symbols(at,ptr(int(layout.tree)),ptr(ptr(int(layout.root))))
	return Japanese.symbols(self,pointer,ptr(int(layout.tree)),ptr(ptr(int(layout.root))),glyphs,menu_ligature)

func menu_ligature(bytes: Array, at: int) -> String:
	# Native narrow menu names; FE7 assigns different glyph runs from FE6.
	# Match complete glyph runs rather than replacing individual symbols.
	if at+14 > bytes.size(): return ""
	for entry in [[0x40,"ドラゴンマスター"],[0x47,"ファルコンナイト"],[0x4e,"サンダーストーム"]]:
		var matched := true
		for index in range(7):
			var expected := 0x83bf if int(entry[0]) == 0x4e and index == 6 else 0x8700+int(entry[0])+index
			if (int(bytes[at+index*2])<<8)|int(bytes[at+index*2+1]) != expected: matched = false; break
		if matched: return entry[1]
	return ""

func symbols(id: int) -> Array:
	if text_symbols.has(id): return text_symbols[id].duplicate()
	if id < 0 or id > 0x7fff: fail("FE7 text","Invalid text ID."); return []
	var result := pointer_symbols(u32(ptr(int(layout.text))+id*4))
	if error.is_empty() and text_symbols.size() < 4096: text_symbols[id] = result
	return result

func text(id: int) -> String:
	if layout.get("event_variant","") == "fe7u": return super.text(id)
	return Japanese.plain(symbols(id))

func terrain_name(id: int) -> String:
	if id < 0 or id >= 65: fail("FE7 terrain","Invalid terrain ID."); return ""
	if layout.get("event_variant","") == "fe7u":
		return text(u16(ptr(int(layout.terrain_names))+id*2))
	return Japanese.plain(pointer_symbols(u32(ptr(int(layout.terrain_names))+id*4)|0x80000000))
