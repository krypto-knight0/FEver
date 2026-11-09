extends "res://runtime/rom_dynamic_library.gd"
## FE6 native gallery layouts; shared discovery and decoding live in the base.
const Fe6Decoder = preload("res://runtime/fe6/fe6_decoder.gd")

func make_decoder() -> RefCounted:
	var d := Fe6Decoder.new(); d.rom = rom
	return d

func portrait_table() -> int: return pointer(0x7fd8)
func background_table() -> int: return pointer(0xe374)

func background_id(path: String) -> int:
	return path.get_file().get_basename().to_int() if path.contains("/rom/backgrounds/") else -1

func portrait_valid(table: int, id: int) -> bool:
	var at := table+id*16
	if table < 0 or not span(at,16): return false
	var minimug := int(rom.decode_u32(at+4))
	return compressed(pointer(at)) and span(pointer(at+8),32) and (minimug == 0 or span(pointer(at+4),32))

