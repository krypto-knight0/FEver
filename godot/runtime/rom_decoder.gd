extends RefCounted
## Bounded FE7U decoders. Only ROM offsets and layout parameters are bundled.
var layout: Dictionary = {}
var rom: PackedByteArray
var blocks: Dictionary = {}
var block_bytes := 0
var sheets: Dictionary = {}
var worldmap_pixels: Image
signal failed(details: Dictionary)
var error: Dictionary = {}
var import_text_cache_enabled := false
var import_symbols: Dictionary = {}
var import_symbol_bytes := 0
const IMPORT_SYMBOL_BYTES := 2 * 1024 * 1024
const IMPORT_SYMBOL_ENTRIES := 2048
const MAX_BLOCK_BYTES := 8 * 1024 * 1024
const MAX_IMAGE_PIXELS := 16 * 1024 * 1024
const MAX_TEXT_BYTES := 65536
const SIZES := [[[8,8],[16,16],[32,32],[64,64]], [[16,8],[32,8],[32,16],[64,32]], [[8,16],[8,32],[16,32],[32,64]]]

func fail(operation: String, reason: String, offset: int = -1, length: int = 0) -> void:
	# Preserve the first cause; dependent reads must not produce cascaded errors.
	if not error.is_empty(): return
	error = {"operation": operation, "reason": reason, "offset": offset, "length": length, "rom_size": rom.size()}
	blocks.clear()
	sheets.clear()
	worldmap_pixels = null
	block_bytes = 0
	clear_import_text_cache()
	failed.emit(error.duplicate())

func clear_import_text_cache() -> void:
	import_text_cache_enabled = false
	import_symbols.clear()
	import_symbol_bytes = 0

func require_range(at: int, count: int, operation: String = "ROM read") -> bool:
	if not error.is_empty(): return false
	if at < 0 or count < 0 or at > rom.size() or count > rom.size() - at:
		fail(operation, "Read exceeds cartridge bounds.", at, count)
		return false
	return true

func u8(at: int) -> int: return int(rom[at]) if require_range(at, 1) else 0
func u16(at: int) -> int: return rom.decode_u16(at) if require_range(at, 2) else 0
func u32(at: int) -> int: return rom.decode_u32(at) if require_range(at, 4) else 0
func ptr(at: int) -> int: return u32(at) - 0x08000000
func raw(at: int, count: int) -> PackedByteArray:
	return rom.slice(at, at + count) if require_range(at, count) else PackedByteArray()

func lz(at: int) -> PackedByteArray:
	if not error.is_empty(): return PackedByteArray()
	if blocks.has(at): return blocks[at]
	if not require_range(at, 4, "LZ header"): return PackedByteArray()
	if rom[at] != 16:
		fail("LZ header", "Unsupported compression header.", at, 4)
		return PackedByteArray()
	var count := u32(at) >> 8
	if count < 1 or count > MAX_BLOCK_BYTES:
		fail("LZ header", "Expanded block exceeds the permitted size.", at, count)
		return PackedByteArray()
	var result := PackedByteArray()
	result.resize(count)
	var source := at + 4
	var out := 0
	while out < count:
		if not require_range(source, 1, "LZ flags"): return PackedByteArray()
		var flags := rom[source]
		source += 1
		for bit in range(7, -1, -1):
			if out >= count: break
			if flags & (1 << bit):
				if not require_range(source, 2, "LZ back-reference"): return PackedByteArray()
				var first := rom[source]
				var distance := ((first & 15) << 8 | rom[source + 1]) + 1
				source += 2
				if distance > out:
					fail("LZ back-reference", "Reference precedes decoded output.", source - 2, distance)
					return PackedByteArray()
				for n in range(mini((first >> 4) + 3, count - out)):
					result[out] = result[out - distance]
					out += 1
			else:
				if not require_range(source, 1, "LZ literal"): return PackedByteArray()
				result[out] = rom[source]
				source += 1
				out += 1
	while not blocks.is_empty() and block_bytes + result.size() > 16 * 1024 * 1024:
		var oldest: int = blocks.keys()[0]
		block_bytes -= blocks[oldest].size()
		blocks.erase(oldest)
	blocks[at] = result
	block_bytes += result.size()
	return result

func blank(w: int, h: int) -> Image:
	if not error.is_empty(): return null
	if w < 1 or h < 1 or w > 16384 or h > 16384 or w * h > MAX_IMAGE_PIXELS:
		fail("Image dimensions", "Image exceeds the permitted dimensions.")
		return null
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func colors(palette: PackedByteArray, transparent: bool = true) -> Array:
	var result: Array = []
	@warning_ignore("integer_division") # Intentional integer truncation.
	for i in range(palette.size() / 2):
		var c := palette.decode_u16(i * 2)
		@warning_ignore("integer_division") # Intentional integer truncation.
		result.append(PackedByteArray([(c & 31) * 255 / 31, ((c >> 5) & 31) * 255 / 31, ((c >> 10) & 31) * 255 / 31, 0 if transparent and i % 16 == 0 else 255]))
	return result

func tiles(data: PackedByteArray, w: int, h: int, palette: PackedByteArray, transparent: bool = true) -> Image:
	if not error.is_empty(): return null
	if w < 8 or h < 1 or w % 8 != 0 or w > 16384 or h > 16384 or w * h > MAX_IMAGE_PIXELS:
		fail("Tiles", "Invalid tile image dimensions.")
		return null
	@warning_ignore("integer_division") # Intentional integer truncation.
	if data.size() < (w / 8) * ceili(h / 8.0) * 32 or palette.size() < 32:
		fail("Tiles", "Tile data or palette is incomplete.")
		return null
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	var bank := colors(palette, transparent)
	for y in range(h):
		for x in range(w):
			@warning_ignore("integer_division") # Intentional integer truncation.
			var tile: int = (y / 8) * (w / 8) + x / 8
			@warning_ignore("integer_division") # Intentional integer truncation.
			var byte: int = data[tile * 32 + (y % 8) * 4 + (x % 8) / 2]
			var color: PackedByteArray = bank[(byte >> ((x % 2) * 4)) & 15]
			var at := (y * w + x) * 4
			for channel in range(4): rgba[at + channel] = color[channel]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)

func copy(dst: Image, src: Image, dx: int, dy: int, sx: int, sy: int, w: int, h: int, flip_x: bool = false, flip_y: bool = false, blend: bool = false) -> void:
	if not error.is_empty(): return
	if dst == null or src == null:
		fail("Image composition", "A decoded image is missing.")
		return
	if flip_x or flip_y:
		src = src.get_region(Rect2i(sx, sy, w, h))
		if flip_x: src.flip_x()
		if flip_y: src.flip_y()
		sx = 0
		sy = 0
	if blend: dst.blend_rect(src, Rect2i(sx, sy, w, h), Vector2i(dx, dy))
	else: dst.blit_rect(src, Rect2i(sx, sy, w, h), Vector2i(dx, dy))

func tsa_image(data: PackedByteArray, palette: PackedByteArray, tsa: PackedByteArray, w: int = 256, h: int = 160, header: bool = true) -> Image:
	var result := blank(w, h)
	if result == null: return null
	if palette.size() < 32 or (header and tsa.size() < 2):
		fail("Tile map", "Tile map header or palette is incomplete.")
		return null
	var bank := colors(palette, false)
	if header: result.fill(Color8(bank[0][0], bank[0][1], bank[0][2]))
	@warning_ignore("integer_division") # Intentional integer truncation.
	var cols := int(tsa[0]) + 1 if header else w / 8
	@warning_ignore("integer_division") # Intentional integer truncation.
	var rows := int(tsa[1]) + 1 if header else h / 8
	if tsa.size() < (2 if header else 0) + rows * cols * 2:
		fail("Tile map", "Tile map entries are incomplete.")
		return null
	var atlas: Dictionary = {}
	for row in range(rows):
		for col in range(cols):
			var y := rows - row - 1 if header else row
			if col * 8 >= w or y * 8 >= h: continue
			var value := tsa.decode_u16((2 if header else 0) + (row * cols + col) * 2)
			var offset := (value & 1023) * 32
			if value == 65535 or offset + 32 > data.size(): continue
			var key := value & ~3072
			if not atlas.has(key): atlas[key] = tiles(data.slice(offset, offset + 32), 8, 8, palette.slice((value >> 12) * 32, (value >> 12) * 32 + 32), false)
			copy(result, atlas[key], col * 8, y * 8, 0, 0, 8, 8, bool(value & 1024), bool(value & 2048))
	return result

func portrait(id: int, animated: bool) -> Image:
	var record := ptr(int(layout.get("portraits",0x6b30))) + id * 28
	var pal := raw(ptr(record + 8), 32)
	if u32(record) == 0:
		var portrait_data := lz(ptr(record + 16))
		@warning_ignore("integer_division") # Intentional integer truncation.
		return tiles(portrait_data, 80, portrait_data.size() * 2 / 80, pal)
	var face := ptr(record)
	var data := lz(face) if u8(face) == 16 else raw(face + 4, 5120)
	var source := tiles(data, 256, 32, pal)
	if source == null: return null
	var base := blank(96, 80)
	for r in [[16,0,0,0,64,32],[16,32,64,0,64,32],[16,64,128,0,32,16],[0,48,160,0,16,32],[48,64,128,16,32,16],[80,48,176,0,16,32]]:
		copy(base, source, r[0],r[1],r[2],r[3],r[4],r[5])
	var closed := u8(record + 24) == 6
	var ex := u8(record + 22) * 8
	var ey := u8(record + 23) * 8
	if not animated:
		if closed: copy(base, source, ex, ey, 192,16,32,16)
		return base
	var result := blank(288, 240)
	var mouth: Image = tiles(raw(ptr(record + 12), 1536), 32, 96, pal) if u32(record + 12) else null
	for eye in range(3):
		for talk in range(3):
			var frame := base.duplicate() as Image
			if talk and mouth: copy(frame, mouth, u8(record+20)*8, u8(record+21)*8, 0,talk*16,32,16,false,false,true)
			if eye or closed: copy(frame, source, ex,ey,192,16 if closed or eye == 2 else 0,32,16,false,false,true)
			copy(result, frame,talk*96,eye*80,0,0,96,80)
	return result

func sprite(id: int, faction: int, idle: bool) -> Image:
	var record := ptr(int(layout.get("sprites",0x24da0))) + id * 8
	var shape := u16(record + 2)
	var data := lz(ptr(record + 4))
	if not error.is_empty(): return null
	if shape < 0 or shape >= 3:
		fail("Map sprite", "Invalid sprite shape.", record + 2)
		return null
	var w := 32 if shape == 2 else 16
	var h: int = [16,24,32][shape]
	@warning_ignore("integer_division") # Intentional integer truncation.
	var source := tiles(data,w,data.size()*2/w,raw(int(layout.get("sprite_palette",0x194594))+faction*32,32))
	var result := blank(w * (3 if idle else 1),h)
	for i in range(3 if idle else 1): copy(result,source,i*w,0,0,(8 if shape == 1 else 0)+(16 if shape == 0 else 32)*i,w,h)
	return result

func movement(class_id: int, faction: int) -> Image:
	var record := ptr(int(layout.get("movement",0x6d574))) + (class_id - 1) * 8
	var data := lz(ptr(record))
	data.resize(data.size() + (128 - data.size() % 128) % 128)
	var palette := raw(int(layout.get("sprite_palette",0x194594))+faction*32,32)
	var ap := ptr(record+4)
	var start := u16(ap)
	@warning_ignore("integer_division") # Intentional integer truncation.
	var count := (u16(ap+2)-start)/2
	var result := blank(count*64,64)
	if result == null: return null
	for i in range(count):
		var at := ap+start+u16(ap+start+i*2)
		var parts := u16(at)
		if not require_range(at + 2, parts * 8, "Movement pieces"): return null
		for n in range(parts-1,-1,-1):
			var a := u16(at+2+n*6)
			var b := u16(at+4+n*6)
			if a >> 14 >= SIZES.size():
				fail("Movement pieces", "Invalid object shape.", at + 2 + n * 6)
				return null
			var size: Array = SIZES[a>>14][b>>14]
			var x := b & 511
			var y := a & 255
			if x >= 256: x -= 512
			if y >= 128: y -= 256
			# SpriteAnimSync has one packed source tile offset per OAM piece.
			# OAM2 identifies its VRAM destination, not its source in ROM.
			var tile := u16(at+2+parts*6+n*2) & 1023
			@warning_ignore("integer_division") # Intentional integer truncation.
			var source := tiles(data.slice(tile*32,tile*32+int(size[0])*int(size[1])/2),size[0],size[1],palette)
			copy(result,source,i*64+32+x,56+y,0,0,size[0],size[1],bool(b&4096),bool(b&8192),true)
	return result

func map_image(chapter: int, change_id: int = -1) -> Image:
	var rec := ptr(int(layout.get("chapters",0x31580))) + chapter * int(layout.get("chapter_stride",152))
	var config := lz(ptr(ptr(int(layout.get("config",0x191c8)))+u8(rec+7)*4))
	var data := lz(ptr(ptr(int(layout.get("maps",0x3159c)))+u8(rec+8)*4))
	var graphics := lz(ptr(ptr(int(layout.get("graphics",0x19230)))+u8(rec+4)*4)).duplicate()
	if u8(rec+5): graphics.append_array(lz(ptr(ptr(int(layout.get("graphics",0x19230)))+u8(rec+5)*4)))
	var palette := raw(ptr(ptr(int(layout.get("palettes",0x19264)))+u8(rec+6)*4),512)
	if not error.is_empty(): return null
	if data.size() < 2:
		fail("Map", "Map dimensions are missing.")
		return null
	var x := 0
	var y := 0
	var w := int(data[0])
	var h := int(data[1])
	if w == 0 or h == 0 or data.size() < 2 + w * h * 2:
		fail("Map", "Map cells are incomplete.")
		return null
	var changes := PackedByteArray()
	if change_id >= 0:
		var table := ptr(ptr(int(layout.get("changes",0x315b8)))+u8(rec+11)*4)
		for i in range(64):
			var at := table+i*12
			if u8(at) == 255: break
			if u8(at) != change_id: continue
			x=u8(at+1); y=u8(at+2); w=u8(at+3); h=u8(at+4)
			changes=raw(ptr(at+8),w*h*2)
			break
	var result := blank(w*16,h*16)
	if result == null: return null
	if x + w > int(data[0]) or y + h > int(data[1]):
		fail("Map change", "Map change lies outside the map.")
		return null
	var rendered: Dictionary = {}
	for row in range(h):
		for col in range(w):
			var tile := changes.decode_u16((row*w+col)*2) if not changes.is_empty() else data.decode_u16(2+((row+y)*data[0]+col+x)*2)
			if tile == 0 and not changes.is_empty():
				if layout.is_empty() and chapter in [6,7,8]: continue
				tile=data.decode_u16(2+((row+y)*data[0]+col+x)*2)
			if not rendered.has(tile):
				if tile * 2 + 8 > config.size():
					fail("Map tiles", "Tile configuration is incomplete.")
					return null
				var tsa := PackedByteArray([1,1])
				tsa.append_array(config.slice(tile*2+4,tile*2+8))
				tsa.append_array(config.slice(tile*2,tile*2+4))
				rendered[tile]=tsa_image(graphics,palette,tsa,16,16)
			copy(result,rendered[tile],col*16,row*16,0,0,16,16)
	return result

func battle_frame(token: Array, oam: PackedByteArray, palette: PackedByteArray) -> Image:
	if not error.is_empty(): return null
	if token.size() < 2 or int(token[1]) < 0 or int(token[1]) > oam.size() - 12 or palette.size() < 32:
		fail("Battle frame", "Frame data or palette is incomplete.")
		return null
	var parts: Array = []
	var matrices: Array = []
	var at := int(token[1])
	while at+12 <= oam.size():
		if oam.decode_u32(at) == 0xffffff00: break
		# FE's extended OAM stores a block of 8.8 affine matrices before pieces.
		# A one-matrix block starts with 1 too, so check its marker before END.
		if oam.decode_u16(at+2) == 0xffff:
			matrices.append([oam.decode_s16(at+4), oam.decode_s16(at+6), oam.decode_s16(at+8), oam.decode_s16(at+10)])
		elif oam[at] == 1: break
		elif oam[at] == 0: parts.append(at)
		else: break
		at += 12
	var result := blank(288,160)
	parts.reverse()
	for n in parts:
		@warning_ignore("integer_division") # Intentional integer truncation.
		var bank := mini(int(oam[n+5]>>4),palette.size()/32-1)
		var colors_for_part := palette.slice(bank*32,bank*32+32)
		var key := str(token[0])+":"+str(colors_for_part)
		if not sheets.has(key):
			var sheet := tiles(lz(int(token[0])-0x08000000),256,64,colors_for_part)
			if sheet == null: return null
			sheets[key] = sheet
		if oam[n+1] >> 6 >= SIZES.size():
			fail("Battle frame", "Invalid object shape.", n)
			return null
		var size: Array = SIZES[oam[n+1]>>6][oam[n+3]>>6]
		var x := oam.decode_s16(n+6)+148
		var y := oam.decode_s16(n+8)+88
		var source := Vector2i((oam[n+4]&31)*8, (oam[n+4]>>5)*8)
		if oam[n+1]&1:
			var slot := (int(oam[n+3]) >> 1)&31
			var matrix: Array = matrices[slot] if slot < matrices.size() else [256,0,0,256]
			var rotated := affine_sprite(sheets[key], source, Vector2i(size[0],size[1]), matrix, bool(oam[n+1]&2))
			if rotated == null: return null
			result.blend_rect(rotated, Rect2i(Vector2i.ZERO,rotated.get_size()),Vector2i(x,y))
		elif not oam[n+1]&2:
			copy(result,sheets[key],x,y,source.x,source.y,size[0],size[1],bool(oam[n+3]&16),bool(oam[n+3]&32),true)
	return result

func affine_sprite(sheet: Image, origin: Vector2i, size: Vector2i, matrix: Array, doubled: bool) -> Image:
	if not error.is_empty(): return null
	if sheet == null or matrix.size() != 4 or origin.x < 0 or origin.y < 0:
		fail("Affine sprite", "Invalid source image or transform.")
		return null
	var bounds := size * (2 if doubled else 1)
	var result := blank(bounds.x,bounds.y)
	if result == null: return null
	# GBA matrices map destination pixels back into source space. Affine slots
	# occupy the normal flip bits; applying both causes the Hero's return glitch.
	for y in range(bounds.y):
		for x in range(bounds.x):
			@warning_ignore("integer_division") # Intentional integer truncation.
			var dx := x - bounds.x / 2
			@warning_ignore("integer_division") # Intentional integer truncation.
			var dy := y - bounds.y / 2
			@warning_ignore("integer_division") # Intentional integer truncation.
			var sx := ((int(matrix[0])*dx + int(matrix[1])*dy) >> 8) + size.x / 2
			@warning_ignore("integer_division") # Intentional integer truncation.
			var sy := ((int(matrix[2])*dx + int(matrix[3])*dy) >> 8) + size.y / 2
			if sx >= 0 and sy >= 0 and sx < size.x and sy < size.y and origin.x+sx < sheet.get_width() and origin.y+sy < sheet.get_height():
				result.set_pixel(x,y,sheet.get_pixel(origin.x+sx,origin.y+sy))
	return result

func battle_atlas(recipe: Dictionary) -> Image:
	sheets.clear()
	var frames: Array = recipe.frames
	var result := blank(2304,ceili(frames.size()/8.0)*160)
	if result == null: return null
	var palette := lz(int(recipe.palette)).slice(int(recipe.bank)*32,int(recipe.bank)*32+32)
	if recipe.has("secondary_palette"): palette.append_array(raw(int(recipe.secondary_palette),32))
	var oam := lz(int(recipe.oam))
	if not error.is_empty(): return null
	for i in range(frames.size()):
		var frame := blank(288,160)
		for token in frames[i]:
			var layer := battle_frame(token,oam,palette)
			if layer == null: return null
			copy(frame,layer,0,0,0,0,288,160,false,false,true)
		@warning_ignore("integer_division") # Intentional integer truncation.
		copy(result,frame,(i%8)*288,(i/8)*160,0,0,288,160)
	sheets.clear()
	return result

func scene(recipe: Dictionary) -> Image:
	var graphics := PackedByteArray()
	for source in recipe.graphics:
		graphics.append_array(lz(int(source[0])) if source.size() == 1 else raw(int(source[0]),int(source[1])))
	var palette := lz(int(recipe.palette)) if recipe.get("palette_lz",false) else raw(int(recipe.palette),int(recipe.get("palette_size",512)))
	if palette.size() == 32:
		var bank := palette.duplicate()
		for n in range(15): palette.append_array(bank)
	var tsa := lz(int(recipe.tsa)) if recipe.get("tsa_lz",false) else raw(int(recipe.tsa),2+(int(u8(int(recipe.tsa)))+1)*(int(u8(int(recipe.tsa)+1))+1)*2)
	var scene_image := tsa_image(graphics,palette,tsa,int(recipe.get("width",256)),int(recipe.get("height",160)),recipe.get("header",true))
	if scene_image == null or not error.is_empty(): return null
	if recipe.get("transparent",false):
		var key := u16(int(recipe.palette))
		var pixels := scene_image.get_data()
		for at in range(0,pixels.size(),4):
			@warning_ignore("integer_division") # Intentional integer truncation.
			if pixels[at] == (key&31)*255/31 and pixels[at+1] == ((key>>5)&31)*255/31 and pixels[at+2] == ((key>>10)&31)*255/31: pixels[at+3]=0
		scene_image=Image.create_from_data(scene_image.get_width(),scene_image.get_height(),false,Image.FORMAT_RGBA8,pixels)
	if recipe.has("crop"):
		var c: Array = recipe.crop
		scene_image=scene_image.get_region(Rect2i(c[0],c[1],c[2],c[3]))
	return scene_image

func worldmap() -> Image:
	# One source atlas per active decoder. Camera crops reuse it in memory;
	# cartridge switching creates a new decoder and nothing is written to disk.
	if worldmap_pixels != null: return worldmap_pixels
	var result := blank(1024,688)
	var images := ptr(int(layout.get("world_images",0xb5bf4)))
	var maps := ptr(int(layout.get("world_maps",0xb5bec)))
	for i in range(12):
		var h := 256 if i < 8 else 176
		@warning_ignore("integer_division") # Intentional integer truncation.
		var part := scene({"graphics":[[ptr(images+i*4),256*h/2]],"palette":ptr(int(layout.get("world_palette",0xb5df4))),"tsa":ptr(maps+i*4),"width":256,"height":256})
		@warning_ignore("integer_division") # Intentional integer truncation.
		copy(result,part,(i%4)*256,(i/4)*256,0,0,256,h)
	if error.is_empty(): worldmap_pixels = result
	return result

func title_object(index: int, anchor: Array) -> Image:
	var graphics := lz(ptr(int(layout.get("title_graphics",0xba4b0)))).duplicate()
	if not error.is_empty(): return null
	if graphics.size() < 32768: graphics.resize(32768)
	var palette := ptr(int(layout.get("title_palette",0xba4ac)))
	var ap := ptr(int(layout.get("title_ap",0xba4b8)))
	var start := u16(ap)
	var at := ap+start+u16(ap+start+index*2)
	var result := blank(240,160)
	if result == null: return null
	var banks: Dictionary = {}
	var parts := u16(at)
	if not require_range(at + 2, parts * 6, "Title pieces"): return null
	for n in range(parts-1,-1,-1):
		var a := u16(at+2+n*6)
		var b := u16(at+4+n*6)
		var c := u16(at+6+n*6)
		if a >> 14 >= SIZES.size():
			fail("Title pieces", "Invalid object shape.", at + 2 + n * 6)
			return null
		var size: Array = SIZES[a>>14][b>>14]
		var x := b&511
		var y := a&255
		if x>=256: x-=512
		if y>=128: y-=256
		var bank := c>>12
		if not banks.has(bank): banks[bank]=tiles(graphics,256,256,raw(palette+bank*32,32))
		var tile := c&1023
		@warning_ignore("integer_division") # Intentional integer truncation.
		copy(result,banks[bank],int(anchor[0])+x,int(anchor[1])+y,tile%32*8,tile/32*8,size[0],size[1],bool(b&4096),bool(b&8192),true)
	return result

func platform(terrain_id: int = 1) -> Image:
	var at := ptr(int(layout.get("battle_terrain",0x4d100))) + (terrain_id - 1) * 24
	var graphics := lz(ptr(at+12))
	@warning_ignore("integer_division") # Intentional integer truncation.
	var source := tiles(graphics,256,graphics.size()/128,raw(ptr(at+16),32))
	var result := blank(240,160)
	for r in [[4,14,0,0,11,2,1],[5,12,11,0,10,2,1],[6,11,21,0,9,1,1],[15,14,0,0,11,2,0],[15,12,11,0,10,2,0],[15,11,21,0,9,1,0]]:
		copy(result,source,r[0]*8,r[1]*8,r[2]*8,r[3]*8,r[4]*8,r[5]*8,bool(r[6]),false,true)
	return result

func image(recipe: Dictionary) -> Image:
	var result := _image(recipe) if error.is_empty() else null
	return result if error.is_empty() else null

func _image(recipe: Dictionary) -> Image:
	if not error.is_empty(): return null
	match str(recipe.kind):
		"portrait": return portrait(int(recipe.id),recipe.get("animated",false))
		"sprite": return sprite(int(recipe.id),int(recipe.faction),recipe.get("idle",false))
		"movement": return movement(int(recipe.id),int(recipe.faction))
		"map": return map_image(int(recipe.chapter),int(recipe.get("change",-1)))
		"battle": return battle_atlas(recipe)
		"battle_rom":
			var resolved := preload("res://runtime/rom_battle_data.gd").atlas(self,recipe,str(layout.get("game","fe7")))
			return battle_atlas(resolved) if not resolved.is_empty() else null
		"scene": return scene(recipe)
		"platform": return platform(int(recipe.get("id", 1)))
		"worldmap":
			var result := worldmap()
			if not error.is_empty(): return null
			if recipe.has("crop"):
				var c: Array = recipe.crop
				return result.get_region(Rect2i(c[0],c[1],c[2],c[3]))
			return result
		"title_object": return title_object(int(recipe.id),recipe.anchor)
		"compose":
			var result := blank(240,160)
			for layer in recipe.layers: copy(result,image(layer),0,0,0,0,240,160,false,false,true)
			return result
		"icon":
			var result := tiles(raw(ptr(int(layout.get("icons",0x4e20)))+int(recipe.id)*128,128),16,16,raw(ptr(int(layout.get("icon_palette",0x4d40))),32))
			if result == null: return null
			if recipe.get("rotate",false):
				result.flip_x()
				result.flip_y()
			return result
	fail("Image recipe", "Unsupported image recipe.")
	return null

func symbols(id: int) -> Array:
	if not error.is_empty(): return []
	if import_text_cache_enabled and import_symbols.has(id): return Array(import_symbols[id])
	var result := _symbols(id)
	if import_text_cache_enabled and error.is_empty():
		var packed := PackedInt32Array(result)
		var bytes := packed.size() * 4
		if bytes <= IMPORT_SYMBOL_BYTES:
			if import_symbol_bytes + bytes > IMPORT_SYMBOL_BYTES or import_symbols.size() >= IMPORT_SYMBOL_ENTRIES:
				import_symbols.clear()
				import_symbol_bytes = 0
			import_symbols[id] = packed
			import_symbol_bytes += bytes
	return result

func _symbols(id: int) -> Array:
	@warning_ignore("integer_division") # Intentional integer truncation.
	if id < 0 or id >= rom.size() / 4:
		fail("Text lookup", "Invalid text identifier.", id)
		return []
	var tree := ptr(0x6bc)
	var root := ptr(ptr(0x6b8))
	var at := ptr(ptr(0x12cb8)+id*4)
	return huffman_symbols(at, tree, root)

func huffman_symbols(at: int, tree: int, root: int) -> Array:
	if not require_range(at, 1, "Huffman text") or not require_range(tree, 4, "Huffman tree") or not require_range(root, 4, "Huffman root"):
		return []
	if root < tree or (root - tree) % 4 != 0:
		fail("Huffman tree", "Invalid tree bounds.", tree)
		return []
	var node := root
	var result: Array = []
	for source in range(at, mini(at + MAX_TEXT_BYTES, rom.size())):
		for bit in range(8):
			# The whole tree span is validated above. Each transition preserves
			# that bound, so these two reads need no repeated helper calls per bit.
			node = tree + rom.decode_u16(node + ((rom[source] >> bit) & 1) * 2) * 4
			if node < tree or node > root:
				fail("Huffman node", "Node lies outside the text tree.", node, 4)
				return []
			var value := rom.decode_u32(node)
			if value & 0x80000000:
				if value & 255 == 0: return result
				result.append(value&65535)
				node=root
	fail("Huffman text", "Text has no terminator within the read limit.", at)
	return []

func text(id: int) -> String:
	var result := ""
	var previous := 0
	for value in symbols(id):
		var codes: Array = [value] if previous in [16,128] or value&0xff00 == 0 or value&0xff00 >= 0x8100 else [value&255,value>>8]
		for code in codes:
			if previous not in [16,17,128] and code >= 32 and code < 128: result += String.chr(code)
			elif code == 1 and previous not in [16,17,128]: result += "\n"
			previous=code
	return result

func dialogue_pages(id: int) -> Array:
	var tokens: Array = []
	var previous := 0
	for value in symbols(id):
		var codes: Array = [value] if previous in [16,128] or value&0xff00 == 0 or value&0xff00 >= 0x8100 else [value&255,value>>8]
		for code in codes:
			tokens.append([code,previous in [16,17,128] or code<32 or code>=128])
			previous=code
	var pages: Array = []
	var buffer := ""
	var i := 0
	while i<tokens.size():
		var code := int(tokens[i][0])
		var special := bool(tokens[i][1])
		i+=1
		if not special:
			buffer+=String.chr(code)
			continue
		var flush := code in [3,8,9,10,11,12,13,14,15,17]
		if code==16 and i<tokens.size():
			flush=int(tokens[i][0])>=256
			i+=1
		elif code==128 and i<tokens.size():
			var argument := int(tokens[i][0])
			i+=1
			flush=(argument>=10 and argument<=17) or argument==35
			if argument==32: buffer+="Tactician"
			elif argument==35:
				while i<tokens.size() and int(tokens[i][0])!=1: i+=1
		elif code in [1,2]: buffer+=" "
		if flush:
			var page_text := normalize_text(buffer)
			if not page_text.is_empty(): pages.append(page_text)
			buffer=""
	var clean := normalize_text(buffer)
	if not clean.is_empty(): pages.append(clean)
	return pages

func normalize_text(value: String) -> String:
	return " ".join(value.replace("\n"," ").replace("\t"," ").replace("\r"," ").split(" ",false))
