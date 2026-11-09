extends RefCounted
## Imported backgrounds remain in private storage.
static var fe7_store = preload("res://runtime/portrait_store.gd").new("user://background-art/", true, "fe7")
static var fe6_store = preload("res://runtime/portrait_store.gd").new("user://background-art-fe6/", true, "fe6")
static var store:
	get: return for_game(str(load("res://runtime/rom_assets.gd").game_id))
	set(value):
		if str(load("res://runtime/rom_assets.gd").game_id) == "fe6": fe6_store = value
		else: fe7_store = value

static func for_game(game: String):
	return fe6_store if game == "fe6" else fe7_store

static func identifier(path: String) -> String:
	var name := path.get_file().get_basename()
	if path.contains("/rom/backgrounds/") and name.is_valid_int(): return "background_%03d" % name.to_int()
	if name in ["title_card", "title_screen"]: return "title_fe6" if path.contains("/fe6/") else "title_fe7"
	if path.contains("/battle/"):
		return "battle_" + name if name.begins_with("platform_") else "battle_background_" + name
	return name

static func texture(path: String) -> Texture2D:
	var selected = for_game("fe6") if path.contains("/fe6/") or path.get_file().get_basename() == "title_fe6" else for_game("fe7") if path.contains("/fe7/") or path.get_file().get_basename() == "title_fe7" else store
	var entry: Dictionary = selected.find_portrait(identifier(path))
	if not entry.is_empty(): return selected.texture(entry)
	return null
