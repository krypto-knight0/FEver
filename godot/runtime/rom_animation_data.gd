extends RefCounted
## Decode timelines and atlas layers together so their frame indices agree.
const MODES := {1:"attack", 3:"critical", 5:"ranged", 6:"ranged_critical", 7:"dodge", 8:"ranged_dodge", 9:"ready", 10:"idle", 11:"ranged_ready", 12:"miss"}

static func fail(decoder: RefCounted, reason: String) -> Dictionary:
	decoder.fail("Animation metadata", reason)
	return {}

static func tokens(decoder: RefCounted, data: PackedByteArray, offsets: Array, mode: int) -> Array:
	var at := int(offsets[mode - 1])
	var end := int(offsets[mode]) if mode < 12 else data.size()
	if at == 0: end = int(offsets[1])
	if end == 0: end = data.size()
	if at < 0 or at > end or end > data.size():
		fail(decoder, "Invalid battle mode bounds.")
		return []
	var result: Array = []
	while at < end:
		if at + 4 > end or result.size() >= 8192:
			fail(decoder, "Truncated or oversized battle timeline.")
			return []
		var word := data.decode_u32(at)
		match word >> 24:
			0x86:
				if at + 12 > end:
					fail(decoder, "Truncated battle frame.")
					return []
				result.append({"ticks":maxi(1, word & 65535), "graphics":data.decode_u32(at + 4), "oam":data.decode_u32(at + 8)})
				at += 12
			0x85:
				result.append({"command":word & 0xffffff})
				at += 4
			0x80: break
			_:
				fail(decoder, "Unknown battle timeline opcode.")
				return []
	return result

static func battle(decoder: RefCounted, record: int, game: String) -> Dictionary:
	if not decoder.require_range(record, 32, "Battle animation record"): return {}
	var table: int = decoder.ptr(record + 12)
	if not decoder.require_range(table, 48, "Battle mode table"): return {}
	var offsets: Array = []
	for i in range(12): offsets.append(decoder.u32(table + i * 4))
	var data: PackedByteArray = decoder.lz(decoder.ptr(record + 16))
	if not decoder.error.is_empty(): return {}
	var frames := {}
	var layers: Array = []
	var modes := {}
	var commands: Array = []
	for mode in MODES:
		var foreground := tokens(decoder, data, offsets, mode)
		var backs: Array = tokens(decoder, data, offsets, mode + 1).filter(func(t): return t.has("graphics")) if mode in [1, 3] else []
		if not decoder.error.is_empty(): return {}
		var index := 0
		var timeline: Array = []
		for token in foreground:
			if token.has("command"):
				timeline.append(token)
				var command: int = int(token.command) & 255
				if command not in commands: commands.append(command)
				continue
			var identity: Array = [token.graphics, token.oam]
			if index < backs.size():
				# FE6 rear OAM shares the foreground VRAM sheet. FE7's existing
				# atlas renderer tracks both script image pointers separately.
				identity += [token.graphics if game == "fe6" else backs[index].graphics, backs[index].oam]
			index += 1
			var key := JSON.stringify(identity)
			if not frames.has(key):
				frames[key] = frames.size()
				var frame: Array = []
				if identity.size() == 4: frame.append([identity[2],identity[3]])
				frame.append([identity[0],identity[1]])
				layers.append(frame)
			if frames.size() > 4096: return fail(decoder, "Battle atlas exceeds its frame limit.")
			timeline.append({"frame":frames[key], "ticks":token.ticks})
		modes[MODES[mode]] = timeline
	commands.sort()
	return {"modes":modes, "commands":commands, "frame_count":frames.size(), "frames":layers}

static func movement(decoder: RefCounted, address: int) -> Dictionary:
	var first: int = decoder.u16(address)
	var modes_at: int = decoder.u16(address + 2)
	if not decoder.error.is_empty(): return {}
	if first < 4 or first >= modes_at or modes_at > 256 or (modes_at - first) % 2 != 0:
		return fail(decoder, "Invalid movement animation header.")
	var earliest := 65536
	for i in range(first, modes_at, 2): earliest = mini(earliest, decoder.u16(address + i))
	var end := first + earliest
	if end < modes_at or (end - modes_at) % 2 != 0 or end - modes_at > 512: return fail(decoder, "Invalid movement mode table.")
	@warning_ignore("integer_division") # Intentional integer truncation.
	var count := (modes_at - first) / 2
	var modes := {}
	var names := ["left", "right", "down", "up", "ready"]
	@warning_ignore("integer_division") # Intentional integer truncation.
	for i in range((end - modes_at) / 2):
		var at: int = address + modes_at + decoder.u16(address + modes_at + i * 2)
		var timeline: Array = []
		var terminated := false
		for step in range(256):
			var ticks: int = decoder.u16(at + step * 4)
			var frame: int = decoder.u16(at + step * 4 + 2)
			if not decoder.error.is_empty(): return {}
			if ticks == 0:
				terminated = true
				break
			if frame >= count: return fail(decoder, "Movement frame exceeds its table.")
			timeline.append({"frame":frame, "ticks":ticks})
		if not terminated: return fail(decoder, "Unterminated movement timeline.")
		if i < names.size(): modes[names[i]] = timeline
	for name in names.slice(0, 4):
		if modes.get(name, []).is_empty(): return fail(decoder, "Missing directional movement timeline.")
	return {"modes":modes, "frame_count":count}
