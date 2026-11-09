extends RefCounted
static var store = preload("res://runtime/map_art_store.gd").new()

static func texture(path: String) -> Texture2D:
	if path.begins_with("res://content/fe6/"): return null
	if not store.available(): return null
	var entry: Dictionary = store.find_portrait(path.get_file().get_basename())
	if not entry.is_empty(): return store.texture(entry)
	return null

static func record(path: String) -> Dictionary:
	if path.begins_with("res://content/fe6/"): return {}
	return store.catalog.get(path.get_file().get_basename(), {})
