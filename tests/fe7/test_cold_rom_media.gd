extends SceneTree
const Player = preload("res://runtime/m4a_player.gd")
const Assets = preload("res://runtime/rom_assets.gd")
const Card = preload("res://runtime/rom_card_art.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func decoder(value: int) -> RefCounted:
	var d := preload("res://runtime/rom_decoder.gd").new()
	d.rom.resize(128)
	d.rom.encode_u32(4, 0x08000020)
	d.rom.encode_u32(36, 22050 * 1024)
	d.rom.encode_u32(44, 8)
	for i in range(8): d.rom[48 + i] = value
	return d

func _initialize() -> void:
	var player := Player.new()
	player.decoder = decoder(10)
	var first := player.sample(0,64)
	Player.song_cache[7] = {"stale":true}
	player.decoder = decoder(80)
	var second := player.sample(0,64)
	check(first.data != second.data, "sample at same address is decoded again for a new ROM")
	check(Player.song_cache.is_empty(), "song cache belongs to one decoder")
	player.free()
	# A legacy on-disk card must never substitute for an unavailable cartridge.
	DirAccess.make_dir_recursive_absolute("user://game-library")
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	image.save_png("user://game-library/fe6-card-v2.png")
	image.save_png("user://game-library/fe7-card-v49.png")
	Assets._reset_loaded_state()
	check(Card.texture({"id":"fe6","path":"user://missing.gba"}) == null, "FE6 ignores legacy card cache")
	check(Card.texture({"id":"fe7","path":"user://missing.gba"}) == null, "FE7 ignores legacy card cache")
	print("Cold ROM media: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
