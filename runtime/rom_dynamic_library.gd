extends RefCounted
## Runtime-only browsing indexes. No templates, packages, pixels or cache files
## are written. Table probes inspect headers; image decoding happens on selection.
const Decoder = preload("res://runtime/rom_decoder.gd")
const Pointer = preload("res://runtime/rom_audio.gd")
var rom := PackedByteArray()
var prefix := ""
var catalogs := {}
var assets := {}
var timings := {}
var failures := {}

func pointer(at: int) -> int: return Pointer.pointer(rom,at)
func span(at: int, size: int) -> bool: return at >= 0 and size >= 0 and at <= rom.size()-size
func compressed(at: int) -> bool:
	return span(at,4) and rom[at] == 16 and (rom.decode_u32(at)>>8) > 0 and (rom.decode_u32(at)>>8) <= Decoder.MAX_BLOCK_BYTES

# Game adapters supply native layouts; common gallery operations stay here.
func make_decoder() -> RefCounted:
	var d := Decoder.new(); d.rom = rom
	return d

func portrait_table() -> int: return -1
func background_table() -> int: return -1
func background_id(_path: String) -> int: return -1
func portrait_valid(_table: int, _id: int) -> bool: return false

func map_dimensions(d: RefCounted, id: int) -> Vector2i:
	var at: int = d.ptr(int(d.layout.chapters))+id*int(d.layout.chapter_stride)
	var grid: PackedByteArray = d.lz(d.ptr(d.ptr(int(d.layout.maps))+d.u8(at+8)*4))
	if not d.error.is_empty() or grid.size() < 2: return Vector2i.ZERO
	return Vector2i(grid[0],grid[1])

func background_valid(table: int, id: int) -> bool:
	var at := table+id*12
	if table < 0 or not span(at,12): return false
	var tiles := pointer(at+4)
	return compressed(pointer(at)) and span(pointer(at+8),512) and span(tiles,2) and span(tiles,2+(int(rom[tiles])+1)*(int(rom[tiles+1])+1)*2)

func catalog(kind: String, chapters: Array, names: Dictionary, known_assets: Dictionary) -> Array:
	if catalogs.has(kind): return catalogs[kind]
	var start := Time.get_ticks_usec()
	var entries: Array = []
	match kind:
		"portraits":
			var table := portrait_table()
			var ids := {}
			# Bound a contiguous, structurally valid portrait table,
			# then include valid character references beyond any gap.
			for id in range(1,1024):
				if not portrait_valid(table,id): break
				ids[id] = true
			for face in names:
				if int(face) > 0 and int(face) < 65536 and portrait_valid(table,int(face)): ids[int(face)] = true
			for id in ids:
				var path := prefix+"portraits/%03d.png" % id
				assets[path] = {"kind":"portrait","id":id}
				entries.append({"id":str(id),"path":path,"title":names.get(id,"Portrait %d" % id),"rom_portrait_id":id})
		"backgrounds":
			var table := background_table()
			var ids := {}
			for id in range(256):
				if not background_valid(table,id): break
				ids[id] = true
			for path in known_assets:
				var id := background_id(str(path))
				if id >= 0 and id < 256 and background_valid(table,id): ids[id] = true
			for id in ids:
				var at: int = table+int(id)*12
				var path := prefix+"rom/backgrounds/%03d.png" % id
				assets[path] = {"kind":"scene","graphics":[[pointer(at)]],"tsa":pointer(at+4),"palette":pointer(at+8),"crop":[0,0,240,160]}
				entries.append({"id":str(id),"path":path,"title":"Background %d" % id,"kind":"dialogue_background"})
			var title_path := prefix.trim_suffix("library/")+"rom/title/title_screen.png"
			if known_assets.has(title_path):
				var path := prefix+"title_screen.png"
				assets[path] = known_assets[title_path].duplicate(true)
				entries.append({"id":"title_screen","path":path,"title":"Title screen","kind":"title_screen"})
		"maps":
			for chapter in chapters:
				var id := int(chapter.rom_chapter_index)
				var path := prefix+"maps/%d.png" % id
				var d := make_decoder()
				var dimensions := map_dimensions(d,id)
				var width := dimensions.x; var height := dimensions.y
				assets[path] = {"kind":"map","chapter":id}
				entries.append({"id":str(chapter.id),"path":path,"title":str(chapter.title),"width":width,"height":height,"rom_chapter_index":id})
		_: return []
	catalogs[kind] = entries
	timings[kind] = (Time.get_ticks_usec()-start)/1000.0
	return entries

func image(path: String) -> Image:
	if not assets.has(path): return null
	# Malformed optional artwork must never poison the campaign decoder.
	var d := make_decoder()
	var result: Image = d.image(assets[path])
	if not d.error.is_empty(): failures[path] = d.error; return null
	return result
