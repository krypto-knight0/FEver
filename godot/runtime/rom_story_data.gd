extends RefCounted
## Expand conversation controls while retaining the engine's event/scene adapters.
## Only character names live for this import; pages and slot state belong to one read.
const Dialogue = preload("res://runtime/rom_dialogue_controls.gd")
const Data = preload("res://runtime/rom_data.gd")
const Scene = preload("res://runtime/rom_story_scene.gd")
const Sequence = preload("res://runtime/rom_story_flow.gd")
const NATIVE := ["speaker", "speaker_faction", "text", "source_text_id", "source_speaker_slot", "source_portrait_id", "portrait", "portrait_role", "speaker_side", "left_portrait", "right_portrait", "left_portrait_role", "right_portrait_role", "rom_portrait_slots"]
const TEXT_WORDS := {"fe7":{0xd:[1],0xe:[1],0x11:[1],0xf:[1,2],0x12:[1,2],0x18:[1,2],0x19:[1,2],0x1a:[2,3],0x1b:[2,3],0x1c:[2,3],0x1d:[2,3],0xcf:[1],0xd0:[1],0xd1:[1],0xb3:[1]}, "fe6":{7:[1],8:[1]}}
var decoder: RefCounted
var game := ""
var names := {}
var character_names := {}
var enemy_names := {}
var context := {}

func fail(reason: String) -> Variant:
	decoder.fail("ROM story dialogue", reason)
	return null

func configure(source: RefCounted, selected_game: String) -> bool:
	decoder = source
	game = selected_game
	if not TEXT_WORDS.has(game):
		fail("Unknown story profile.")
		return false
	names.clear()
	character_names.clear()
	enemy_names.clear()
	var layout: Array = Data.RECORD_LAYOUTS[game]
	var table: int = decoder.ptr(int(layout[0]))
	var count := 253 if game == "fe7" else 226
	if not decoder.require_range(table,count*int(layout[1]),"Story characters"): return false
	for index in range(count):
		var at := table+index*int(layout[1])
		var id: int = decoder.u8(at+4)
		var tid: int = decoder.u16(at)
		var face: int = decoder.u16(at+6)
		var name: String = decoder.text(tid) if tid else ""
		character_names[id] = name
		if not name.is_empty() and decoder.u32(at+40) & 0x8000: enemy_names[name] = true
		if face != 0 and not name.is_empty() and (game == "fe7" or not names.has(face)): names[face] = name
	if game == "fe7" and names.has(22): names[26] = names[22]
	return decoder.error.is_empty()

func text_id(spec: Variant) -> int:
	if not spec is Dictionary:
		fail("Invalid story text selector.")
		return -1
	if spec.size() == 1 and Data.integer(spec.get("id"),0,65535): return int(spec.id)
	if spec.size() != 3 or not Data.integer(spec.get("event")) or not Data.integer(spec.get("opcode"),0,65535) or not Data.integer(spec.get("word"),1,3):
		fail("Invalid story command selector.")
		return -1
	if int(spec.word) not in TEXT_WORDS[game].get(int(spec.opcode),[]):
		fail("Unsupported story text command operand.")
		return -1
	var at := int(spec.event)
	if not decoder.require_range(at,(int(spec.word)+1)*4,"Story text command"): return -1
	if decoder.u16(at) != int(spec.opcode):
		fail("Story text command changed to an unsupported instruction.")
		return -1
	return decoder.u16(at+int(spec.word)*4)

func presentation(value: Variant, resolve: Callable) -> Variant:
	if not value is Dictionary: return fail("Invalid scene presentation fields.")
	for key in value:
		if not key is String or key in NATIVE or key.begins_with("$"):
			return fail("Scene adapters cannot override native dialogue controls: " + str(key))
	return resolve.call(value)

func read(spec: Variant, resolve: Callable) -> Variant:
	if not spec is Dictionary or spec.size() != 2 or not spec.get("game") is String or spec.game != game or not spec.get("parts") is Array or spec.parts.size() > 16384:
		return fail("Invalid story recipe.")
	var result: Array = []
	var state := {}
	var parts: Array = []
	for part in spec.parts:
		if part is Dictionary and part.has("sequence"):
			if part.size() != 1: return fail("A dialogue sequence cannot contain extra fields.")
			var expanded: Variant = Sequence.read(decoder,part.sequence,game)
			if expanded == null: return null
			parts.append_array(expanded)
		else: parts.append(part)
		if parts.size() > 16384: return fail("Expanded story part limit exceeded.")
	for part in parts:
		if not part is Dictionary: return fail("Invalid story part.")
		if part.has("literal"):
			if part.size() != 1 or not part.literal is Dictionary: return fail("Invalid explicit story page.")
			result.append(resolve.call(part.literal))
			if not decoder.error.is_empty(): return null
			state = {}
			continue
		for key in part:
			if key not in ["text","reset","state","fallback","set","first","pages","stop","enemy_speakers","select","scene"]: return fail("Unknown story part field.")
		if part.has("enemy_speakers") and not part.enemy_speakers is bool: return fail("Invalid speaker faction policy.")
		if part.has("reset"):
			if not part.reset is bool or not part.reset: return fail("Invalid conversation reset.")
			state = {}
		if part.has("state"):
			var initial_state: Variant = part.state
			if part.has("reset") or not initial_state is Dictionary or initial_state.size() != 2 or not Data.integer(initial_state.get("slot"),0,15) or not initial_state.get("faces") is Array or initial_state.faces.size() > 8:
				return fail("Invalid initial face-slot state.")
			state = {"slot":int(initial_state.slot),"faces":{}}
			for face in initial_state.faces:
				if not face is Array or face.size() != 2 or not Data.integer(face[0],0,15) or not Data.integer(face[1],-1,65534) or state.faces.has(int(face[0])):
					return fail("Invalid initial portrait slot.")
				state.faces[int(face[0])] = int(face[1])
		var scene: Variant = Scene.read(decoder,part.scene,game) if part.has("scene") else {"fields":{},"clear":false}
		if scene == null: return null
		if scene["clear"]: state = {}
		var fallback: Variant = part.get("fallback", "")
		if fallback is Dictionary:
			if fallback.size() != 1 or not Data.integer(fallback.get("character"),1,255) or not character_names.has(int(fallback.character)):
				return fail("Invalid fallback character.")
			fallback = character_names[int(fallback.character)]
		if not fallback is String or fallback.length() > 256: return fail("Invalid fallback speaker.")
		var id := text_id(part.get("text"))
		if id < 0 or not decoder.error.is_empty(): return null
		context.text_id = id
		var controls := Dialogue.new()
		var pages := controls.read(decoder,game,names,id,fallback,state)
		if not decoder.error.is_empty(): return null
		state = {"slot":controls.slot,"faces":controls.faces}
		if part.has("select"):
			var window: Variant = part.select
			if not window is Array or window.size() != 2 or not Data.integer(window[0],0,65535) or not Data.integer(window[1],1,65536) or int(window[0])+int(window[1]) > pages.size():
				return fail("Selected story pages are outside the ROM conversation.")
			pages = pages.slice(int(window[0]),int(window[0])+int(window[1]))
		var common: Variant = presentation(part.get("set",{}),resolve)
		var first: Variant = presentation(part.get("first",{}),resolve)
		var patches: Variant = part.get("pages",{})
		if common == null or first == null: return null
		if not first.is_empty() and pages.is_empty(): return fail("Scene entry cue has no dialogue page.")
		if not patches is Dictionary: return fail("Invalid per-page scene adapters.")
		var resolved_patches := {}
		for key in patches:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= pages.size():
				return fail("Scene adapter is outside the ROM conversation.")
			resolved_patches[int(key)] = presentation(patches[key],resolve)
			if resolved_patches[int(key)] == null: return null
		var stop: Variant = part.get("stop", "")
		if not stop is String or stop not in ["", "first", "each"]: return fail("Invalid conversation skip policy.")
		for index in range(pages.size()):
			var page: Dictionary = pages[index]
			if part.get("enemy_speakers",false) and enemy_names.has(page.speaker): page.speaker_faction = "enemy"
			page.erase("skip_stop")
			if stop == "each" or (stop == "first" and index == 0): page.skip_stop = index == 0
			page.merge(common.duplicate(true))
			if index == 0: page.merge(first.duplicate(true))
			page.merge(resolved_patches.get(index,{}).duplicate(true))
			for field in scene.fields:
				# A missing color already means no overlay; avoid adding redundant
				# empty metadata while still clearing an authored fade color.
				if field != "background_color" or page.has(field): page[field] = scene.fields[field]
			result.append(page)
		if result.size() > 65536: return fail("Story page limit exceeded.")
	# A narration can span several ROM text entries. Number the complete run
	# after decoding, so translated page breaks track the native actor cues.
	# Explicit indices remain supported for authored/legacy presentations.
	number_worldmap_pages(result)
	return result

static func number_worldmap_pages(pages: Array) -> void:
	var start := 0
	while start < pages.size():
		var world: Variant = pages[start].get("worldmap")
		if not world is Dictionary or world.has("page_index"):
			start += 1
			continue
		var end := start + 1
		while end < pages.size():
			var next: Variant = pages[end].get("worldmap")
			if not next is Dictionary or next.has("page_index"): break
			end += 1
		for index in range(start,end):
			pages[index].worldmap["page_index"] = index-start
			pages[index].worldmap["page_count"] = end-start
		start = end
