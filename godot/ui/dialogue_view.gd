extends ColorRect
signal native_choice_selected(answer: bool)
const Art = preload("res://runtime/art_textures.gd")
const CustomPortraits = preload("res://runtime/custom_portraits.gd")
var portrait_context: Dictionary = {}
var portrait_speakers: Dictionary = {}
var speaker_factions: Dictionary = {}
## Dialogue presentation only. Speaker roles and scene art come from the pack.

var panel: PanelContainer
var speaker_label: Label
var text_label: Label
var left_portrait: TextureRect
var right_portrait: TextureRect
var background: TextureRect
var continue_mark: Label
var choice_buttons: Array[Button] = []
var choice_row: HBoxContainer
var text_speed := 2
var left_speakers: Array = []
var left_path := ""
var right_path := ""
var left_speaker := ""
var right_speaker := ""
var background_path := ""
var background_color := ""
var active_side := "left"
var reveal_count := 0.0
var texture_cache: Dictionary = {}
var current: Dictionary = {}
var lord_paths: Dictionary = {}
var route: Control
var animations_enabled := true
var transition_speed := 1.0
var movement_speed := 1.0
var presentation_generation := 0
var portrait_tweens: Dictionary = {}
var portrait_offsets: Dictionary = {}
var departing_portraits: Array[TextureRect] = []
var panel_tween: Tween
var closing := false
var content_visible := true
var speech_tail: Polygon2D
var speech_tail_border: Polygon2D
var portrait_animations: Dictionary = {}
var portrait_frames: Dictionary = {}
var face_clock := 0.0

func _ready() -> void:
	color = Color(0.01, 0.02, 0.04, 0.12)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	route = load("res://ui/worldmap_route.gd").new()
	route.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(route)
	left_portrait = _face(true)
	right_portrait = _face(false)
	panel = PanelContainer.new()
	# Child order keeps the paper above portraits without raising it above
	# later sibling overlays such as Info and Settings.
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f1eee1")
	paper.border_color = Color("61543c")
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(8)
	paper.shadow_color = Color(0, 0, 0, 0.28)
	paper.shadow_size = 3
	paper.content_margin_left = 18
	paper.content_margin_right = 22
	paper.content_margin_top = 10
	paper.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", paper)
	add_child(panel)
	speech_tail_border = Polygon2D.new()
	speech_tail_border.color = paper.border_color
	panel.add_child(speech_tail_border)
	speech_tail = Polygon2D.new()
	speech_tail.color = paper.bg_color
	panel.add_child(speech_tail)
	panel.resized.connect(_anchor_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 20)
	speaker_label.add_theme_color_override("font_color", Color("726039"))
	column.add_child(speaker_label)
	text_label = Label.new()
	text_label.add_theme_font_size_override("font_size", 24)
	text_label.add_theme_color_override("font_color", Color("302f36"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(text_label)
	choice_row = HBoxContainer.new()
	choice_row.add_theme_constant_override("separation",16)
	column.add_child(choice_row)
	for answer in [true,false]:
		var button := Button.new()
		button.text = "Yes" if answer else "No"
		button.custom_minimum_size = Vector2(120,44)
		button.pressed.connect(func():native_choice_selected.emit(answer))
		choice_buttons.append(button); choice_row.add_child(button)
	choice_row.hide()
	continue_mark = Label.new()
	continue_mark.text = "▾"
	continue_mark.add_theme_font_size_override("font_size", 24)
	continue_mark.add_theme_color_override("font_color", Color("6a70c4"))
	continue_mark.tooltip_text = "Tap anywhere to continue"
	add_child(continue_mark)
	resized.connect(layout)
	visibility_changed.connect(func():
		if not visible: _cancel_presentation())
	hide()

func _face(left: bool) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.flip_h = left
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	return portrait

func reset() -> void:
	scene_speakers.clear()
	filter_scene_speakers = false
	_cancel_presentation()
	texture_cache.clear()
	portrait_frames.clear()
	for portrait in [left_portrait, right_portrait]:
		portrait.texture = null
		if portrait.has_meta("base_texture"): portrait.remove_meta("base_texture")
		portrait.hide()
	left_path = ""
	right_path = ""
	left_speaker = ""
	right_speaker = ""
	background_path = ""
	background_color = ""
	current = {}
	choice_row.hide()
	portrait_speakers.clear()
	speaker_factions.clear()
	lord_paths.clear()
	if route: route.reset()
	content_visible = true
	face_clock = 0.0

func prepare(lines: Array) -> void:
	var paths: Dictionary = {}
	for line in lines:
		if not line is Dictionary: continue
		if line.has("speaker_faction"): speaker_factions[str(line.get("speaker", "")).to_lower()] = line.speaker_faction
		for prefix in ["", "left_", "right_"]:
			var path := str(line.get(prefix + "portrait", ""))
			if not path.is_empty(): paths[path] = true
			_remember_portrait(path, str(line.get(prefix + "speaker", "")))
	# Resolve preferred slots after all named speakers have been registered.
	lord_paths.clear()
	for path in paths:
		if _is_lord(_speaker_for_portrait(path)): lord_paths[path] = true

var scene_speakers: Dictionary = {}
var filter_scene_speakers := false

func present(line: Dictionary, _following: Array) -> void:
	var listeners := {left_speaker: left_path, right_speaker: right_path}
	var previous_speaker := str(current.get("speaker", ""))
	line = line.duplicate(true)
	line.speaker = _portrait_identity(str(line.get("portrait", "")), str(line.get("speaker", "")))
	if closing: _cancel_presentation()
	presentation_generation += 1
	var opening := not visible or not panel.visible
	current = line.duplicate(true)
	choice_row.visible = bool(current.get("native_choice",false))
	speaker_label.text = _display_speaker_name(str(line.get("speaker", "")))
	text_label.text = str(line.get("text", ""))
	reveal_count = 0
	text_label.visible_characters = -1 if text_speed == 3 else 0
	continue_mark.visible = text_speed == 3 and not current.get("native_choice",false)
	var speaker := str(line.get("speaker", ""))
	var path := str(line.get("portrait", ""))
	var scene_changed := (line.has("background") and str(line.background) != background_path) or (line.has("background_color") and str(line.background_color) != background_color)
	if scene_changed or line.get("clear_portraits", false):
		scene_speakers.clear()
		filter_scene_speakers = true
	if not path.is_empty(): scene_speakers[speaker] = true
	_remember_portrait(path, speaker)
	for prefix in ["left_", "right_"]:
		_remember_portrait(str(line.get(prefix + "portrait", "")), str(line.get(prefix + "speaker", "")))
	active_side = ""
	var clear: bool = scene_changed or line.get("clear_portraits", false) or (line.get("scene_type", "") in ["cg", "worldmap"] and path.is_empty())
	if clear:
		listeners.clear()
		previous_speaker = ""
		left_path = ""; right_path = ""
		left_speaker = ""; right_speaker = ""
	var rom_slots: bool = line.get("rom_portrait_slots", false) or (line.has("source_speaker_slot") and line.has("left_portrait") and line.has("right_portrait"))
	if rom_slots:
		left_path = str(line.get("left_portrait", ""))
		right_path = str(line.get("right_portrait", ""))
		left_speaker = _speaker_for_portrait(left_path)
		right_speaker = _speaker_for_portrait(right_path)
		active_side = str(line.get("speaker_side", "")) if not path.is_empty() else ""
	elif not path.is_empty():
		# ROM slots are snapshots of the original four-face stage, not a list
		# of participants to resurrect in our two-face presentation.
		var listener := previous_speaker
		if listener == speaker or not listeners.has(listener):
			listener = right_speaker if left_speaker == speaker else left_speaker
		var listener_path := str(listeners.get(listener, ""))
		# The first line may already place a listening lord in the scene.
		# Seed that role once; later slot snapshots must not revive old guests.
		if previous_speaker.is_empty() and listener_path.is_empty():
			for prefix in ["left_", "right_"]:
				var candidate_path := str(line.get(prefix + "portrait", ""))
				var candidate := _speaker_for_portrait(candidate_path)
				if candidate != speaker and _is_lord(candidate): listener = candidate; listener_path = candidate_path; break
		var speaking_enemy := _enemy_speaker(speaker)
		# Keep the lord only while present in this conversation. A hostile
		# listener takes precedence so player speakers can rotate on the left.
		for listener_name in listeners:
			if listener_name != speaker and _enemy_speaker(listener_name) and not speaking_enemy:
				listener = listener_name; listener_path = listeners[listener_name]; break
		if not speaking_enemy and not _enemy_speaker(listener):
			for listener_name in listeners:
				if listener_name != speaker and _is_lord(listener_name):
					listener = listener_name; listener_path = listeners[listener_name]; break
		# Explicit single-face pages include direct addresses to the tactician.
		if line.has("left_portrait") and line.has("right_portrait"):
			if str(line.left_portrait) in ["",path] and str(line.right_portrait) in ["",path] and (str(line.left_portrait)==path or str(line.right_portrait)==path):
				listener = ""; listener_path = ""
		if line.get("tactician_address", false): listener = ""; listener_path = ""
		if (line.has("right_portrait") and str(line.right_portrait).is_empty() and not line.has("left_portrait")) or (line.has("left_portrait") and str(line.left_portrait).is_empty() and not line.has("right_portrait")):
			listener = ""; listener_path = ""
		var on_left := _is_lord(speaker) or _enemy_speaker(listener) or listener_path.is_empty()
		if listener_path.is_empty() and not lord_paths.is_empty() and not _is_lord(speaker): on_left = false
		if speaking_enemy and not _enemy_speaker(listener): on_left = false
		elif not speaking_enemy and _enemy_speaker(listener): on_left = true
		elif _is_lord(listener) and (not _is_lord(speaker) or _lord_priority(listener) <= _lord_priority(speaker)): on_left = false
		elif speaker == right_speaker and not listener_path.is_empty() and not _is_lord(speaker): on_left = false
		if speaker == left_speaker and listener == right_speaker: on_left = true
		elif speaker == right_speaker and listener == left_speaker: on_left = false
		left_path = path if on_left else listener_path
		right_path = listener_path if on_left else path
		left_speaker = speaker if on_left else listener
		right_speaker = listener if on_left else speaker
		active_side = "left" if on_left else "right"
		if left_path == right_path:
			if on_left: right_path = ""; right_speaker = ""
			else: left_path = ""; left_speaker = ""
	# A backdrop cut starts a new scene; keep only its current speaker.
	# Slot snapshots can still contain listeners from the previous scene.
	if scene_changed:
		if active_side != "left": left_path = ""; left_speaker = ""
		if active_side != "right": right_path = ""; right_speaker = ""
	if filter_scene_speakers:
		if not scene_speakers.has(left_speaker): left_path = ""; left_speaker = ""
		if not scene_speakers.has(right_speaker): right_path = ""; right_speaker = ""
	if not left_path.is_empty() and not right_path.is_empty() and (left_path == right_path or (not left_speaker.is_empty() and left_speaker == right_speaker)):
		if active_side == "left": right_path = ""; right_speaker = ""
		else: left_path = ""; left_speaker = ""
	if line.has("background"): background_path = str(line.background)
	if line.get("worldmap_portraits",false):
		left_path = str(line.get("left_portrait","")); right_path = str(line.get("right_portrait",""))
		left_speaker = ""; right_speaker = ""; active_side = ""
	if line.has("background_color"): background_color = str(line.background_color)
	elif line.get("scene_type", "") == "map": background_color = ""
	_update_art(true)
	if line.get("worldmap", {}) is Dictionary: route.present(line.get("worldmap", {}), background.texture)
	else: route.hide()
	show()
	set_content_visible(content_visible)
	layout()
	call_deferred("layout")
	if opening: _open_panel()

func _display_speaker_name(speaker: String) -> String:
	# Keep placeholder identities for portrait tracking, but never show them
	# as a person's name in the dialogue heading.
	var speaker_name := speaker.strip_edges()
	var placeholder := RegEx.create_from_string("(?i)^(?:portrait(?:[\\s_·:-]|$)|character\\s+[0-9]+$|fe[67]_unit_[0-9]+$)")
	return "" if placeholder.search(speaker_name) != null else speaker_name

func _enemy_speaker(speaker_name: String) -> bool:
	var unit: Dictionary = portrait_context.get(speaker_name.to_lower(), {})
	return unit.get("faction", speaker_factions.get(speaker_name.to_lower(), "")) == "enemy"

func _is_lord(speaker_name: String) -> bool:
	if left_speakers.has(speaker_name): return true
	var assets = preload("res://runtime/rom_assets.gd")
	if not assets.initialized(): return false
	for id in ([1] if assets.game_id == "fe6" else [1,2,3]):
		if speaker_name == preload("res://runtime/rom_names.gd").character(assets.decoder,assets.game_id,id): return true
	return false

func _lord_priority(speaker_name: String) -> int:
	return 0 if left_speakers.has(speaker_name) else 1

func _remember_portrait(path: String, speaker: String) -> void:
	if not path.is_empty() and not speaker.is_empty(): portrait_speakers[path] = _portrait_identity(path, speaker)

func _speaker_for_portrait(path: String) -> String:
	if path.is_empty(): return ""
	if portrait_speakers.has(path): return portrait_speakers[path]
	var identity := _portrait_identity(path, "")
	if not identity.is_empty(): return identity
	for portrait_name in portrait_context:
		var unit: Dictionary = portrait_context[portrait_name]
		if str(unit.get("portrait", "")) == path:
			var speaker := str(unit.get("name", portrait_name))
			_remember_portrait(path, speaker)
			return speaker
	var decoder = preload("res://runtime/rom_assets.gd").decoder
	if decoder:
		var portrait_id := path.get_file().get_basename().to_int()
		for index in range(int(decoder.layout.get("character_count",253))):
			var at: int = decoder.ptr(int(decoder.layout.get("characters",0x9a274))) + index * int(decoder.layout.get("character_stride",52))
			if decoder.u16(at + 6) == portrait_id:
				var speaker: String = decoder.normalize_text(decoder.text(decoder.u16(at)))
				_remember_portrait(path, speaker)
				return speaker
	return ""

func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if texture_cache.has(path): return texture_cache[path]
	var cropped := Art.region_texture(path, Art.original_image(path).get_used_rect())
	texture_cache[path] = cropped
	return cropped

func configure_animations(manifest_path: String) -> void:
	portrait_animations.clear()
	portrait_frames.clear()
	if not FileAccess.file_exists(manifest_path): return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if manifest is Dictionary and manifest.get("entries") is Dictionary:
		portrait_animations = manifest.entries

func _expression_texture(path: String, eye: int, mouth: int) -> Texture2D:
	var base := _texture(path)
	if not portrait_animations.has(path) or not base is AtlasTexture: return base
	var entry: Dictionary = portrait_animations[path]
	var atlas_path := str(entry.get("atlas", ""))
	if not ResourceLoader.exists(atlas_path): return base
	eye = mini(eye, int(entry.get("eye_frames", 1)) - 1)
	mouth = mini(mouth, int(entry.get("mouth_frames", 1)) - 1)
	var key := "%s:%s:%s" % [path, eye, mouth]
	if portrait_frames.has(key): return portrait_frames[key]
	var region: Rect2 = base.region
	region.position += Vector2(mouth * 96, eye * 80)
	var frame := Art.region_texture(atlas_path, region)
	portrait_frames[key] = frame
	return frame

func _animate_faces() -> void:
	if not content_visible or _portraits_suppressed(): return
	for side in ["left", "right"]:
		var portrait := left_portrait if side == "left" else right_portrait
		var path := left_path if side == "left" else right_path
		if not portrait.visible or path.is_empty(): continue
		if not portrait.get_meta("custom", {}).is_empty(): continue
		# Keep the cadence independent for listeners. Only the active portrait
		# moves its mouth while actual glyphs are being revealed.
		var blink := fmod(face_clock + (1.8 if side == "right" else 0.0), 4.2)
		var eye := 0
		if blink >= 3.98 and blink < 4.04: eye = 1
		elif blink >= 4.04 and blink < 4.13: eye = 2
		elif blink >= 4.13: eye = 1
		var mouth := 0
		if active_side == side and is_typing():
			mouth = [0, 1, 2, 1][int(face_clock / 0.085) % 4]
		portrait.texture = _expression_texture(path, eye, mouth)

func _update_art(animate: bool = false) -> void:
	choice_row.visible = content_visible and bool(current.get("native_choice",false))
	# Save restoration and manual portrait placement use this path as well.
	if not left_path.is_empty() and not right_path.is_empty() and (left_path == right_path or (not left_speaker.is_empty() and left_speaker == right_speaker)):
		if active_side == "left": right_path = ""; right_speaker = ""
		else: left_path = ""; left_speaker = ""
	# Guide pages temporarily cover a conversation. Keep its face slots so the
	# next story page can restore listeners, but never show their exit clones.
	if _portraits_suppressed(): _remove_departing_portraits()
	# Moving a character across sides must not leave a second exit-clone of
	# that same character while the new side enters.
	if (not left_speaker.is_empty() and left_speaker == str(right_portrait.get_meta("character", ""))) or (not right_speaker.is_empty() and right_speaker == str(left_portrait.get_meta("character", ""))):
		_remove_departing_portraits()
		animate = false
	color = Color(background_color) if Color.html_is_valid(background_color) else Color(0.01, 0.02, 0.04, 0.12)
	_update_face(left_portrait, left_path, left_speaker, "left", animate)
	_update_face(right_portrait, right_path, right_speaker, "right", animate)
	background.visible = not background_path.is_empty() and ResourceLoader.exists(background_path)
	background.texture = preload("res://runtime/custom_backdrops.gd").texture(background_path) if background.visible else null
	if background.visible and background.texture == null: background.texture = preload("res://runtime/custom_maps.gd").texture(background_path)
	if background.visible and background.texture == null: background.texture = Art.texture(background_path)
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if background.texture is ImageTexture else CanvasItem.TEXTURE_FILTER_NEAREST

func _update_face(portrait: TextureRect, path: String, speaker: String, side: String, animate: bool) -> void:
	speaker = _portrait_identity(path, speaker)
	var context: Dictionary = portrait_context.get(speaker.to_lower(), {}).duplicate(true)
	context.portrait_id = path.get_file().get_basename().to_int()
	if context.size() == 1 and not path.is_empty():
		var decoder = preload("res://runtime/rom_assets.gd").decoder
		if decoder:
			var portrait_id := path.get_file().get_basename().to_int()
			for index in range(int(decoder.layout.get("character_count",253))):
				var at: int = decoder.ptr(int(decoder.layout.get("characters",0x9a274))) + index * int(decoder.layout.get("character_stride",52))
				if decoder.u16(at + 6) == portrait_id:
					context.merge({"rom_character_id": decoder.rom[at + 4], "rom_class_id": decoder.rom[at + 5]})
					break
	context.game_id = "fe6" if path.begins_with("res://content/fe6/") else "fe7"
	var custom: Dictionary = CustomPortraits.find_portrait(speaker, context) if not path.is_empty() else {}
	var texture: Texture2D = CustomPortraits.texture(custom) if not custom.is_empty() else null
	if texture == null: custom = {}; texture = _texture(path)
	_update_portrait(portrait, texture, side, animate)
	portrait.set_meta("custom", custom)
	portrait.set_meta("character", speaker)
	portrait.flip_h = (side == "left") != bool(custom.get("flip_h", false))
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if not custom.is_empty() else CanvasItem.TEXTURE_FILTER_NEAREST

func _portraits_suppressed() -> bool:
	return bool(current.get("tutorial", false)) or str(current.get("speaker", "")) == "Guide" or _image_only_page()

func _image_only_page() -> bool:
	return str(current.get("scene_type", "")) == "cg" and str(current.get("text", "")).strip_edges().is_empty()

func _remove_departing_portraits() -> void:
	for departing in departing_portraits:
		if is_instance_valid(departing):
			departing.hide()
			departing.queue_free()
	departing_portraits.clear()

func refresh_art() -> void:
	# A setting change replaces textures without replaying the page, resetting
	# typewriter progress, or leaving a departing unscaled face over the new one.
	_remove_departing_portraits()
	texture_cache.clear()
	portrait_frames.clear()
	_update_art(false)
	_animate_faces()
	if route: route.refresh_art()
	layout()

func _update_portrait(portrait: TextureRect, texture: Texture2D, side: String, animate: bool) -> void:
	var previous: Texture2D = portrait.get_meta("base_texture") if portrait.has_meta("base_texture") else null
	var changed: bool = previous != texture
	var tween: Tween = portrait_tweens.get(side)
	if changed and tween and tween.is_valid(): tween.kill()
	portrait.texture = texture
	portrait.set_meta("base_texture", texture)
	portrait.visible = texture != null and content_visible and not _portraits_suppressed()
	var tint := Color.WHITE if active_side == side else Color(0.78, 0.78, 0.82)
	# Color indicates the active speaker; self_modulate owns the fade so active
	# speaker changes cannot interrupt a portrait still entering.
	portrait.modulate = tint
	if not changed: return
	portrait_offsets[side] = 0.0
	portrait.self_modulate.a = 1.0
	if texture == null or not animate or not animations_enabled: return
	portrait_offsets[side] = -45.0 if side == "left" else 45.0
	portrait.self_modulate.a = 0.0
	tween = create_tween().set_parallel(true)
	portrait_tweens[side] = tween
	tween.tween_method(func(offset: float): portrait_offsets[side] = offset; _position_portraits(), float(portrait_offsets[side]), 0.0, 0.15 / maxf(0.1, transition_speed)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait, "self_modulate:a", 1.0, 0.10 / maxf(0.1, transition_speed))

func _position_portraits() -> void:
	for portrait in [left_portrait, right_portrait]:
		var side := "left" if portrait == left_portrait else "right"
		# Center the visible (alpha-cropped) face within its side gutter, rather
		# than anchoring narrow portraits against a distant screen edge.
		var center := panel.position.x * 0.5 if side == "left" else (panel.position.x + panel.size.x + size.x) * 0.5
		var x := clampf(center - portrait.size.x * 0.5, 0.0, maxf(0.0, size.x - portrait.size.x))
		portrait.position = Vector2(x, size.y - portrait.size.y) + Vector2(float(portrait_offsets.get(side, 0)), 0)
		var custom: Dictionary = portrait.get_meta("custom", {})
		portrait.position += Vector2(float(custom.get("x_percent", 0)) * size.x * (-1 if portrait == left_portrait else 1), float(custom.get("y_percent", 0)) * size.y) / 100.0

func _open_panel() -> void:
	if panel_tween and panel_tween.is_valid(): panel_tween.kill()
	panel.scale = Vector2.ONE
	panel.modulate.a = 1.0
	if not animations_enabled: return
	panel.scale = Vector2(0.86, 0.72)
	panel.modulate.a = 0.0
	panel_tween = create_tween().set_parallel(true)
	panel_tween.tween_property(panel, "scale", Vector2.ONE, 0.18 / maxf(0.1, transition_speed)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panel_tween.tween_property(panel, "modulate:a", 1.0, 0.09 / maxf(0.1, transition_speed))

func close_presentation() -> void:
	closing = true
	presentation_generation += 1
	var token := presentation_generation
	if panel_tween and panel_tween.is_valid(): panel_tween.kill()
	if not visible or not animations_enabled:
		hide()
		return
	panel_tween = create_tween().set_parallel(true)
	panel_tween.tween_property(panel, "scale", Vector2(0.9, 0.75), 0.10 / maxf(0.1, transition_speed)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	panel_tween.tween_property(panel, "modulate:a", 0.0, 0.10 / maxf(0.1, transition_speed))
	for portrait in [left_portrait, right_portrait]:
		var side := "left" if portrait == left_portrait else "right"
		var entrance: Tween = portrait_tweens.get(side)
		if entrance and entrance.is_valid(): entrance.kill()
		panel_tween.tween_method(func(offset: float): portrait_offsets[side] = offset; _position_portraits(), float(portrait_offsets.get(side, 0)), -45.0 if side == "left" else 45.0, 0.10 / maxf(0.1, transition_speed))
		panel_tween.tween_property(portrait, "self_modulate:a", 0.0, 0.10 / maxf(0.1, transition_speed))
	# Poll generation instead of awaiting Tween.finished: killed tweens never
	# finish, and load/restart must be able to cancel a closing dialogue.
	while panel_tween and panel_tween.is_running():
		if token != presentation_generation or not is_inside_tree(): return
		await get_tree().process_frame
	if token == presentation_generation: hide()

func _cancel_presentation() -> void:
	presentation_generation += 1
	closing = false
	if panel_tween and panel_tween.is_valid(): panel_tween.kill()
	for tween in portrait_tweens.values():
		if tween and tween.is_valid(): tween.kill()
	portrait_tweens.clear()
	portrait_offsets.clear()
	for departing in departing_portraits:
		if is_instance_valid(departing): departing.queue_free()
	departing_portraits.clear()
	if panel:
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0
	for portrait in [left_portrait, right_portrait]:
		if portrait: portrait.self_modulate.a = 1.0

func layout() -> void:
	if not panel: return
	var portrait_width := minf(400, size.x * 0.29)
	for portrait in [left_portrait, right_portrait]:
		if portrait.texture:
			var texture_size: Vector2 = portrait.texture.get_size()
			# Original faces share a 96×80 canvas. Cropping transparent margins
			# must not magnify narrow faces or shrink broad shoulders.
			portrait.size = texture_size * (portrait_width * 1.13 / 96.0)
			var custom: Dictionary = portrait.get_meta("custom", {})
			if not custom.is_empty(): portrait.size = texture_size * (portrait_width * 1.13 * 80.0 / 96.0 / texture_size.y) * float(custom.get("scale_percent", 100)) / 100.0
	# Reserve both portrait gutters even for narration or a lone speaker.
	# A scene's text no longer changes width or jumps sideways as faces enter.
	var width := minf(720, size.x - portrait_width * 2 - 32)
	# A page can open before PanelContainer's first sorting pass. Give the
	# wrapping label its actual text width before querying/assigning the panel
	# size; otherwise a temporary one-pixel width creates a huge minimum height.
	var text_width := maxf(1.0, floorf(width - 40))
	text_label.size.x = text_width
	var font := text_label.get_theme_font("font")
	var text_height := font.get_multiline_string_size(str(TranslationServer.translate(text_label.text)), HORIZONTAL_ALIGNMENT_LEFT, text_width, 24).y
	var height := maxf(116, text_height + 62 + (48 if current.get("native_choice",false) else 0))
	panel.size = Vector2(width, height)
	panel.pivot_offset = Vector2(width * 0.5, height)
	panel.position.x = (size.x - width) * 0.5
	_anchor_panel()
	_position_portraits()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): layout.call_deferred()

func _anchor_panel() -> void:
	if not continue_mark: return
	panel.position.y = size.y - panel.size.y - 12
	continue_mark.position = panel.position + Vector2(panel.size.x - 30, panel.size.y - 31)
	_update_tail()

func _update_tail() -> void:
	if not speech_tail: return
	var speaker_visible := (active_side == "left" and left_portrait.visible) or (active_side == "right" and right_portrait.visible)
	speech_tail.visible = content_visible and speaker_visible
	speech_tail_border.visible = speech_tail.visible
	var at := Vector2(0.0 if active_side == "left" else panel.size.x, minf(68, panel.size.y * 0.5))
	var direction := -1.0 if active_side == "left" else 1.0
	speech_tail_border.polygon = PackedVector2Array([at + Vector2(-direction * 2, -15), at + Vector2(direction * 19, 0), at + Vector2(-direction * 2, 15)])
	speech_tail.polygon = PackedVector2Array([at + Vector2(-direction * 4, -11), at + Vector2(direction * 14, 0), at + Vector2(-direction * 4, 11)])

func set_content_visible(value: bool) -> void:
	content_visible = value
	panel.visible = value and not _image_only_page()
	continue_mark.visible = value and not _image_only_page() and not is_typing() and not current.get("native_choice",false)
	left_portrait.visible = value and left_portrait.texture != null and not _portraits_suppressed()
	right_portrait.visible = value and right_portrait.texture != null and not _portraits_suppressed()
	for departing in departing_portraits:
		if is_instance_valid(departing): departing.visible = value and not _portraits_suppressed()
	_update_tail()

func _process(delta: float) -> void:
	if not visible: return
	if route: route.movement_speed = movement_speed
	if is_typing() and content_visible:
		var rate: float = [20.0, 45.0, 90.0, 0.0][text_speed]
		reveal_count += delta * rate
		text_label.visible_characters = mini(int(reveal_count), text_label.get_total_character_count()) if rate > 0 else -1
	continue_mark.visible = content_visible and not _image_only_page() and not is_typing() and not current.get("native_choice",false)
	face_clock += delta
	_animate_faces()

func is_typing() -> bool:
	return text_label.visible_characters >= 0 and text_label.visible_characters < text_label.get_total_character_count()

func reveal() -> void:
	text_label.visible_characters = -1
	continue_mark.visible = content_visible and not _image_only_page() and not current.get("native_choice",false)
	_animate_faces()

func capture_state() -> Dictionary:
	return {"scene_speakers":scene_speakers.duplicate(), "filter_scene_speakers":filter_scene_speakers, "left":left_path, "right":right_path, "left_speaker":left_speaker, "right_speaker":right_speaker, "portrait_speakers":portrait_speakers.duplicate(), "speaker_factions":speaker_factions.duplicate(), "background":background_path, "background_color":background_color, "side":active_side, "visible_characters":text_label.visible_characters, "current":current.duplicate(true), "lord_paths":lord_paths.keys(), "route":route.capture_state()}

func restore_state(state: Dictionary) -> void:
	scene_speakers = state.get("scene_speakers", {}).duplicate() if state.get("scene_speakers", {}) is Dictionary else {}
	filter_scene_speakers = bool(state.get("filter_scene_speakers", false))
	_cancel_presentation()
	left_path = str(state.get("left", ""))
	right_path = str(state.get("right", ""))
	left_speaker = str(state.get("left_speaker", ""))
	right_speaker = str(state.get("right_speaker", ""))
	portrait_speakers = state.get("portrait_speakers", {}).duplicate()
	if state.get("speaker_factions", {}) is Dictionary: speaker_factions = state.get("speaker_factions", {}).duplicate()
	_remember_portrait(left_path, left_speaker)
	_remember_portrait(right_path, right_speaker)
	background_path = str(state.get("background", ""))
	background_color = str(state.get("background_color", ""))
	active_side = str(state.get("side", "left"))
	current = state.get("current", {}).duplicate(true) if state.get("current", {}) is Dictionary else {}
	speaker_label.text = _display_speaker_name(str(current.get("speaker", "")))
	text_label.text = str(current.get("text", ""))
	lord_paths.clear()
	for path in state.get("lord_paths", []): lord_paths[str(path)] = true
	text_label.visible_characters = clampi(int(state.get("visible_characters", -1)), -1, text_label.get_total_character_count())
	reveal_count = float(maxi(0, text_label.visible_characters))
	_update_art()
	if current.get("worldmap", {}) is Dictionary: route.present(current.get("worldmap", {}), background.texture)
	else: route.hide()
	if state.get("route", {}) is Dictionary: route.restore_state(state.get("route", {}))
	set_content_visible(content_visible)
	layout()

func _portrait_identity(path: String, fallback: String) -> String:
	if not fallback.is_empty() and not fallback.begins_with("Portrait"): return fallback
	var assets = preload("res://runtime/rom_assets.gd")
	if not assets.initialized() or not path.begins_with("res://content/"+assets.game_id+"/rom/portraits/"): return fallback
	var id := path.get_file().get_basename().to_int()
	return preload("res://runtime/rom_names.gd").portrait(assets.decoder,assets.game_id,id)
