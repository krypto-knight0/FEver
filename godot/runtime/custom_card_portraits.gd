extends RefCounted
## Unit-card packs are selected and cached independently from dialogue packs.
static var fe7_store = preload("res://runtime/portrait_store.gd").new("user://card-portraits/")
static var fe6_store = preload("res://runtime/portrait_store.gd").new("user://card-portraits-fe6/", false, "fe6")
static var store:
	get: return for_game(str(load("res://runtime/rom_assets.gd").game_id))
	set(value):
		if str(load("res://runtime/rom_assets.gd").game_id) == "fe6": fe6_store = value
		else: fe7_store = value

static func for_game(game: String):
	return fe6_store if game == "fe6" else fe7_store
