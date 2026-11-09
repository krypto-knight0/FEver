extends "res://runtime/rom_dynamic_library.gd"
## FE7 table layouts around the shared in-memory gallery. Includes class cards
## and CGs; decoding a bad optional image never touches the campaign decoder.
const Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")

func make_decoder() -> RefCounted:
	var d := preload("res://runtime/rom_decoder.gd").new()
	d.rom = rom; d.layout = Profile.layout_for(rom)
	return d

func portrait_table() -> int: return pointer(int(Profile.layout_for(rom).portraits))
func background_table() -> int: return pointer(int(Profile.layout_for(rom).backgrounds))

func portrait_valid(table: int, id: int) -> bool:
	var at := table+id*28
	if table < 0 or not span(at,28) or not span(pointer(at+8),32): return false
	if rom.decode_u32(at) == 0: return compressed(pointer(at+16))
	var face := pointer(at)
	if not span(face,4): return false
	return compressed(face) if rom[face] == 16 else span(face+4,5120) and rom[face] == 0

func background_id(path: String) -> int:
	var file := path.get_file().get_basename()
	return file.trim_prefix("background_").to_int() if file.begins_with("background_") else -1

func cg_recipe(id: int) -> Dictionary:
	var layout := Profile.layout_for(rom)
	var table := pointer(int(layout.cgs))
	if layout.event_variant == "fe7u": return us_cg_recipe(table,id)
	var at := table+id*12
	if table < 0 or not span(at,12): return {}
	var graphics := pointer(at)
	var tsa := pointer(at+4)
	var palette := pointer(at+8)
	if not span(graphics,40) or not span(palette,512) or not span(tsa,2): return {}
	if not span(tsa,2+(int(rom[tsa])+1)*(int(rom[tsa+1])+1)*2): return {}
	var blocks: Array = []
	for index in range(10):
		var block := pointer(graphics+index*4)
		if not compressed(block): return {}
		blocks.append([block])
	return {"kind":"scene","graphics":blocks,"tsa":tsa,"palette":palette,"crop":[0,0,240,160]}

func catalog(kind: String, chapters: Array, names: Dictionary, known_assets: Dictionary) -> Array:
	if catalogs.has(kind): return catalogs[kind]
	var start := Time.get_ticks_usec()
	var result := super.catalog(kind,chapters,names,known_assets)
	if kind == "backgrounds":
		var ids := {}
		for id in range(256):
			var recipe := cg_recipe(id)
			if recipe.is_empty(): break
			ids[id] = recipe
		for path in known_assets:
			var file := str(path).get_file().get_basename()
			if not file.begins_with("cg_"): continue
			var id := file.trim_prefix("cg_").to_int()
			if id < 0 or id > 65535: continue
			var recipe := cg_recipe(id)
			if not recipe.is_empty(): ids[id] = recipe
		for id in ids:
			var path := prefix+"cg_%03d.png" % int(id)
			assets[path] = ids[id]
			result.append({"id":"cg_%d" % int(id),"path":path,"title":"CG %d" % int(id),"kind":"cg"})
		catalogs[kind] = result
	timings[kind] = (Time.get_ticks_usec()-start)/1000.0
	return result

func us_cg_recipe(table: int, id: int) -> Dictionary:
	var at := table+id*16
	if table < 0 or not span(at,16) or rom.decode_u32(at) not in [0,1]: return {}
	var graphics := pointer(at+4)
	var tsa := pointer(at+8)
	var palette := pointer(at+12)
	if not span(palette,512) or not span(tsa,2) or not span(tsa,2+(int(rom[tsa])+1)*(int(rom[tsa+1])+1)*2): return {}
	var blocks: Array = []
	if rom.decode_u32(at) == 0:
		if not compressed(graphics): return {}
		blocks.append([graphics])
	else:
		if not span(graphics,40): return {}
		for index in range(10):
			var block := pointer(graphics+index*4)
			if not compressed(block): return {}
			blocks.append([block])
	return {"kind":"scene","graphics":blocks,"tsa":tsa,"palette":palette,"crop":[0,0,240,160]}
