extends RefCounted
## FE7 ending records: type, character, partner, padding, text ID (8 bytes).
## Ending text stays in the player's ROM.
const Army = preload("res://engine/army_roster.gd")

static func pages(state: RefCounted, route: String, decoder: RefCounted) -> Array:
	var result: Array = []
	if decoder == null: return result
	var japanese: bool = decoder.layout.get("event_variant","") == "fe7j"
	var roster: Dictionary = {}
	for unit in Army.all_units(state):
		if unit.get("faction", "") == "player": roster[int(unit.get("rom_character_id", -1))] = unit
	# fe7_unit_37 leaves the active formation for story reasons; her recruitment and
	# support identity remain in the campaign's carryover roster.
	for unit in state.chapter.get("campaign_roster", {}).values():
		var id := int(unit.get("rom_character_id", -1))
		if unit.get("id", "") == "fe7_unit_37" and not roster.has(id): roster[id] = unit
	# fe7_unit_3's tutorial identity is a separate character record.
	if roster.has(3) and not roster.has(45): roster[45] = roster[3]
	if roster.has(41) and not roster.has(38): roster[38] = roster[41]
	var titles: Dictionary = {}
	var at: int = decoder.ptr(0xB8C1C if japanese else 0xB7EB8)
	var terminated := false
	for index in range(256):
		if not decoder.require_range(at+index*8,8,"FE7 ending titles"): return []
		var id: int = decoder.u32(at + index * 8)
		if id == 0: terminated = true; break
		if id > 255: decoder.fail("FE7 ending","Invalid ending title character.",at+index*8); return []
		titles[id] = decoder.text(decoder.u32(at + index * 8 + 4)).strip_edges()
	if not terminated: decoder.fail("FE7 ending","Unterminated title table.",at); return []
	var route_table: int = decoder.ptr(0xB8F2C if japanese else 0xB8290)
	at = decoder.ptr(route_table+(4 if route == "fe7_unit_2" else 0))
	var records: Array = []
	terminated = false
	for index in range(256):
		var address := at + index * 8
		if not decoder.require_range(address,8,"FE7 ending records"): return []
		var kind: int = decoder.rom[address]
		if kind == 0: terminated = true; break
		if kind == 5 and decoder.rom[address+1] == 205 and decoder.u32(address+4) == 0:
			if state.chapter.get("dynamic_rom",false): records.append({"kind":5,"first":205,"second":0,"text":0})
			continue
		if kind not in [1,2,3,4]: decoder.fail("FE7 ending","Unsupported character ending.",address); return []
		records.append({"kind": kind, "first": int(decoder.rom[address + 1]), "second": int(decoder.rom[address + 2]), "text": decoder.u32(address + 4)})
	if not terminated: decoder.fail("FE7 ending","Unterminated character endings.",at); return []
	if not decoder.error.is_empty(): return []
	var chosen: Array = []
	var paired: Dictionary = {}
	# Reserve valid A-support pairs before any single ending, including lords
	# whose records occur after their potential partners' single endings.
	for record in records:
		if record.kind not in [2, 4] or not roster.has(record.first) or not roster.has(record.second): continue
		var first: Dictionary = roster[record.first]
		var second: Dictionary = roster[record.second]
		if not _survived(state, first) or not _survived(state, second) or paired.has(record.first) or paired.has(record.second): continue
		var ids: Array = [str(first.id), str(second.id)]; ids.sort()
		if record.kind == 2 and int(state.support_ranks.get("|".join(ids), 0)) < 3: continue
		chosen.append(record); paired[record.first] = true; paired[record.second] = true
	for record in records:
		if record.kind != 3 or paired.has(record.first) or paired.has(record.second): continue
		if not roster.has(record.first) or not roster.has(record.second): continue
		if not _survived(state, roster[record.first]) or not _survived(state, roster[record.second]): continue
		chosen.append(record); paired[record.first] = true; paired[record.second] = true
	var shown: Dictionary = {}
	for record in records:
		if record.kind == 5:
			var ranking := preload("res://engine/fe7_campaign_rank.gd").page(state,decoder)
			if not ranking.is_empty(): result.append(ranking)
			continue
		if not roster.has(record.first) or shown.has(record.first): continue
		if not chosen.has(record) and (record.kind != 1 or paired.has(record.first)): continue
		var first: Dictionary = roster[record.first]
		var members: Array = [first]
		var heading := str(titles.get(record.first, first.get("name", "")))
		var text: String = decoder.text(int(record.text)).replace("\n", " ").strip_edges()
		if chosen.has(record):
			members.append(roster[record.second]); shown[record.second] = true
			heading = str(first.name) + " & " + str(roster[record.second].name)
		elif not _survived(state, first):
			# Don't invent a surviving life story or death chapter for a fallen ally.
			text = "%s fell during the journey. Their companions carried their memory into the peace that followed." % first.name
		shown[record.first] = true
		if not text.is_empty(): result.append({"title": heading, "text": text, "units": members})
	# The ROM provides only a combined fe7_unit_21/fe7_unit_15 ending. If that record is
	# unavailable, still account for their actual survival without inventing a pair.
	for id in [21, 15]:
		if not roster.has(id) or shown.has(id): continue
		var unit: Dictionary = roster[id]
		result.append({"title": str(titles.get(id, unit.name)), "text": "%s survived the journey." % unit.name if _survived(state, unit) else "%s fell during the journey." % unit.name, "units": [unit]})
	return result

static func _survived(state: RefCounted, unit: Dictionary) -> bool:
	return int(unit.get("hp", 0)) > 0 or (not bool(state.rules.get("permadeath", true)) and unit.get("casualty_mode","") != "permanent")
