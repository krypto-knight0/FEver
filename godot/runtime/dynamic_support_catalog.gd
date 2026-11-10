extends RefCounted
## Index support metadata now; decode conversation pages only when requested.
const Reader = preload("res://runtime/rom_support_data.gd")
const AFFINITIES := ["fire","thunder","wind","ice","dark","light","anima"]
const STATS := ["atk","def","hit","avo","crit","ddg"]
static func catalog(d: RefCounted, prefix: String, assets: Dictionary, game: String, rules: Dictionary, affinity_operand: int) -> Dictionary:
	var reader := Reader.new()
	if not reader.configure(d,game,true): return {}
	var result := {"schema_version":1,"game_id":game,"characters":[],"pairs":[],"rules":rules.duplicate(true)}
	var characters := {}
	for id in reader.character_addresses:
		if int(id) == 0: continue
		var at := int(reader.character_addresses[id])
		if d.u32(at+44) == 0: continue
		var affinity: int = d.u8(at+9)
		if affinity < 1 or affinity > AFFINITIES.size(): d.fail(game.to_upper()+" supports","Invalid affinity."); return {}
		var face: int = d.u16(at+6)
		var path := prefix+"rom/portraits/%03d.png" % face
		assets[path] = {"kind":"portrait","id":face}
		var character := {"id":"%s_unit_%d" % [game,id],"name":reader.character_names[id],"rom_character_ids":[id],"affinity":AFFINITIES[affinity-1],"portrait":path}
		characters[id] = character; result.characters.append(character)
	# Alternate deployment records use the preceding native character identity.
	for id in reader.character_addresses:
		if game == "fe6" and d.u32(int(reader.character_addresses[id])+40)&0x800000 and characters.has(int(id)-1): characters[int(id)-1].rom_character_ids.append(id)
	for key in reader.conversations:
		var at := int(reader.conversations[key])
		var a: int = d.u8(at); var b: int = d.u8(at+1)
		if not characters.has(a) or not characters.has(b): d.fail(game.to_upper()+" supports","Conversation has no character/growth record."); return {}
		var growth := reader.growth(a,b)
		if growth != reader.growth(b,a): d.fail(game.to_upper()+" supports","Asymmetric support growth."); return {}
		if not d.error.is_empty(): return {}
		var pair := {"a":characters[a].id,"b":characters[b].id,"a_name":characters[a].name,"b_name":characters[b].name,
			"rom_character_ids":[a,b],"points":mini(240,int(growth[0])) if game == "fe7" else growth[0],"growth":growth[1],"rank":3 if game == "fe7" and int(growth[0]) > 240 else 0,"dialogue_reference":true,
			"source_text_ids":{},"dialogue_path":prefix+"supports/%d_%d.json" % [a,b]}
		for rank in range(3): pair.source_text_ids[["C","B","A"][rank]] = d.u32(at+4+rank*4)
		result.pairs.append(pair)
	result.rules.support_affinities = {}
	var table: int = d.ptr(affinity_operand)
	for i in range(AFFINITIES.size()):
		var at := table+i*8
		if d.u8(at) != i+1: d.fail(game.to_upper()+" supports","Invalid affinity table."); return {}
		var values := {}
		for stat in range(STATS.size()): values[STATS[stat]] = d.u8(at+1+stat)/2.0
		result.rules.support_affinities[AFFINITIES[i]] = values
	return result if d.error.is_empty() else {}
