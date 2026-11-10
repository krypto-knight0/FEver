extends "res://runtime/rom_decoder.gd"
## FE6 record/text adapters share the bounded GBA graphics primitives.
var glyphs: Dictionary = {}

func _init() -> void:
	layout = {"game":"fe6", "sprites":0x21c74, "sprite_palette":0x100968, "movement":0x60ed8,
		"chapters":0x2bb20, "chapter_stride":68, "config":0x18a7c, "maps":0x2bb70,
		"graphics":0x18ae4, "palettes":0x18b18, "changes":0x2bb9c,
		"characters":0x17680, "character_stride":48, "character_count":226, "icons":0x4cec, "icon_palette":0x4ac4, "songs":0x3748,
		"battle_terrain":0x44534,"title_graphics":0x9b524,"title_palette":0x9b52c,"title_ap":0x9b530}

func _image(recipe: Dictionary) -> Image:
	if not error.is_empty(): return null
	if recipe.kind == "fe6_title_object": return title_object(int(recipe.id),recipe.anchor)
	if recipe.kind == "fe6_title_bg": return title_background(recipe)
	if recipe.kind == "compose":
		var result := blank(240,160)
		for layer in recipe.layers: copy(result,image(layer),0,0,0,0,240,160,false,false,true)
		return result
	return super._image(recipe)

func title_background(recipe: Dictionary) -> Image:
	var data := lz(int(recipe.graphics))
	var pal := raw(int(recipe.palette),256 if recipe.has("tsa") else 32)
	if not recipe.has("tsa"):
		@warning_ignore("integer_division") # Intentional integer truncation.
		var source := tiles(data,256,data.size()*2/256,pal,false)
		return source.get_region(Rect2i(0,0,240,160)) if source != null else null
	var tsa := lz(int(recipe.tsa))
	if not error.is_empty(): return null
	if tsa.size() < 20 * 32 * 2:
		fail("FE6 title", "Title tile map is incomplete.")
		return null
	var result := blank(240,160)
	var rendered := {}
	for y in range(20):
		for x in range(30):
			var value := tsa.decode_u16((y*32+x)*2)
			var tile := value&1023
			if tile*32+32 > data.size(): continue
			if not rendered.has(value):
				var bank := (value>>12)*32
				rendered[value]=tiles(data.slice(tile*32,tile*32+32),8,8,pal.slice(bank,bank+32))
			copy(result,rendered[value],x*8,y*8,0,0,8,8,bool(value&1024),bool(value&2048),true)
	if recipe.has("opacity"):
		if not error.is_empty(): return null
		var pixels := result.get_data()
		for i in range(3,pixels.size(),4): pixels[i]=int(pixels[i]*float(recipe.opacity))
		result=Image.create_from_data(240,160,false,Image.FORMAT_RGBA8,pixels)
	return result

func portrait(id: int, _animated: bool) -> Image:
	var record := ptr(0x7fd8) + id * 16
	var data := lz(ptr(record))
	var pal := raw(ptr(record + 8),32)
	# FE6 class cards are distinguished by an absent minimug pointer.
	@warning_ignore("integer_division") # Intentional integer truncation.
	if u32(record + 4) == 0: return tiles(data,80,data.size()*2/80,pal)
	var source := tiles(data,256,32,pal)
	var result := blank(96,80)
	for r in [[16,0,0,0,64,32],[16,32,64,0,64,32],[16,64,128,0,32,16],[0,48,160,0,16,32],[48,64,128,16,32,16],[80,48,176,0,16,32]]:
		copy(result,source,r[0],r[1],r[2],r[3],r[4],r[5])
	return result

func symbols(id: int) -> Array:
	@warning_ignore("integer_division") # Intentional integer truncation.
	if id < 0 or id >= rom.size() / 4:
		fail("Text lookup", "Invalid text identifier.", id)
		return []
	return pointer_symbols(u32(ptr(0x13b10)+id*4))

func terrain_name(id: int) -> String:
	@warning_ignore("integer_division") # Intentional integer truncation.
	if id < 0 or id >= rom.size() / 4:
		fail("Terrain text", "Invalid terrain identifier.", id)
		return ""
	var result := ""
	for code in pointer_symbols(u32(ptr(0x192c0)+id*4) | 0x80000000):
		if code >= 32: result += String.chr(code)
	return result

func pointer_symbols(pointer: int) -> Array:
	var at := (pointer & 0x7fffffff)-0x08000000
	if not require_range(at, 1, "FE6 text"): return []
	var bytes: Array = []
	if pointer & 0x80000000:
		var terminated := false
		for pos in range(at, mini(at + MAX_TEXT_BYTES, rom.size())):
			if rom[pos] == 0:
				terminated = true
				break
			bytes.append(int(rom[pos]))
		if not terminated:
			fail("FE6 text", "Text has no terminator within the read limit.", at)
			return []
	else:
		var tree := ptr(0x6e0)
		var root := ptr(ptr(0x6dc))
		for value in huffman_symbols(at, tree, root):
			bytes.append(value & 255)
			if value & 0xff00: bytes.append((value >> 8) & 255)
		if not error.is_empty(): return []
	var result: Array = []
	var i := 0
	while i < bytes.size():
		var value: int = bytes[i]
		i += 1
		if value in [16,128]:
			var count := 2 if value == 16 else 1
			if i + count > bytes.size():
				fail("FE6 text control", "Control argument is incomplete.", at)
				return []
			var argument: int = bytes[i]
			if count == 2: argument |= int(bytes[i+1])<<8
			result.append(value); result.append(argument); i += count
		elif value in [0x81,0x82,0x83]:
			if i >= bytes.size():
				fail("FE6 text glyph", "Character sequence is incomplete.", at)
				return []
			var glyph := str(glyphs.get(str((value << 8) | int(bytes[i])), "�"))
			if glyph.is_empty():
				fail("FE6 text glyph", "Character mapping is empty.", at)
				return []
			result.append(glyph.unicode_at(0))
			i += 1
		else: result.append(value)
	return result

func text(id: int) -> String:
	var result := ""
	var argument := false
	for code in symbols(id):
		if argument:
			argument = false
			continue
		if code in [16,128]: argument = true
		elif code >= 32: result += String.chr(code)
		elif code == 1: result += "\n"
	return result

func dialogue_pages(id: int) -> Array:
	var tokens := symbols(id)
	var pages: Array = []
	var buffer := ""
	var i := 0
	while i < tokens.size():
		var code: int = tokens[i]
		i += 1
		if code == 128:
			if i < tokens.size() and int(tokens[i]) >= 10 and int(tokens[i]) <= 17:
				var page_text := normalize_text(buffer)
				if not page_text.is_empty(): pages.append(page_text)
				buffer = ""
			i += 1
			continue
		if code in [3,8,9,10,11,12,13,14,15,16,17]:
			var pending_text := normalize_text(buffer)
			if not pending_text.is_empty(): pages.append(pending_text)
			buffer = ""
			if code == 16: i += 1
		elif code in [1,2]: buffer += " "
		elif code >= 32: buffer += String.chr(code)
	var clean := normalize_text(buffer)
	if not clean.is_empty(): pages.append(clean)
	return pages
