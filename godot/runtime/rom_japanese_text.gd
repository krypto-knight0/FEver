extends RefCounted
## Shared bounded raw/Huffman Shift-JIS decoding for native Japanese cartridges.

static func symbols(source: RefCounted, pointer: int, tree: int, root: int, glyphs: Dictionary, ligatures: Callable = Callable()) -> Array:
	var at := (pointer&0x7fffffff)-0x08000000
	if not source.require_range(at,1,"Japanese text"): return []
	var bytes: Array = []
	if pointer&0x80000000:
		var ended := false
		var arguments_left := 0
		for pos in range(at,mini(at+source.MAX_TEXT_BYTES,source.rom.size())):
			var value := int(source.rom[pos])
			if arguments_left == 0 and value == 0: ended = true; break
			bytes.append(value)
			if arguments_left > 0: arguments_left -= 1
			elif value in [16,128]: arguments_left = 2 if value == 16 else 1
		if not ended: source.fail("Japanese text","Unterminated text.",at); return []
	else:
		for value in source.huffman_symbols(at,tree,root):
			bytes.append(value&255)
			if value&0xff00: bytes.append((value>>8)&255)
	var result: Array = []
	var index := 0
	while index < bytes.size():
		var ligature: String = ligatures.call(bytes,index) if ligatures.is_valid() else ""
		if not ligature.is_empty():
			for character in ligature: result.append(character.unicode_at(0))
			index += 14
			continue
		var value: int = bytes[index]; index += 1
		if value in [16,128]:
			var count := 2 if value == 16 else 1
			if index+count > bytes.size(): source.fail("Japanese text","Truncated control.",at); return []
			var argument: int = bytes[index]
			if count == 2: argument |= int(bytes[index+1])<<8
			result.append(value); result.append(argument); index += count
		elif (value >= 0x81 and value <= 0x9f) or (value >= 0xe0 and value <= 0xef):
			if index >= bytes.size(): source.fail("Japanese text","Truncated glyph.",at); return []
			var key := str((value<<8)|int(bytes[index])); index += 1
			if not glyphs.has(key): source.fail("Japanese text","Unsupported glyph encoding: "+key,at); return []
			result.append(str(glyphs[key]).unicode_at(0))
		elif value >= 0xa1 and value <= 0xdf: result.append(0xff61+value-0xa1)
		else: result.append(value)
	return result

static func plain(codes: Array) -> String:
	var result := ""
	var argument := false
	for code in codes:
		if argument:
			argument = false
			continue
		if code in [16,128]: argument = true
		elif code >= 32: result += String.chr(code)
		elif code == 1: result += "\n"
	return result
