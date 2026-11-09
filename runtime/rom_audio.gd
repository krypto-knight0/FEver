extends RefCounted
## Probe native sound headers without poisoning the decoder on a stale saved cue.
const Flags = preload("res://engine/native_event_flags.gd")

static func pointer(rom: PackedByteArray, at: int) -> int:
	if at < 0 or at > rom.size() - 4: return -1
	var target := int(rom.decode_u32(at)) - 0x08000000
	return target if target >= 0 and target < rom.size() else -1

static func has_song(decoder: RefCounted, id: Variant) -> bool:
	if decoder == null or not Flags.integer(id,0,65535): return false
	var rom: PackedByteArray = decoder.rom
	var table := pointer(rom,int(decoder.layout.get("songs",0x3f50)))
	if table < 0: return false
	var header := pointer(rom,table+int(id)*8)
	if header < 0 or header > rom.size()-8: return false
	var tracks := int(rom[header])
	if tracks < 1 or tracks > 16 or header > rom.size()-8-tracks*4: return false
	if pointer(rom,header+4) < 0: return false
	for track in range(tracks):
		if pointer(rom,header+8+track*4) < 0: return false
	return true
