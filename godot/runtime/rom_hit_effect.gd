extends RefCounted
## Original normal-hit BG: native graphics/palette, ten TSA frames and their
## frame-duration LUT. Addresses select the routine's literal pointers, so ROM
## repoints remain effective. The supplied FE8 symbols identify the same effect;
## its graphics, palette and duration LUT match the supplied FE6 and FE7 ROMs.
static func read(decoder: RefCounted, game: String) -> Dictionary:
	var pool := int(decoder.layout.get("hit_effect",0x56d04 if game == "fe6" else 0x6277c))
	var timing: int = decoder.ptr(pool)
	var maps: int = decoder.ptr(pool + 4)
	var palette: int = decoder.ptr(pool + 8)
	var graphics: int = decoder.ptr(pool + 12)
	var frames: Array = []
	var ticks: Array = []
	for i in range(32):
		var index: int = decoder.u16(timing + i * 4)
		if index == 65535: break
		if index >= 10: return {}
		var image: Image = decoder.scene({"graphics":[[graphics]], "palette":palette, "palette_size":32, "tsa":decoder.ptr(maps + index * 4), "tsa_lz":true, "header":false, "width":240, "height":160, "transparent":true})
		if image == null: return {}
		frames.append(image)
		ticks.append(maxi(1, decoder.u16(timing + i * 4 + 2)))
	return {"frames":frames, "ticks":ticks}
