extends Control
## Presentation only: all combat outcomes are resolved by the engine before play().
## Original OAM frames and timing are decoded from the selected cartridge.
const Art = preload("res://runtime/art_textures.gd")

signal strike_presented(strike: Dictionary)
signal combat_finished
signal level_presented(unit_id: String, level: Dictionary)
signal reward_presented(unit_id: String, reward: Dictionary)
signal stat_upgraded(unit_id: String, stat: String, gain: int)
signal sound_requested(cue: String)
signal voice_requested(unit: Dictionary, action: String)

var manifest: Dictionary = {}
var textures: Dictionary = {}
var frame_textures: Dictionary = {}
var battle: RefCounted
var combat_playing := false
var animation_time_scale := 1.0
var generation := 0
var actors: Dictionary = {}
var profiles: Dictionary = {}
var combat_stats: Dictionary = {}
var frames: Dictionary = {}
var display_hp: Dictionary = {}
var sprite_alpha: Dictionary = {}
var left_id := ""
var right_id := ""
var active_id := ""
var feedback := ""
var flash := 0.0
var shake := 0.0
var shake_y := 0.0
var shake_strength := 1.0
var shake_elapsed := 0.0
var shake_duration := 0.0
var shake_critical := false
var backdrop: Texture2D
var backdrop_y := 0.0
const HIT_BRIGHTNESS := Color(2.0, 2.0, 2.0, 1.0)
var platform: Texture2D
var custom_platforms: Dictionary = {}
const BattleArt = preload("res://runtime/battle_art.gd")
var last_scene: Dictionary = {}
var reward_stage := ""
var rank_message := ""
var reward_unit: Dictionary = {}
var reward_exp := 0.0
var reward_level := 1
var reward_threshold := 100
var reward_stats: Dictionary = {}
var reward_gains: Dictionary = {}
var reward_portrait: Texture2D
var reward_portrait_region := Rect2()
var reward_portrait_flipped := false
var reward_portrait_custom: Dictionary = {}
var scene_scale := 1.0
var scene_origin := Vector2.ZERO
var text_commands: Array = []
var native_labels: Array[Label] = []
var text_update_pending := false
var auto_continue_rewards := false
var awaiting_reward_continue := false
var reward_continue := false
var reward_pointer := -1
var level_fanfare_duration := 1.45
var stat_reveal_delay := preload("res://ui/unit_stat_labels.gd").STAT_REVEAL_DELAY
var stat_punch_times: Dictionary = {}
var feedback_elapsed := 0.0
var feedback_duration := 0.4
var feedback_defender_id := ""
var sprite_flash: Dictionary = {}
var triangle_helpers: Array = []
var silhouette_textures: Dictionary = {}
var silhouette_sources: Dictionary = {}
var ranged_encounter := false
var hit_frames: Array = []
var hit_ticks: Array = []
var hit_elapsed := -1.0
var hit_target := ""
var hit_game := ""
var impact_centers: Dictionary = {}
var level_alpha := 1.0
var held_for_rewards := false
var level_intro_progress := 0.0
var level_intro_duration := 1.0
var level_title_time := 0.0
var damage_material: ShaderMaterial
var damage_font: FontVariation
var feedback_color_time := 0.0
var projectile: Dictionary = {}
var reroll_button: Button
var reroll_requested := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	reroll_button = Button.new()
	reroll_button.text = "Reroll (5)"
	reroll_button.hide()
	reroll_button.pressed.connect(func(): reroll_requested = true)
	add_child(reroll_button)
	# Create the text pool before any scene is drawn. Updating these synchronously
	# with the geometry avoids one-frame stale labels at scene/stage boundaries.
	_ensure_native_labels(64)
	damage_material = ShaderMaterial.new()
	damage_font = FontVariation.new()
	damage_font.base_font = ThemeDB.fallback_font
	damage_font.variation_embolden = 1.0
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float center_y = 0.0;
uniform float half_height = 1.0;
uniform float left_x = 0.0;
uniform float text_width = 1.0;
uniform bool rainbow = false;
uniform float color_time = 0.0;
vec3 hue_color(float hue) {
	vec3 channels = clamp(abs(fract(vec3(hue) + vec3(0.0, 0.666667, 0.333333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return mix(vec3(1.0), channels, 0.78);
}
void fragment() {
	vec4 base = COLOR;
	float center = 1.0 - clamp(abs(FRAGCOORD.y - center_y) / max(half_height, 1.0), 0.0, 1.0);
	vec3 ink = mix(vec3(1.0, 0.60, 0.12), vec3(1.0, 1.0, 0.84), pow(center, 0.65));
	if (rainbow) {
		float hue = (FRAGCOORD.x - left_x) / max(text_width, 1.0) * 0.75 - color_time * 0.65;
		ink = mix(hue_color(hue), vec3(1.0), center * 0.18);
	}
	// Preserve the black outline while recoloring only the pale glyph fill.
	COLOR = vec4(mix(base.rgb, ink, step(0.5, base.r)), base.a);
}"""
	damage_material.shader = shader

func _process(delta: float) -> void:
	if not visible: return
	var step := delta * maxf(0.01, animation_time_scale)
	feedback_color_time += delta
	if damage_material: damage_material.set_shader_parameter("color_time", feedback_color_time)
	if reroll_button and reroll_button.visible:
		reroll_button.position = scene_origin + Vector2(88, 135) * scene_scale
		reroll_button.size = Vector2(62, 15) * scene_scale
		reroll_button.add_theme_font_size_override("font_size", maxi(12, roundi(6 * scene_scale)))
	var active_effects := not feedback.is_empty()
	if level_title_time > 0:
		level_title_time = maxf(0, level_title_time - delta)
		active_effects = true
	if shake_duration > 0:
		advance_shake(delta)
		active_effects = true
	if not feedback.is_empty(): feedback_elapsed += step
	if hit_elapsed >= 0:
		hit_elapsed += delta
		if hit_elapsed * 60.0 >= 16.0: hit_elapsed = -1.0
		active_effects = true
	for stat in stat_punch_times.keys():
		if float(stat_punch_times[stat]) < 0.65:
			stat_punch_times[stat] = minf(0.65, float(stat_punch_times[stat]) + delta)
			active_effects = true
	for id in sprite_flash.keys():
		if float(sprite_flash[id]) > 0:
			sprite_flash[id] = maxf(0, float(sprite_flash[id]) - delta / 0.30)
			active_effects = true
	if active_effects: queue_redraw()

func popup_style(progress: float) -> Dictionary:
	var t := clampf(progress, 0, 1)
	return {"alpha":clampf(minf(t / 0.1, (1.0 - t) / 0.16), 0, 1), "scale":1.0 + sin(minf(t / 0.48, 1.0) * PI) * 0.4, "rise":t * 13.0}

func stat_punch(stat: String) -> float:
	return 1.0 + 0.4 * sin(clampf(float(stat_punch_times.get(stat, 0.4)) / 0.4, 0, 1) * PI)

func stat_glow(stat: String) -> float:
	return pow(1.0 - clampf(float(stat_punch_times.get(stat, 0.65)) / 0.65, 0, 1), 0.6)

func impact_shake_offset(elapsed: float, duration: float, critical: bool) -> Vector2:
	# Begin with a definite kick instead of a zero-crossing that disappears on
	# short/accelerated hits. The camera, sprite art and native HUD text all use
	# this same offset; its amplitude is expressed in the original 240px scene.
	var envelope := pow(1.0 - clampf(elapsed / maxf(duration, 0.01), 0, 1), 1.2)
	var amplitude := 7.0 if critical else 4.2
	return Vector2(cos(elapsed * TAU * 17.0), sin(elapsed * TAU * 13.0 + 0.65) * 0.45) * amplitude * envelope * clampf(shake_strength, 0, 2)

func start_shake(critical: bool) -> void:
	shake_elapsed = 0.0
	shake_duration = 0.45 if critical else 0.28
	shake_critical = critical
	advance_shake(0.0)

func advance_shake(delta: float) -> void:
	# A real-time camera clock is independent of sprite/strike playback speed.
	shake_elapsed += maxf(0, delta)
	var offset := impact_shake_offset(shake_elapsed, shake_duration, shake_critical)
	shake = offset.x
	shake_y = offset.y
	if shake_elapsed >= shake_duration:
		shake_duration = 0.0
		shake = 0.0
		shake_y = 0.0

func _fade(target: float, seconds: float, token: int, level_only: bool = false) -> bool:
	var from := level_alpha if level_only else modulate.a
	var elapsed := 0.0
	var started := Time.get_ticks_usec()
	while elapsed < seconds:
		if token != generation or not is_inside_tree(): return false
		elapsed = (Time.get_ticks_usec() - started) / 1000000.0
		var amount := smoothstep(0, 1, clampf(elapsed / seconds, 0, 1))
		if level_only: level_alpha = lerpf(from, target, amount)
		else: modulate.a = lerpf(from, target, amount)
		queue_redraw()
		await get_tree().process_frame
	return token == generation

func configure(path: String = "res://content/fe7/battle/manifest.json") -> bool:
	cancel()
	manifest.clear()
	hit_frames.clear(); hit_ticks.clear(); hit_game = ""
	textures.clear()
	silhouette_textures.clear()
	silhouette_sources.clear()
	impact_centers.clear()
	backdrop = null
	platform = null
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("animations", null) is Dictionary:
		return false
	manifest = parsed
	backdrop = _texture(str(manifest.get("background", "")))
	platform = _texture(str(manifest.get("platform", "")))
	return not manifest.animations.is_empty()

func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if not textures.has(path):
		textures[path] = Art.texture(path)
	return textures[path]

func refresh_art() -> void:
	# Settings can change image categories while a completed scene is retained.
	# Replace textures without touching its actors, frames, rewards or generation.
	textures.clear()
	frame_textures.clear()
	silhouette_textures.clear()
	silhouette_sources.clear()
	impact_centers.clear()
	backdrop = _texture(str(manifest.get("background", "")))
	platform = _texture(str(manifest.get("platform", "")))
	_select_battle_art()
	_load_reward_portrait()
	queue_redraw()

func _select_battle_art() -> void:
	if not manifest.get("supported",true):
		hit_frames.clear(); hit_ticks.clear(); custom_platforms.clear()
		backdrop = null; platform = null
		return
	var assets = preload("res://runtime/rom_assets.gd")
	var game: String = assets.game_id
	if assets.decoder != null and (hit_frames.is_empty() or hit_game != game):
		hit_game = game
		hit_frames.clear()
		var effect := preload("res://runtime/rom_hit_effect.gd").read(assets.decoder, game)
		hit_ticks = effect.get("ticks", [])
		for frame in effect.get("frames", []): hit_frames.append(ImageTexture.create_from_image(frame))
	custom_platforms.clear()
	var unit: Dictionary = actors.get(left_id, actors.get(right_id, {}))
	var state = battle
	if state == null and last_scene.get("battle") is WeakRef: state = last_scene.battle.get_ref()
	var custom := BattleArt.texture("background", state, unit)
	var family := BattleArt.family(state, unit)
	var art_root := str(manifest.get("background", "res://content/fe7/battle/plains.png")).get_base_dir() + "/"
	var native := BattleArt.native_terrain(state,unit)
	var original_bg := str(native.get("background",art_root + family + ".png"))
	backdrop = custom if custom else _texture(original_bg if ResourceLoader.exists(original_bg) else str(manifest.get("background", "")))
	backdrop_y = BattleArt.background_y(state, unit) if custom else 0.0
	platform = null if family == "arena" else _texture(str(manifest.get("platform", "")))
	for id in actors:
		var ground := BattleArt.platform(state, actors[id])
		if ground: custom_platforms[id] = ground
		else:
			var original_ground := str(BattleArt.native_terrain(state,actors[id]).get("platform",art_root + "platform_" + BattleArt.family(state, actors[id]) + ".png"))
			if not ResourceLoader.exists(original_ground) and BattleArt.family(state, actors[id]) != "arena": original_ground = str(manifest.get("platform", ""))
			if ResourceLoader.exists(original_ground):
				var region := AtlasTexture.new()
				region.atlas = _texture(original_ground)
				region.region = Rect2(120, 88, 88, 40)
				custom_platforms[id] = region

func _load_reward_portrait() -> void:
	reward_portrait_flipped = false
	reward_portrait_custom = {}
	var path := str(reward_unit.get("portrait", ""))
	reward_portrait = _texture(path)
	var original := Art.original_image(path) if not path.is_empty() else null
	reward_portrait_region = Rect2(original.get_used_rect()) if original else Rect2()
	var context := reward_unit.duplicate(true)
	context.portrait_id = path.get_file().get_basename().to_int()
	for store in [preload("res://runtime/custom_portraits.gd").store]:
		var entry: Dictionary = store.find_portrait(str(reward_unit.get("name", "")), context)
		if entry.is_empty(): continue
		var custom: Texture2D = store.texture(entry)
		if custom:
			reward_portrait = custom
			reward_portrait_custom = entry
			reward_portrait_flipped = bool(entry.get("flip_h", false))
			reward_portrait_region = Rect2(Vector2.ZERO, custom.get_size())
			break

func profile_for(unit: Dictionary) -> Dictionary:
	if manifest.get("game_id", "fe7") == "fe7" and int(unit.get("weapon", {}).get("rom_item_id", 0)) in [52, 53, 54]:
		var ballista_id := int(unit.weapon.rom_item_id)
		var named: Dictionary = manifest.get("animations", {}).get("ballista_" + str(unit.get("faction", "enemy")) + ("_%d" % ballista_id if ballista_id != 52 else ""), {})
		if not named.is_empty(): return named
		# Dynamic profiles retain the native class/item mapping below.
	var class_id := int(unit.get("rom_class_id", 0))
	var character_id := int(unit.get("rom_character_id", 0))
	var weapon: String = str(unit.get("weapon", {}).get("type", "sword"))
	if unit.get("weapon", {}).is_empty() and unit.get("can_use_staves", false): weapon = "staff"
	if unit.get("weapon", {}).is_empty():
		for value in manifest.get("animations", {}).values():
			if int(value.class_id) == class_id and str(value.weapon) == "unarmed":
				weapon = "unarmed"
				break
	var item_id := int(unit.get("weapon", {}).get("rom_item_id", 0))
	var fallback: Dictionary = {}
	var best_score := -1
	for value in manifest.get("animations", {}).values():
		if int(value.class_id) != class_id or str(value.weapon) != weapon:
			continue
		var item_ids: Array = value.get("item_ids", [])
		if not item_ids.is_empty() and not item_ids.any(func(id): return int(id) == item_id): continue
		var score := 8 if not item_ids.is_empty() else 0
		for candidate in value.characters:
			if character_id > 0 and character_id == int(candidate):
				score += 4
		if str(value.get("faction", "")) == str(unit.get("faction", "player")): score += 2
		if value.characters.is_empty(): score += 1
		if score > best_score:
			fallback = value
			best_score = score
	return fallback

func can_present(state: RefCounted, strikes: Array) -> bool:
	if manifest.is_empty() or strikes.is_empty():
		return false
	for strike in strikes:
		for key in ["attacker_id", "defender_id"]:
			var unit: Dictionary = state.get_unit(str(strike.get(key, ""))).duplicate(true)
			if strike.has(key.replace("_id", "_weapon")): unit.weapon = strike[key.replace("_id", "_weapon")]
			var profile := profile_for(unit)
			if profile.is_empty():
				return false
			for path in profile.get("atlas", {}).values():
				if not ResourceLoader.exists(str(path)):
					return false
	return true

func prepare_arena(state: RefCounted, manifest_path: String) -> bool:
	# A random arena class may not appear in any chapter loaded so far. Prepare
	# and decode both fighters before the wager or the first damaging strike.
	var assets = preload("res://runtime/rom_assets.gd")
	if not assets.prepare_battle_art(state.units) or not configure(manifest_path): return false
	var preview := [{"attacker_id":state.units[0].id,"defender_id":state.units[1].id}]
	if not can_present(state,preview):
		if assets.diagnostic_sink.is_valid(): assets.diagnostic_sink.call("arena_animation_missing",{"rom_sha256":assets.rom_digest,"fighters":state.units.map(func(u):return {"class":u.rom_class_id,"weapon":u.weapon.get("rom_item_id",0)})})
		return false
	for unit in state.units:
		for path in profile_for(unit).get("atlas",{}).values():
			if _texture(str(path)) == null: return false
	return true

func cancel() -> void:
	hit_elapsed = -1.0
	custom_platforms.clear()
	if reroll_button: reroll_button.hide()
	rank_message = ""
	frame_textures.clear()
	generation += 1
	combat_playing = false
	visible = false
	modulate.a = 1.0
	level_alpha = 1.0
	held_for_rewards = false
	level_intro_progress = 0.0
	battle = null
	actors.clear()
	profiles.clear()
	combat_stats.clear()
	frames.clear()
	display_hp.clear()
	sprite_alpha.clear()
	sprite_flash.clear()
	triangle_helpers.clear()
	left_id = ""
	right_id = ""
	active_id = ""
	feedback = ""
	feedback_defender_id = ""
	feedback_elapsed = 0.0
	projectile.clear()
	flash = 0
	shake = 0
	shake_y = 0
	shake_duration = 0
	last_scene.clear()
	reward_stage = ""
	reward_unit.clear()
	reward_stats.clear()
	reward_gains.clear()
	stat_punch_times.clear()
	reward_portrait = null
	reward_portrait_region = Rect2()
	awaiting_reward_continue = false
	reward_continue = false
	reward_pointer = -1
	text_commands.clear()
	for label in native_labels: label.hide()
	queue_redraw()

func _exit_tree() -> void:
	cancel()
	textures.clear()
	silhouette_textures.clear()
	silhouette_sources.clear()
	impact_centers.clear()
	backdrop = null
	platform = null

func play(state: RefCounted, strikes: Array, hold_for_rewards: bool = false, continuing: bool = false) -> void:
	cancel()
	# Keep only the current encounter's large atlas references. The art service
	# also bounds its resident cache, but a local reference would bypass that.
	if not continuing:
		textures.clear()
		silhouette_textures.clear()
		silhouette_sources.clear()
	if not can_present(state, strikes):
		return
	var token := generation
	battle = state
	combat_playing = true
	for strike in strikes:
		for key in ["attacker_id", "defender_id"]:
			var id := str(strike[key])
			actors[id] = state.get_unit(id).duplicate(true)
			var cell: Array = strike.get(key.replace("_id", "_cell"), [])
			if cell.size() == 2: actors[id].x = int(cell[0]); actors[id].y = int(cell[1])
			if strike.has(key.replace("_id", "_weapon")): actors[id].weapon = strike[key.replace("_id", "_weapon")]
			profiles[id] = profile_for(actors[id])
			frames[id] = _first_frame(profiles[id], "idle")
			display_hp[id] = float(actors[id].hp)
			sprite_alpha[id] = 1.0
	# Reverse resolved results to reconstruct the HP before the first shown hit.
	for index in range(strikes.size() - 1, -1, -1):
		var strike: Dictionary = strikes[index]
		display_hp[str(strike.get("damage_target_id", strike.defender_id))] = float(strike.get("previous_hp", int(strike.remaining_hp) + int(strike.get("damage", 0))))
		if strike.has("attacker_previous_hp"): display_hp[str(strike.attacker_id)] = float(strike.attacker_previous_hp)
	modulate.a = 1.0 if continuing else 0.05
	visible = true
	_set_pair(str(strikes[0].attacker_id), str(strikes[0].defender_id))
	ranged_encounter = state._distance(state.position(actors[left_id]), state.position(actors[right_id])) > 1
	_select_battle_art()
	combat_stats[left_id] = strikes[0].get("attacker_stats" if left_id == str(strikes[0].attacker_id) else "defender_stats", {}).duplicate(true)
	combat_stats[right_id] = strikes[0].get("attacker_stats" if right_id == str(strikes[0].attacker_id) else "defender_stats", {}).duplicate(true)
	if not continuing and not await _fade(1.0, 0.14, token): return
	for strike in strikes:
		if token != generation:
			return
		var attacker_id := str(strike.attacker_id)
		var defender_id := str(strike.defender_id)
		_set_pair(attacker_id, defender_id)
		combat_stats[attacker_id] = strike.get("attacker_stats", {}).duplicate(true)
		combat_stats[defender_id] = strike.get("defender_stats", {}).duplicate(true)
		active_id = attacker_id
		feedback = ""
		queue_redraw()
		if not await _wait(0.18, token):
			return
		var mode := strike_mode(state, actors[attacker_id], actors[defender_id], bool(strike.get("critical", false)))
		var ranged := mode.begins_with("ranged")
		if strike.get("triangle_attack", false):
			for id in strike.get("triangle_members", []):
				if id == attacker_id: continue
				var helper: Dictionary = state.get_unit(str(id))
				var profile := profile_for(helper)
				if profile.is_empty(): continue
				actors[id] = helper.duplicate(true); profiles[id] = profile
				frames[id] = _first_frame(profile, "idle"); sprite_alpha[id] = 1.0
				triangle_helpers.append(id)
			feedback = "TRIANGLE ATTACK!"; feedback_defender_id = defender_id; feedback_elapsed = 0; feedback_duration = 0.55
			queue_redraw()
			if not await _wait(0.55, token, false): return
		voice_requested.emit(actors[attacker_id], "crit" if strike.get("critical", false) else "attack")
		if not await _attack_sequence(attacker_id, mode, strike, ranged, token):
			return
		triangle_helpers.clear()
		frames[attacker_id] = _first_frame(profiles[attacker_id], "idle")
		feedback = ""
		if not await _wait(0.18, token):
			return
	if token != generation:
		return
	var rank_changes: Dictionary = {}
	for strike in strikes:
		var gained: Dictionary = strike.get("weapon_experience", {})
		if gained.is_empty() or state.get_unit(str(gained.unit_id)).get("faction", "") != "player": continue
		var key := str(gained.unit_id) + ":" + str(gained.type)
		if not rank_changes.has(key): rank_changes[key] = gained.duplicate(true)
		rank_changes[key].total = gained.total
	for gained in rank_changes.values():
		var before := _rank_name(int(gained.previous))
		var after := _rank_name(int(gained.total))
		if before == after: continue
		rank_message = "%s Rank %s → %s !" % [str(gained.type).capitalize(), before, after]
		queue_redraw()
		sound_requested.emit("stat_up")
		if not await _wait(1.1, token, false): return
	rank_message = ""
	if not hold_for_rewards and not await _fade(0.0, 0.14, token): return
	combat_playing = false
	held_for_rewards = hold_for_rewards
	visible = hold_for_rewards
	last_scene = {"battle": weakref(state), "actors": actors.duplicate(true), "profiles": profiles.duplicate(true), "stats": combat_stats.duplicate(true), "frames": frames.duplicate(), "hp": display_hp.duplicate(), "alpha": sprite_alpha.duplicate(), "left": left_id, "right": right_id}
	battle = null
	combat_finished.emit()
	if token != generation:
		return
	if hold_for_rewards: return
	actors.clear()
	profiles.clear()
	combat_stats.clear()
	frames.clear()
	display_hp.clear()
	sprite_alpha.clear()

static func strike_mode(state: RefCounted, actor: Dictionary, target: Dictionary, critical: bool = false) -> String:
	var distance := absi(int(actor.x) - int(target.x)) + absi(int(actor.y) - int(target.y))
	var weapon_range: Vector2i = state.item_range(actor, actor.get("weapon", {}))
	var ranged := distance > 1
	if state.Rogue.count(actor, "omni_counter") > 0 and (distance < weapon_range.x or distance > weapon_range.y): ranged = false
	return ("ranged_critical" if ranged else "critical") if critical else ("ranged" if ranged else "attack")

func play_assist(state: RefCounted, actor_id: String, target_id: String, item: Dictionary, result: Dictionary) -> void:
	cancel()
	if actor_id == target_id or item.get("staff_effect", "") in ["unlock", "torch"]: return
	var actor: Dictionary = state.get_unit(actor_id).duplicate(true)
	var target: Dictionary = state.get_unit(target_id).duplicate(true)
	if actor.is_empty() or target.is_empty(): return
	actor.weapon = item.duplicate(true) if not item.is_empty() else {"type": "unarmed", "name": "Dance" if actor.get("class_name", "") == "Dancer" else "Play"}
	for unit in [target, actor]:
		var id := str(unit.id)
		actors[id] = unit
		var profile := profile_for(unit)
		if profile.is_empty():
			for candidate in manifest.get("animations", {}).values():
				if int(candidate.get("class_id", -1)) == int(unit.get("rom_class_id", -2)) and candidate.get("faction", "") == "player": profile = candidate; break
		if profile.is_empty(): cancel(); return
		profiles[id] = profile
		frames[id] = _first_frame(profile, "idle")
		display_hp[id] = float(unit.hp)
		sprite_alpha[id] = 1.0
	var token := generation
	battle = state
	right_id = actor_id
	left_id = target_id if target_id != actor_id else ""
	_select_battle_art()
	combat_playing = true
	display_hp[target_id] = float(target.hp) - int(result.get("healed", 0))
	show()
	modulate.a = 0.0
	if not await _fade(1.0, 0.14, token): return
	var timeline: Array = profiles[actor_id].get("modes", {}).get("attack", [])
	for entry in timeline:
		if entry.has("frame"):
			frames[actor_id] = int(entry.frame)
			if not await _wait(clampf(float(entry.get("ticks", 1)) / 60.0, 0.016, 0.15), token): return
	feedback = "Miss" if result.has("status_hit") and not result.status_hit else "+%d" % int(result.healed) if int(result.get("healed", 0)) > 0 else "Refresh" if item.is_empty() else str(item.get("name", "Staff"))
	feedback_defender_id = target_id
	feedback_elapsed = 0.0
	feedback_duration = 0.65
	var initial_hp := float(display_hp[target_id])
	sound_requested.emit("miss" if result.has("status_hit") and not result.status_hit else "heal")
	var heal_started := Time.get_ticks_usec()
	while token == generation:
		var progress := minf(1.0, (Time.get_ticks_usec() - heal_started) / 450000.0)
		display_hp[target_id] = lerpf(initial_hp, float(target.hp), progress)
		queue_redraw()
		if progress >= 1.0: break
		await get_tree().process_frame
	if token != generation: return
	queue_redraw()
	if not await _wait(0.65, token, false): return
	if not result.get("experience", []).is_empty():
		feedback = ""
		frames[actor_id] = _first_frame(profiles[actor_id], "idle")
		combat_playing = false
		held_for_rewards = true
		last_scene = {"battle": weakref(state), "actors": actors.duplicate(true), "profiles": profiles.duplicate(true), "stats": combat_stats.duplicate(true), "frames": frames.duplicate(), "hp": display_hp.duplicate(), "alpha": sprite_alpha.duplicate(), "left": left_id, "right": right_id}
		battle = null
		queue_redraw()
		combat_finished.emit()
		return
	if not await _fade(0.0, 0.14, token): return
	cancel()

func _rank_name(points: int) -> String:
	var rank_name := "—"
	var thresholds: Dictionary = battle.rules.weapon_rank_thresholds if battle != null else ({"E":1,"D":51,"C":101,"B":151,"A":201,"S":251} if manifest.get("game_id") == "fe6" else {"E":1,"D":31,"C":71,"B":121,"A":181,"S":251})
	for rank in ["E","D","C","B","A","S"]:
		if points >= int(thresholds[rank]): rank_name = rank
	return rank_name

func play_rewards(state: RefCounted, rewards: Array, with_battle_scene: bool = false) -> void:
	var previous_scene := last_scene.duplicate(true)
	var continuing: bool = held_for_rewards and visible and with_battle_scene and previous_scene.get("battle") is WeakRef and previous_scene.battle.get_ref() == state
	if continuing:
		generation += 1
		held_for_rewards = false
		feedback = ""
		sprite_flash.clear()
		flash = 0
		shake = 0
		shake_y = 0
		shake_duration = 0
	else: cancel()
	var token := generation
	if rewards.is_empty():
		if continuing and not await _fade(0.0, 0.14, token): return
		cancel()
		return
	if with_battle_scene and previous_scene.get("battle") is WeakRef and previous_scene.battle.get_ref() == state:
		actors = previous_scene.actors
		profiles = previous_scene.profiles
		combat_stats = previous_scene.stats
		frames = previous_scene.frames
		display_hp = previous_scene.hp
		sprite_alpha = previous_scene.alpha
		left_id = previous_scene.left
		right_id = previous_scene.right
	battle = state
	combat_playing = true
	_select_battle_art()
	for reward in rewards:
		if token != generation: return
		if int(reward.get("amount", 0)) <= 0: continue
		reward_unit = state.get_unit(str(reward.get("unit_id", ""))).duplicate(true)
		if reward_unit.is_empty(): continue
		reward_threshold = maxi(1, int(reward.get("threshold", 100)))
		reward_level = int(reward.get("before_level", int(reward_unit.get("level", 1)) - reward.get("levels", []).size()))
		reward_exp = clampf(float(reward.get("before_exp", 0)), 0, reward_threshold)
		_load_reward_portrait()
		reward_stage = "exp"
		if not visible:
			modulate.a = 0.0
			visible = true
			if not await _fade(1.0, 0.14, token): return
		var remaining := int(reward.get("amount", 0))
		var level_index := 0
		while remaining > 0:
			var portion := mini(remaining, reward_threshold - int(reward_exp))
			if portion <= 0: break
			if not await _animate_experience(reward_exp + portion, clampf(portion * 0.016, 0.3, 1.3), token): return
			remaining -= portion
			if reward_exp >= reward_threshold:
				var levels: Array = reward.get("levels", [])
				if level_index < levels.size():
					if not await _show_level(levels[level_index], token): return
					level_index += 1
				reward_exp = 0
				reward_stage = "exp"
		if token != generation: return
		reward_exp = float(reward.get("after_exp", reward_unit.get("exp", reward_exp)))
		reward_level = int(reward.get("after_level", reward_unit.get("level", reward_level)))
		if not await _wait(0.45, token, false): return
		reward_presented.emit(str(reward_unit.id), reward)
		if token != generation: return
	if token == generation:
		if not await _fade(0.0, 0.14, token): return
		cancel()

func _animate_experience(target: float, duration: float, token: int) -> bool:
	var from := reward_exp
	var elapsed := 0.0
	var started := Time.get_ticks_usec()
	while elapsed < duration:
		if skip_combat_animations and reward_stage.is_empty(): break
		if token != generation or not is_inside_tree(): return false
		elapsed = (Time.get_ticks_usec() - started) / 1000000.0
		reward_exp = lerpf(from, target, clampf(elapsed / duration, 0, 1))
		queue_redraw()
		await get_tree().process_frame
	if token != generation: return false
	reward_exp = target
	return true

func _show_level(level: Dictionary, token: int) -> bool:
	reward_stage = "level_intro"
	level_intro_progress = 0.0
	level_alpha = 0.0
	reward_level = int(level.get("level", reward_level + 1))
	reward_stats = level.get("before_stats", {}).duplicate(true)
	reward_gains.clear()
	stat_punch_times.clear()
	level_presented.emit(str(reward_unit.id), level)
	var elapsed := 0.0
	var started := Time.get_ticks_usec()
	while elapsed < level_intro_duration:
		if token != generation or not is_inside_tree(): return false
		elapsed = (Time.get_ticks_usec() - started) / 1000000.0
		level_intro_progress = clampf(elapsed / level_intro_duration, 0, 1)
		queue_redraw()
		await get_tree().process_frame
	if token != generation: return false
	reward_stage = "level"
	level_title_time = 2.4
	if token != generation or not await _fade(1.0, 0.14, token, true): return false
	if not await _wait(maxf(0, level_fanfare_duration - level_intro_duration - 0.14), token, false): return false
	for stat in preload("res://ui/unit_stat_labels.gd").level_keys(reward_unit):
		if token != generation: return false
		var gain := int(level.get("gains", {}).get(stat, 0))
		reward_stats[stat] = int(level.get("after_stats", {}).get(stat, int(reward_stats.get(stat, reward_unit.get(stat, 0))) + gain))
		if gain > 0:
			reward_gains[stat] = gain
			stat_punch_times[stat] = 0.0
			stat_upgraded.emit(str(reward_unit.id), stat, gain)
			if token != generation or not await _wait(stat_reveal_delay, token, false): return false
	if auto_continue_rewards:
		if not await _wait(0.35, token, false): return false
		return await _fade(0.0, 0.14, token, true)
	awaiting_reward_continue = true
	reroll_requested = false
	var rogue = preload("res://engine/rogue_mode.gd")
	if battle and rogue.active(battle) and reward_unit.get("faction", "") == "player":
		reroll_button.text = "Reroll (%d)" % int(battle.chapter.rogue.get("training", 0))
		reroll_button.visible = int(battle.chapter.rogue.get("training", 0)) > 0
	reward_continue = false
	reward_pointer = -1
	queue_redraw()
	while not reward_continue:
		if token != generation or not is_inside_tree(): return false
		if reroll_requested:
			reroll_requested = false
			var unit: Dictionary = battle.get_unit(str(reward_unit.id))
			unit.rogue_last_level = level.get("gains", {}).duplicate(true)
			if rogue.reroll_level(battle, unit):
				level.gains = unit.rogue_last_level.duplicate(true)
				for stat in level.before_stats: level.after_stats[stat] = int(level.before_stats[stat]) + int(level.gains.get(stat, 0))
				reward_unit = unit.duplicate(true)
				reroll_button.hide()
				awaiting_reward_continue = false
				return await _show_level(level, token)
		await get_tree().process_frame
	reroll_button.hide()
	awaiting_reward_continue = false
	reward_pointer = -1
	return await _fade(0.0, 0.14, token, true)

func _gui_input(event: InputEvent) -> void:
	# Finish the full gesture on this overlay before returning to the map.
	# Early taps while stats are revealing are consumed, never queued.
	if event is InputEventScreenTouch:
		if awaiting_reward_continue:
			if event.pressed and reward_pointer == -1: reward_pointer = event.index
			elif not event.pressed and reward_pointer == event.index:
				reward_continue = not event.canceled
				reward_pointer = -1
		accept_event()
	elif event is InputEventMouseButton:
		if event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT and awaiting_reward_continue:
			if event.pressed: reward_pointer = -2
			elif reward_pointer == -2:
				reward_continue = true
				reward_pointer = -1
		accept_event()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		accept_event()

func _set_pair(attacker_id: String, defender_id: String) -> void:
	if str(actors[attacker_id].faction) != "enemy":
		right_id = attacker_id
		left_id = defender_id
	else:
		left_id = attacker_id
		right_id = defender_id

func _first_frame(profile: Dictionary, mode: String) -> int:
	for entry in profile.get("modes", {}).get(mode, []):
		if entry.has("frame"):
			return int(entry.frame)
	return 0

func _attack_sequence(id: String, mode: String, strike: Dictionary, ranged: bool, token: int) -> bool:
	var impacted := false
	var clock := {"remaining":0.0,"previous":Time.get_ticks_usec()}
	var entries: Array = profiles[id].modes.get(mode, [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		if token != generation:
			return false
		if entry.has("frame"):
			frames[id] = int(entry.frame)
			if not await _wait_frame(clampf(float(entry.ticks) / 60.0, 1.0 / 60.0, 3.0), token, clock):
				return false
		elif (int(entry.get("command", 0)) & 255) == 0x13 and not impacted and not profiles[id].get("item_ids", []).is_empty():
			# The original throwing poses dispatch the separate hardcoded weapon
			# effect here. Use the extracted weapon icon for a short flight/return
			# while keeping the ROM release and recovery poses around it.
			for next in entries.slice(index + 1):
				if next.has("frame"):
					frames[id] = int(next.frame)
					break
			if not await _axe_flight(id, str(strike.defender_id), false, token): return false
			impacted = true
			if not await _impact(strike, ranged, token): return false
			if not await _axe_flight(id, str(strike.defender_id), true, token): return false
			clock = {"remaining":0.0,"previous":Time.get_ticks_usec()}
		elif (int(entry.get("command", 0)) & 255) == 1 and not impacted:
			impacted = true
			var tail := 0.0
			for next in entries.slice(index + 1):
				if next.has("frame"): tail += clampf(float(next.ticks) / 60.0, 1.0 / 60.0, 3.0)
			if not await _impact(strike, ranged, token, tail):
				return false
			clock = {"remaining":0.0,"previous":Time.get_ticks_usec()}
	if not impacted:
		return await _impact(strike, ranged, token)
	return token == generation

func _wait_frame(seconds: float, token: int, clock: Dictionary) -> bool:
	# Carry render-frame overshoot into the next ROM frame. At ×3, several
	# one-tick poses can advance in one rendered frame instead of each waiting
	# a full frame (or two). Impact pauses start a fresh timeline segment.
	clock.remaining += seconds
	while true:
		if token != generation or not is_inside_tree(): return false
		if skip_combat_animations: return true
		var now := Time.get_ticks_usec()
		clock.remaining -= (now-int(clock.previous))/1000000.0 * maxf(0.01,animation_time_scale)
		clock.previous = now
		queue_redraw()
		if clock.remaining <= 0.0: return true
		await get_tree().process_frame
	return false

func _axe_flight(attacker_id: String, defender_id: String, returning: bool, token: int) -> bool:
	var icon := _texture(str(actors[attacker_id].get("weapon", {}).get("icon", "")))
	if icon == null: return token == generation
	var start := Vector2(_anchor_x(attacker_id == right_id), 60)
	var finish := Vector2(_anchor_x(defender_id == right_id), 60)
	if returning:
		var swap := start
		start = finish
		finish = swap
	var duration := 0.24
	var elapsed := 0.0
	while elapsed < duration:
		if skip_combat_animations and reward_stage.is_empty(): break
		if token != generation or not is_inside_tree(): return false
		var amount := clampf(elapsed / duration, 0, 1)
		projectile = {"texture":icon, "position":start.lerp(finish, amount) - Vector2(0, sin(amount * PI) * 7), "angle":amount * TAU * 2.0 * signf(finish.x - start.x)}
		queue_redraw()
		await get_tree().process_frame
		elapsed += get_process_delta_time() * maxf(0.01, animation_time_scale)
	projectile.clear()
	queue_redraw()
	return token == generation

func _impact(strike: Dictionary, ranged: bool, token: int, tail_duration: float = 0.0) -> bool:
	if token != generation:
		return false
	var defender_id := str(strike.get("damage_target_id", strike.defender_id))
	var hit := bool(strike.get("hit", false))
	var critical := bool(strike.get("critical", false))
	feedback_defender_id = defender_id
	sprite_flash[defender_id] = 1.0 if hit and int(strike.get("damage", 0)) > 0 else 0.0
	if hit and int(strike.get("damage", 0)) > 0:
		hit_elapsed = 0.0
		hit_target = defender_id
		start_shake(critical)
		voice_requested.emit(actors[defender_id], "damage")
	feedback = ("CRITICAL!" if critical else str(strike.get("damage", 0))) if hit else "MISS!"
	if strike.get("silencer", false): feedback = "SILENCER!"
	elif strike.get("backfire", false): feedback = "BACKFIRE!"
	elif strike.get("triangle_attack", false): feedback = "TRIANGLE ATTACK!"
	feedback_elapsed = 0.0
	feedback_duration = tail_duration + 0.12
	if hit:
		feedback_duration += (0.45 if critical else 0.28) + (0.35 if int(strike.remaining_hp) <= 0 else 0.0)
	else:
		for entry in profiles[defender_id].modes.get("ranged_dodge" if ranged else "dodge", []):
			if entry.has("frame"): feedback_duration += minf(float(entry.ticks) / 60.0, 0.15)
	strike_presented.emit(strike)
	# A signal handler may replace the battle or dismiss this presenter.
	if token != generation:
		return false
	if not hit:
		var dodge: Array = profiles[defender_id].modes.get("ranged_dodge" if ranged else "dodge", [])
		for entry in dodge:
			if entry.has("frame"):
				frames[defender_id] = int(entry.frame)
				if not await _wait(minf(float(entry.ticks) / 60.0, 0.15), token):
					return false
	else:
		var initial := float(display_hp[defender_id])
		var duration := 0.45 if critical else 0.28
		var elapsed := 0.0
		# Present the initial kick before consuming delta. A cold texture upload
		# or fast animation setting can otherwise advance the entire effect in
		# its first frame, making the camera appear perfectly still.
		queue_redraw()
		await get_tree().process_frame
		while elapsed < duration:
			if skip_combat_animations: break
			if token != generation or not is_inside_tree():
				return false
			elapsed += minf(get_process_delta_time() * maxf(0.01, animation_time_scale), duration / 8.0)
			var amount := clampf(elapsed / duration, 0, 1)
			display_hp[defender_id] = lerpf(initial, float(strike.remaining_hp), amount)
			if int(strike.get("healed", 0)) > 0: display_hp[str(strike.attacker_id)] = lerpf(float(strike.attacker_previous_hp), float(strike.attacker_remaining_hp), amount)
			flash = (1.0 - amount) * (0.65 if critical else 0.22)
			queue_redraw()
			await get_tree().process_frame
		if token != generation:
			return false
		display_hp[defender_id] = float(strike.remaining_hp)
		flash = 0
		if int(strike.remaining_hp) <= 0:
			voice_requested.emit(actors[defender_id], "defeat")
			var elapsed_fade := 0.0
			while elapsed_fade < 0.35:
				if skip_combat_animations: break
				if token != generation or not is_inside_tree():
					return false
				elapsed_fade += get_process_delta_time() * maxf(0.01, animation_time_scale)
				sprite_alpha[defender_id] = 1.0 - clampf(elapsed_fade / 0.35, 0, 1)
				queue_redraw()
				await get_tree().process_frame
	if token != generation:
		return false
	frames[defender_id] = _first_frame(profiles[defender_id], "idle")
	# Let the native sparks finish on their own real-time clock, even when
	# the attack and HP animation finish sooner at an accelerated speed.
	while hit_elapsed >= 0 and not skip_combat_animations:
		if token != generation or not is_inside_tree(): return false
		await get_tree().process_frame
	return await _wait(0.12, token)

var skip_combat_animations := false

func _anchor_x(right: bool) -> float:
	return (180.0 if right else 60.0) if ranged_encounter else (152.0 if right else 88.0)

func _wait(seconds: float, token: int, attack_clock: bool = true) -> bool:
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	while elapsed < seconds:
		if skip_combat_animations and reward_stage.is_empty(): return token == generation
		if token != generation or not is_inside_tree():
			return false
		var current := Time.get_ticks_usec()
		elapsed += (current - previous) / 1000000.0 * (maxf(0.01, animation_time_scale) if attack_clock else 1.0)
		previous = current
		if elapsed >= seconds: break
		queue_redraw()
		await get_tree().process_frame
	return token == generation

func _panel(rect: Rect2, tint: Color, opacity: float = 1.0) -> void:
	draw_rect(rect, Color(Color("211b18"), opacity))
	draw_rect(rect.grow(-1), Color(Color("e2cc91"), opacity))
	var inner := rect.grow(-2)
	var top := tint.lightened(0.28)
	var bottom := tint.darkened(0.45)
	top.a *= opacity
	bottom.a *= opacity
	draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x,inner.position.y), inner.end, Vector2(inner.position.x,inner.end.y)]), PackedColorArray([top,top,bottom,bottom]))
	draw_line(inner.position, inner.position + Vector2(inner.size.x, 0), Color(tint.lightened(0.6), opacity), 0.5)

func _text(at: Vector2, text: String, font_size: int = 8, color: Color = Color("fff6d1"), punch: float = 1.0, glow: float = 0.0, damage: bool = false, max_width: float = 0) -> void:
	# Text is rasterized at viewport resolution by unscaled child Labels. Only
	# ROM art and panel geometry use the 240x160 scene transform.
	text_commands.append({"at": scene_origin + at * scene_scale, "text": text, "font_size": maxi(12, roundi(font_size * scene_scale)), "color": color, "scale":punch, "glow":glow, "damage":damage, "max_width":max_width * scene_scale})

func _ensure_native_labels(count: int) -> void:
	while native_labels.size() < count:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		label.add_theme_color_override("font_shadow_color", Color("29211b"))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(label)
		native_labels.append(label)
		label.hide()

func _apply_native_text() -> void:
	text_update_pending = false
	if not is_inside_tree(): return
	_ensure_native_labels(text_commands.size())
	for i in range(native_labels.size()):
		var label := native_labels[i]
		label.visible = i < text_commands.size() and visible
		if not label.visible: continue
		var command: Dictionary = text_commands[i]
		var damage: bool = command.get("damage", false)
		if damage: label.add_theme_font_override("font", damage_font)
		else: label.remove_theme_font_override("font")
		label.text = command.text
		label.add_theme_font_size_override("font_size", int(command.font_size))
		label.add_theme_color_override("font_color", Color(command.color, 1.0))
		label.add_theme_color_override("font_outline_color", Color.BLACK if damage else Color(1.0, 0.72, 0.12, float(command.get("glow", 0.0)) * 0.85))
		label.add_theme_constant_override("outline_size", maxi(1, roundi(scene_scale * 0.3)) if damage else maxi(2, roundi(scene_scale)))
		label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT if damage else Color("29211b"))
		label.material = damage_material if damage else null
		label.modulate.a = command.color.a
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if float(command.get("max_width", 0)) > 0 else TextServer.OVERRUN_NO_TRIMMING
		label.reset_size()
		if float(command.get("max_width", 0)) > 0: label.size.x = float(command.max_width)
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE * float(command.get("scale", 1.0))
		label.position = Vector2(command.at) - (label.size * 0.5 if command.get("centered", false) else Vector2(0, label.get_theme_font("font").get_ascent(int(command.font_size))))
		if damage:
			var rect := label.get_global_rect()
			damage_material.set_shader_parameter("center_y", rect.get_center().y)
			damage_material.set_shader_parameter("half_height", rect.size.y * 0.5)
			damage_material.set_shader_parameter("left_x", rect.position.x)
			damage_material.set_shader_parameter("text_width", rect.size.x)
			damage_material.set_shader_parameter("rainbow", str(command.text).begins_with("CRITICAL") or str(command.text) == "LEVEL UP!")

func _draw_actor(id: String, side: String, anchor_override: Vector2 = Vector2.INF, actor_scale: float = 1.0) -> void:
	if not profiles.has(id):
		return
	var profile: Dictionary = profiles[id]
	var frame := int(frames.get(id, 0))
	var frame_size := Vector2(float(profile.frame_size[0]), float(profile.frame_size[1]))
	@warning_ignore("integer_division") # Intentional integer truncation.
	var source := Rect2(Vector2(frame % int(profile.columns), frame / int(profile.columns)).floor() * frame_size, frame_size)
	# A 4x battle atlas can exceed mobile texture limits. Resolve only the
	# displayed frame; the art service preserves original logical dimensions.
	var texture := Art.region_texture(str(profile.atlas[side]), source)
	if texture == null: return
	# Draw commands retain a RID, not the temporary AtlasTexture resource.
	# Keep each actor's current region alive through the rendering frame.
	frame_textures[id] = texture
	var anchor := Vector2(_anchor_x(side == "right"), 88) if anchor_override == Vector2.INF else anchor_override
	var origin := anchor - Vector2(float(profile.anchor[0]), float(profile.anchor[1])) * actor_scale
	draw_texture_rect(texture, Rect2(origin, frame_size * actor_scale), false, Color(1, 1, 1, float(sprite_alpha.get(id, 1))))
	var whiteness := float(sprite_flash.get(id, 0))
	if whiteness > 0:
		var silhouette := _white_silhouette(texture.atlas, Rect2i(texture.region)) if texture is AtlasTexture else _white_silhouette(texture, Rect2i(Vector2i.ZERO, Vector2i(frame_size)))
		draw_texture_rect(silhouette, Rect2(origin, frame_size * actor_scale), false, Color(1, 1, 1, minf(1.0, whiteness / 0.25) * float(sprite_alpha.get(id, 1))))

func _white_silhouette(texture: Texture2D, region: Rect2i) -> Texture2D:
	# Cache only displayed frames, not a second copy of the large attack atlas.
	var key := "%d:%s" % [texture.get_instance_id(), region]
	if not silhouette_textures.has(key):
		var source_id := texture.get_instance_id()
		if not silhouette_sources.has(source_id):
			# Read back a large atlas once per encounter, not for each flashed frame.
			silhouette_sources[source_id] = texture.get_image()
		var image: Image = silhouette_sources[source_id].get_region(region)
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		for offset in range(0, bytes.size(), 4):
			bytes[offset] = 255
			bytes[offset + 1] = 255
			bytes[offset + 2] = 255
		silhouette_textures[key] = ImageTexture.create_from_image(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes))
	return silhouette_textures[key]

func feedback_origin() -> Vector2:
	# Follow the struck sprite, including a counterattack or a ranged defender.
	var id := feedback_defender_id
	var side := "right" if id == right_id else "left"
	var anchor := Vector2(_anchor_x(side == "right"), 88)
	if not profiles.has(id): return anchor - Vector2(0, 29)
	var profile: Dictionary = profiles[id]
	var path := str(profile.atlas[side])
	if not impact_centers.has(path):
		var frame := _first_frame(profile, "idle")
		var frame_size := Vector2i(int(profile.frame_size[0]), int(profile.frame_size[1]))
		@warning_ignore("integer_division") # Intentional integer truncation.
		var cell := Vector2i(frame % int(profile.columns), frame / int(profile.columns))
		var used := Art.original_image(path).get_region(Rect2i(cell * frame_size, frame_size)).get_used_rect()
		impact_centers[path] = Vector2(used.get_center()) - Vector2(float(profile.anchor[0]), float(profile.anchor[1]))
	return anchor + Vector2(impact_centers[path]) - Vector2(0, 5)

func _hud(id: String, right: bool) -> void:
	if not actors.has(id):
		return
	var unit: Dictionary = actors[id]
	var x := 120.0 if right else 0.0
	var tint := Color("234f9e") if str(unit.faction) == "player" else Color("27844a") if str(unit.faction) == "neutral" else Color("a92632")
	_panel(Rect2(x, 140, 120, 20), tint)
	var stats_x := 200.0 if right else 0.0
	var weapon_rect := Rect2(x if right else x + 40, 121, 80, 20)
	_panel(weapon_rect, Color("d3c198"))
	_panel(Rect2(stats_x, 111, 40, 30), tint)
	_panel(Rect2(184 if right else 0, 6, 56, 20), tint)
	_text(Vector2(188 if right else 4, 20), str(unit.get("name", id)), 9)
	var weapon: Dictionary = unit.get("weapon", {})
	var icon := _texture(str(weapon.get("icon", "")))
	_text(weapon_rect.position + Vector2(22 if icon else 4, 13), str(weapon.get("name", "Unarmed")), 8, Color("fff4d7"), 1, 0, false, 54 if icon else 72)
	if icon: draw_texture_rect(icon, Rect2(weapon_rect.position + Vector2(3, 2), Vector2(16, 16)), false)
	var stats: Dictionary = combat_stats.get(id, {})
	var row := 0
	for key in ["hit", "damage", "crit"]:
		_text(Vector2(stats_x + 3, 120 + row * 9), ["HIT", "DMG", "CRT"][row], 7)
		var value := str(stats.get(key, "--"))
		var doubled: bool = key == "damage" and int(stats.get("strikes", 1)) > 1
		if doubled: value += "×%d" % int(stats.strikes)
		_text(Vector2(stats_x + 22, 120 + row * 9), value, 6 if doubled else 7)
		row += 1
	var hp := maxi(0, ceili(float(display_hp.get(id, unit.hp))))
	_text(Vector2(x + 7, 154), str(hp), 11)
	var maximum := maxi(1, int(unit.get("max_hp", 1)))
	var bar := Rect2(x + 29, 147, 83, 7)
	draw_rect(bar.grow(1), Color("22271b"))
	draw_rect(bar, Color("133318"))
	var ratio := clampf(float(display_hp.get(id, unit.hp)) / maximum, 0, 1)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color("83de20") if ratio > 0.3 else Color("f4ad2b"))
	for i in range(1, mini(maximum, 40)):
		var line_x := bar.position.x + bar.size.x * float(i) / mini(maximum, 40)
		draw_line(Vector2(line_x, bar.position.y), Vector2(line_x, bar.end.y), Color("295c16"), 0.5)

func _draw() -> void:
	text_commands.clear()
	if not visible or (actors.is_empty() and reward_stage.is_empty()):
		return
	var scale_factor := minf(size.x / 240.0, size.y / 160.0)
	var origin := (size - Vector2(240, 160) * scale_factor) * 0.5
	scene_scale = scale_factor
	scene_origin = origin + Vector2(shake, shake_y) * scale_factor
	draw_set_transform(scene_origin, 0, Vector2.ONE * scale_factor)
	if not actors.is_empty():
		draw_rect(Rect2(-scene_origin / scale_factor, size / scale_factor), Color("0d1015"))
		if backdrop:
			var dimensions := backdrop.get_size()
			var visible_height := 160.0 - absf(backdrop_y)
			if visible_height > 0:
				draw_texture_rect_region(backdrop, Rect2(0, maxf(0, backdrop_y), 240, visible_height), Rect2(0, maxf(0, -backdrop_y) * dimensions.y / 160.0, dimensions.x, visible_height * dimensions.y / 160.0))
			# Extend the exposed edge instead of repeating the unshifted picture.
			if backdrop_y > 0:
				draw_texture_rect_region(backdrop, Rect2(0, 0, 240, backdrop_y), Rect2(0, 0, dimensions.x, 1))
			elif backdrop_y < 0:
				draw_texture_rect_region(backdrop, Rect2(0, 160 + backdrop_y, 240, -backdrop_y), Rect2(0, dimensions.y - 1, dimensions.x, 1))
		else: draw_rect(Rect2(0, 0, 240, 160), Color("7b9d54"))
		if not BattleArt.platforms_hidden():
			if custom_platforms.is_empty():
				if platform: draw_texture_rect(platform, Rect2(0, 0, 240, 160), false)
			else:
				for side in [[left_id, _anchor_x(false)], [right_id, _anchor_x(true)]]:
					if custom_platforms.has(side[0]): draw_texture_rect(custom_platforms[side[0]], Rect2(float(side[1]) - 34, 96, -68 if side[0] == left_id else 68, 15), false)
		# The attacker draws last so weapons cross the defender cleanly.
		for index in range(triangle_helpers.size()):
			var right := active_id == right_id
			var anchor := Vector2(170 if index == 0 else 210, 60 if index == 0 else 83)
			if not right: anchor.x = 240 - anchor.x
			_draw_actor(str(triangle_helpers[index]), "right" if right else "left", anchor, 0.7)
		if active_id == left_id:
			_draw_actor(right_id, "right")
			_draw_actor(left_id, "left")
		else:
			_draw_actor(left_id, "left")
			_draw_actor(right_id, "right")
		if not projectile.is_empty():
			draw_set_transform(scene_origin + Vector2(projectile.position) * scale_factor, float(projectile.angle), Vector2.ONE * scale_factor)
			draw_texture_rect(projectile.texture, Rect2(-8, -8, 16, 16), false)
			draw_set_transform(scene_origin, 0, Vector2.ONE * scale_factor)
		if hit_elapsed >= 0 and not skip_combat_animations:
			var tick := hit_elapsed * 60.0
			for i in range(hit_frames.size()):
				if tick < float(hit_ticks[i]):
					draw_texture(hit_frames[i], Vector2(_anchor_x(hit_target == right_id) - 152.0, 0), HIT_BRIGHTNESS)
					break
				tick -= float(hit_ticks[i])
		if flash > 0: draw_rect(Rect2(0, 0, 240, 121), Color(1, 1, 1, flash))
		_hud(left_id, false)
		_hud(right_id, true)
		if not feedback.is_empty():
			var effect := popup_style(feedback_elapsed / maxf(0.01, feedback_duration))
			var point := feedback_origin() - Vector2(0, float(effect.rise))
			var text_width := ThemeDB.fallback_font.get_string_size(feedback, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, roundi(14 * scene_scale))).x / scene_scale
			point.x = clampf(point.x - text_width * 0.5, 3, 237 - text_width)
			_text(point, feedback, 15, Color(Color("70ed8b") if feedback.begins_with("+") else Color(1.0, 1.0, 0.95), float(effect.alpha)), float(effect.scale), 0, (feedback.is_valid_int() and not feedback.begins_with("+")) or feedback.begins_with("CRITICAL"))
	if not reward_stage.is_empty():
		if reward_stage == "level": text_commands.clear()
		elif reward_stage == "exp":
			text_commands = text_commands.filter(func(command): return not Rect2(42, 129, 156, 29).has_point((Vector2(command.at) - scene_origin) / scene_scale))
		_draw_reward()
		if reward_stage == "level" and level_title_time > 0:
			_text(Vector2(70, 28), "LEVEL UP!", 20, Color(1, 1, 1, minf(1, level_title_time / 0.5)), 1.0, 0, true)
	if not rank_message.is_empty():
		_panel(Rect2(24, 42, 192, 27), Color("283d78"))
		_text(Vector2(120, 55.5), rank_message, 10, Color("fff09b"))
		text_commands[-1]["centered"] = true
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_apply_native_text()

func level_intro_style(progress: float) -> Dictionary:
	# Two distinct half-second beats: a screen-wide light beam, then gold text.
	# The calling clock is unscaled, independent of attack/counter speed.
	var t := clampf(progress, 0, 1)
	var beam := clampf(t / 0.035, 0, 1) * (1.0 - smoothstep(0.46, 0.5, t)) if t < 0.5 else 0.0
	var title := smoothstep(0.5, 0.54, t) if t >= 0.5 else 0.0
	return {"beam_alpha":beam, "text_alpha":title, "sweep":clampf(t / 0.065, 0, 1)}

func _draw_reward() -> void:
	if reward_stage == "level_intro":
		var effect := level_intro_style(level_intro_progress)
		var line_y := 51.0
		var start := -scene_origin.x / scene_scale
		var finish := start + size.x / scene_scale * float(effect.sweep)
		var opacity := float(effect.beam_alpha)
		if opacity > 0:
			var clear := Color(1, 0.64, 0.06, 0)
			var bright := Color(1, 0.78, 0.14, opacity * 0.56)
			draw_polygon(PackedVector2Array([Vector2(start,line_y-14),Vector2(finish,line_y-14),Vector2(finish,line_y),Vector2(start,line_y)]), PackedColorArray([clear,clear,bright,bright]))
			draw_polygon(PackedVector2Array([Vector2(start,line_y),Vector2(finish,line_y),Vector2(finish,line_y+14),Vector2(start,line_y+14)]), PackedColorArray([bright,bright,clear,clear]))
			draw_line(Vector2(start, line_y), Vector2(finish, line_y), Color(1, 0.92, 0.45, opacity), 3.5)
			draw_line(Vector2(start, line_y), Vector2(finish, line_y), Color(1, 1, 0.96, opacity), 1.5)
		if float(effect.text_alpha) > 0:
			var alpha := float(effect.text_alpha)
			var width := ThemeDB.fallback_font.get_string_size("LEVEL UP!", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, roundi(20 * scene_scale))).x / scene_scale
			_text(Vector2(120 - width * 0.5, line_y + 6), "LEVEL UP!", 20, Color(1, 1, 1, alpha), 1.0 + 0.12 * sin(alpha * PI), 0.85, true)
	elif reward_stage == "exp":
		_panel(Rect2(42, 129, 156, 29), Color("55599c"))
		_text(Vector2(48, 139), "%s   Lv %d" % [str(reward_unit.get("name", "Unit")), reward_level], 7)
		_text(Vector2(48, 151), "EXP", 7)
		var bar := Rect2(68, 144, 100, 7)
		draw_rect(bar.grow(1), Color("fff0ac"))
		draw_rect(bar, Color("624e62"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(reward_exp / reward_threshold, 0, 1), bar.size.y)), Color("ffdc39"))
		_text(Vector2(176, 151), str(int(reward_exp)), 8)
	else:
		draw_rect(Rect2(-scene_origin / scene_scale, size / scene_scale), Color(0.02, 0.03, 0.1, 0.6 * level_alpha))
		_panel(Rect2(10, 34, 142, 23), Color("2f63ad"), level_alpha)
		_text(Vector2(17, 50), "%s   Lv %d" % [str(reward_unit.get("name", "Unit")), reward_level], 9, Color(Color("fff6d1"), level_alpha))
		_panel(Rect2(10, 65, 142, 86), Color("284f9b"), level_alpha)
		var keys := preload("res://ui/unit_stat_labels.gd").level_keys(reward_unit)
		var names := ["HP", preload("res://ui/unit_stat_labels.gd").power(reward_unit, true), "Skill", "Spd", "Luck", "Def", "Res"]
		var rows := 4
		for i in range(keys.size()):
			var stat: String = keys[i]
			var x := 17.0 + (73 if i >= rows else 0)
			var y := 81.0 + (i % rows) * (15 if rows == 5 else 20)
			var glow := stat_glow(stat)
			var upgraded := reward_gains.has(stat)
			var number_color := Color("ffe04f").lerp(Color("fffbd5"), glow) if upgraded else Color("fff6d1")
			if glow > 0:
				for radius in [4, 2, 0]:
					draw_style_box(_stat_highlight(glow * level_alpha * 0.08), Rect2(x + 23, y - 10, 34, 14).grow(radius))
			_text(Vector2(x, y), names[i], 8, Color(Color("ffe78e"), level_alpha))
			_text(Vector2(x + 27, y), str(reward_stats.get(stat, reward_unit.get(stat, 0))), 8, Color(number_color, level_alpha), stat_punch(stat), glow)
			if upgraded: _text(Vector2(x + 42, y), "+%d" % int(reward_gains[stat]), 8, Color(number_color, level_alpha), stat_punch(stat), glow)
		if reward_portrait:
			var region := reward_portrait_region
			var extent := region.size * minf(83.0 / maxf(1, region.size.x), 124.0 / maxf(1, region.size.y))
			var portrait_rect := Rect2(Vector2(156, 158) - Vector2(0, extent.y), extent)
			if not reward_portrait_custom.is_empty(): portrait_rect = preload("res://ui/dialogue_unit_portrait.gd").art_rect(region.size, reward_portrait_custom, Vector2(240, 160), false)
			if reward_portrait_flipped: portrait_rect.size.x = -portrait_rect.size.x
			draw_texture_rect_region(reward_portrait, portrait_rect, region, Color(1, 1, 1, level_alpha))
		if awaiting_reward_continue: _text(Vector2(19, 157), "Tap to continue", 6, Color(Color("fff1c8"), level_alpha))

func _stat_highlight(opacity: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.68, 0.08, opacity)
	style.set_corner_radius_all(4)
	return style
