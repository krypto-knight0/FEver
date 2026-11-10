extends RefCounted
## Both packaged dialogue and per-cartridge lazy conversations share this access.
static func available(pair: Dictionary, rank: String) -> bool:
	if not str(pair.get("dialogue_path","")).is_empty(): return int(pair.get("source_text_ids",{}).get({"1":"C","2":"B","3":"A"}.get(rank,""),0)) > 0
	return not pair.get("dialogue",{}).get(rank,[]).is_empty()

static func pages(pair: Dictionary, rank: String) -> Array:
	var path := str(pair.get("dialogue_path",""))
	if path.is_empty(): return pair.get("dialogue",{}).get(rank,[]).duplicate(true)
	if not preload("res://runtime/rom_assets.gd").ensure_resource(path): return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("dialogue",{}).get(rank,[]).duplicate(true) if data is Dictionary else []
