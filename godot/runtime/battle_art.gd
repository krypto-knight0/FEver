extends RefCounted
## Battle art shares the backgrounds/CG pack and its original-art preference.
const Backdrops = preload("res://runtime/custom_backdrops.gd")
static var platforms: Dictionary = {}
static var hide_platforms := false
static var preferences_loaded := false
const PREFERENCES := "user://battle_art.cfg"

static func platforms_hidden() -> bool:
	if not preferences_loaded:
		var settings := ConfigFile.new()
		settings.load(PREFERENCES)
		hide_platforms = bool(settings.get_value("art", "hide_platforms", false))
		preferences_loaded = true
	return hide_platforms

static func set_platforms_hidden(hidden: bool) -> void:
	hide_platforms = hidden
	preferences_loaded = true
	var settings := ConfigFile.new()
	settings.set_value("art", "hide_platforms", hidden)
	settings.save(PREFERENCES)

static func family(state, unit: Dictionary) -> String:
	if state == null or unit.is_empty(): return "plains"
	if state.rules.get("arena", false): return "arena"
	var terrain := str(state.terrain_at(state.position(unit)).get("name", "Plain")).to_lower()
	if terrain in ["desert", "sand", "dune", "dunes"]: return "desert"
	if terrain in ["sea", "lake", "river", "water", "deeps", "ocean"]: return "water"
	if terrain in ["deck", "gunnel", "mast", "barrel", "ship"]: return "ship"
	if state.chapter.get("id", "") in ["fe7_eli_chapter17", "fe7_hec_chapter18"]: return "ship"
	return "castle" if terrain in ["floor", "throne", "pillar", "wall", "stairs", "door", "chest", "indoor", "tile"] else "plains"

static func entry(kind: String, state = null, unit: Dictionary = {}) -> Dictionary:
	var store = Backdrops.store
	if not store.loaded: store.reload()
	if not store.enabled: return {}
	var terrain := str(state.terrain_at(state.position(unit)).get("name", "Plain")).to_lower().replace(" ", "_") if state != null and not unit.is_empty() else "plain"
	var prefix := "battle_" + kind + "_"
	for id in [prefix + terrain, prefix + family(state, unit), prefix + "default"]:
		var portrait_entry: Dictionary = store.find_portrait(id)
		if not portrait_entry.is_empty(): return portrait_entry
	return {}

static func texture(kind: String, state = null, unit: Dictionary = {}) -> Texture2D:
	var selected := entry(kind, state, unit)
	# No matching player import: the cutscene uses its cartridge artwork.
	return Backdrops.store.texture(selected) if not selected.is_empty() else null

static func background_y(state = null, unit: Dictionary = {}) -> float:
	return clampf(float(entry("background", state, unit).get("battle_y_percent", 0)), -100, 100) * 1.6

static func platform(state, unit: Dictionary) -> Texture2D:
	if platforms_hidden(): return null
	var source := texture("platform", state, unit)
	if source == null: return null
	var key := source.get_instance_id()
	if not platforms.has(key):
		# Trim transparent padding at draw time; preserve the user's PNG unchanged.
		var image := source.get_image()
		if image.is_compressed(): image.decompress()
		var region := AtlasTexture.new()
		region.atlas = source
		region.region = Rect2(image.get_used_rect())
		if platforms.size() >= 8: platforms.clear()
		platforms[key] = region
	return platforms[key]

static func native_terrain(state, unit: Dictionary) -> Dictionary:
	if state == null or unit.is_empty(): return {}
	var id := str(int(state.terrain_at(state.position(unit)).get("id",-1)))
	return state.chapter.get("native_battle_terrain",{}).get(id,{})
