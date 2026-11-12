extends SceneTree
## Synthetic regressions for the rendering fixes behind the refreshed goldens.
class SyntheticDecoder extends "res://runtime/rom_decoder.gd":
	var graphics := PackedByteArray()
	func lz(_address: int) -> PackedByteArray: return graphics

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func halfwords(values: Array) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(values.size() * 2)
	for index in range(values.size()): result.encode_u16(index * 2, int(values[index]) & 65535)
	return result

func _initialize() -> void:
	var decoder := SyntheticDecoder.new()
	decoder.graphics.resize(8192)
	for index in range(32):
		decoder.graphics[index] = 0x11
		decoder.graphics[index + 32] = 0x22
	var palette := PackedByteArray()
	palette.resize(32)
	palette.encode_u16(2, 31)
	palette.encode_u16(4, 31 << 5)
	var end := halfwords([1, 0, 0, 0, 0, 0])
	var identity := halfwords([1, 65535, 256, 0, 0, 256])
	var piece := halfwords([256, 0, 0, -148, -88, 0])
	var image := decoder.battle_frame([0x08000000, 0], identity + piece + end, palette)
	check(image.get_used_rect() == Rect2i(0, 0, 8, 8), "one-matrix header does not terminate the frame")
	check(image.get_pixel(0, 0) == Color.RED, "affine identity preserves sprite pixels")
	var matrices := halfwords([2, 65535, 32767, 0, 0, 32767, 2, 65535, 256, 0, 0, 256])
	piece = halfwords([256, 512, 0, -148, -88, 0])
	image = decoder.battle_frame([0x08000000, 0], matrices + piece + end, palette)
	check(image.get_used_rect() == Rect2i(0, 0, 8, 8), "affine slot one selects the second matrix")
	piece = halfwords([768, 0, 0, -148, -88, 0])
	image = decoder.battle_frame([0x08000000, 0], identity + piece + end, palette)
	check(image.get_used_rect() == Rect2i(4, 4, 8, 8), "double-size affine bounds keep the sprite centered")

	# Two AP pieces share an OAM2 destination, but have distinct packed ROM tiles.
	# Reading tile_base + OAM2 for both would incorrectly draw the red tile twice.
	decoder.rom.resize(512)
	decoder.layout = {"movement":0, "sprite_palette":16}
	decoder.rom.encode_u32(0, 0x08000040)
	decoder.rom.encode_u32(64, 0x08000080)
	decoder.rom.encode_u32(68, 0x08000100)
	for index in range(32): decoder.rom[16 + index] = palette[index]
	var ap := halfwords([4, 6, 2, 2, 200, 480, 0, 200, 488, 0, 0, 1])
	for index in range(ap.size()): decoder.rom[256 + index] = ap[index]
	image = decoder.movement(1, 0)
	check(image.get_used_rect() == Rect2i(0, 0, 16, 8), "both movement pieces render")
	check(image.get_pixel(0, 0) == Color.RED and image.get_pixel(8, 0) == Color.GREEN, "each movement piece reads its own ROM tile offset")
	check(decoder.error.is_empty(), "synthetic records decode without errors")
	print("Image decoding regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
