extends RefCounted
## Menu labels follow live chapter and sound-room table pointers.
## Some cartridges have graphical chapter headings and empty text entries.
const CHAPTERS := {"fe7":[0x31580,152,67,0x74], "fe6":[0x2bb20,68,75,0x38]}
const SOUNDS := {"fe7":[0x1b468,16,12], "fe6":[0x8b9c4,12,4]}

static func invalid(d: RefCounted, reason: String) -> Variant:
	d.fail("ROM labels",reason)
	return null

static func number(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum and value == int(value)

static func title(d: RefCounted, id: int) -> String:
	if id == 0: return ""
	if id > 0x7fff:
		invalid(d,"Invalid label text ID.")
		return ""
	return d.text(id).replace("\n"," ").strip_edges()

static func chapter(d: RefCounted, spec: Dictionary, game: String) -> Variant:
	var layout: Array = CHAPTERS[game]
	if not number(spec.get("chapter"),int(layout[2])-1) or not spec.get("parts") is Array or spec.parts.is_empty() or spec.parts.size() > 4:
		return invalid(d,"Invalid chapter label recipe.")
	var table: int = d.ptr(int(layout[0]))
	var at: int = table + int(spec.chapter) * int(layout[1])
	if table < 0: return invalid(d,"Invalid chapter table pointer.")
	if not d.require_range(at,int(layout[1]),"Chapter labels"): return null
	var name := title(d,d.u16(at+int(layout[3])))
	var parts: PackedStringArray = []
	for part in spec.parts:
		if not part is Dictionary or not part.get("prefix") is String or not number(part.get("character",0),255):
			return invalid(d,"Invalid chapter label prefix.")
		for key in part:
			if key not in ["prefix","character"]: return invalid(d,"Unknown chapter label prefix field.")
		var prefix: String = part.prefix
		if int(part.get("character",0)) > 0:
			var characters: int = d.ptr(0x17680 if game == "fe6" else 0x9a274)
			var character: int = characters + (int(part.character)-(0 if game == "fe6" else 1)) * (48 if game == "fe6" else 52)
			if characters < 0: return invalid(d,"Invalid route character table pointer.")
			if not d.require_range(character,2,"Chapter route name"): return null
			var route := title(d,d.u16(character))
			if not route.is_empty(): prefix = route + " · " + prefix
		parts.append(prefix + (": " + name if not name.is_empty() else ""))
	if d.error.is_empty(): return " / ".join(parts)
	return null

static func sound_room(d: RefCounted, game: String) -> Variant:
	var layout: Array = d.layout.get("sound_room_layout",SOUNDS[game])
	var table: int = d.ptr(int(layout[0]))
	if table < 0: return invalid(d,"Invalid sound-room table pointer.")
	if not d.require_range(table,int(layout[1]),"Sound-room labels"): return null
	var result: Array = []
	for index in range(256):
		var at: int = table + index * int(layout[1])
		if not d.require_range(at,int(layout[1]),"Sound-room labels"): return null
		var song: int = d.u32(at)
		# Native lists use an all-ones song ID as their sentinel.
		if song == 0xffffffff: return result
		if song > 0xffff: return invalid(d,"Invalid sound-room song ID.")
		var name := preload("res://runtime/rom_japanese_text.gd").plain(d.pointer_symbols(d.u32(at+int(layout[2]))|0x80000000)) if d.layout.get("sound_room_pointers",false) else title(d,d.u32(at+int(layout[2])))
		if not d.error.is_empty(): return null
		result.append({"number":index+1,"song_id":song,"title":name if not name.is_empty() else "Track %d" % song})
	return invalid(d,"Sound-room table has no bounded terminator.")

static func audio(d: RefCounted, value: Dictionary, game: String) -> Variant:
	if value.get("$rom_audio_labels") != game or not SOUNDS.has(game) or value.has("sound_room_catalog"):
		return invalid(d,"Invalid audio label recipe.")
	var room: Variant = sound_room(d,game)
	if room == null: return null
	var names := {}
	for entry in room: names[int(entry.song_id)] = entry.title
	var result := value.duplicate(true)
	result.erase("$rom_audio_labels")
	result.sound_room_catalog = room
	for bank in ["music","sfx"]:
		if not result.get(bank,{}) is Dictionary: return invalid(d,"Invalid audio cue bank.")
		for entry in result.get(bank,{}).values():
			if not entry is Dictionary or not number(entry.get("song_id"),0xffff): return invalid(d,"Invalid audio cue song ID.")
			entry.title = names.get(int(entry.song_id),"Track %d" % int(entry.song_id))
			entry.silent = not preload("res://runtime/rom_audio.gd").has_song(d,entry.song_id)
	return result
