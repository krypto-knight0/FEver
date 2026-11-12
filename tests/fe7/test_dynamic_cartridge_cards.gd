extends SceneTree
const Cards = preload("res://runtime/rom_card_art.gd")
const Identity = preload("res://runtime/game_identity.gd")
const Header = preload("res://runtime/rom_header.gd")
const Start = preload("res://runtime/rom_start.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)

func run() -> void:
	header_checks()
	for name in ["assets.json","templates.json","text_audit.json","rom_import_cache.gd","rom_live_program.gd","rom_unit_groups.gd"]:
		check(not FileAccess.file_exists("res://runtime/"+name),"Retired static file absent: "+name)
	var identities := {}
	for path in OS.get_cmdline_user_args():
		var digest := FileAccess.get_sha256(path)
		var bytes := FileAccess.get_file_as_bytes(path)
		var header := Header.from_bytes(bytes)
		check(header.get("code", "") in ["AE7E", "AE7J", "FX7E"], "Supported FE7 cartridge header")
		if header.get("code", "") not in ["AE7E", "AE7J", "FX7E"]: continue
		var game := "fe7"
		check(Header.from_file(path) == header,"Header-only read matches full ROM metadata")
		var label := Header.display_name(header)
		check(Start._card_name({"id":game,"name":"12345678-1234-1234-1234-123456789abc","path":path,"dynamic_rom":true}) == label,"Existing opaque library name resolves from ROM header")
		check(label.contains(str(header.code)) and not label.contains("compatibility"),"Readable title includes native game code")
		# Existing library cards can lack dynamic metadata even though the ROM
		# now uses dynamic import. Artwork must still decode without a catalog.
		check(Cards.texture({"id":game,"path":path}) != null,"Native title for existing card "+path.get_file())
		check(Cards.texture({"id":game+"-"+digest,"path":path,"dynamic_rom":true,"rom_sha256":digest}) != null,"Hash-identified title card")
		check(Cards.texture({"path":path,"rom_sha256":"0".repeat(64)}) == null,"Changed cartridge identity is rejected")
		var save := Identity.save_path(game,digest)
		check(not identities.has(save),"Distinct regional/cartridge save namespace")
		identities[save] = true
		check(FileAccess.get_sha256(path) == digest,"Source cartridge untouched")
	var route = preload("res://ui/route_select.gd").new()
	root.add_child(route)
	route.present(false,"fe7")
	check(route.heading.text == "Choose a starting story" and route.description.text == "Start from the beginning of any campaign.","New Game has ordinary story instructions without a caveat")
	route.queue_free()
	print("Dynamic cartridge cards: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func header_checks() -> void:
	check(Start._card_name({"name":"Saved title · AE7E","dynamic_rom":true}) == "Saved title · AE7E","Unavailable source keeps the persisted header title")
	check(Start._card_name({"name":""}) == "Cartridge","Empty legacy name has a readable fallback")
	check(Header.from_bytes(PackedByteArray()).is_empty(),"Empty header has no metadata")
	var bytes := PackedByteArray(); bytes.resize(0xc0)
	var title := "MY HACK".to_ascii_buffer()
	for index in range(title.size()): bytes[0xa0+index] = title[index]
	var code := "AE7E".to_ascii_buffer()
	for index in range(code.size()): bytes[0xac+index] = code[index]
	check(Header.display_name(Header.from_bytes(bytes)) == "MY HACK · AE7E","Custom title survives normalization")
	check(Header.from_bytes(bytes.slice(0,0xbf)).is_empty(),"Truncated header has no metadata")
	bytes[0xa0] = 1
	check(Header.display_name(Header.from_bytes(bytes),"FE7") == "FE7 · AE7E","Invalid title falls back without losing game code")
	bytes.fill(0)
	check(Header.display_name(Header.from_bytes(bytes),"FE7") == "FE7","Blank header uses safe fallback")
	for title_text in ["CUSTOM6","CUSTOM7","CUSTOME","CUSTOM TITLE"]:
		check(Header.display_name({"title":title_text}) == title_text,"Cartridge title is preserved without a name catalog")
	var path := "user://12345678-1234-1234-1234-123456789abc.gba"
	var file := FileAccess.open(path,FileAccess.WRITE)
	for index in range(title.size()): bytes[0xa0+index] = title[index]
	file.store_buffer(bytes); file.close()
	check(Start._card_name({"path":path,"name":path.get_file(),"dynamic_rom":true}) == "MY HACK","Mobile-style private path never becomes display title")
	DirAccess.remove_absolute(path)
