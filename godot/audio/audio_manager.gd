extends Node
## Pack-independent audio playback. A content manifest maps logical cues to assets.
## Source synthesis/provenance belongs to the content pack, not this component.

signal settings_changed

const SETTINGS_PATH := "user://audio_settings.cfg"
const SFX_VOICES := 6

var manifest: Dictionary = {}
var current_music: String = ""
var muted: bool = false
var music_volume: float = 0.5
var sfx_volume: float = 0.8
var music_player: Node
var sfx_players: Array[Node] = []
var sfx_cursor := 0
var sfx_cache: Dictionary = {}
var playback_enabled: bool = AudioServer.get_driver_name() != "Dummy"
var music_fade: Tween
var music_gain := 1.0
var suspended := false
var deferred_music := ""
var saved_event_music: Variant = null

func save_event_music() -> void:
	# Native MUSS has one saved-song register, not a nesting stack.
	saved_event_music = current_music

func restore_event_music() -> bool:
	if saved_event_music == null: return false
	if str(saved_event_music).is_empty(): stop_music()
	else: play_music(str(saved_event_music))
	return true

func suspend_for_loading(value: bool) -> void:
	if suspended == value: return
	suspended = value
	if value:
		saved_event_music = null
		deferred_music = ""
		stop_music()
		for player in sfx_players: player.stop()
	else:
		var track := deferred_music
		deferred_music = ""
		if not track.is_empty(): play_music(track)

func _ready() -> void:
	_ensure_players()

func _exit_tree() -> void:
	stop_music()
	for player in sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	sfx_cache.clear()

func _ensure_players() -> void:
	if music_player != null:
		return
	music_player = _new_player()
	music_player.name = "Music"
	add_child(music_player)
	for index in range(SFX_VOICES):
		var player := _new_player()
		player.name = "Effect%d" % index
		add_child(player)
		sfx_players.append(player)
	_apply_volume()

func _new_player() -> Node:
	if preload("res://runtime/rom_assets.gd").initialized(): return preload("res://runtime/m4a_player.gd").new()
	return AudioStreamPlayer.new()

func configure(manifest_path: String, restore_preferences: bool = true) -> bool:
	_ensure_players()
	if not FileAccess.file_exists(manifest_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or int(data.get("schema_version", 0)) != 1 or not data.get("music", {}) is Dictionary or not data.get("sfx", {}) is Dictionary:
		return false
	stop_music()
	for player in sfx_players:
		player.stop()
	sfx_cache.clear()
	manifest = data
	saved_event_music = null
	# Include the original ROM music bank, even tracks no campaign has used yet.
	var assets = preload("res://runtime/rom_assets.gd")
	if assets.initialized():
		var cues := preload("res://runtime/rom_map_sounds.gd").cues(assets.game_id)
		for cue in cues: manifest.sfx[cue] = {"song_id":cues[cue],"loop":false}
		var decoder = assets.decoder
		for song in manifest.get("sound_room_catalog", []):
			var id := int(song.song_id)
			if not preload("res://runtime/rom_audio.gd").has_song(decoder,id): continue
			var key := "song_%03x" % id
			if not manifest.music.has(key): manifest.music[key] = {"song_id": id, "loop": true}
			manifest.music[key].title = str(song.title)
	if restore_preferences:
		_load_preferences()
	_apply_volume()
	return true

func _stream(entry: Dictionary) -> AudioStream:
	if str(entry.get("path", "")).is_empty() and entry.has("song_id") and preload("res://runtime/rom_assets.gd").initialized():
		var stream := AudioStreamWAV.new()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if entry.get("loop", false) else AudioStreamWAV.LOOP_DISABLED
		stream.set_meta("rom_song", int(entry.song_id))
		stream.set_meta("rom_loop", entry.get("loop", false))
		return stream
	var path := str(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if not resource is AudioStream:
		return null
	if resource is AudioStreamWAV:
		var stream: AudioStreamWAV = resource.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if entry.get("loop", false) else AudioStreamWAV.LOOP_DISABLED
		stream.loop_begin = maxi(0, int(entry.get("loop_begin", 0)))
		stream.loop_end = maxi(stream.loop_begin, int(entry.get("loop_end", 0)))
		return stream
	return resource

func has_music(track: String) -> bool:
	if manifest.get("music", {}).get(track) is Dictionary: return true
	var assets = preload("res://runtime/rom_assets.gd")
	if not assets.initialized() or not track.begins_with("song_"): return false
	var number := track.trim_prefix("song_")
	if not number.is_valid_hex_number(false): return false
	var id := number.hex_to_int()
	return track == "song_%03x" % id and preload("res://runtime/rom_audio.gd").has_song(assets.decoder,id)

func has_sfx(cue: String) -> bool:
	return manifest.get("sfx", {}).get(cue) is Dictionary

func play_music(track: String, restart: bool = false) -> bool:
	if suspended:
		deferred_music = track
		return true
	_ensure_players()
	if track.is_empty():
		stop_music()
		return true
	if not has_music(track):
		return false
	# A zero-track ROM song is unavailable. Keep the last playable cue.
	var entry: Dictionary = manifest.music[track] if manifest.get("music",{}).has(track) else {"song_id":track.trim_prefix("song_").hex_to_int(),"loop":true}
	if entry.get("silent", false): return false
	if current_music == track and (music_player.playing or not playback_enabled) and not restart:
		return true
	var stream := _stream(entry)
	if stream == null:
		return false
	current_music = track
	# Headless runs use the Dummy audio driver, which has no output device. Keep
	# cue/stream state testable without scheduling abandoned mixer playbacks.
	if music_fade: music_fade.kill()
	if playback_enabled and music_player.playing:
		music_fade = create_tween()
		music_fade.tween_method(_set_music_gain, music_gain, 0.0, 0.12)
		music_fade.tween_callback(func():
			music_player.stop()
			music_player.stream = stream
			music_player.pitch_scale = 1.0
			music_player.play())
		music_fade.tween_method(_set_music_gain, 0.0, 1.0, 0.16)
	else:
		music_player.stop()
		music_player.stream = stream
		music_player.pitch_scale = 1.0
		if playback_enabled:
			_set_music_gain(0.0)
			music_player.play()
			music_fade = create_tween()
			music_fade.tween_method(_set_music_gain, 0.0, 1.0, 0.16)
	return true

func _set_music_gain(value: float) -> void:
	music_gain = value
	_apply_volume()

func stop_music() -> void:
	if music_fade: music_fade.kill()
	music_gain = 1.0
	if music_player != null:
		music_player.stop()
		music_player.stream = null
	current_music = ""

func play_sfx(cue: String) -> bool:
	if suspended: return false
	_ensure_players()
	if muted or sfx_volume <= 0.0 or not has_sfx(cue):
		return false
	if not sfx_cache.has(cue):
		var stream := _stream(manifest.sfx[cue])
		if stream == null:
			return false
		sfx_cache[cue] = stream
	return _play_effect_stream(sfx_cache[cue])

func play_rom_sfx(id: int) -> bool:
	if suspended: return false
	_ensure_players()
	var assets = preload("res://runtime/rom_assets.gd")
	if muted or sfx_volume <= 0.0 or not assets.initialized(): return false
	if not preload("res://runtime/rom_audio.gd").has_song(assets.decoder,id): return false
	return _play_effect_stream(_stream({"song_id":id,"loop":false}))

func _play_effect_stream(stream: AudioStream) -> bool:
	if stream == null: return false
	# Prefer an idle voice; otherwise replace the oldest scheduled effect.
	var index := sfx_cursor
	for offset in range(SFX_VOICES):
		var candidate := (sfx_cursor + offset) % SFX_VOICES
		if not sfx_players[candidate].playing:
			index = candidate
			break
	var player := sfx_players[index]
	player.stop()
	player.stream = stream
	if playback_enabled:
		player.play()
	sfx_cursor = (index + 1) % SFX_VOICES
	return true

func set_muted(value: bool, persist: bool = true) -> void:
	muted = value
	_apply_volume()
	if muted:
		for player in sfx_players:
			player.stop()
	_update_preferences(persist)

func set_music_volume(value: float, persist: bool = true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	_update_preferences(persist)

func set_sfx_volume(value: float, persist: bool = true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	_update_preferences(persist)

func _apply_volume() -> void:
	if music_player != null:
		music_player.volume_db = -80.0 if muted or music_volume * music_gain <= 0.0001 else linear_to_db(music_volume * music_gain)
	for player in sfx_players:
		player.volume_db = -80.0 if muted or sfx_volume <= 0.0 else linear_to_db(sfx_volume)

func _update_preferences(persist: bool) -> void:
	if persist:
		var settings := ConfigFile.new()
		settings.set_value("audio", "muted", muted)
		settings.set_value("audio", "music_volume", music_volume)
		settings.set_value("audio", "sfx_volume", sfx_volume)
		settings.save(SETTINGS_PATH)
	settings_changed.emit()

func _load_preferences() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	muted = bool(settings.get_value("audio", "muted", false))
	music_volume = clampf(float(settings.get_value("audio", "music_volume", 0.5)), 0.0, 1.0)
	sfx_volume = clampf(float(settings.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
