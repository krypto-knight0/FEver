extends RefCounted
## Compatibility facade for the dialogue pack; card portraits have a separate store.
const ROOT := "user://dialogue-portraits/"
static var fe7_store = preload("res://runtime/portrait_store.gd").new(ROOT)
static var fe6_store = preload("res://runtime/portrait_store.gd").new("user://dialogue-portraits-fe6/", false, "fe6")
static var store:
	get: return for_game(str(load("res://runtime/rom_assets.gd").game_id))
	set(value):
		if str(load("res://runtime/rom_assets.gd").game_id) == "fe6": fe6_store = value
		else: fe7_store = value

static func for_game(game: String):
	return fe6_store if game == "fe6" else fe7_store

static var entries: Array:
	get: return store.entries

static var directory: String:
	get: return store.directory

static var loaded: bool:
	get: return store.loaded

static var textures: Dictionary:
	get: return store.textures

static var defaults: Dictionary:
	get: return store.defaults

static var editable_defaults: bool:
	get: return store.editable_defaults

# Use a distinct name: GDScript resources already expose a native reload().
static func reload_cache() -> void:
	store.reload()

static func disable() -> void:
	store.disable()

static func default_values() -> Dictionary:
	return store.default_values()

static func save_defaults(scale_percent: float, x_percent: float, y_percent: float) -> String:
	return store.save_defaults(scale_percent, x_percent, y_percent)

static func import_pack(path: String, refresh: bool = true) -> String:
	return store.import_pack(path, refresh)

static func find_portrait(character: String, context: Dictionary = {}) -> Dictionary:
	return store.find_portrait(character, context)

static func texture(entry: Dictionary) -> Texture2D:
	return store.texture(entry)
