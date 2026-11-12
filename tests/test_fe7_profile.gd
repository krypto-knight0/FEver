extends SceneTree
## ROM-free synthetic ABI checks.
const Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)

func fixture(code: String) -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(0xc0000)
	for index in range(4): bytes[0xac+index] = code.unicode_at(index)
	var layout := Profile.layout_for(bytes)
	var operands: Array = []
	for key in ["characters","items","text","tree","root","chapters","maps","config","graphics","palettes","changes","portraits","sprites","icons","icon_palette"]:
		operands.append(layout[key])
	operands.append_array([layout.record_layout[3],layout.deployment_layout[4],layout.deployment_layout[5]])
	for index in range(operands.size()): bytes.encode_u32(operands[index],0x080a0000+index*0x1000)
	for entry in [[layout.characters,0,4],[layout.record_layout[3],84,4],[layout.items,36,6]]:
		bytes[bytes.decode_u32(entry[0])-0x08000000+entry[1]+entry[2]] = 1
	var dispatch := bytes.decode_u32(layout.deployment_layout[5])-0x08000000
	var commands := [[10,1],[0xd,2],[0x24,3],[0x30,2],[0x37,3],[0x3c,2],[0x7f,1]] if code == "AE7J" else [[10,1],[0xd,2],[0x26,3],[0x32,2],[0x39,3],[0x3e,2],[0x81,1]]
	for entry in commands: bytes.encode_u32(dispatch+entry[0]*8+4,entry[1])
	return bytes

func _initialize() -> void:
	for code in ["AE7J","AE7E","FX7E"]:
		var bytes := fixture(code)
		var detected := Profile.detect(bytes)
		check(detected.error.is_empty() and detected.get("region") == code,"Accept supported code "+code)
		check(Profile.layout_for(bytes).event_variant == ("fe7j" if code == "AE7J" else "fe7u"),"Correct regional layout "+code)
		check(detected.get("version") == (Profile.VERSION if code == "AE7J" else Profile.US.VERSION),"Correct decoder version "+code)
	var bytes := fixture("FX7E")
	var layout := Profile.layout_for(bytes)
	var damaged := bytes.duplicate(); damaged.encode_u32(layout.characters,0xffffffff)
	check(not Profile.detect(damaged).error.is_empty(),"FX7E cannot bypass pointer checks")
	var path := "user://fx7e-invalid-profile.gba"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		file.store_buffer(damaged); file.close()
		var error := preload("res://runtime/rom_assets.gd").load_rom(path,false)
		check(error.contains("FE7 compatibility"),"Main cartridge loader routes FX7E to FE7 validation")
		check(preload("res://runtime/rom_assets.gd").decoder == null,"Failed custom load clears decoder state")
		DirAccess.remove_absolute(path)
	else: check(false,"Can write isolated synthetic cartridge")
	damaged = bytes.duplicate(); damaged[damaged.decode_u32(layout.items)-0x08000000+36+6] = 9
	check(not Profile.detect(damaged).error.is_empty(),"FX7E cannot bypass record checks")
	damaged = bytes.duplicate(); damaged.encode_u32(damaged.decode_u32(layout.deployment_layout[5])-0x08000000+0x26*8+4,7)
	check(not Profile.detect(damaged).error.is_empty(),"FX7E cannot bypass event command checks")
	damaged = bytes.duplicate(); damaged[0xaf] = 0x58
	check(not Profile.detect(damaged).error.is_empty(),"Unknown FX7X code rejected")
	check(not Profile.detect(bytes.slice(0,0x90000)).error.is_empty(),"Truncated cartridge rejected")
	# Relocation remains supported for the custom code, not just a stock offset.
	var original := bytes.decode_u32(layout.characters)-0x08000000
	bytes.append_array(bytes.slice(original,original+52))
	bytes.encode_u32(layout.characters,0x080c0000)
	check(Profile.detect(bytes).error.is_empty(),"FX7E accepts relocated character records")
	print("FE7 profile checks: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
