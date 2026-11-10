extends RefCounted
## FE6 condition/death flags and reviewed script operands. Recipes retain only
## structural selectors; flag numbers always come from the loaded cartridge.
const Groups = preload("res://runtime/rom_deployments.gd")
const Flags = preload("res://engine/native_event_flags.gd")

static func fail(d: RefCounted, message: String) -> bool:
	d.fail("FE6 native flags",message)
	return false

static func flag(d: RefCounted, value: int) -> int:
	if value in [0,100] or Flags.valid_id(value,"any","fe6"): return value
	fail(d,"Flag exceeds FE6's chapter or permanent storage.")
	return -1

static func bindings(d: RefCounted, chapter: int, sites: Array) -> Variant:
	# These getters delimit the real bit banks, not just the facade's <=99 test.
	if d.raw(0x6ba90,4).hex_encode() != "05207047" or d.raw(0x6ba9c,4).hex_encode() != "04207047":
		fail(d,"Unsupported FE6 flag-bank layout."); return null
	var result := {"defeats":[],"sites":[]}
	var at := Groups.pointer(d,0x6b7fc)
	if at < 0: return null
	var characters := {}
	var ended := false
	for i in range(256):
		if not d.require_range(at,16,"FE6 death flag"): return null
		var character: int = d.u8(at)
		if character in [0,255]: ended = true; break
		# Death entries are searched in order. A chapter-specific entry (even
		# one without a flag) takes precedence over a later global entry.
		if d.u8(at+1) in [chapter,45] and not characters.has(character):
			characters[character] = true
			var value := flag(d,d.u32(at+8))
			if value < 0: return null
			if value not in [0,100]: result.defeats.append({"character":character,"flag":value})
		at += 16
	if not ended: fail(d,"Unterminated death table."); return null
	var header := Groups.chapter_events(d,"fe6",chapter)
	if header < 0: return null
	at = Groups.pointer(d,header+8)
	if at < 0: return null
	for i in range(128):
		if not d.require_range(at,12,"FE6 site flag"): return null
		if d.u16(at) == 0: return result
		if d.u16(at) in [6,7,8]:
			var value := flag(d,d.u16(at+2))
			if value < 0: return null
			if value not in [0,100]:
				var matches: Array = sites.filter(func(s):return int(s.get("x",-1)) == d.u8(at+8) and int(s.get("y",-1)) == d.u8(at+9))
				if matches.size() != 1: fail(d,"Flagged site has no unique engine interaction."); return null
				result.sites.append({"id":matches[0].id,"flag":value})
		at += 12
	fail(d,"Unterminated site table.")
	return null

