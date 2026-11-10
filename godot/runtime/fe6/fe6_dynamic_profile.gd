extends RefCounted
## Compatibility ABI for FE6-based cartridges. No chapter/event/character catalog.
## Data tables may relocate through these pointer operands; engine layouts may not.
const Decoder = preload("res://runtime/fe6/fe6_dynamic_decoder.gd")
const POINTERS := [0x17680,0x176e0,0x16410,0x13b10,0x2bb20,0x2bbcc,0x2bb70,0x18a7c,0xe038,0x7fd8,0x21c74,0x60ed8,0x3748,0x4b0f8]
const MAX_CHAPTERS := 75
const VERSION := "fe6-dynamic-2"
const GAME_CODES := ["AFEJ", "FX6E"]

static func detect(bytes: PackedByteArray) -> Dictionary:
	# The movement-table operand at 0x60ed8 must exist before reading pointers.
	if bytes.size() < 0x60edc or bytes.size() > 32*1024*1024: return {"error":"Not a supported FE6-sized cartridge."}
	if bytes.slice(0xac,0xb0).get_string_from_ascii() not in GAME_CODES: return {"error":"This cartridge is not identified as a supported FE6-compatible base (AFEJ or FX6E)."}
	for at in POINTERS:
		var value := bytes.decode_u32(at)
		if value < 0x08000000 or value-0x08000000+4 > bytes.size() or value%4:
			return {"error":"FE6 compatibility: invalid table pointer at 0x%x." % at}
	for entry in [[0x17680,48],[0x176e0,72],[0x16410,32]]:
		var at := bytes.decode_u32(entry[0])-0x08000000+int(entry[1])
		if at+int(entry[1]) > bytes.size() or bytes[at+(6 if entry[0] == 0x16410 else 4)] != 1:
			return {"error":"FE6 compatibility: character, class, or item record layout has changed."}
	var dispatch := bytes.decode_u32(0xe038)-0x08000000
	for entry in [[6,1],[7,2],[0x12,2],[0x1f,3],[0x3d,2]]:
		if dispatch+int(entry[0])*8+8 > bytes.size() or bytes.decode_u32(dispatch+int(entry[0])*8+4) != entry[1]:
			return {"error":"FE6 compatibility: event command layout has changed."}
	return {"error":"","game_id":"fe6","version":VERSION}

static func decoder(bytes: PackedByteArray) -> RefCounted:
	var result := Decoder.new()
	result.rom = bytes
	result.configure_text()
	return result
