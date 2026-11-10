extends RefCounted
## One cold import's support-table index and character names. No decoded pages
## survive between pair reads, and the importer releases this object on completion.
const Data = preload("res://runtime/rom_data.gd")
const Dialogue = preload("res://runtime/rom_dialogue_controls.gd")
# Conversation-table pointer, record size, character count, partner capacity.
const LAYOUTS := {"fe7":[0x78a94,20,253,7], "fe6":[0x6afe0,16,226,10]}
var decoder: RefCounted
var game := ""
var conversations: Dictionary = {}
var names: Dictionary = {}
var character_names: Dictionary = {}
var character_addresses: Dictionary = {}
var context: Dictionary = {}
var layout: Array = []

func configure(source: RefCounted, selected_game: String, dynamic: bool = false) -> bool:
	decoder = source
	game = selected_game
	conversations.clear()
	names.clear()
	character_names.clear()
	character_addresses.clear()
	if not LAYOUTS.has(game): return fail("Unknown support profile.")
	layout = decoder.layout.get("support_layout",LAYOUTS[game])
	var character_layout: Array = decoder.layout.get("record_layout",Data.RECORD_LAYOUTS[game])
	var table: int = decoder.ptr(int(character_layout[0]))
	if not decoder.require_range(table, int(layout[2]) * int(character_layout[1]), "Support characters"): return false
	for index in range(256 if dynamic and game == "fe6" else int(layout[2])):
		var at := table + index * int(character_layout[1])
		if dynamic and game == "fe6" and (at+int(character_layout[1]) > decoder.rom.size() or (index > 0 and decoder.u8(at+4) != index)): break
		var id: int = decoder.u8(at + 4)
		var name_id: int = decoder.u16(at)
		var face: int = decoder.u16(at + 6)
		var name: String = decoder.text(name_id) if name_id != 0 else ""
		character_addresses[id] = at
		character_names[id] = name
		if face != 0 and not name.is_empty() and (game == "fe7" or not names.has(face)):
			names[face] = name
	# Alternate fe7_unit_3 portrait uses the same character name, read from the ROM.
	if game == "fe7" and names.has(22): names[26] = names[22]
	if not decoder.error.is_empty(): return false
	table = decoder.ptr(int(layout[0]))
	for index in range(1024):
		var at := table + index * int(layout[1])
		if not decoder.require_range(at, int(layout[1]), "Support conversation table"): return false
		var a: int = decoder.u8(at)
		var b: int = decoder.u8(at + 1)
		if a == 0 and b == 0: return true
		if a == 0 or b == 0 or a == b: return fail("Invalid support pair.", at)
		var key := pair_key(a, b)
		if conversations.has(key): return fail("Duplicate support pair.", at)
		conversations[key] = at
	return fail("Unterminated support conversation table.", table)

func fail(reason: String, at: int = -1) -> bool:
	decoder.fail("ROM supports", reason, at)
	return false

func pair_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a,b),maxi(a,b)]

func growth(a: int, b: int) -> Array:
	if not character_addresses.has(a):
		fail("Support character is absent.")
		return []
	var count := int(layout[3])
	var table: int = decoder.ptr(int(character_addresses[a]) + 44)
	if not decoder.require_range(table, count * 3 + 2, "Support growth table"): return []
	var size: int = decoder.u8(table + count * 3)
	if size > count:
		fail("Invalid support partner count.", table)
		return []
	for index in range(size):
		if decoder.u8(table + index) == b:
			return [decoder.u8(table + count + index), decoder.u8(table + count * 2 + index)]
	fail("Support partner is absent from the growth table.", table)
	return []

func read(spec: Variant, pair: Dictionary) -> Variant:
	if not spec is Dictionary or spec.size() != 2 or spec.get("game") != game or not spec.get("characters") is Array or spec.characters.size() != 2:
		fail("Invalid support recipe.")
		return null
	for id in spec.characters:
		if not Data.integer(id, 1, 255):
			fail("Invalid support character ID.")
			return null
	if not pair.get("a") is String or not pair.get("b") is String or pair.a.is_empty() or pair.b.is_empty() or pair.a == pair.b:
		fail("Support identities must be distinct stable IDs.")
		return null
	if pair.get("rom_character_ids") != spec.characters:
		fail("Support recipe conflicts with its character identities.")
		return null
	var a := int(spec.characters[0])
	var b := int(spec.characters[1])
	var key := pair_key(a,b)
	context.support_pair = key
	if not conversations.has(key):
		fail("Support pair is absent from the conversation table.")
		return null
	var values := growth(a,b)
	var reverse := growth(b,a)
	if not decoder.error.is_empty(): return null
	if values != reverse:
		fail("Asymmetric support growth.")
		return null
	var at := int(conversations[key])
	var initial := int(values[0])
	var result := {"a_name":character_names[a], "b_name":character_names[b],
		"points":mini(240,initial) if game == "fe7" else initial, "growth":values[1],
		"rank":3 if game == "fe7" and initial > 240 else 0, "source_offset":"0x%x" % at,
		"source_text_ids":{}, "dialogue":{}}
	if game == "fe7": result.source_initial_points = initial
	for rank in range(1,4):
		var label: String = ["C","B","A"][rank-1]
		var id: int = decoder.u32(at + rank * 4)
		context.text_id = id
		context.support_rank = label
		result.source_text_ids[label] = id
		var pages := Dialogue.new().read(decoder, game, names, id, str(result.a_name))
		if not decoder.error.is_empty(): return null
		for page in pages:
			page.scene_type = "dialogue"
			page.background = ""
			page.support_pair = pair.a + "|" + pair.b
			page.support_rank = label
			page.skip_group = "support_%s_%s_%s" % [pair.a,pair.b,label] if game == "fe7" else "fe6_support_%d_%d_%s" % [a,b,label]
		if game == "fe7" and not pages.is_empty(): pages[0].skip_stop = true
		result.dialogue[str(rank)] = pages
	return result
