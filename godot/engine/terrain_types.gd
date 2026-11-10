extends RefCounted
## FE6/FE7 terrain identities. Labels are presentation only; map symbols retain
## these IDs through map changes and saved terrain rows.
const SYMBOLS := "0.rvcVA$a1OEFts2RMPB3wS_4fWC5IDTQqHG6uK789!%#YX&()*Nb,dehj-/:kz+l"
const UNKNOWN := -1
const PLAIN := 1
const FORT := 10
const FOREST := 12
const DESERT := 15
const RIVER := 16
const MOUNTAIN := 17
const PEAK := 18
const SEA := 21
const LAKE := 22
const GLACIER := 47
const WATER := [RIVER, SEA, LAKE]
const HIGHLANDS := [MOUNTAIN, PEAK]

static func from_symbol(symbol: String) -> int:
	return SYMBOLS.find(symbol) if symbol.length() == 1 else UNKNOWN

static func blocks_free_movement(id: int, game: String) -> bool:
	# FE6 uses the fence slots as walls. Closed doors/roofs and the unnamed
	# impassable structure must stay blocked even when a class can cross them.
	return id in [26,27,30,34,44,46] or (game == "fe6" and id in [25,50])
