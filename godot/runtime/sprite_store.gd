extends "res://runtime/portrait_store.gd"
## Class/faction sheets. Unspecified states retain the original ROM animation.
const STATES := ["idle", "ready", "left", "right", "up", "down", "attack", "hit"]
var index: Dictionary = {}
var cached_bytes := 0

func _init(storage_root: String = "user://map-sprites/") -> void:
	super(storage_root)
	config_name = "sprites.json"
	array_key = "sprites"
	maximum_entries = 512
	maximum_config_bytes = 1024 * 1024

func validate_entry(entry: Dictionary, identifiers: Dictionary) -> String:
	if not entry.get("class_ids") is Array or entry.class_ids.is_empty(): return "Each sprite needs a nonempty class_ids array."
	if not entry.get("faction", "") in ["player", "enemy", "npc", "neutral"]: return "Sprite faction must be player, enemy, or npc (neutral)."
	if entry.faction == "neutral": entry.faction = "npc"
	for id in entry.class_ids:
		if not (id is float or id is int) or float(id) != int(id) or int(id) < 1 or int(id) > 99: return "Class IDs must be integers from 1 to 99."
		var key := "%d:%s" % [int(id), entry.faction]
		if identifiers.has(key): return "Duplicate class/faction: " + key
		identifiers[key] = true
	for field in ["frame_size", "draw_size", "anchor"]:
		if not entry.get(field) is Array or entry[field].size() != 2: return field + " needs two numbers."
		for number in entry[field]:
			if not (number is float or number is int) or not is_finite(float(number)): return field + " needs finite numbers."
	for number in entry.frame_size:
		if number != int(number) or number < 16 or number > 512: return "Frame dimensions must be integers from 16 to 512."
	for number in entry.draw_size:
		if number < 0.25 or number > 8: return "draw_size must be between 0.25 and 8 map tiles."
	for number in entry.anchor:
		if number < 0 or number > 1: return "anchor must be between 0 and 1."
	if not entry.get("animations") is Dictionary or not entry.animations.has("idle"): return "Provide animations with at least an idle animation."
	for state in entry.animations:
		if not state in STATES: return "Unknown sprite animation: " + str(state)
		var animation: Variant = entry.animations[state]
		if not animation is Dictionary or not animation.get("frames") is Array or animation.frames.is_empty() or animation.frames.size() > 64: return "Each animation needs 1–64 frame indices."
		var fps: Variant = animation.get("fps", 6)
		if not (fps is int or fps is float) or not is_finite(float(fps)) or fps < 1 or fps > 30: return "Animation fps must be between 1 and 30."
		for frame in animation.frames:
			if not (frame is float or frame is int) or frame != int(frame) or frame < 0: return "Frame indices must be nonnegative integers."
		if animation.has("ticks"):
			if not animation.ticks is Array or animation.ticks.size() != animation.frames.size(): return "Animation ticks must match the number of frames."
			for ticks in animation.ticks:
				if not (ticks is float or ticks is int) or ticks != int(ticks) or ticks < 1 or ticks > 3600: return "Frame durations must be integers from 1 to 3600 ticks (60 ticks per second)."
	entry.character = str(entry.class_ids[0]) + ":" + str(entry.faction)
	return ""

func validate_dimensions(entry: Dictionary, width: int, height: int) -> String:
	if width * height > 4194304: return "Keep spritesheets at or below 4 megapixels for mobile."
	var fw := int(entry.frame_size[0]); var fh := int(entry.frame_size[1])
	if width % fw != 0 or height % fh != 0: return "Sheet dimensions must be whole multiples of frame_size."
	@warning_ignore("integer_division") # Intentional integer truncation.
	var count := (width / fw) * (height / fh)
	for animation in entry.animations.values():
		for frame in animation.frames:
			if int(frame) >= count: return "Animation frame is outside the spritesheet."
	return ""

func reload() -> void:
	super()
	cached_bytes = 0
	index.clear()
	for entry in entries:
		for id in entry.class_ids: index["%d:%s" % [int(id), entry.faction]] = entry

func disable() -> void:
	super()
	cached_bytes = 0
	index.clear()

func find_sheet(class_id: int, faction: String) -> Dictionary:
	if not loaded: reload()
	if not enabled: return {}
	return index.get("%d:%s" % [class_id, "npc" if faction == "neutral" else faction], {})

func texture(entry: Dictionary) -> Texture2D:
	# Faction entries may share a sheet. Decode it once.
	var key := str(entry.get("source_image", entry.image))
	if not textures.has(key):
		var image := Image.load_from_file(directory + str(entry.image))
		if image == null: return null
		var bytes := image.get_width() * image.get_height() * 4
		while not textures.is_empty() and cached_bytes + bytes > 64 * 1024 * 1024:
			var oldest: String = textures.keys()[0]
			cached_bytes -= textures[oldest].get_width() * textures[oldest].get_height() * 4
			textures.erase(oldest)
		textures[key] = ImageTexture.create_from_image(image)
		cached_bytes += bytes
	return textures[key]
