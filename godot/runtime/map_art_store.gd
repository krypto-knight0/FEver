extends "res://runtime/portrait_store.gd"
## Map artwork changes pixels only. Terrain and events always come from the ROM.
const Assets = preload("res://runtime/rom_assets.gd")
const CATALOG := "res://runtime/map_art_catalog.json"
const NEED_CARTRIDGE := "Load a supported FE7 cartridge before importing custom maps."
var _catalog: Dictionary = {}
var _catalog_generation := -1
var _catalog_error := ""
var _catalog_mutex := Mutex.new()
var catalog: Dictionary:
	get:
		_catalog_mutex.lock()
		_load_catalog()
		var result := _catalog
		_catalog_mutex.unlock()
		return result

func _init(storage_root: String = "user://map-art/") -> void:
	super(storage_root)
	config_name = "maps.json"
	array_key = "maps"

func _load_catalog() -> void:
	# Script preloads construct the store before cartridge import completes.
	# Mounted PCKs can survive a game switch, so file existence is insufficient.
	if not Assets.content_ready or not Assets.initialized() or Assets.game_id != "fe7":
		_catalog = {}
		_catalog_generation = -1
		_catalog_error = NEED_CARTRIDGE
		return
	if _catalog_generation == Assets.content_generation: return
	_catalog_generation = Assets.content_generation
	_catalog = {}
	_catalog_error = "Could not read the imported map catalog. Load the cartridge again."
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(CATALOG)) == OK and parser.data is Array and not parser.data.is_empty():
		var records := {}
		for record in parser.data:
			if not record is Dictionary or not record.get("id") is String or record.id.is_empty() or records.has(record.id): break
			if not preload("res://runtime/rom_data.gd").integer(record.get("width"), 1, 255) or not preload("res://runtime/rom_data.gd").integer(record.get("height"), 1, 255): break
			records[record.id] = record
		if records.size() == parser.data.size():
			_catalog = records
			_catalog_error = ""
	if not _catalog_error.is_empty() and Assets.diagnostic_sink.is_valid():
		Assets.diagnostic_sink.call("map_catalog_invalid", {"game_id":"fe7", "resource":CATALOG})

func available() -> bool:
	return not catalog.is_empty()

func import_pack(path: String, refresh: bool = true, image_field: String = "image", activate: bool = true, pack_id: String = "") -> String:
	report = preload("res://runtime/import_report.gd").new()
	if not available(): return _catalog_error
	return super.import_pack(path, refresh, image_field, activate, pack_id)

func validate_entry(entry: Dictionary, identifiers: Dictionary) -> String:
	if not available(): return _catalog_error
	var id := str(entry.get("id", ""))
	if not catalog.has(id): return "Unknown map artwork id: " + id
	if identifiers.has(id): return "Duplicate map artwork id: " + id
	identifiers[id] = true
	entry.character = id
	return ""

func validate_dimensions(entry: Dictionary, width: int, height: int) -> String:
	if not available(): return _catalog_error
	var record: Dictionary = catalog.get(str(entry.id), {})
	if record.is_empty(): return "Unknown map artwork id: " + str(entry.id)
	var columns := int(record.width)
	var rows := int(record.height)
	@warning_ignore("integer_division") # Intentional integer truncation.
	if width % columns != 0 or height % rows != 0 or width / columns != height / rows:
		return "%s must have %d × %d square tiles, without borders or cropping." % [entry.id, columns, rows]
	if width * height > 4194304: return "Keep each map image at or below 4 megapixels for mobile."
	return ""
