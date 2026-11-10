extends RefCounted
## Known FE7 presentation commands. This reads operands, never executes event ASM.
const Data = preload("res://runtime/rom_data.gd")
const OPS := {"background":[5,7,9,0xd3,0xda,0xd9],"music":[0x78,0x79,0x7a,0x7b,0x7c],"clear":[9]}

static func fail(decoder: RefCounted, message: String) -> Variant:
	decoder.fail("ROM story scene",message)
	return null

static func read(decoder: RefCounted, spec: Variant, game: String) -> Variant:
	if game != "fe7" or not spec is Dictionary or spec.size() > 3: return fail(decoder,"Invalid scene command recipe.")
	var result := {"fields":{},"clear":false}
	for field in spec:
		if not OPS.has(field): return fail(decoder,"Unknown scene command field.")
		var command: Variant = spec[field]
		if not command is Array or command.size() != 2 or not Data.integer(command[0]) or not Data.integer(command[1],0,255):
			return fail(decoder,"Invalid scene command reference.")
		var at := int(command[0])
		var op := int(command[1])
		if op not in OPS[field]: return fail(decoder,"Unexpected scene opcode for field.")
		if not decoder.require_range(at,8 if op in [0xd9,0xda] else 4,"Story scene command"): return null
		if decoder.u16(at) != op: return fail(decoder,"Story scene command changed to an unsupported instruction.")
		var value: int = decoder.u32(at) >> 16
		if field == "clear": result["clear"] = true
		elif field == "music":
			result.fields.music = "player_phase" if op == 0x7a else ("" if op == 0x7c or value in [0,0x7fff] else "song_%03x" % value)
		elif op == 9:
			result.fields.merge({"background":"","scene_type":"dialogue"})
		else:
			if op in [0xd9,0xda]: value = decoder.u16(at+4)
			var cg := op in [0xd3,0xda]
			result.fields.merge({"background":"res://content/fe7/rom/scenes/%s_%03d.png" % ["cg" if cg else "background",value],"scene_type":"cg" if cg else "dialogue","background_color":""})
	return result

static func asset(decoder: RefCounted, path: String) -> Variant:
	if path.begins_with("res://content/fe6/rom/backgrounds/"):
		var scene_number := path.get_file().get_basename()
		if not scene_number.is_valid_int() or int(scene_number) < 0 or int(scene_number) > 255: return fail(decoder,"Invalid FE6 background identity.")
		var scene_at: int = decoder.ptr(0xe374)+int(scene_number)*12
		if not decoder.require_range(scene_at,12,"FE6 background record"): return null
		var scene := {"kind":"scene","graphics":[[decoder.ptr(scene_at)]],"tsa":decoder.ptr(scene_at+4),"palette":decoder.ptr(scene_at+8),"crop":[0,0,240,160]}
		if not decoder.error.is_empty(): return null
		return scene
	var prefix := "res://content/fe7/rom/scenes/"
	if not path.begins_with(prefix): return null
	var name := path.get_file().get_basename()
	var cg := name.begins_with("cg_")
	if not cg and not name.begins_with("background_"): return null
	var number := name.get_slice("_",1)
	if not number.is_valid_int() or int(number) < 0 or int(number) > 65535: return fail(decoder,"Invalid background identity.")
	if cg and decoder.layout.get("event_variant","") == "fe7j":
		# Japanese CG records are three pointers; graphics always use ten LZ
		# slices. The US release added a leading format word to each record.
		var record: int = decoder.ptr(int(decoder.layout.cgs))+int(number)*12
		if not decoder.require_range(record,12,"Japanese CG record"): return null
		var table: int = decoder.ptr(record)
		if not decoder.require_range(table,40,"Japanese CG slices"): return null
		var slices: Array = []
		for index in range(10): slices.append([decoder.ptr(table+index*4)])
		return {"kind":"scene","graphics":slices,"tsa":decoder.ptr(record+4),"palette":decoder.ptr(record+8),"crop":[0,0,240,160]}
	var at: int = decoder.ptr(int(decoder.layout.get("cgs",0xb6b64) if cg else decoder.layout.get("backgrounds",0xb874))) + int(number)*(16 if cg else 12)
	if not decoder.require_range(at,16 if cg else 12,"Story background record"): return null
	var graphics: Array = []
	if cg:
		var table: int = decoder.ptr(at+4)
		if decoder.u8(at) != 0:
			if not decoder.require_range(table,40,"CG graphics table"): return null
			for i in range(10): graphics.append([decoder.ptr(table+i*4)])
		else: graphics.append([table])
	else: graphics.append([decoder.ptr(at)])
	var result := {"kind":"scene","graphics":graphics,"tsa":decoder.ptr(at+(8 if cg else 4)),"palette":decoder.ptr(at+(12 if cg else 8)),"crop":[0,0,240,160]}
	for layer in graphics:
		if not decoder.require_range(int(layer[0]),4,"Story background graphics"): return null
	for key in ["tsa","palette"]:
		if not decoder.require_range(int(result[key]),4,"Story background data"): return null
	return result
