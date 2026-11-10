extends Control
const Art = preload("res://runtime/art_textures.gd")
## Original map coordinates, actor classes and entrance cues come from the pack.
## Narration can introduce another actor; an existing journey never page-jumps.
var points: PackedVector2Array = []
var marker: Texture2D
var image_size := Vector2(240, 160)
var progress := 0.0
var start_progress := 0.0
var end_progress := 0.0
var elapsed := 0.0
var animation_elapsed := 0.0
var movement_speed := 1.0
var route_key := ""
var duration := 5.0
var data: Dictionary = {}
var actors: Array[Dictionary] = []
var actor_elapsed: Dictionary = {}
var textures: Dictionary = {}
var movement_manifest: Dictionary = {}
var animation_manifest_path := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	hide()

func configure_animations(path: String) -> void:
	if path == animation_manifest_path: return
	animation_manifest_path = path
	movement_manifest.clear()
	if not FileAccess.file_exists(path): return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if manifest is Dictionary and manifest.get("movement") is Dictionary:
		movement_manifest = manifest.movement

func present(next_data: Dictionary, backdrop: Texture2D) -> void:
	if next_data.is_empty() or backdrop == null:
		reset()
		return
	# page_index belongs to narration, not the identity of its journey.
	var key := JSON.stringify([next_data.get("source_route", []), next_data.get("viewport", []), next_data.get("from", []), next_data.get("to", []), next_data.get("marker", ""), next_data.get("actors", [])])
	if next_data.has("journey_id"): key = str(next_data.journey_id)
	data = next_data.duplicate(true)
	if key == route_key:
		if data.has("journey_id"): _sync_native_actors()
		_activate_actors(int(data.get("page_index", 0)))
		show()
		return
	route_key = key
	points.clear()
	actors.clear()
	actor_elapsed.clear()
	textures.clear()
	image_size = backdrop.get_size()
	points = _route_points(data.get("source_route", []))
	if points.size() < 2:
		points.clear()
		for endpoint in ["from", "to"]:
			var point: Array = data.get(endpoint, [0.5, 0.5])
			points.append(Vector2(point[0], point[1]))
	configure_animations(str(data.get("animation_manifest", "")))
	for actor in data.get("actors", []):
		if not actor is Dictionary: continue
		var compiled: Dictionary = actor.duplicate(true)
		compiled["points"] = _route_points(actor.get("source_route", []))
		if compiled.points.is_empty(): continue
		compiled["duration"] = _route_duration(compiled.points)
		actors.append(compiled)
	if data.has("journey_id"): _sync_native_actors()
	start_progress = 0.0
	end_progress = 1.0
	duration = _route_duration(points)
	progress = start_progress
	elapsed = 0
	_activate_actors(int(data.get("page_index", 0)))
	refresh_art()
	show()

func _sync_native_actors() -> void:
	var page := int(data.get("page_index",0))
	for actor in actors:
		var source: Array = actor.get("source_route",[])
		var cues: Array = actor.get("waypoint_pages",[])
		var count := 0
		while count < source.size() and (count >= cues.size() or int(cues[count]) <= page): count += 1
		var previous_count := int(actor.get("released_points",count))
		var id := str(actor.id)
		if count != previous_count and actor_elapsed.has(id): actor_elapsed[id] = minf(float(actor_elapsed[id]),float(actor.duration) if previous_count > 1 else 0.0)
		actor.released_points = count
		actor.points = _route_points(source.slice(0,maxi(1,count)))
		actor.duration = _route_duration(actor.points)

func _route_points(source: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var viewport: Array = data.get("viewport", [0, 0, image_size.x, image_size.y])
	for point in source:
		result.append((Vector2(float(point[0]), float(point[1])) - Vector2(float(viewport[0]), float(viewport[1]))) / Vector2(float(viewport[2]), float(viewport[3])))
	return result

func _route_duration(path: PackedVector2Array) -> float:
	var distance := 0.0
	for index in range(1, path.size()): distance += ((path[index] - path[index - 1]) * image_size).length()
	return maxf(1.0, distance / 16.0)

func _activate_actors(page: int) -> void:
	for actor in actors:
		var id := str(actor.get("id", ""))
		if page >= int(actor.get("start_page", 0)) and not actor_elapsed.has(id): actor_elapsed[id] = 0.0

func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not textures.has(path): textures[path] = Art.texture(path)
	return textures[path]

func refresh_art() -> void:
	textures.clear()
	marker = _texture(str(data.get("marker", "")))
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var step := delta * maxf(0.1, movement_speed)
	elapsed += step
	animation_elapsed += delta
	for id in actor_elapsed: actor_elapsed[id] = float(actor_elapsed[id]) + step
	progress = lerpf(start_progress, end_progress, minf(1.0, elapsed / duration))
	queue_redraw()

func reset() -> void:
	route_key = ""
	progress = 0.0
	elapsed = 0.0
	actors.clear()
	actor_elapsed.clear()
	data.clear()
	textures.clear()
	marker = null
	hide()

func capture_state() -> Dictionary:
	return {"route_key": route_key, "elapsed": elapsed, "actor_elapsed": actor_elapsed.duplicate()}

func restore_state(state: Dictionary) -> void:
	if str(state.get("route_key", "")) != route_key: return
	if state.get("elapsed", 0.0) is float or state.get("elapsed", 0.0) is int:
		elapsed = maxf(0.0, float(state.get("elapsed", 0.0)))
		progress = minf(1.0, elapsed / duration)
	var saved = state.get("actor_elapsed", {})
	if saved is Dictionary:
		actor_elapsed.clear()
		for actor in actors:
			var id := str(actor.get("id", ""))
			if saved.get(id) is float or saved.get(id) is int: actor_elapsed[id] = maxf(0.0, float(saved[id]))
	queue_redraw()

func _sample(path: PackedVector2Array, fraction: float) -> Dictionary:
	if path.is_empty(): return {"at": Vector2.ZERO, "direction": Vector2.ZERO}
	var total := 0.0
	for i in range(1, path.size()): total += ((path[i] - path[i - 1]) * image_size).length()
	var distance := total * clampf(fraction, 0, 1)
	for i in range(1, path.size()):
		var direction := (path[i] - path[i - 1]) * image_size
		var segment := direction.length()
		if distance <= segment or i == path.size() - 1:
			return {"at": path[i - 1].lerp(path[i], clampf(distance / maxf(segment, 0.001), 0, 1)), "direction": direction}
		distance -= segment
	return {"at": path[0], "direction": Vector2.ZERO}

func actor_frame(actor: Dictionary) -> Dictionary:
	var time := float(actor_elapsed.get(str(actor.get("id", "")), 0.0))
	var path: PackedVector2Array = actor.get("points", PackedVector2Array())
	var moving := path.size() > 1 and time < float(actor.get("duration", 1.0))
	var profile: Dictionary = movement_manifest.get(str(int(actor.get("rom_class_id", 0))), {})
	if moving and not profile.is_empty():
		var direction: Vector2 = _sample(path, time / float(actor.duration)).direction
		var mode := "left" if direction.x < 0 else "right"
		if absf(direction.y) > absf(direction.x): mode = "up" if direction.y < 0 else "down"
		var timeline: Array = profile.get("modes", {}).get(mode, [])
		var total := 0
		for entry in timeline: total += int(entry.ticks)
		if total > 0:
			var tick := int(animation_elapsed * 60) % total
			for entry in timeline:
				if tick < int(entry.ticks):
					return {"path": str(profile.paths.get(actor.get("faction", "player"), "")), "frame": int(entry.frame), "size": Vector2(profile.frame_size[0], profile.frame_size[1]), "anchor": Vector2(profile.anchor[0], profile.anchor[1]), "moving": true, "mode": mode}
				tick -= int(entry.ticks)
	var idle_path := str(actor.get("sprite_idle", ""))
	var idle := _texture(idle_path)
	var texture := idle if idle else _texture(str(actor.get("sprite", "")))
	if texture == null: return {}
	var frame_size := texture.get_size() / Vector2(3 if idle else 1, 1)
	return {"path": idle_path if idle else str(actor.get("sprite", "")), "frame": [0, 1, 2, 1][int(animation_elapsed / 0.22) % 4] if idle else 0, "size": frame_size, "anchor": Vector2(frame_size.x * 0.5, frame_size.y * 0.85), "moving": false}

func _draw() -> void:
	if points.size() < 2: return
	var scale_factor := maxf(size.x / image_size.x, size.y / image_size.y)
	var extent := image_size * scale_factor
	var offset := (size - extent) * 0.5
	for dot in data.get("dots",[]):
		var positions := _route_points([dot.point])
		if positions.is_empty(): continue
		var center := offset+positions[0]*extent
		draw_circle(center,3.0*minf(scale_factor,3.0),Color("f2d17d") if int(dot.get("palette",0)) == 0 else Color("b94b48"))
	if actors.is_empty():
		var center: Vector2 = offset + Vector2(_sample(points, progress).at) * extent
		if marker:
			var marker_size := marker.get_size() * minf(scale_factor, 3.0)
			draw_texture_rect(marker, Rect2(center - Vector2(marker_size.x * 0.5, marker_size.y * 0.85), marker_size), false)
		return
	for actor in actors:
		var id := str(actor.get("id", ""))
		if int(data.get("page_index",0)) >= int(actor.get("end_page",2147483647)): continue
		if not actor_elapsed.has(id): continue
		var frame := actor_frame(actor)
		if frame.is_empty(): continue
		var texture := _texture(str(frame.path))
		if texture == null: continue
		var at: Vector2 = _sample(actor.points, float(actor_elapsed[id]) / float(actor.duration)).at
		# ROM formation styles identify distinct relative positions. Preserve
		# their direction with compact spacing adapted to this larger viewport.
		var formation: Vector2 = {1: Vector2(-5, 3), 2: Vector2(5, 3), 3: Vector2(-5, -3), 4: Vector2(5, -3), 5: Vector2(0, -5), 6: Vector2(0, 5), 7: Vector2(-5, 0), 8: Vector2(5, 0)}.get(int(actor.get("style", 0)), Vector2.ZERO)
		var center := offset + at * extent + formation * minf(scale_factor, 3.0)
		var sprite_scale := minf(scale_factor, 3.0)
		var frame_size: Vector2 = frame.size
		var source := Rect2(Vector2(frame_size.x * int(frame.frame), 0), frame_size)
		textures["frame:" + id] = Art.region_texture(str(frame.path), source)
		draw_texture_rect(textures["frame:" + id], Rect2(center - Vector2(frame.anchor) * sprite_scale, frame_size * sprite_scale), false)
