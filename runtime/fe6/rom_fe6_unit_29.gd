extends RefCounted
## Reviewed conditional arrival, squad retreat and reward graph. Operands stay
## in the cartridge; structural selectors describe the supported event shape.
const Groups = preload("res://runtime/rom_deployments.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Flags = preload("res://engine/native_event_flags.gd")

static func fail(d: RefCounted, message: String) -> bool:
	d.fail("FE6 conditional cavalry",message)
	return false

static func command(d: RefCounted, chapter: int, source: Dictionary, index: int, opcode: int, words: int) -> int:
	var header := Groups.chapter_events(d,"fe6",chapter)
	if header < 0: return -1
	var root := Groups.script_root(d,header,source,"fe6")
	if root < 0: return -1
	var entry := Groups.command(d,root,index,"fe6")
	if entry.is_empty(): return -1
	if entry.opcode != opcode or entry.words != words:
		fail(d,"Conditional event shape changed."); return -1
	return int(entry.offset)

static func escape_points(d: RefCounted, chapter: int, green: bool = true, allow_empty: bool = false) -> Variant:
	# AiGetNearestEscapePoint's green-faction pointer literal. Entries are
	# four-byte {x,y,facing,padding} records terminated by x=255.
	var table := Groups.pointer(d,0x32cac if green else 0x32c60)
	if table < 0: return null
	var at := Groups.pointer(d,table+chapter*4)
	if at < 0: return null
	var points: Array = []
	for i in range(64):
		if not d.require_range(at,4,"FE6 green escape points"): return null
		if d.u8(at) == 255:
			if points.is_empty() and not allow_empty: fail(d,"Squad has no native escape point."); return null
			return points
		points.append([d.u8(at),d.u8(at+1)])
		at += 4
	fail(d,"Unterminated native escape list.")
	return null

