extends Node
var store = preload("res://runtime/voice_store.gd").new()
var rng := RandomNumberGenerator.new()
var players: Array[AudioStreamPlayer] = []
var owners: Array[String] = []
var actions: Array[String] = []
var fades: Array[Tween] = []
var bags: Dictionary = {}
var cursor := 0
var last_clip := ""
var master_muted := false
var playback_enabled := AudioServer.get_driver_name() != "Dummy"

func _ready() -> void:
	rng.randomize() # Cosmetic randomness never consumes the battle RNG.
	store.reload()
	for i in range(4):
		var player := AudioStreamPlayer.new()
		add_child(player); players.append(player); owners.append(""); actions.append(""); fades.append(null)

func begin_battle() -> void:
	bags.clear()

func _choose(options: Array, key: String) -> String:
	var bag: Dictionary = bags.get(key, {})
	if bag.get("options", []) != options: bag = {"options":options.duplicate(), "remaining":[], "last":""}
	var remaining: Array = bag.remaining
	if remaining.is_empty(): remaining = options.duplicate()
	var candidates := remaining.filter(func(path): return remaining.size() == 1 or path != bag.last)
	if candidates.is_empty(): candidates = remaining
	var selected := str(candidates[rng.randi_range(0, candidates.size()-1)])
	remaining.erase(selected)
	bag.remaining = remaining; bag.last = selected; bags[key] = bag
	return selected

func play_unit(unit: Dictionary, action: String) -> void:
	if unit.is_empty() or not store.enabled or master_muted or store.volume <= 0: return
	var options: Array = store.clips(unit, action)
	if options.is_empty(): return
	var unit_id := str(unit.get("id", unit.get("name", "")))
	var path := _choose(options, unit_id + ":" + action) if action in ["attack", "crit", "damage", "defeat"] else str(options[rng.randi_range(0, options.size()-1)])
	play_clip(path, unit_id, action)

func play_clip(path: String, unit_id: String = "preview", action: String = "preview") -> void:
	if master_muted or store.volume <= 0 or players.is_empty(): return
	var stream: AudioStream = store.stream(path)
	if stream == null: return
	var index := owners.find(unit_id)
	if index < 0: index = cursor; cursor = (cursor + 1) % players.size()
	var player := players[index]
	if fades[index]: fades[index].kill(); fades[index] = null
	player.stop(); player.stream = stream; player.volume_db = linear_to_db(store.volume)
	owners[index] = unit_id; actions[index] = action; last_clip = path
	if playback_enabled: player.play()

func fade_status(unit_id: String) -> void:
	var index := owners.find(unit_id)
	if index < 0 or actions[index] != "status" or players[index].stream == null: return
	if fades[index]: fades[index].kill()
	var player := players[index]
	fades[index] = create_tween()
	fades[index].tween_property(player, "volume_db", -60.0, 0.15)
	fades[index].tween_callback(func():
		player.stop(); player.stream = null; owners[index] = ""; actions[index] = ""; fades[index] = null)

func stop() -> void:
	for fade in fades:
		if fade: fade.kill()
	fades.fill(null)
	for player in players: player.stop(); player.stream = null
	owners.fill("")
	actions.fill("")

func update_volume() -> void:
	for player in players: player.volume_db = linear_to_db(maxf(0.0001, store.volume))
	if not store.enabled or master_muted or store.volume <= 0: stop()
