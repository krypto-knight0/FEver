extends RefCounted
## FE6's event words and 12-byte condition rows are distinct from FE7's VM.
## Import reviewed operands; complex callbacks retain their gameplay adapters.
const Groups = preload("res://runtime/rom_deployments.gd")
const PHASES := {0:"player", 64:"npc", 128:"enemy"}

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("FE6 chapter events", reason)
	return null

static func script(d: RefCounted, chapter: int, source: Dictionary) -> int:
	var header := Groups.chapter_events(d,"fe6",chapter)
	return Groups.script_root(d,header,source,"fe6") if header >= 0 else -1

static func commands(d: RefCounted, start: int) -> Array:
	var result: Array = []
	var at := start
	for i in range(Groups.MAX_COMMANDS):
		var entry := Groups.command(d,at,0,"fe6")
		if entry.is_empty(): return []
		result.append(entry)
		if entry.opcode == 6: return result
		at += int(entry.words)*4
	fail(d,"Event script has no bounded terminator.")
	return []

