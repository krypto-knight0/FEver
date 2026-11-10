extends RefCounted
static var store = preload("res://runtime/sprite_store.gd").new()

static func frame(unit: Dictionary, state: String, elapsed: float) -> Dictionary:
	if unit.get("game_id", "fe7") != "fe7": return {}
	var entry: Dictionary = store.find_sheet(int(unit.get("rom_class_id", 0)), str(unit.get("faction", "player")))
	if entry.is_empty() or not entry.animations.has(state): return {}
	var texture: Texture2D = store.texture(entry)
	if texture == null: return {}
	var animation: Dictionary = entry.animations[state]
	var frames: Array = animation.frames
	var frame_id := int(frames[animation_step(animation, state, elapsed)])
	var cell := Vector2(entry.frame_size[0], entry.frame_size[1])
	var columns := int(texture.get_width() / cell.x)
	@warning_ignore("integer_division") # Intentional integer truncation.
	return {"texture":texture, "source":Rect2(Vector2(frame_id % columns, int(frame_id / columns)) * cell, cell), "size":Vector2(entry.draw_size[0], entry.draw_size[1]), "anchor":Vector2(entry.anchor[0], entry.anchor[1])}

static func animation_step(animation: Dictionary, state: String, elapsed: float) -> int:
	var frames: Array = animation.frames
	var once := state in ["attack", "hit"]
	if animation.has("ticks"):
		var durations: Array = animation.ticks
		var total := 0
		for duration in durations: total += int(duration)
		var tick := int(floor(maxf(0, elapsed) * 60.0 + 0.000001))
		if once and tick >= total: return frames.size() - 1
		tick %= total
		for index in range(durations.size()):
			if tick < int(durations[index]): return index
			tick -= int(durations[index])
	var step := int(maxf(0, elapsed) * float(animation.get("fps", 6)))
	return mini(step, frames.size() - 1) if once else step % frames.size()
