extends RefCounted
## Decode reviewed unrolled trap constructors; never execute cartridge ASM.
const Groups = preload("res://runtime/rom_deployments.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const FIRE := "0802a6d79d41e65319e44662d11f124e989ad0d74bfd652dd07b3608e5da83e3"
const GAS := "6a0ea19a848ab356a0d3854b2c295e5137c972c18801be804a907419f3d0f9e0"
const CORE := "1abd34636f50597b587d0ced6d4dbcef4c36b89989e608771664a06768c957fb"

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("FE6 trap imports",reason)
	return null

static func helper(d: RefCounted, call_at: int, fire: bool) -> int:
	var at := Pure.call_target(d,call_at)
	if at < 0: return -1
	var width := 26 if fire else 32
	var mask := [8,16,17,18,19] if fire else [12,20,21,22,23]
	if not Pure.signature(d,at,width,mask,FIRE if fire else GAS):
		fail(d,"Unrecognized trap constructor."); return -1
	var core := Pure.call_target(d,at+(16 if fire else 20))
	if core < 0 or not Pure.signature(d,core,26,[],CORE):
		fail(d,"Unrecognized trap record writer."); return -1
	return d.u8(at+(8 if fire else 12))

static func read(d: RefCounted, opening: int, kind: String) -> Variant:
	if kind not in ["fire","poison_gas","light_arrow"]: return fail(d,"Unknown trap family.")
	var command := Groups.command(d,opening,0,"fe6")
	if command.is_empty(): return null
	if command.opcode != 0x17 or command.words != 2: return fail(d,"Opening has no reviewed trap callback.")
	var callback: int = d.u32(int(command.offset)+4)
	if callback & 1 == 0 or callback < 0x08000001: return fail(d,"Invalid trap callback.")
	var at := (callback-0x08000000)&~1
	if kind == "light_arrow": return arrows(d,at)
	var fire := kind == "fire"
	var period := 0
	if fire:
		if d.u16(at) != 0xb500: return fail(d,"Unrecognized fire initialization.")
		at += 2
	else:
		if d.u16(at) != 0xb510 or d.u16(at+2) != 0xb081 or d.u16(at+4)&0xff00 != 0x2400: return fail(d,"Unrecognized gas initialization.")
		period = d.u8(at+4)
		if period == 0: return fail(d,"Invalid gas period.")
		at += 6
	var result: Array = []
	for i in range(65):
		if not d.require_range(at,14,"Trap initializer"): return null
		if fire and d.u16(at) == 0xbc01:
			if d.u16(at+2) != 0x4700: return fail(d,"Invalid fire callback return.")
			return result
		if not fire and d.u16(at) == 0xb001:
			if d.u16(at+2) != 0xbc10 or d.u16(at+4) != 0xbc01 or d.u16(at+6) != 0x4700: return fail(d,"Invalid gas callback return.")
			return result
		if i == 64: return fail(d,"Too many native traps.")
		if not fire:
			if d.u16(at) != 0x9400: return fail(d,"Invalid gas period argument.")
			at += 2
		var values: Array = []
		for register in range(4):
			if d.u16(at+register*2)&0xff00 != 0x2000+register*0x100: return fail(d,"Unsupported trap argument instruction.")
			values.append(d.u8(at+register*2))
		var amount := helper(d,at+8,fire)
		if amount <= 0: return fail(d,"Invalid trap damage or range.")
		if fire:
			if values[3] == 0: return fail(d,"Invalid fire period.")
			result.append({"type":kind,"x":values[0],"y":values[1],"first_turn":values[2],"period":values[3],"damage":amount})
		else:
			if values[2] > 3: return fail(d,"Invalid poison-gas direction.")
			result.append({"type":kind,"x":values[0],"y":values[1],"direction":values[2],"first_turn":values[3],"period":period,"length":amount,"damage":0})
		at += 12
	return fail(d,"Unterminated trap initialization.")

static func arrows(d: RefCounted, at: int) -> Variant:
	if d.u16(at) != 0xb500: return fail(d,"Unrecognized arrow initialization.")
	at += 2
	var result: Array = []
	for i in range(65):
		if not d.require_range(at,10,"Arrow initializer"): return null
		if d.u16(at) == 0xbc01:
			if d.u16(at+2) != 0x4700: return fail(d,"Invalid arrow callback return.")
			return result
		if i == 64: return fail(d,"Too many arrow traps.")
		for register in range(3):
			if d.u16(at+register*2)&0xff00 != 0x2000+register*0x100: return fail(d,"Unsupported arrow argument.")
		var helper_at := Pure.call_target(d,at+6)
		if helper_at < 0 or not Pure.signature(d,helper_at,28,[8,18,19,20,21],"0f8d3aea8e37a9b2298b2badd37a62904b0c116a95cea7ab75e4fd555d20409a"): return fail(d,"Unrecognized arrow constructor.")
		var core := Pure.call_target(d,helper_at+18)
		if core < 0 or not Pure.signature(d,core,26,[],CORE): return fail(d,"Unrecognized arrow writer.")
		var first: int = d.u8(at+2)
		var period: int = d.u8(at+4)
		var damage: int = d.u8(helper_at+8)
		if first == 0 or period == 0 or damage == 0: return fail(d,"Invalid arrow timing or damage.")
		result.append({"type":"light_arrow","x":d.u8(at),"y":0,"first_turn":first,"period":period,"damage":damage})
		at += 10
	return fail(d,"Unterminated arrow initialization.")
