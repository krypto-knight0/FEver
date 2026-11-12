extends RefCounted
## Both games generate campaign data and asset recipes from the inserted cartridge.
const Header = preload("res://runtime/rom_header.gd")
static var game_id := "fe7"
static var rom_digest := ""
static var dynamic_content: RefCounted
static var dynamic_publication := 0
static var dynamic_mutex := Mutex.new()
static var dynamic_directory_prepared := false
static var display_name := "FE7"
static var decoder: RefCounted
static var assets: Dictionary = {}
static var import_root := ""
static var loader: ResourceFormatLoader
static var dialogue_cache: Dictionary = {}
static var progress := ""
static var error := ""
static var source_path := ""
static var diagnostic_sink := Callable()
static var decode_context: Dictionary = {}
static var content_ready := false
static var content_generation := 0
static var item_catalog: Dictionary = {}
const DECODE_FAILURE := "Could not prepare game data. Try loading the cartridge again. If this continues, export diagnostics from Settings and information."

static func initialized() -> bool: return decoder != null and error.is_empty() and decoder.error.is_empty()

static func _decode_failed(details: Dictionary) -> void:
	if not error.is_empty(): return
	error = DECODE_FAILURE
	dialogue_cache.clear()
	record_decode_failure(details, decode_context, game_id)

static func record_decode_failure(details: Dictionary, context: Dictionary, selected_game: String) -> void:
	var event := details.duplicate()
	event.merge(context)
	event.game_id = selected_game
	# The caller supplies Journal.write on the main thread. It is mutex-protected
	# and can be called from the ROM worker without looking up scene-tree nodes.
	if diagnostic_sink.is_valid(): diagnostic_sink.call("rom_decode_failed", event)

static func _reset_loaded_state() -> void:
	dynamic_content = null
	dynamic_publication = 0
	rom_digest = ""
	content_ready = false
	content_generation += 1
	decoder = null
	assets.clear()
	dialogue_cache.clear()
	import_root = ""
	source_path = ""
	decode_context.clear()
	item_catalog.clear()

static func load_rom(path: String, private_copy: bool = OS.has_feature("mobile")) -> String:
	_reset_loaded_state()
	error = ""
	progress = "Checking ROM…"
	var failure := _load_rom(path, private_copy)
	if decoder != null and decoder.has_meta("deployment_groups"): decoder.remove_meta("deployment_groups")
	if not failure.is_empty():
		error = failure
		progress = failure
		_reset_loaded_state()
	return failure

static func _load_rom(path: String, private_copy: bool) -> String:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return "Cannot open the saved ROM. Choose the file again."
	if file.get_length() > 32*1024*1024 or file.get_length() < 192:
		return "Unsupported cartridge size. Choose a supported FE7 or FE6 ROM."
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() != file.get_length(): return "Could not finish reading the cartridge. Choose the file again."
	file.close()
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	var digest := hasher.finish().hex_encode()
	var code := bytes.slice(0xac,0xb0).get_string_from_ascii()
	return _load_dynamic(bytes,digest,path,private_copy,"fe7" if code in preload("res://runtime/fe7/fe7_dynamic_profile.gd").GAME_CODES else "fe6")

static func _load_dynamic(bytes: PackedByteArray, digest: String, path: String, private_copy: bool, selected_game: String) -> String:
	var profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd") if selected_game == "fe7" else preload("res://runtime/fe6/fe6_dynamic_profile.gd")
	var detection: Dictionary = profile.detect(bytes)
	if not detection.error.is_empty(): return "Unsupported cartridge. "+str(detection.error)
	progress = "Reading %s cartridge…" % selected_game.to_upper()
	import_root = "user://rom-import/dynamic"
	if DirAccess.make_dir_recursive_absolute(import_root) != OK: return "Cannot create temporary ROM import storage."
	if not dynamic_directory_prepared:
		# Previous-process packages only: packs mounted this session stay alive.
		for name in DirAccess.get_files_at(import_root):
			if name.begins_with("dynamic-") and (name.ends_with(".pck") or name.ends_with(".json")):
				DirAccess.remove_absolute(import_root.path_join(name))
		dynamic_directory_prepared = true
	var content: RefCounted
	if selected_game == "fe7": content = preload("res://runtime/fe7/fe7_dynamic_content.gd").new()
	else: content = preload("res://runtime/fe6/fe6_dynamic_content.gd").new()
	if not content.initialize(bytes,digest,import_root): return content.error
	var selected_path := path
	if private_copy:
		var target := "user://roms/"+selected_game+"-"+digest+".gba"
		if path != target:
			DirAccess.make_dir_recursive_absolute("user://roms")
			var file := FileAccess.open(target+".pending",FileAccess.WRITE)
			if file == null: return "Cannot save this cartridge on the device."
			file.store_buffer(bytes); file.flush()
			var result := file.get_error(); file.close()
			if result != OK or FileAccess.get_sha256(target+".pending") != digest: return "Could not finish saving this cartridge."
			if DirAccess.rename_absolute(target+".pending",target) != OK: return "Cannot install this cartridge."
		selected_path = target
	game_id = selected_game; rom_digest = digest; dynamic_content = content
	display_name = Header.display_name(Header.from_bytes(bytes), selected_game.to_upper())
	source_path = selected_path
	decoder = profile.decoder(bytes)
	decoder.failed.connect(_decode_failed)
	assets = content.assets.duplicate(true); item_catalog = content.items.duplicate(true)
	dynamic_publication = content.revision
	content_ready = true; progress = "Ready"
	return ""

static func ensure_resource(path: String) -> bool:
	if dynamic_content == null: return true
	dynamic_mutex.lock()
	if not dynamic_content.ensure(path):
		progress = dynamic_content.error
		if diagnostic_sink.is_valid(): diagnostic_sink.call("dynamic_chapter_unsupported",{"game_id":game_id,"rom_sha256":rom_digest,"path":path,"reason":progress})
		dynamic_mutex.unlock()
		return false
	_publish_dynamic_assets()
	dynamic_mutex.unlock()
	return true

static func _publish_dynamic_assets() -> void:
	if dynamic_publication != dynamic_content.revision:
		# Publish replacement dictionaries; active readers retain their old snapshot.
		assets = dynamic_content.assets.duplicate(true)
		item_catalog = dynamic_content.items.duplicate(true)
		dynamic_publication = dynamic_content.revision
		progress = "Ready"

static func prepare_battle_art(units: Array) -> bool:
	if dynamic_content == null: return true
	dynamic_mutex.lock()
	var ok: bool = dynamic_content.prepare_battle_art(units)
	if ok: _publish_dynamic_assets()
	else:
		progress = dynamic_content.error
		if diagnostic_sink.is_valid(): diagnostic_sink.call("dynamic_arena_unsupported",{"rom_sha256":rom_digest,"reason":progress})
	dynamic_mutex.unlock()
	return ok

static func prepare_story_art(pages: Array) -> Variant:
	if dynamic_content == null: return pages
	dynamic_mutex.lock()
	var ok: bool = dynamic_content.prepare_story_art(pages)
	var result: Variant = null
	if ok:
		_publish_dynamic_assets()
		result = dynamic_content.rebase_support(pages)
	else:
		progress = dynamic_content.error
		if diagnostic_sink.is_valid(): diagnostic_sink.call("dynamic_ending_unsupported",{"rom_sha256":rom_digest,"reason":progress})
	dynamic_mutex.unlock()
	return result

static func library_catalog(kind: String) -> Array:
	if dynamic_content == null: return []
	dynamic_mutex.lock()
	var result: Array = dynamic_content.library_catalog(kind)
	_publish_dynamic_assets()
	dynamic_mutex.unlock()
	return result

static func install_loader() -> void:
	if loader==null:
		loader=preload("res://runtime/rom_resource_loader.gd").new()
		ResourceLoader.add_resource_format_loader(loader,true)

static func image(path: String) -> Image:
	if not initialized() or not assets.has(path): return null
	if dynamic_content != null and dynamic_content.library != null and dynamic_content.library.assets.has(path):
		var pixels: Image = dynamic_content.library.image(path)
		if pixels == null and diagnostic_sink.is_valid(): diagnostic_sink.call("dynamic_library_image_failed",{"rom_sha256":rom_digest,"path":path,"error":dynamic_content.library.failures.get(path,{})})
		return pixels
	decode_context = {"stage": "image", "resource": path, "recipe": str(assets[path].get("kind", ""))}
	var result: Image = decoder.image(assets[path])
	if not decoder.error.is_empty():
		_decode_failed(decoder.error)
		return null
	return result

static func resource(path: String) -> Resource:
	if not assets.has(path): return null
	var recipe: Dictionary = assets[path]
	if recipe.kind=="audio":
		var stream := AudioStreamWAV.new()
		stream.set_meta("rom_song",int(recipe.song_id))
		stream.set_meta("rom_loop",recipe.get("loop",false))
		return stream
	var pixels := image(path)
	return ImageTexture.create_from_image(pixels) if pixels else null
