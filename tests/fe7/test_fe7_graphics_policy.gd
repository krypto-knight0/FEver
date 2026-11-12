extends SceneTree
## English FE7 graphics mutations: resource relocation must not weaken code guards.
const Decoder = preload("res://runtime/rom_decoder.gd")
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const YES := "d836e83faab5a1009a9f0fd59b3f4a059bf92167beeafa8b29dfc294e983e965"
const WORLD := "2370372c98ddd7a339ca92c19052d506d640bb785170aa06b50db96b36627339"
var failures := 0
var checks := 0
var base: PackedByteArray

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("English FE7 or Flux Echo 7 ROM path required"); quit(2); return
	base = FileAccess.get_file_as_bytes(args[0])
	if base.size() < 0xb6264: printerr("Incomplete cartridge"); quit(2); return
	if base.slice(0xac,0xb0).get_string_from_ascii() not in ["AE7E","FX7E"]:
		printerr("Supported English FE7 cartridge identity required"); quit(2); return
	var d := fresh()
	check(yes(d),"Current yes/no graphics accepted")
	check(world(d),"Current continent graphics accepted")
	# Follow a second valid resource relocation without cartridge branding.
	d = fresh()
	var tiles: PackedByteArray = d.lz(d.ptr(0x155bc))
	var graphic: int = d.rom.size()
	d.rom.append_array(literal_lz(tiles))
	d.rom[0xaf] = 0x58
	d.rom.encode_u32(0x155bc,0x08000000+graphic)
	check(yes(d),"Valid second graphics relocation accepted without header identity")
	d = fresh(); d.rom[0x15592] ^= 1
	check(not yes(d),"Changed source-load opcode rejected")
	d = fresh(); d.rom[0x15598] ^= 2
	check(not yes(d),"Changed decompressor call rejected")
	d = fresh(); d.rom[0x155c0] ^= 4
	check(not yes(d),"RAM destination literal remains signed")
	d = fresh(); d.rom.encode_u32(0x155bc,0x02000000)
	check(not yes(d),"Non-cartridge source pointer rejected")
	d = fresh(); d.rom.encode_u32(0x155bc,0x08000000+d.rom.size())
	check(not yes(d),"Out-of-bounds graphics pointer rejected")
	d = fresh(); d.rom.encode_u32(d.ptr(0x155bc),0x00080010)
	check(not yes(d),"Wrong decoded tile count rejected")
	d = fresh()
	var malformed: int = d.ptr(0x155bc)
	d.rom[malformed+4] = 0x80; d.rom[malformed+5] = 0; d.rom[malformed+6] = 0
	check(not yes(d),"Back-reference before output rejected despite valid header")
	d = fresh(); d.rom[0xb6034] ^= 1
	check(not world(d),"World upload opcode remains signed")
	d = fresh(); d.rom.encode_u32(0xb6078,0x08000000+d.rom.size()-4)
	check(not world(d),"Truncated palette rejected")
	d = fresh(); d.rom[d.ptr(0xb6088)] = 28
	check(not world(d),"Wrong world TSA dimensions rejected")
	d = fresh(); d.rom.encode_u16(d.ptr(0xb6088)+2,640)
	check(not world(d),"TSA tile outside native allocation rejected")
	d = fresh(); d.rom.encode_u16(d.ptr(0xb6088)+2,0x4000)
	check(not world(d),"TSA palette bank outside four banks rejected")
	check(base == FileAccess.get_file_as_bytes(args[0]),"Supplied cartridge unchanged")
	print("FE7 graphics policy: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func fresh() -> RefCounted:
	var d := Decoder.new()
	d.rom = base.duplicate()
	d.layout = {"event_variant":"fe7u"}
	return d

func yes(d: RefCounted) -> bool:
	return Policy.actual_signature(d,0x15590,60,[],YES) and Policy.signature(d,0x15a0c,60,[],YES)

func world(d: RefCounted) -> bool:
	return Policy.signature(d,0xb6e40,560,[],WORLD)

func literal_lz(decoded: PackedByteArray) -> PackedByteArray:
	var packed := PackedByteArray()
	packed.resize(4)
	packed.encode_u32(0,(decoded.size()<<8)|0x10)
	for at in range(0,decoded.size(),8):
		packed.append(0)
		packed.append_array(decoded.slice(at,mini(at+8,decoded.size())))
	return packed

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
