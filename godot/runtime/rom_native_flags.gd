extends RefCounted
## Import reviewed chapter-flag producers and a pure recruitment count query.
## This recognizes bounded native programs; it does not execute arbitrary ASM.
const Groups = preload("res://runtime/rom_deployments.gd")
const Predicates = preload("res://runtime/rom_event_predicates.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const COUNTERS := [
	{"size":60,"operands":[2,18,32],"threshold":48,"hash":"4c3f8a1c456c75d95384560df52e6ca233844b0d4f906989b4a126b73623843c"},
	{"size":146,"operands":[2,18,32,46,60,74,88,102,116],"threshold":130,"hash":"ed5f0701075830b6fdf74fed4de7936199b763c42e339ea9d58a33b0372b99b8"}]
const GETTER := "ff7c3ec7bc08c73537819be46301aeb70d54019d9fd46b43e62b5dbedc762e60"
const CHAPTER_GETTER := "8c688d4656656ba16bde98783e76cc0cda70bac38b37f7666a09c10e27ad28f2"
const PERMANENT_GETTER := "a7ed91580b0314b005f529a82639e7fc4a6ff0cf08de861fb4ebd41dfc988b5c"

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("ROM native flags",reason)
	return null

static func counter(d: RefCounted, callback: int) -> Variant:
	if callback < 0x08000001 or callback >= 0x08000000+d.rom.size() or callback & 1 == 0: return fail(d,"Expected a ROM Thumb flag query.")
	var at := (callback-0x08000000) & ~1
	# Prisoner rewards share a three-death-flag counter through small wrappers.
	# Decode the calls and operands; reject changes to the actual computation.
	var zero := Predicates.signature(d,at,22,[2,3,4,5],"7ffa6ed2fa637362f18f914498246649ef1ca8462554f0903930622f0b06ac03")
	var bounded := Predicates.signature(d,at,24,[2,3,4,5,12],"439447bee9e34e164a9d6ea71f4c5c5809f1f9b5b0372e98be21a5a218e68794")
	if zero or bounded:
		var target := Predicates.call_target(d,at+2)
		if target < 0 or not Predicates.signature(d,target,58,[2,18,32,4,5,6,7,20,21,22,23,34,35,36,37],"baa48f03a86fa4d457ba84379d802d8385e22677053801c939651a95be3d9290"): return fail(d,"Unrecognized prisoner counter.")
		var flags: Array = []
		for operand in [2,18,32]:
			var flag: int = d.u8(target+operand)
			var getter := Predicates.call_target(d,target+operand+2)
			if not Flags.valid_id(flag,"chapter") or flags.has(flag) or getter < 0 or not Predicates.signature(d,getter,24,[],GETTER): return fail(d,"Invalid prisoner flag lookup.")
			var storage := Predicates.call_target(d,getter+12)
			if storage < 0 or not Predicates.signature(d,storage,60,[],"376ecee7dcf8f69fe03f4dff05eb2c11dd0ac36a504cf20b32a3f22eb6d9a5f5" if d.layout.get("event_variant","") == "fe7j" else CHAPTER_GETTER): return fail(d,"Unrecognized prisoner flag storage.")
			flags.append(flag)
		var threshold: int = 0 if zero else d.u8(at+12)
		if threshold >= flags.size(): return fail(d,"Invalid prisoner count threshold.")
		return {"flags":flags,"threshold":threshold}
	for shape in COUNTERS:
		var mask: Array = shape.operands.duplicate()
		mask.append(shape.threshold)
		for operand in shape.operands:
			for byte in range(2,6): mask.append(operand+byte)
		if at+int(shape.size) > d.rom.size(): continue
		if not Predicates.signature(d,at,int(shape.size),mask,shape.hash): continue
		var flags: Array = []
		for operand in shape.operands:
			var flag: int = d.u8(at+int(operand))
			var getter := Predicates.call_target(d,at+int(operand)+2)
			if not Flags.valid_id(flag) or flags.has(flag): return fail(d,"Query requires distinct supported native flags.")
			if getter < 0 or not Predicates.signature(d,getter,24,[],GETTER): return fail(d,"Unrecognized native flag reader.")
			var chapter_getter := Predicates.call_target(d,getter+(6 if flag >= 101 else 12))
			if chapter_getter < 0 or not Predicates.signature(d,chapter_getter,60,[],PERMANENT_GETTER if flag >= 101 else CHAPTER_GETTER): return fail(d,"Unrecognized native flag storage query.")
			var bits := Groups.pointer(d,chapter_getter+52)
			if bits < 0 or not d.require_range(bits,8,"Flag bit masks"): return null
			for bit in range(8):
				if d.u8(bits+bit) != 1 << bit: return fail(d,"Unsupported native flag bit masks.")
			flags.append(flag)
		var threshold: int = d.u8(at+int(shape.threshold))
		if threshold >= flags.size(): return fail(d,"Unsupported always-true recruitment query.")
		return {"flags":flags,"threshold":threshold}
	return fail(d,"Unrecognized recruitment flag-count callback.")
