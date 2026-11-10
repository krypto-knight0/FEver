extends RefCounted
## Dialogue ordering only where a run shares one reviewed presentation adapter.
const Flow = preload("res://runtime/rom_event_flow.gd")
const Data = preload("res://runtime/rom_data.gd")
const Scene = preload("res://runtime/rom_story_scene.gd")
const SINGLE := [0xd,0xe,0x11,0xcf,0xd0,0xd1,0xb3]
const TEXT := [0xd,0xe,0x11,0xf,0x12,0x18,0x19,0x1a,0x1b,0x1c,0x1d,0xcf,0xd0,0xd1,0xb3]

static func fail(decoder: RefCounted, message: String) -> Variant:
	decoder.fail("ROM dialogue sequence",message)
	return null

static func read(decoder: RefCounted, spec: Variant, game: String) -> Variant:
	if not spec is Dictionary or not spec.keys().all(func(key):return key in ["flow","template","skip_prefix","pad","scene_flow","first_pages"]) or not spec.get("template") is Dictionary or not spec.get("skip_prefix") is String or spec.skip_prefix.length() > 128 or not Data.integer(spec.get("pad"),0,3) or int(spec.pad) not in [0,3]: return fail(decoder,"Invalid dialogue sequence adapter.")
	if spec.has("first_pages") and not spec.first_pages is Dictionary: return fail(decoder,"Invalid sequence-entry presentation.")
	var template: Dictionary = spec.template
	if not template.get("set") is Dictionary: return fail(decoder,"Missing sequence presentation fields.")
	for key in ["text","literal","sequence","pages","select"]:
		if template.has(key): return fail(decoder,"Sequence template cannot contain a page or text selection.")
	var reader := Flow.new()
	var entries: Variant = reader.read(decoder,spec.get("flow"),game)
	if entries == null: return null
	if not template.get("scene",{}) is Dictionary: return fail(decoder,"Invalid sequence scene context.")
	var scene: Dictionary = template.get("scene",{}).duplicate(true)
	# A bounded prefix supplies the scene state at the selected conversation.
	# It never emits pages or executes gameplay, callbacks, or tutorial controls.
	if spec.has("scene_flow"):
		var prefix := Flow.new()
		var context: Variant = prefix.read(decoder,spec.scene_flow,game)
		if context == null: return null
		for entry in context:
			for field in Scene.OPS:
				if entry.opcode in Scene.OPS[field]: scene[field] = [entry.offset,entry.opcode]
	var result: Array = []
	for entry in entries:
		var op: int = entry.opcode
		for field in Scene.OPS:
			if op in Scene.OPS[field]: scene[field] = [entry.offset,op]
		if op not in TEXT: continue
		if op not in SINGLE or entry.words.size() < 2: return fail(decoder,"Branch-specific text command needs an explicit adapter.")
		var part := template.duplicate(true)
		if result.is_empty() and spec.has("first_pages"): part.pages = spec.first_pages.duplicate(true)
		var id: int = decoder.u16(int(entry.offset)+4)
		part.text = {"event":entry.offset,"opcode":op,"word":1}
		part["set"]["source_event_offset"] = "0x%x" % int(entry.offset)
		part["set"]["skip_group"] = spec.skip_prefix+("%03x" % id if int(spec.pad) == 3 else "%x" % id)
		if not scene.is_empty(): part.scene = scene.duplicate(true)
		result.append(part)
		scene.erase("clear")
	return result
