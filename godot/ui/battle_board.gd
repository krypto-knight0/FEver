extends Control
const Art = preload("res://runtime/art_textures.gd")
const CustomMaps = preload("res://runtime/custom_maps.gd")
const CustomSprites = preload("res://runtime/custom_sprites.gd")
var sprite_actions: Dictionary = {}
var custom_sprite_tick := -1
var tentative_movement := false
var reinforcement_warnings: Array[Vector2i] = []

signal cell_pressed(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cell_held(cell: Vector2i)
signal view_changed
signal strike_presented(strike: Dictionary)
signal voice_requested(unit: Dictionary, action: String)
signal combat_finished
signal movement_finished(unit_id: String)
signal rom_sound_requested(song_id: int)
var step_sounds: Array[int] = []
var step_sound_frame := -1
signal enemy_focused(unit_id: String)
signal story_action_started(action: Dictionary)
signal unit_drag_started(unit_id: String)
signal unit_dropped(unit_id: String, cell: Vector2i)
var drag_candidate := ""
var unit_dragging := false

var map_data: Dictionary = {}
var battle: RefCounted
var selected_id: String = ""
var pending_target: String = ""
var pending_target_beneficial := false
var staff_cells: Array = []
var reachable_cells: Dictionary = {}
var target_cells: Array = []
var beneficial_cells: Array = []
var show_grid: bool = false
var spectator: bool = false
var map_texture: Texture2D
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var press_position: Vector2
var last_position: Vector2
var dragging: bool = false
var pointer_down: bool = false
var textures: Dictionary = {}
var touches: Dictionary = {}
var touch_moved: bool = false
var combat_playing: bool = false
var animation_time_scale: float = 1.0
var movement_speed: float = 1.0
var battle_speed: float = 1.0
var ally_choice_ids: Array[String] = []
var choice_active := false
var idle_frame: int = 0
var idle_elapsed: float = 0.0
var combat_offsets: Dictionary = {}
var combat_hp: Dictionary = {}
var combat_alpha: Dictionary = {}
var combat_flash: Dictionary = {}
var combat_visible: Dictionary = {}
var fog_combat_reveal: Dictionary = {}
var pending_map_changes: Dictionary = {}
var combat_feedback: Dictionary = {}
var combat_generation: int = 0
var movement_positions: Dictionary = {}
var walking_id: String = ""
var phase_callback_active: bool = false
var presentation_rewards_pending := false
var incremental_phase := false
var drawing_visibility := false
var drawn_positions: Dictionary = {}
var drawn_visibility: Dictionary = {}
var _fog_region_key := -1
var _fog_regions: Array[Rect2i] = []
var movement_manifest: Dictionary = {}
var walk_directions: Dictionary = {}
var walk_elapsed := 0.0
var enemy_focus_id := ""
var story_actors: Dictionary = {}
var story_active := false
var story_playing := false
var story_generation := 0
var story_pending_actions: Array = []
var hidden_passengers: Dictionary = {}
var story_patches: Array = []
var hold_cell := Vector2i(-1, -1)
var hold_elapsed := 0.0
var hold_fired := false

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_view_updated)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_reset_hold()
		touches.clear()
		pointer_down = false
		dragging = false
		touch_moved = false

func _process(delta: float) -> void:
	if hold_cell.x >= 0 and not hold_fired:
		hold_elapsed += delta
		if hold_elapsed >= 0.45:
			hold_fired = true
			cell_held.emit(hold_cell)
	idle_elapsed += delta
	var sprite_tick := int(idle_elapsed * 60)
	if (not CustomSprites.store.entries.is_empty() or not selected_id.is_empty()) and sprite_tick != custom_sprite_tick:
		custom_sprite_tick = sprite_tick
		queue_redraw()
	if not walking_id.is_empty():
		walk_elapsed += delta
		var frame := int(walk_elapsed * 60 * (1.0 if story_active else movement_speed))
		if not step_sounds.is_empty():
			var unit: Dictionary = story_actors.get(walking_id, {}) if story_active else battle.get_unit(walking_id)
			if story_active or is_unit_visible(unit):
				for tick in range(maxi(step_sound_frame + 1, frame - 60), frame + 1):
					var sound := step_sounds[tick % step_sounds.size()]
					if sound > 0: rom_sound_requested.emit(sound)
		step_sound_frame = frame
	var next_frame: int = [0, 1, 2, 1][int(idle_elapsed / 0.22) % 4]
	if next_frame != idle_frame or combat_playing or (battle and (int(battle.rules.get("weather", 0)) == 4 or battle.rules.get("weather_effect", "") in ["sandstorm","snow"])):
		idle_frame = next_frame
		queue_redraw()

func set_map(data: Dictionary) -> void:
	staff_cells.clear()
	drag_candidate = ""
	unit_dragging = false
	_reset_hold()
	clear_story()
	ally_choice_ids.clear()
	choice_active = false
	map_data = data
	textures.clear()
	var path: String = data.get("image", "")
	map_texture = _map_art(path)
	cancel_combat()
	touches.clear()
	pointer_down = false
	fit_map()

func refresh_art() -> void:
	# Changing quality must not reset a walk, a story scene, or the map camera.
	textures.clear()
	var path := str(map_data.get("image", ""))
	map_texture = _map_art(path)
	queue_redraw()

func _map_art(path: String) -> Texture2D:
	var custom := CustomMaps.texture(path)
	return custom if custom != null else Art.texture(path) if ResourceLoader.exists(path) else null

func _draw_map_patch(patch: Dictionary, rect: Rect2, tile: float) -> void:
	var path := str(patch.get("image", ""))
	if path.is_empty(): return
	if not textures.has(path): textures[path] = _map_art(path)
	var texture: Texture2D = textures[path]
	if texture == null: return
	var columns := int(patch.width)
	var rows := int(patch.height)
	# Respect skipped cells even if an imported PNG fills the entire rectangle.
	# This also preserves overlapping changes made by earlier switches/events.
	var mask: Array = patch.get("mask", CustomMaps.record(path).get("mask", []))
	if mask.is_empty():
		draw_texture_rect(texture, Rect2(rect.position + Vector2(patch.x, patch.y) * tile, Vector2(columns, rows) * tile), false)
		return
	var source_tile := texture.get_size() / Vector2(columns, rows)
	for y in range(rows):
		for x in range(columns):
			if not bool(mask[y][x]): continue
			draw_texture_rect_region(texture, Rect2(rect.position + Vector2(int(patch.x) + x, int(patch.y) + y) * tile, Vector2.ONE * tile), Rect2(Vector2(x,y) * source_tile, source_tile))

func sprite_path_for(unit: Dictionary, idle: bool = false) -> String:
	var path := str(unit.get("sprite", ""))
	if idle: path = str(unit.get("sprite_idle", path.get_basename() + "_idle.png"))
	# A recruitment changes the runtime faction, not the imported deployment.
	# Match the static/idle palette to the same live faction as walking frames.
	var suffix := "_idle.png" if idle else ".png"
	for faction in ["player", "enemy", "neutral", "npc"]:
		var old_suffix: String = "_" + faction + suffix
		if path.ends_with(old_suffix):
			var current_faction := str(unit.get("faction", faction))
			if current_faction == "neutral": current_faction = "npc"
			var candidate := path.trim_suffix(old_suffix) + "_" + current_faction + suffix
			if ResourceLoader.exists(candidate): return candidate
	return path

func configure_animations(path: String) -> bool:
	movement_manifest.clear()
	if not FileAccess.file_exists(path): return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("movement") is Dictionary: return false
	movement_manifest = data.movement
	return true

func map_rect() -> Rect2:
	var dim := Vector2(map_data.get("width", 15), map_data.get("height", 10))
	var available := size
	var cell_size: float = maxf(1.0, minf(available.x / dim.x, available.y / dim.y)) * zoom
	var extent := dim * cell_size
	return Rect2((size - extent) * 0.5 + pan, extent)

func cell_at(position_in_board: Vector2) -> Vector2i:
	var rect := map_rect()
	var tile: float = rect.size.x / float(map_data.get("width", 15))
	return Vector2i(floori((position_in_board.x - rect.position.x) / tile), floori((position_in_board.y - rect.position.y) / tile))

func cell_screen_position(cell: Vector2i) -> Vector2:
	var rect := map_rect()
	return rect.position + (Vector2(cell) + Vector2.ONE * 0.5) * (rect.size.x / float(map_data.get("width", 15)))

func fit_map() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	_view_updated()

func focus_cell(cell: Vector2i) -> void:
	pan += size * 0.5 - cell_screen_position(cell)
	_view_updated()

func _view_updated() -> void:
	var limit := ((map_rect().size - size) * 0.5).max(Vector2.ZERO)
	pan = pan.clamp(-limit, limit)
	queue_redraw()
	view_changed.emit()

func set_ally_choices(ids: Array, active: bool = false) -> void:
	choice_active = active or not ids.is_empty()
	ally_choice_ids.clear()
	for id in ids:
		if not str(id).is_empty() and not ally_choice_ids.has(str(id)):
			ally_choice_ids.append(str(id))
	queue_redraw()

func overlay_tile_rect(cell: Vector2i) -> Rect2:
	var rect := map_rect()
	var tile := rect.size.x / float(map_data.get("width", 15))
	# Retain a small visible seam at every zoom, including touching blue/red tiles.
	return Rect2(rect.position + Vector2(cell) * tile, Vector2.ONE * tile).grow(-maxf(0.65, tile * 0.035))

func movement_origin_cell() -> Vector2i:
	if battle == null or spectator or story_active or not battle.pending_moves.has(selected_id): return Vector2i(-1, -1)
	var origin: Dictionary = battle.pending_moves[selected_id]
	var unit: Dictionary = battle.get_unit(selected_id)
	var cell := Vector2i(int(origin.x), int(origin.y))
	if unit.is_empty() or cell == Vector2i(int(unit.x), int(unit.y)): return Vector2i(-1, -1)
	return cell

func change_zoom(factor: float, anchor: Vector2 = Vector2.INF) -> void:
	if not is_finite(factor) or factor <= 0:
		return
	if anchor == Vector2.INF:
		anchor = size * 0.5
	var before := map_rect()
	var relative := (anchor - before.position) / before.size
	zoom = clampf(zoom * factor, 1.0, 4.0)
	var extent := map_rect().size
	pan = anchor - (size - extent) * 0.5 - relative * extent
	_view_updated()

func _emit_cell(position_in_board: Vector2) -> void:
	if not combat_playing or not walking_id.is_empty():
		cell_pressed.emit(cell_at(position_in_board))

func _reset_hold() -> void:
	hold_cell = Vector2i(-1, -1)
	hold_elapsed = 0.0
	hold_fired = false

func _begin_hold(at: Vector2) -> void:
	_reset_hold()
	drag_candidate = ""
	unit_dragging = false
	if battle == null or spectator or story_active or combat_playing or not walking_id.is_empty(): return
	var cell := cell_at(at)
	var unit: Dictionary = battle.unit_at(cell)
	if unit.get("faction", "") == "enemy": hold_cell = cell
	if unit.get("faction", "") == "player" and not unit.get("acted", true): drag_candidate = str(unit.id)

func _drag_unit(at: Vector2) -> bool:
	if drag_candidate.is_empty(): return false
	if not unit_dragging:
		unit_dragging = true
		unit_drag_started.emit(drag_candidate)
	cell_hovered.emit(cell_at(at))
	return true

func _drop_unit(at: Vector2, canceled: bool = false) -> void:
	if unit_dragging and not canceled: unit_dropped.emit(drag_candidate, cell_at(at))
	drag_candidate = ""
	unit_dragging = false

func _touch_input(event: InputEvent) -> void:
	pointer_down = false
	if event is InputEventScreenTouch:
		if event.pressed:
			if touches.is_empty():
				touch_moved = false
				press_position = event.position
				_begin_hold(event.position)
			touches[event.index] = event.position
			if touches.size() > 1:
				drag_candidate = ""
				unit_dragging = false
				touch_moved = true
				_reset_hold()
		else:
			_drop_unit(event.position, event.canceled)
			if touches.has(event.index) and touches.size() == 1 and not touch_moved and not event.canceled and not hold_fired:
				_emit_cell(event.position)
			touches.erase(event.index)
			_reset_hold()
	elif event is InputEventScreenDrag and touches.has(event.index):
		var previous: Vector2 = touches[event.index]
		if touches.size() >= 2:
			var ids: Array = touches.keys()
			var a: Vector2 = touches[ids[0]]
			var b: Vector2 = touches[ids[1]]
			touches[event.index] = event.position
			var next_a: Vector2 = touches[ids[0]]
			var next_b: Vector2 = touches[ids[1]]
			var distance := a.distance_to(b)
			if distance > 1:
				change_zoom(next_a.distance_to(next_b) / distance, (a + b) * 0.5)
			pan += (next_a + next_b - a - b) * 0.5
			touch_moved = true
			_view_updated()
		else:
			touches[event.index] = event.position
			if event.position.distance_to(press_position) > 8:
				touch_moved = true
				_reset_hold()
			if touch_moved:
				if not _drag_unit(event.position):
					pan += event.position - previous
					_view_updated()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		accept_event()
		return
	# Godot emits synthetic mouse events for touches when GUI emulation is on.
	# Native touch above owns these gestures, preventing duplicate taps/drags.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			change_zoom(1.2, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			change_zoom(1.0 / 1.2, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down = true
				dragging = false
				press_position = event.position
				last_position = event.position
				_begin_hold(event.position)
			else:
				_drop_unit(event.position)
				if pointer_down and not dragging and not hold_fired:
					_emit_cell(event.position)
				pointer_down = false
				_reset_hold()
		accept_event()
	elif event is InputEventMouseMotion:
		cell_hovered.emit(cell_at(event.position))
		if pointer_down:
			if event.position.distance_to(press_position) > 8:
				dragging = true
				_reset_hold()
			if dragging:
				if not _drag_unit(event.position):
					pan += event.position - last_position
					_view_updated()
			last_position = event.position
	elif event is InputEventMagnifyGesture:
		change_zoom(event.factor, event.position)
		accept_event()

var presented_acted: Dictionary = {}

func cancel_combat() -> void:
	presented_acted.clear()
	sprite_actions.clear()
	combat_generation += 1
	combat_playing = false
	combat_offsets.clear()
	combat_hp.clear()
	combat_alpha.clear()
	combat_flash.clear()
	combat_visible.clear()
	fog_combat_reveal.clear()
	pending_map_changes.clear()
	combat_feedback.clear()
	movement_positions.clear()
	walking_id = ""
	phase_callback_active = false
	presentation_rewards_pending = false
	walk_directions.clear()
	enemy_focus_id = ""
	hidden_passengers.clear()
	queue_redraw()

func _animate(duration: float, generation: int, update: Callable, movement: bool = false, attack: bool = false) -> bool:
	var elapsed := 0.0
	duration = maxf(0.001, duration * animation_time_scale / maxf(0.1, movement_speed if movement else (battle_speed if attack else 1.0)))
	while elapsed < duration:
		if skip_phase_animations:
			update.call(1.0)
			return generation == combat_generation
		if generation != combat_generation or not is_inside_tree():
			return false
		update.call(clampf(elapsed / duration, 0, 1))
		queue_redraw()
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if generation != combat_generation:
		return false
	update.call(1.0)
	return true

func play_movement(unit_id: String, path: Array) -> void:
	if path.size() < 2:
		return
	tentative_movement = true
	await play_phase([{"type": "move", "unit_id": unit_id, "path": path}])
	tentative_movement = false

func play_healing(result: Dictionary) -> void:
	var id := str(result.get("target_id", result.get("unit_id", "")))
	if battle == null or battle.get_unit(id).is_empty() or int(result.get("healed", 0)) <= 0: return
	cancel_combat()
	var token := combat_generation
	combat_playing = true
	var target: Dictionary = battle.get_unit(id)
	var final_hp := float(result.get("remaining_hp", target.hp))
	var previous_hp := float(result.get("previous_hp", final_hp - int(result.healed)))
	combat_hp[id] = previous_hp
	combat_visible[id] = true
	combat_feedback = {"id": id, "text": "+%d" % int(result.healed), "hit": true, "kind": "heal", "alpha": 0.0, "scale": 1.0, "rise": 0.0}
	if not await _animate(1.0, token, func(t):
		combat_hp[id] = lerpf(previous_hp, final_hp, smoothstep(0.08, 0.85, t))
		combat_feedback.alpha = clampf(minf(t / 0.12, (1.0 - t) / 0.2), 0, 1)
		combat_feedback.scale = 1.0 + sin(minf(t / 0.35, 1.0) * PI) * 0.22
		combat_feedback.rise = t): return
	cancel_combat()
	combat_finished.emit()

func play_combat(strikes: Array) -> void:
	if phase_callback_active:
		var generation := combat_generation
		for strike in strikes:
			if not await _play_strike(strike, generation):
				return
		return
	var actions: Array = []
	for strike in strikes:
		actions.append({"type": "strike", "strike": strike})
	await play_phase(actions)

var skip_phase_animations := false

func play_phase(actions: Array, combat_presenter: Callable = Callable(), reward_presenter: Callable = Callable(), assist_presenter: Callable = Callable()) -> void:
	if actions.is_empty() or battle == null:
		return
	cancel_combat()
	var generation := combat_generation
	combat_playing = true
	var strikes: Array = []
	for action in actions:
		if action.get("type", "") == "map_change": pending_map_changes[str(action.id)] = true
		if action.get("type", "") == "strike":
			strikes.append(action.strike)
		elif action.get("type", "") == "move":
			var id := str(action.get("unit_id", ""))
			var path: Array = action.get("path", [])
			if not path.is_empty() and not battle.get_unit(id).is_empty():
				# This batch has already resolved. Keep its movers at their
				# original tiles until their movement is shown.
				if not movement_positions.has(id):
					movement_positions[id] = Vector2(path[0])
				combat_visible[id] = true
	# Underlying combat has already resolved. Reconstruct display HP backwards
	# and retain defeated sprites until the strike that actually defeats them.
	for strike in strikes:
		if strike.get("released_passenger", {}) is Dictionary and not strike.get("released_passenger", {}).is_empty():
			hidden_passengers[str(strike.released_passenger.unit_id)] = true
		for id in [str(strike.get("attacker_id", "")), str(strike.get("defender_id", ""))]:
			var unit: Dictionary = battle.get_target(id)
			if not unit.is_empty():
				combat_visible[id] = true
				combat_hp[id] = int(unit.hp)
				combat_alpha[id] = 1.0
	for index in range(actions.size() - 1, -1, -1):
		var action: Dictionary = actions[index]
		if action.get("type", "") == "skill":
			var id := str(action.unit_id)
			if int(action.previous_hp) >= 0:
				combat_hp[id] = int(action.previous_hp)
				combat_visible[id] = true
				combat_alpha[id] = 1.0
			continue
		if action.get("type", "") in ["staff", "trap"]:
			var healing: Dictionary = action.result
			if healing.has("previous_hp"): combat_hp[str(healing.target_id)] = int(healing.previous_hp)
			if action.type == "trap":
				combat_visible[str(healing.target_id)] = true
				if healing.has("released_passenger"): hidden_passengers[str(healing.released_passenger)] = true
			continue
		if action.get("type", "") != "strike": continue
		var strike: Dictionary = action.strike
		var defender: Dictionary = battle.get_target(str(strike.get("damage_target_id", strike.get("defender_id", ""))))
		if not defender.is_empty():
			combat_hp[str(defender.id)] = int(strike.get("previous_hp", mini(int(defender.max_hp), int(strike.get("remaining_hp", defender.hp)) + int(strike.get("damage", 0)))))
		if strike.has("attacker_previous_hp"): combat_hp[str(strike.attacker_id)] = int(strike.attacker_previous_hp)
	var action_index := 0
	var focused_enemy := ""
	var encounter_ready := false
	while action_index < actions.size():
		var action: Dictionary = actions[action_index]
		if skip_phase_animations and action.get("type", "") != "experience":
			if action.get("type") == "staff" and reward_presenter.is_valid(): await reward_presenter.call(action.result.get("experience", []))
			if generation != combat_generation: return
			action_index += 1
			continue
		var diagnostics := get_node_or_null("/root/Diagnostics")
		if diagnostics: diagnostics.record("phase_animation", {"type": action.get("type", ""), "unit": action.get("unit_id", ""), "static_bytes": OS.get_static_memory_usage()})
		if generation != combat_generation:
			return
		if action.get("type", "") == "move":
			encounter_ready = false
			var mover: Dictionary = battle.get_unit(str(action.get("unit_id", "")))
			if mover.get("faction", "") == "enemy":
				focused_enemy = str(mover.id)
				if not await _focus_enemy(focused_enemy, generation): return
			if not await _play_walk(str(action.get("unit_id", "")), action.get("path", []), generation):
				return
		elif action.get("type", "") == "strike":
			fog_combat_reveal[str(action.strike.attacker_id)] = true
			fog_combat_reveal[str(action.strike.defender_id)] = true
			var attacker: Dictionary = battle.get_unit(str(action.strike.get("attacker_id", "")))
			if not encounter_ready:
				if attacker.get("faction", "") == "enemy" and focused_enemy != str(attacker.id):
					focused_enemy = str(attacker.id)
					if not await _focus_enemy(focused_enemy, generation): return
				if not focused_enemy.is_empty() and not await _animate(0.28, generation, func(_t): pass): return
				encounter_ready = true
			if combat_presenter.is_valid():
				var group: Array = []
				while action_index < actions.size() and actions[action_index].get("type", "") == "strike":
					group.append(actions[action_index].strike)
					action_index += 1
				phase_callback_active = true
				var reward_index := action_index
				if reward_index < actions.size() and actions[reward_index].get("type", "") == "combat_end": reward_index += 1
				presentation_rewards_pending = reward_index < actions.size() and actions[reward_index].get("type", "") == "experience" and not actions[reward_index].get("rewards", []).is_empty()
				await combat_presenter.call(group)
				if generation != combat_generation:
					return
				phase_callback_active = false
				presentation_rewards_pending = false
				for strike in group:
					_release_passenger(strike)
					var defender_id := str(strike.get("damage_target_id", strike.get("defender_id", "")))
					if strike.has("attacker_remaining_hp"): combat_hp[str(strike.attacker_id)] = int(strike.attacker_remaining_hp)
					combat_hp[defender_id] = int(strike.get("remaining_hp", 0))
					if int(combat_hp[defender_id]) <= 0:
						combat_alpha[defender_id] = 0.0
				continue
			elif not await _play_strike(action.strike, generation):
				return
		elif action.get("type", "") == "skill":
			if not await _play_skill_effect(action, generation): return
		elif action.get("type", "") == "trap":
			var effect: Dictionary = action.result
			var id := str(effect.target_id)
			combat_hp[id] = int(effect.remaining_hp)
			var victim: Dictionary = battle.get_unit(id)
			if not victim.is_empty() and (victim.faction == "player" or _visible_cells().has(battle.position(victim))):
				combat_feedback = {"id": id, "text": "Mine recovered" if effect.get("recovered", false) else "%s −%d" % [str(effect.get("trap_name", "Mine")), int(effect.damage)], "hit": true, "alpha": 1.0, "scale": 1.0, "rise": 0.0}
				if not await _animate(0.8, generation, func(t): _feedback_motion(t)): return
				combat_feedback.clear()
			if int(effect.remaining_hp) <= 0: combat_alpha[id] = 0.0
			if effect.has("released_passenger"): hidden_passengers.erase(str(effect.released_passenger))
		elif action.get("type", "") == "staff":
			var staff_result: Dictionary = action.result
			var target_id := str(staff_result.target_id)
			var target: Dictionary = battle.get_unit(target_id)
			var shown: bool = not target.is_empty() and _visible_to_player(target)
			if shown:
				if assist_presenter.is_valid():
					phase_callback_active = true
					await assist_presenter.call(action)
					if generation != combat_generation: return
					phase_callback_active = false
				var text := "+%d" % int(staff_result.healed) if int(staff_result.get("healed", 0)) > 0 else (str(staff_result.get("status", "")).capitalize() if staff_result.get("status_hit", false) else "Miss" if staff_result.has("status_hit") else str(staff_result.get("item_name", "Staff")))
				combat_feedback = {"id": target_id, "text": text, "hit": true, "kind": "heal", "alpha": 1.0, "scale": 1.0, "rise": 0.0}
				if staff_result.has("remaining_hp"): combat_hp[target_id] = int(staff_result.remaining_hp)
				if not await _animate(0.7, generation, func(t): _feedback_motion(t)): return
				combat_feedback.clear()
			if generation != combat_generation: return
			if reward_presenter.is_valid() and not staff_result.get("experience", []).is_empty(): await reward_presenter.call(staff_result.experience)
		elif action.get("type", "") == "experience" and reward_presenter.is_valid():
			await reward_presenter.call(action.get("rewards", []))
			if generation != combat_generation:
				return
		elif action.get("type", "") == "map_change":
			pending_map_changes.erase(str(action.id))
			queue_redraw()
		elif action.get("type", "") == "escape":
			var escaping_id := str(action.get("unit_id", ""))
			if not await _animate(0.2, generation, func(t): combat_alpha[escaping_id] = 1.0 - t): return
			combat_visible.erase(escaping_id)
			movement_positions.erase(escaping_id)
			if enemy_focus_id == escaping_id: enemy_focus_id = ""
		elif action.get("type", "") == "acted":
			presented_acted[str(action.unit_id)] = true
			queue_redraw()
		elif action.get("type", "") == "enemy_phase_end":
			presented_acted.clear()
			queue_redraw()
		elif action.get("type", "") == "combat_end":
			fog_combat_reveal.clear()
			focused_enemy = ""
			enemy_focus_id = ""
			encounter_ready = false
		action_index += 1
	if generation == combat_generation:
		cancel_combat()
		combat_finished.emit()

func unit_display_cell(unit_id: String) -> Vector2:
	if story_active and story_actors.has(unit_id):
		return Vector2(story_actors[unit_id].get("x", 0), story_actors[unit_id].get("y", 0))
	if movement_positions.has(unit_id):
		return Vector2(movement_positions[unit_id])
	if drawing_visibility and drawn_positions.has(unit_id): return drawn_positions[unit_id]
	var unit: Dictionary = battle.get_target(unit_id) if battle else {}
	return Vector2(unit.get("x", -1), unit.get("y", -1))

func _play_walk(unit_id: String, path: Array, generation: int) -> bool:
	if path.size() < 2 or battle.get_unit(unit_id).is_empty():
		return true
	walking_id = unit_id
	walk_elapsed = 0.0
	_prepare_step_sounds(battle.get_unit(unit_id))
	var step_duration := 0.14
	for index in range(1, path.size()):
		var origin := Vector2(path[index - 1])
		var destination := Vector2(path[index])
		walk_directions[unit_id] = _direction(destination - origin)
		if not await _animate(step_duration, generation, func(t):
			movement_positions[unit_id] = origin.lerp(destination, t)
			combat_offsets[unit_id] = Vector2(0, -sin(t * PI) * 0.045), true):
			return false
	combat_offsets.erase(unit_id)
	walking_id = ""
	movement_finished.emit(unit_id)
	return generation == combat_generation

func _direction(delta: Vector2) -> String:
	if absf(delta.x) > absf(delta.y): return "right" if delta.x > 0 else "left"
	return "down" if delta.y > 0 else "up"

func _focus_enemy(id: String, generation: int) -> bool:
	if not is_unit_visible(battle.get_unit(id)): return generation == combat_generation
	enemy_focus_id = id
	enemy_focused.emit(id)
	if generation != combat_generation: return false
	var before := pan
	var desired := before + size * 0.5 - cell_screen_position(Vector2i(unit_display_cell(id)))
	if not await _animate(0.2, generation, func(t): pan = before.lerp(desired, t); _view_updated()): return false
	return await _animate(0.26, generation, func(_t): pass)

func clear_story() -> void:
	story_generation += 1
	story_playing = false
	story_active = false
	story_actors.clear()
	story_pending_actions.clear()
	story_patches.clear()
	walking_id = ""
	walk_directions.clear()
	queue_redraw()

func play_story(actions: Array) -> void:
	if not valid_story_actions(actions): return
	story_generation += 1
	var token := story_generation
	# Camera-only native event cues still show the live battlefield. An explicit
	# begin action switches to the separate cinematic actors when needed.
	story_playing = true
	story_pending_actions = actions.duplicate(true)
	for action in actions:
		if token != story_generation: return
		if not action is Dictionary: continue
		story_action_started.emit(action)
		if token != story_generation: return
		var id := str(action.get("id", ""))
		match str(action.get("type", "")):
			"begin":
				story_actors.clear()
				story_patches.clear()
				story_active = bool(action.get("hide_units", true))
			"end":
				story_actors.clear()
				story_patches.clear()
				story_active = false
			"map_patch": story_patches.append(action.duplicate(true))
			"spawn":
				var actor: Dictionary = action.duplicate(true)
				actor.merge({"hp":1,"max_hp":1,"name":id,"faction":"npc","acted":false}, false)
				story_actors[id] = actor
			"remove": story_actors.erase(id)
			"focus":
				var cell := Vector2i(int(action.get("x", 0)), int(action.get("y", 0)))
				if story_actors.has(id): cell = Vector2i(unit_display_cell(id))
				focus_cell(cell)
			"move":
				if not story_actors.has(id): continue
				var path: Array = action.get("path", [])
				if action.get("instant", false) and not path.is_empty():
					story_actors[id].x = path[-1][0]
					story_actors[id].y = path[-1][1]
					continue
				walking_id = id
				walk_elapsed = 0
				_prepare_step_sounds(story_actors[id])
				for index in range(path.size()):
					var point = path[index]
					if not story_pending_actions.is_empty(): story_pending_actions[0]["path"] = path.slice(index)
					var destination := Vector2(point[0], point[1]) if point is Array else Vector2(point)
					var origin := unit_display_cell(id)
					walk_directions[id] = _direction(destination - origin)
					var duration := float(action.get("step_duration", 0.16)) * maxf(1, origin.distance_to(destination))
					if not await _story_wait(duration, token, func(t): story_actors[id].x = lerpf(origin.x, destination.x, t); story_actors[id].y = lerpf(origin.y, destination.y, t), true): return
				walking_id = ""
			"wait":
				if not await _story_wait(float(action.get("duration", 0.3)), token): return
		queue_redraw()
		if not story_pending_actions.is_empty(): story_pending_actions.pop_front()
	if token == story_generation: story_playing = false

func capture_story() -> Dictionary:
	return {"active":story_active,"actors":story_actors.duplicate(true),"remaining":story_pending_actions.duplicate(true),"patches":story_patches.duplicate(true)}

func apply_story(actions: Array) -> void:
	if not valid_story_actions(actions): return
	story_generation += 1
	story_playing = false
	story_pending_actions.clear()
	walking_id = ""
	for action in actions:
		if not action is Dictionary: continue
		var id := str(action.get("id", ""))
		match str(action.get("type", "")):
			"begin":
				story_actors.clear()
				story_patches.clear()
				story_active = bool(action.get("hide_units", true))
			"end":
				story_actors.clear()
				story_patches.clear()
				story_active = false
			"map_patch": story_patches.append(action.duplicate(true))
			"spawn":
				var actor: Dictionary = action.duplicate(true)
				actor.merge({"hp":1,"max_hp":1,"name":id,"faction":"npc","acted":false}, false)
				story_actors[id] = actor
			"remove": story_actors.erase(id)
			"move":
				var path: Array = action.get("path", [])
				if not story_actors.has(id) or path.is_empty(): continue
				var point = path[-1]
				story_actors[id].x = point[0] if point is Array else point.x
				story_actors[id].y = point[1] if point is Array else point.y
			"focus":
				focus_cell(Vector2i(unit_display_cell(id)) if story_actors.has(id) else Vector2i(int(action.get("x", 0)),int(action.get("y", 0))))
	queue_redraw()

func restore_story(snapshot: Dictionary) -> Array:
	if not valid_story_snapshot(snapshot): return []
	clear_story()
	story_active = bool(snapshot.get("active", false))
	story_actors = snapshot.get("actors", {}).duplicate(true)
	story_pending_actions = snapshot.get("remaining", []).duplicate(true)
	story_patches = snapshot.get("patches", []).duplicate(true)
	queue_redraw()
	return story_pending_actions.duplicate(true)

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func valid_story_actions(actions: Variant) -> bool:
	if not actions is Array: return false
	for action in actions:
		if not action is Dictionary or not action.get("type", "") is String: return false
		var kind := str(action.get("type", ""))
		if kind in ["spawn","move","remove"] and (not action.get("id") is String or str(action.id).is_empty()): return false
		if kind in ["spawn","map_patch"]:
			for field in ["x","y"]:
				if not _finite_number(action.get(field)): return false
		if kind == "spawn":
			for field in ["sprite","faction","rescued_by","carrying_id"]:
				if action.has(field) and not action[field] is String: return false
			if action.has("acted") and not action.acted is bool: return false
			for field in ["rom_class_id","hp","max_hp"]:
				if action.has(field) and not _finite_number(action[field]): return false
		if kind == "map_patch":
			if not action.get("image", "") is String: return false
			for field in ["width","height"]:
				if not _finite_number(action.get(field)) or float(action[field]) <= 0: return false
		if kind == "move":
			if not action.get("path") is Array: return false
			for point in action.path:
				if point is Vector2 or point is Vector2i:
					if not _finite_number(point.x) or not _finite_number(point.y): return false
				elif not point is Array or point.size() != 2 or not _finite_number(point[0]) or not _finite_number(point[1]): return false
		if kind == "focus" and str(action.get("id", "")).is_empty():
			if not _finite_number(action.get("x")) or not _finite_number(action.get("y")): return false
		for field in ["duration","step_duration"]:
			if action.has(field) and (not _finite_number(action[field]) or float(action[field]) < 0): return false
	return true

func valid_story_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary: return false
	if snapshot.has("active") and not snapshot.active is bool: return false
	if not snapshot.get("actors", {}) is Dictionary or not valid_story_actions(snapshot.get("remaining", [])) or not valid_story_actions(snapshot.get("patches", [])): return false
	for id in snapshot.get("actors", {}):
		var actor = snapshot.actors[id]
		if not actor is Dictionary or str(actor.get("id", "")) != str(id): return false
		var spawn: Dictionary = actor.duplicate(true)
		spawn["type"] = "spawn"
		if not valid_story_actions([spawn]): return false
		for field in ["hp","max_hp"]:
			if not _finite_number(actor.get(field)) or int(actor.max_hp) <= 0: return false
	for patch in snapshot.get("patches", []):
		if str(patch.get("type", "")) != "map_patch": return false
	return true

func _story_wait(duration: float, token: int, update: Callable = Callable(), movement: bool = false) -> bool:
	var elapsed := 0.0
	duration = maxf(0.001, duration * animation_time_scale / maxf(0.1, movement_speed if movement else battle_speed))
	while elapsed < duration:
		if token != story_generation or not is_inside_tree(): return false
		if update.is_valid(): update.call(clampf(elapsed / duration, 0, 1))
		queue_redraw()
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if token != story_generation: return false
	if update.is_valid(): update.call(1.0)
	return true

func movement_frame(unit: Dictionary) -> Dictionary:
	var profile: Dictionary = movement_manifest.get(str(int(unit.get("rom_class_id", 0))), {})
	if profile.is_empty(): return {}
	var mode := str(walk_directions.get(str(unit.id), "down"))
	var elapsed := walk_elapsed * (1.0 if story_active else maxf(0.1, movement_speed))
	if walking_id != str(unit.id):
		if sprite_actions.has(str(unit.id)):
			mode = str(sprite_actions[str(unit.id)].get("direction", "ready"))
			elapsed = (idle_elapsed - float(sprite_actions[str(unit.id)].started)) * battle_speed
		elif selected_id == str(unit.id) and not unit.get("acted", false) and unit.get("status", "") != "sleep":
			mode = "ready"; elapsed = idle_elapsed
		else: return {}
	var timeline: Array = profile.get("modes", {}).get(mode, [])
	var total := 0
	for entry in timeline: total += int(entry.ticks)
	if total <= 0: return {}
	var tick := int(elapsed * 60) % total
	for entry in timeline:
		if tick < int(entry.ticks):
			var faction := str(unit.get("faction", "player"))
			return {"path":profile.paths.get("npc" if faction == "neutral" else faction, ""),"frame":int(entry.frame),"size":Vector2(profile.frame_size[0],profile.frame_size[1]),"anchor":Vector2(profile.anchor[0],profile.anchor[1])}
		tick -= int(entry.ticks)
	return {}

func _visible_cells() -> Dictionary:
	if drawing_visibility: return drawn_visibility
	if int(battle.rules.get("fog_radius", 0)) <= 0: return {}
	if not combat_playing or tentative_movement: return battle.visible_cells()
	var observers := {}
	for unit in battle.units:
		if unit.faction not in ["player", "neutral"]: continue
		var shown: Dictionary = unit.duplicate()
		shown.hp = ceili(float(combat_hp.get(str(unit.id), unit.hp)))
		var cell := Vector2i(unit_display_cell(str(unit.id)))
		shown.x = cell.x; shown.y = cell.y
		if hidden_passengers.has(str(unit.id)): shown.rescued_by = "presented_carrier"
		observers[str(unit.id)] = shown
	return battle.visible_cells(observers)

func _visible_to_player(unit: Dictionary) -> bool:
	if battle._under_roof(unit): return false
	return unit.get("faction", "") != "enemy" or int(battle.rules.get("fog_radius", 0)) <= 0 or _visible_cells().has(battle.position(unit))

func fog_regions(revealed: Dictionary) -> Array[Rect2i]:
	var key := hash([map_data.width, map_data.height, revealed])
	if key == _fog_region_key: return _fog_regions
	_fog_region_key = key
	_fog_regions = []
	# Adjacent fog tiles share one rectangle. Idle sprite redraws can reuse
	# these regions instead of issuing a draw command for every hidden tile.
	for y in range(int(map_data.height)):
		var start := -1
		for x in range(int(map_data.width) + 1):
			var concealed := x < int(map_data.width) and not revealed.has(Vector2i(x, y))
			if concealed and start < 0: start = x
			elif not concealed and start >= 0:
				_fog_regions.append(Rect2i(start, y, x - start, 1))
				start = -1
	return _fog_regions

func displayed_acted(unit: Dictionary) -> bool:
	var id := str(unit.id)
	if unit.get("faction", "") == "enemy" and presented_acted.has(id): return true
	if combat_visible.has(id): return false
	if unit.get("status", "") == "sleep": return true
	if unit.get("faction", "") == "enemy": return incremental_phase and unit.get("acted", false)
	return unit.get("acted", false)

func is_unit_visible(unit: Dictionary) -> bool:
	if unit.get("benched", false): return false
	if not story_active and battle and not fog_combat_reveal.has(str(unit.id)):
		var shown := unit.duplicate()
		var cell := Vector2i(unit_display_cell(str(unit.id)))
		shown.x = cell.x; shown.y = cell.y
		if not _visible_to_player(shown): return false
	return not hidden_passengers.has(str(unit.id)) and str(unit.get("rescued_by", "")).is_empty() and (not unit.get("escaped", false) or combat_visible.has(str(unit.id))) and (int(unit.hp) > 0 or combat_visible.has(str(unit.id)))

func _release_passenger(strike: Dictionary) -> void:
	var released: Dictionary = strike.get("released_passenger", {})
	if released.is_empty(): return
	var id := str(released.unit_id)
	hidden_passengers.erase(id)
	movement_positions[id] = Vector2(released.x, released.y)

func _feedback_motion(progress: float) -> void:
	combat_feedback["rise"] = progress
	combat_feedback["alpha"] = clampf(minf(progress / 0.1, (1.0 - progress) / 0.2), 0, 1)
	combat_feedback["scale"] = 1.0 + sin(minf(progress / 0.45, 1.0) * PI) * 0.4

func _play_strike(strike: Dictionary, generation: int) -> bool:
	var attacker_id := str(strike.get("attacker_id", ""))
	var defender_id := str(strike.get("defender_id", ""))
	var attacker: Dictionary = battle.get_target(attacker_id)
	var defender: Dictionary = battle.get_target(defender_id)
	if attacker.is_empty() or defender.is_empty():
		return true
	if strike.get("triangle_attack", false):
		combat_feedback = {"id":attacker_id, "text":"Triangle Attack!", "hit":true, "alpha":1.0, "scale":1.0, "rise":0.0}
		if not await _animate(0.55, generation, func(_t): pass, false, true): return false
		combat_feedback.clear()
	var direction := (unit_display_cell(defender_id) - unit_display_cell(attacker_id)).normalized()
	var lunge := direction * (0.85 if strike.get("critical", false) else 0.55)
	voice_requested.emit(attacker, "crit" if strike.get("critical", false) else "attack")
	sprite_actions[attacker_id] = {"state":"attack", "started":idle_elapsed,"direction":_direction(direction)}
	if not await _animate(0.18, generation, func(t): combat_offsets[attacker_id] = lunge * sin(t * PI * 0.5), false, true):
		return false
	strike_presented.emit(strike)
	if generation != combat_generation:
		return false
	_release_passenger(strike)
	defender_id = str(strike.get("damage_target_id", defender_id))
	if strike.has("attacker_remaining_hp"): combat_hp[attacker_id] = int(strike.attacker_remaining_hp)
	combat_hp[defender_id] = int(strike.get("remaining_hp", defender.hp))
	var hit: bool = strike.get("hit", true)
	if hit and int(strike.get("damage", 0)) > 0: voice_requested.emit(battle.get_unit(defender_id), "damage")
	if hit: sprite_actions[defender_id] = {"state":"hit", "started":idle_elapsed,"direction":_direction(-direction)}
	var defeated := int(combat_hp.get(defender_id, 1)) <= 0
	var feedback_duration := 0.63 if defeated else 0.38
	combat_feedback = {"id": defender_id, "text": ("CRIT! " if strike.get("critical", false) else "") + str(strike.get("damage", 0)) if hit else "MISS", "alpha": 0.0, "rise": 0.0, "hit": hit}
	if not await _animate(0.38, generation, func(t):
		combat_offsets[attacker_id] = lunge * (1.0 - minf(t * 2.5 * battle_speed, 1.0))
		combat_offsets[defender_id] = direction * sin(t * TAU * 3.0) * (0.08 if hit else 0.16) * (1.0 - t)
		combat_flash[defender_id] = (1.0 - t) if hit else 0.0
		_feedback_motion(t * 0.38 / feedback_duration)):
		return false
	combat_offsets.clear()
	combat_flash.clear()
	sprite_actions.erase(attacker_id)
	sprite_actions.erase(defender_id)
	if defeated:
		voice_requested.emit(battle.get_unit(defender_id), "defeat")
		if not await _animate(0.25, generation, func(t): combat_alpha[defender_id] = 1.0 - t; _feedback_motion((0.38 + t * 0.25) / feedback_duration)):
			return false
	combat_feedback.clear()
	return true

func _draw() -> void:
	# This redraw replaces the previous canvas commands. Keep only textures
	# actually referenced by this frame, including both passes of choice mode.
	for key in textures.keys():
		if str(key).begins_with("custom:"): textures.erase(key)
	draw_rect(Rect2(Vector2.ZERO, size), Color("101e27"))
	if map_data.is_empty():
		return
	# Reuse one displayed-vision calculation for terrain, objects and units.
	drawn_positions.clear()
	if battle:
		for unit in battle.units + battle.destructibles:
			drawn_positions[str(unit.id)] = Vector2(unit.x, unit.y)
	drawn_visibility = _visible_cells() if battle and not story_active else {}
	drawing_visibility = true
	var rect := map_rect()
	var tile: float = rect.size.x / float(map_data.width)
	if map_texture:
		draw_texture_rect(map_texture, rect, false)
	if story_active:
		for patch in story_patches:
			_draw_map_patch(patch, rect, tile)
	if battle and not spectator and not story_active:
		for patch in battle.map_patches:
			var id := str(patch.get("destructible_id", ""))
			if pending_map_changes.has(id): continue
			if combat_visible.has(id) and int(combat_hp.get(id, 0)) > 0: continue
			_draw_map_patch(patch, rect, tile)
	for cell in staff_cells:
		draw_rect(overlay_tile_rect(Vector2i(cell)), Color(0.5, 0.85, 1.0, 0.65))
	for cell in reachable_cells:
		draw_rect(overlay_tile_rect(Vector2i(cell)), Color(0.08, 0.30, 0.95, 0.55))
	for cell in target_cells:
		draw_rect(overlay_tile_rect(Vector2i(cell)), Color(0.95, 0.08, 0.12, 0.50))
	for cell in beneficial_cells:
		draw_rect(overlay_tile_rect(Vector2i(cell)), Color(0.15, 0.90, 0.34, 0.55))
	if show_grid:
		for x in range(int(map_data.width) + 1):
			draw_line(rect.position + Vector2(x * tile, 0), rect.position + Vector2(x * tile, rect.size.y), Color(0.1, 0.17, 0.17, 0.3))
		for y in range(int(map_data.height) + 1):
			draw_line(rect.position + Vector2(0, y * tile), rect.position + Vector2(rect.size.x, y * tile), Color(0.1, 0.17, 0.17, 0.3))
	if spectator or battle == null:
		return
	if not story_active and int(battle.rules.get("fog_radius", 0)) > 0:
		var revealed: Dictionary = _visible_cells()
		for region in fog_regions(revealed):
			var fog_rect := Rect2(rect.position + Vector2(region.position) * tile, Vector2(region.size) * tile)
			if fog_rect.intersects(Rect2(Vector2.ZERO, size)): draw_rect(fog_rect, Color(0.05, 0.09, 0.16, 0.67))
	if not story_active:
		for seal in battle.units:
			var radius := int(seal.get("magic_seal_radius", 0))
			if radius <= 0 or not battle._on_map(seal): continue
			for y in range(maxi(0, int(seal.y) - radius), mini(battle.height, int(seal.y) + radius + 1)):
				for x in range(maxi(0, int(seal.x) - radius), mini(battle.width, int(seal.x) + radius + 1)):
					if absi(x - int(seal.x)) + absi(y - int(seal.y)) <= radius:
						draw_rect(Rect2(rect.position + Vector2(x, y) * tile, Vector2.ONE * tile), Color(0.65, 0.08, 0.20, 0.18))
	var units: Array = story_actors.values() if story_active else battle.units + battle.destructibles
	if not story_active:
		for trap in battle.chapter.get("placed_traps", []):
			var cell := Vector2i(trap.x, trap.y)
			if int(battle.rules.get("fog_radius", 0)) > 0 and not _visible_cells().has(cell): continue
			if trap.kind == "mine" and trap.get("owner", "enemy") != "player": continue
			var center := rect.position + (Vector2(cell) + Vector2.ONE * 0.5) * tile
			if trap.kind == "mine":
				draw_circle(center, tile * 0.16, Color("513643"))
				draw_arc(center, tile * 0.17, 0, TAU, 20, Color("efb297"), maxf(1, tile * 0.03))
				draw_circle(center, tile * 0.05, Color("f86c50"))
			else:
				var diamond := PackedVector2Array([center + Vector2(0, -tile * 0.4), center + Vector2(tile * 0.4, 0), center + Vector2(0, tile * 0.4), center + Vector2(-tile * 0.4, 0), center + Vector2(0, -tile * 0.4)])
				draw_colored_polygon(diamond, Color(0.3, 0.8, 1.0, 0.3))
				draw_polyline(diamond, Color("b7f3ff"), maxf(1, tile * 0.04), true)
				draw_string(ThemeDB.fallback_font, center + Vector2(-tile * 0.1, tile * 0.13), str(trap.turns), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, int(tile * 0.34)), Color.WHITE)
		for site in battle.interactions:
			if not site.get("discovered", false): continue
			var cell := Vector2i(int(site.x), int(site.y))
			if battle.rules.get("fog_radius", 0) > 0 and not _visible_cells().has(cell): continue
			var center := cell_screen_position(cell)
			draw_circle(center, tile * 0.28, Color("213342"))
			draw_arc(center, tile * 0.28, 0, TAU, 24, Color("f5df94"), maxf(1, tile * 0.04))
			draw_string(ThemeDB.fallback_font, center + Vector2(-tile * 0.12, tile * 0.13), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, int(tile * 0.35)), Color("f5df94"))
		for site in battle.chapter.get("emplacements", []):
			var cell := Vector2i(site.x, site.y)
			if int(battle.rules.get("fog_radius", 0)) > 0 and not _visible_cells().has(cell): continue
			var path := str(site.get("sprite", ""))
			if ResourceLoader.exists(path):
				textures["emplacement:" + path] = Art.texture(path)
				draw_texture_rect(textures["emplacement:" + path], Rect2(cell_screen_position(cell) - Vector2(tile * 0.5, tile), Vector2(tile, tile * 1.5)), false)
	if not story_active:
		for cell in reinforcement_warnings:
			var center := cell_screen_position(cell)
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.43, Vector2.ONE * tile * 0.86), Color(0.85, 0.16, 0.08, 0.3))
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.43, Vector2.ONE * tile * 0.86), Color("ffcd69"), false, maxf(2, tile * 0.05))
			draw_string(ThemeDB.fallback_font, center + Vector2(-tile * 0.09, tile * 0.18), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(16, int(tile * 0.6)), Color("fff1b8"))
	if choice_active and not story_active:
		_draw_units(units.filter(func(unit): return not ally_choice_ids.has(str(unit.id))), rect, tile)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.03, 0.07, 0.58))
		_draw_units(units.filter(func(unit): return ally_choice_ids.has(str(unit.id))), rect, tile)
	else:
		_draw_units(units, rect, tile)
	if not story_active and int(battle.rules.get("weather", 0)) == 4:
		draw_rect(rect, Color(0.08, 0.13, 0.24, 0.13))
		for index in range(140):
			var rain := rect.position + Vector2(fposmod(index * 83.7 + idle_elapsed * 95.0, rect.size.x), fposmod(index * 57.3 + idle_elapsed * 320.0, rect.size.y))
			draw_line(rain, rain + Vector2(7, 25), Color(0.93, 0.96, 1.0, 0.7), 1.5)
	if not story_active and battle.rules.get("weather_effect", "") == "snow":
		draw_rect(rect, Color(0.8, 0.88, 1.0, 0.1))
		for index in range(110):
			var flake := rect.position + Vector2(fposmod(index * 83.7 + idle_elapsed * 45.0, rect.size.x), fposmod(index * 57.3 + idle_elapsed * 70.0, rect.size.y))
			draw_circle(flake, 1.5, Color(0.95, 0.98, 1.0, 0.7))
	if not story_active and battle.rules.get("weather_effect", "") == "sandstorm":
		draw_rect(rect, Color(0.63, 0.47, 0.22, 0.13))
		for index in range(80):
			var dust := rect.position + Vector2(fposmod(index * 83.7 + idle_elapsed * 180.0, rect.size.x), fposmod(index * 57.3 + idle_elapsed * 15.0, rect.size.y))
			draw_line(dust, dust + Vector2(13, 1), Color(0.95, 0.81, 0.51, 0.35), 1.2)
	if not combat_feedback.is_empty():
		var target: Dictionary = battle.get_target(str(combat_feedback.id))
		if not target.is_empty():
			var point := rect.position + (unit_display_cell(str(target.id)) + Vector2.ONE * 0.5) * tile - Vector2(0, tile * (0.6 + float(combat_feedback.rise) * 0.4))
			var feedback_color := Color("adffbd") if combat_feedback.get("kind", "") == "heal" else (Color("ff6565") if combat_feedback.get("kind", "") == "damage" else Color("fff1bd") if combat_feedback.hit else Color("cee6ed"))
			feedback_color.a = float(combat_feedback.alpha)
			var feedback_size := maxi(20, int(tile * 0.38 * float(combat_feedback.get("scale", 1.0))))
			var message := preload("res://runtime/text_replacements.gd").apply(str(combat_feedback.text))
			var font := ThemeDB.fallback_font
			var extent := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, feedback_size)
			draw_string_outline(font, point - Vector2(extent.x * 0.5, 0), message, HORIZONTAL_ALIGNMENT_LEFT, -1, feedback_size, 4, Color(0.05, 0.08, 0.1, feedback_color.a))
			draw_string(font, point - Vector2(extent.x * 0.5, 0), message, HORIZONTAL_ALIGNMENT_LEFT, -1, feedback_size, feedback_color)
	drawing_visibility = false

func _draw_units(units: Array, rect: Rect2, tile: float) -> void:
	units = units.duplicate()
	units.sort_custom(func(a, b): return unit_display_cell(str(a.id)).y < unit_display_cell(str(b.id)).y)
	for unit in units:
		var unit_id := str(unit.id)
		var pending_effect := {}
		for effect in battle.pending_skill_effects:
			if effect.unit_id == unit_id and int(effect.previous_hp) >= 0: pending_effect = effect; break
		if not pending_effect.is_empty(): combat_visible[unit_id] = true; combat_hp[unit_id] = int(pending_effect.previous_hp)
		if not is_unit_visible(unit):
			continue
		var center := rect.position + (unit_display_cell(unit_id) + Vector2(0.5, 0.5)) * tile
		center += Vector2(combat_offsets.get(unit_id, Vector2.ZERO)) * tile
		var opacity: float = combat_alpha.get(unit_id, 1.0)
		if opacity <= 0:
			continue
		var acted := displayed_acted(unit)
		var tint := Color("61b8ef") if unit.faction == "player" else Color("ed7971")
		if acted:
			tint = Color("9aabaf")
		tint.a = opacity
		if unit.get("kind", "") != "structure":
			draw_circle(center + Vector2(0, tile * 0.16), tile * 0.36, Color(0.02, 0.04, 0.07, 0.5 * opacity))
		if ally_choice_ids.has(unit_id):
			var choice_rect := Rect2(center - Vector2.ONE * tile * 0.46, Vector2.ONE * tile * 0.92)
			draw_rect(choice_rect, Color(0.35, 0.95, 1.0, 0.24))
			draw_rect(choice_rect, Color("b5fbff"), false, maxf(2, tile * 0.05))
			draw_circle(center + Vector2(0, -tile * 0.43), maxf(3, tile * 0.07), Color("e8ffac"))
		if unit.id == enemy_focus_id:
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.49, Vector2.ONE * tile * 0.98), Color("fff6b9"), false, 4)
		elif unit.id == selected_id:
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.48, Vector2.ONE * tile * 0.96), Color("ffe4a0"), false, 3)
		elif unit.id == pending_target:
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.45, Vector2.ONE * tile * 0.9), Color("8dffab") if pending_target_beneficial else Color("ff9c79"), false, 3)
		var sprite_path := sprite_path_for(unit)
		var custom := custom_sprite_frame(unit)
		for site in battle.chapter.get("emplacements", []):
			if not story_active and not movement_positions.has(unit_id) and unit.get("weapon_types", []).has("bow") and battle.position(unit) == Vector2i(site.x, site.y):
				sprite_path = "res://content/fe7/rom/sprites/079_%s.png" % ("player" if unit.faction == "player" else "enemy")
				var mounted: Dictionary = unit.duplicate(); mounted.rom_class_id = 91
				custom = CustomSprites.frame(mounted, "idle", idle_elapsed)
		if unit.get("kind", "") == "structure":
			draw_rect(Rect2(center - Vector2.ONE * tile * 0.4, Vector2.ONE * tile * 0.8), Color(1, 0.85, 0.6, 0.35 * opacity), false, 1)
		elif not custom.is_empty():
			var extent: Vector2 = custom.size * tile
			var origin: Vector2 = center + Vector2(0, tile * 0.35) - extent * custom.anchor
			var modulation := Color("8c9298") if acted else Color.WHITE
			modulation = modulation.lerp(Color(2, 2, 2, 1), float(combat_flash.get(unit_id, 0.0)))
			modulation.a = opacity
			# Keep the actual texture alive until the renderer consumes the RID.
			textures["custom:" + unit_id] = custom.texture
			draw_texture_rect_region(custom.texture, Rect2(origin, extent), custom.source, modulation)
		elif not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
			var moving := movement_frame(unit) if not sprite_path.contains("/079_") else {}
			var idle_path := sprite_path_for(unit, true) if not sprite_path.contains("/079_") else sprite_path.get_basename() + "_idle.png"
			var animated := ResourceLoader.exists(idle_path)
			var texture_path := str(moving.path) if not moving.is_empty() else (idle_path if animated else sprite_path)
			if not textures.has(texture_path):
				textures[texture_path] = Art.texture(texture_path)
			var texture: Texture2D = textures[texture_path]
			var frame_size: Vector2 = moving.size if not moving.is_empty() else texture.get_size() / Vector2(3 if animated else 1, 1)
			var sprite_size: Vector2 = frame_size * (tile / 16.0)
			var sprite_origin := center + Vector2(-sprite_size.x * 0.5, tile * 0.35 - sprite_size.y)
			if not moving.is_empty(): sprite_origin = center + Vector2(0, tile * 0.35) - Vector2(moving.anchor) * (tile / 16.0)
			draw_circle(center + Vector2(0, tile * 0.1), tile * 0.28, Color(tint, 0.4 * opacity))
			var modulation := Color("8c9298") if acted else Color.WHITE
			modulation = modulation.lerp(Color(2, 2, 2, 1), float(combat_flash.get(unit_id, 0.0)))
			modulation.a = opacity
			var frame: int = int(moving.frame) if not moving.is_empty() else idle_frame
			if not moving.is_empty(): animated = true
			var source := Rect2(Vector2(frame_size.x * (frame if animated else 0), 0), frame_size)
			# Canvas draw commands retain a RID, not a strong Texture2D reference.
			# Keep each actor's current region alive through the rendered frame.
			textures["frame:" + unit_id] = Art.region_texture(texture_path, source)
			draw_texture_rect(textures["frame:" + unit_id], Rect2(sprite_origin, sprite_size), false, modulation)
		else:
			draw_circle(center, tile * 0.32, Color(Color("1c3342"), opacity))
			draw_arc(center, tile * 0.32, 0, TAU, 24, tint, maxf(2, tile * 0.05), true)
			var font := ThemeDB.fallback_font
			var text_size := maxi(12, int(tile * 0.34))
			var initial: String = preload("res://runtime/text_replacements.gd").apply(str(unit.name)).left(1)
			var extent := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
			draw_string(font, center + Vector2(-extent.x * 0.5, extent.y * 0.27), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, tint)
		if not str(unit.get("carrying_id", "")).is_empty():
			var badge := center + Vector2(tile * 0.28, -tile * 0.26)
			draw_circle(badge, tile * 0.15, Color("1749b9"))
			draw_circle(badge + Vector2(0, -tile * 0.04), tile * 0.04, Color.WHITE)
			draw_line(badge, badge + Vector2(0, tile * 0.07), Color.WHITE, maxf(2, tile * 0.05))
		if story_active: continue
		var bar := Rect2(center + Vector2(-tile * 0.35, tile * 0.36), Vector2(tile * 0.7, maxf(3, tile * 0.07)))
		draw_rect(bar, Color(Color("182128"), opacity))
		bar.size.x *= clampf(float(combat_hp.get(unit_id, unit.hp)) / float(unit.max_hp), 0, 1)
		draw_rect(bar, Color(Color.WHITE, opacity))

func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("293c42")
	style.border_color = Color("ba9b65")
	style.set_border_width_all(2)
	return style

func custom_sprite_frame(unit: Dictionary) -> Dictionary:
	var id := str(unit.id)
	if sprite_actions.has(id):
		var action: Dictionary = sprite_actions[id]
		var frame := CustomSprites.frame(unit, action.state, (idle_elapsed - float(action.started)) * battle_speed)
		if not frame.is_empty(): return frame
	if walking_id == id:
		return CustomSprites.frame(unit, str(walk_directions.get(id, "down")), walk_elapsed * (1.0 if story_active else movement_speed))
	if selected_id == id:
		var ready_frame := CustomSprites.frame(unit, "ready", idle_elapsed)
		if not ready_frame.is_empty(): return ready_frame
	return CustomSprites.frame(unit, "idle", idle_elapsed)

func _play_skill_effect(effect: Dictionary, token: int) -> bool:
	var id := str(effect.unit_id)
	var unit: Dictionary = battle.get_unit(id)
	if unit.is_empty() or not _visible_to_player(unit): return true
	combat_feedback = {"id": id, "text": str(effect.skill), "hit": true, "alpha": 1.0, "scale": 1.0, "rise": 0.0}
	if not await _animate(0.65, token, func(t): _feedback_motion(t)): return false
	if int(effect.previous_hp) >= 0 and int(effect.previous_hp) != int(effect.remaining_hp):
		var delta := int(effect.remaining_hp) - int(effect.previous_hp)
		if delta < 0: voice_requested.emit(unit, "damage")
		combat_feedback = {"id": id, "text": "%+d" % delta, "hit": true, "kind": "heal" if delta > 0 else "damage", "alpha": 1.0, "scale": 1.0, "rise": 0.0}
		if not await _animate(0.8, token, func(t):
			combat_hp[id] = lerpf(float(effect.previous_hp), float(effect.remaining_hp), smoothstep(0.0, 0.8, t))
			_feedback_motion(t)): return false
		if int(effect.remaining_hp) <= 0:
			voice_requested.emit(unit, "defeat")
			if not await _animate(0.35, token, func(t): combat_alpha[id] = 1.0 - t): return false
	combat_feedback.clear()
	return true

func _prepare_step_sounds(unit: Dictionary) -> void:
	step_sound_frame = -1
	step_sounds.clear()
	var assets = preload("res://runtime/rom_assets.gd")
	if assets.initialized(): step_sounds = preload("res://runtime/rom_map_sounds.gd").movement(assets.decoder, assets.game_id, int(unit.get("rom_class_id", 0)))
