extends RefCounted
## Native MU step sequences are sparse, 60 Hz sound scripts with a bounded
## frame count. Follow their literal-pool pointers so ROM edits remain audible.
const Assets = preload("res://runtime/rom_assets.gd")
const Data = preload("res://runtime/rom_data.gd")
const POINTERS := {
	"fe6": {"foot":0x607d8,"heavy":0x607cc,"horse":0x607a4,"wyvern":0x60798,"pegasus":0x6078c},
	"fe7": {"foot":0x6cba4,"heavy":0x6cb8c,"horse":0x6cb54,"wyvern":0x6cb48,"pegasus":0x6cb3c,"dragon":0x6cb98},
}

static func movement(d: RefCounted, game: String, class_id: int) -> Array[int]:
	var sounds: Array[int] = []
	if not POINTERS.has(game): return sounds
	var family := "foot"
	var layout: Array = Data.RECORD_LAYOUTS[game]
	var at: int = d.ptr(int(layout[3])) + class_id * int(layout[4])
	if class_id > 0 and at >= 0 and at + int(layout[4]) <= d.rom.size():
		var flags: int = d.u32(at+(36 if game == "fe6" else 40))
		if flags & 1:
			if class_id in ([42,43] if game == "fe6" else [50,51]): family = "pegasus"
			elif class_id in ([44,45,46,47] if game == "fe6" else [52,53,54,55]): family = "wyvern"
			else: family = "horse"
		elif class_id in ([12,13,14,15,60,61] if game == "fe6" else [20,21,22,23,85,91,92,93]): family = "heavy"
		elif game == "fe7" and class_id == 70: family = "dragon"
	var script: int = d.ptr(int(POINTERS[game][family]))
	if script <= 0 or script+4 > d.rom.size(): return sounds
	var frames: int = d.u16(script)
	if frames < 1 or frames > 128 or script+4+frames*2 > d.rom.size():
		if Assets.diagnostic_sink.is_valid(): Assets.diagnostic_sink.call("rom_sound_invalid", {"game":game,"family":family})
		return sounds
	for i in range(frames): sounds.append(d.u16(script+4+i*2))
	return sounds

static func cues(game: String) -> Dictionary:
	return {"phase_change":0x73 if game == "fe6" else 0x393, "item_select":0x67, "item_equip":0x6a}
