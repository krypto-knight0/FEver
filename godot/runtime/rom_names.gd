extends RefCounted
## Character names are read through live character-table pointers. Portrait
## variants carry identity relationships only; unnamed faces use generic labels.
const LAYOUTS := {"fe7":[0x9a274,52,1,253], "fe6":[0x17680,48,0,226]}
const EXPRESSIONS := [[2,3,4,5,6,7,8,9,10,11], [12,13,14,15,16,17,18,19,20,21],
	[22,23,24,25,26], [28,29,30], [51,52], [66,67], [84,85], [95,96,97,98], [104,105]]

static func character(d: RefCounted, game: String, id: int) -> String:
	if (game == "fe7" and id == 40) or (game == "fe6" and id == 66): return "Convoy Merchant"
	var fallback := "Character %d" % id
	if d == null or not LAYOUTS.has(game): return fallback
	var layout: Array = d.layout.get("name_layout",LAYOUTS[game])
	if id < 1 or id >= int(layout[2])+int(layout[3]):
		d.fail("ROM names","Character identity is outside the table.")
		return fallback
	var table: int = d.ptr(int(layout[0]))
	var at: int = table+(id-int(layout[2]))*int(layout[1])
	if not d.require_range(table,int(layout[3])*int(layout[1]),"Character names"): return fallback
	var text_id: int = d.u16(at)
	var name: String = d.text(text_id).strip_edges() if text_id else ""
	return name if not name.is_empty() else fallback

static func portrait(d: RefCounted, game: String, id: int, numbered: bool = false) -> String:
	var fallback := "Portrait · %03d" % id
	if d == null or not LAYOUTS.has(game): return fallback
	var faces: Array = [id]
	if game == "fe7":
		for family in EXPRESSIONS:
			if id in family: faces = family; break
	var layout: Array = d.layout.get("name_layout",LAYOUTS[game])
	var table: int = d.ptr(int(layout[0]))
	if not d.require_range(table,int(layout[3])*int(layout[1]),"Portrait names"): return fallback
	for index in range(int(layout[3])):
		var at: int = table+index*int(layout[1])
		var face: int = d.u16(at+6)
		if face == 0 or face not in faces: continue
		var text_id: int = d.u16(at)
		if text_id == 0 or d.text(text_id).strip_edges().is_empty(): continue
		return character(d, game, index + int(layout[2])) + (" · %03d" % id if numbered else "")
	return fallback
