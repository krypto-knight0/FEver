extends RefCounted
## Shared dialogue controls. Story callers supply the preceding face-slot state;
## support callers start a fresh conversation with the default empty state.
var decoder: RefCounted
var game := ""
var names: Dictionary = {}
var pages: Array = []
var faces: Dictionary = {}
var slot := 0
var portrait: Variant = null
var speaker := ""
var default_speaker := ""
var buffer := ""
var text_id := 0

static func tokenize(source: RefCounted, selected_game: String, id: int) -> Array:
	var tokens: Array = []
	var previous := 0
	for value in source.symbols(id):
		if source.layout.get("unicode_symbols",false):
			var argument := previous in [16,128]
			tokens.append([value,argument or value < 32 or value == 128])
			previous = 0 if argument else int(value)
			continue
		if selected_game == "fe6":
			tokens.append([value,value < 32])
			continue
		var codes: Array = [value] if previous in [16,128] or value & 0xff00 == 0 or value & 0xff00 >= 0x8100 else [value & 255,value >> 8]
		for code in codes:
			tokens.append([code,previous in [16,17,128] or code < 32 or code >= 128])
			previous = code
	return tokens

func read(source: RefCounted, selected_game: String, face_names: Dictionary, id: int, fallback: String, initial: Dictionary = {}, token_stream: Variant = null) -> Array:
	decoder = source
	game = selected_game
	names = face_names
	text_id = id
	default_speaker = fallback
	speaker = fallback if game == "fe7" else ""
	slot = int(initial.get("slot", 12 if game == "fe7" else 0))
	pages = []
	faces = initial.get("faces", {}).duplicate()
	portrait = faces.get(slot)
	if portrait != null: speaker = face_name(portrait)
	buffer = ""
	var tokens: Array = tokenize(decoder,game,id) if token_stream == null else token_stream
	if not decoder.error.is_empty(): return []
	var index := 0
	while index < tokens.size():
		var code := int(tokens[index][0])
		var control := bool(tokens[index][1])
		index += 1
		if game == "fe7" and not control:
			buffer += String.chr(code)
			continue
		if code in [16,128]:
			if index >= tokens.size():
				decoder.fail("Dialogue controls", "Missing control argument for text %d." % id)
				return []
			var argument := int(tokens[index][0])
			index += 1
			if code == 16:
				if game == "fe6" or argument >= 256:
					flush()
					portrait = (-1 if argument == 65535 else argument - 256) if game == "fe7" else (argument - 256 if argument >= 256 and argument != 65535 else 0)
					faces[slot] = portrait
					speaker = face_name(portrait)
			elif argument >= 10 and argument <= 17:
				flush()
				var target := argument - 2
				if faces.has(slot):
					var moving: int = faces[slot]
					if game == "fe6": faces.erase(slot)
					if faces.has(target): faces[slot] = faces[target]
					else: faces.erase(slot)
					faces[target] = moving
				slot = target
				portrait = faces.get(slot)
				speaker = face_name(portrait)
			elif game == "fe7" and argument == 32:
				buffer += "Tactician"
			elif game == "fe7" and argument == 35:
				flush()
				var name := ""
				while index < tokens.size() and int(tokens[index][0]) != 1:
					if not tokens[index][1]: name += String.chr(int(tokens[index][0]))
					index += 1
				speaker = name.strip_edges() if not name.strip_edges().is_empty() else fallback
				portrait = null
		elif code >= 8 and code <= 15:
			flush()
			slot = code
			portrait = faces.get(slot)
			speaker = face_name(portrait)
		elif code == 17:
			flush()
			faces.erase(slot)
			portrait = null
			speaker = ""
		elif code == 3: flush()
		elif code in [1,2]: buffer += " "
		elif game == "fe6" and code >= 32: buffer += String.chr(code)
	flush()
	return pages

func face_name(face: Variant) -> String:
	if face == null: return ""
	if int(face) == -1: return default_speaker
	return str(names.get(int(face), ""))

func portrait_path(face: int) -> String:
	return "res://content/%s/rom/portraits/%03d.png" % [game, face]

func flush() -> void:
	var text: String = decoder.normalize_text(buffer)
	buffer = ""
	if text.is_empty(): return
	var page := {"speaker":speaker, "text":text, "rom_portrait_slots":true}
	if game == "fe7":
		page.source_text_id = text_id
		page.source_speaker_slot = slot
	else:
		page.skip_stop = pages.is_empty()
	if (game == "fe7" and portrait != null) or (game == "fe6" and faces.get(slot, 0) != 0):
		var face := int(portrait)
		if game == "fe7": page.source_portrait_id = face
		if face == -1: page.portrait_role = "visitor"
		else: page.portrait = portrait_path(face)
		page.speaker_side = "left" if slot in [8,9,10,14] else "right"
	if game == "fe6": page.speaker_side = "left" if slot in [8,9,10,14] else "right"
	for side in ["left", "right"]:
		var candidates: Array = [8,9,10,14] if side == "left" else [11,12,13,15]
		var visible: Array = []
		for occupied in faces:
			if occupied in candidates and (game == "fe7" or faces[occupied] != 0): visible.append(occupied)
		var selected: Variant = slot if slot in visible else (visible.back() if not visible.is_empty() else null)
		var face: Variant = faces[selected] if selected != null else null
		page[side + "_portrait"] = portrait_path(int(face)) if face != null and face != -1 else ""
		if face == -1: page[side + "_portrait_role"] = "visitor"
	# FE6 battle quotes load a face into the default slot without opening a
	# dialogue-stage position. Keep that ROM-selected face visible on the left.
	if game == "fe6" and slot not in range(8,16) and page.has("portrait"):
		page.left_portrait = page.portrait
		page.right_portrait = ""
		page.speaker_side = "left"
	pages.append(page)
