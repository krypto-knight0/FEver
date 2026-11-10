extends RefCounted
## FE6 route events: bounded native branches, live predicates and ROM operands.
## Scene-only movement is collapsed before deployment; arbitrary ASM is rejected.
const Finale = preload("res://runtime/fe6/rom_fe6_finale.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Data = preload("res://runtime/rom_data.gd")
const WIDTHS := {3:2,4:2,5:1,6:1,7:2,8:2,0x12:2,0x13:2,0x17:2,0x19:2,0x1b:2,0x1c:2,
	0x1f:3,0x20:3,0x22:3,0x23:3,0x24:3,0x26:2,0x27:3,0x28:2,0x29:2,0x2a:2,
	0x2b:3,0x30:2,0x32:3,0x33:3,0x34:2,0x35:2,0x36:2,0x37:2,0x38:1,0x3c:2,0x3d:2,0x3e:1,0x4c:2}

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("FE6 route events",reason)
	return null

static func query(d: RefCounted, callback: int) -> Variant:
	if callback < 0x08000001 or callback & 1 == 0: return fail(d,"Invalid event predicate.")
	var at := (callback-0x08000000)&~1
	if Finale.recognized(at): return Finale.query(d,at)
	if Pure.signature(d,at,20,[],"9232fb07166b2340ee1ed3ac32935afd34f6b9573c9ff5d4f3093a118a314e04"):
		return {"kind":"phase","value":"player"}
	if Pure.signature(d,at,20,[4],"bd3de45dc343de238d557553cbc7b51df585d0ddc259058998b4c1852282dc75"):
		return {"kind":"turn_after","value":d.u8(at+4)}
	if at == 0x6d3b4:
		if not Pure.signature(d,at,44,[],"06914a32232b8a59053c8789cb71bd9a566836082803cde03c196a0d29c9d317") or not Pure.signature(d,0x6d398,28,[],"4aca061a0d08fd45f00e628c0ba10a3a6cc797483eb160cb3982a380a5b6cfd2"): return fail(d,"Unrecognized ambush lottery.")
		return {"kind":"ambush_roll","denominator":d.u8(0x6d39e),"cap":d.u8(at+16)}
	var found: Variant = Pure.describe(d,callback,"fe6")
	if found == null: return null
	if found.character == 0 or found.excluded_state not in [4,12]: return fail(d,"Unsupported presence mask.")
	var factions: Array
	if found.first == 1 and found.last == 63: factions = ["player"]
	elif found.first == 65 and found.last == 191: factions = ["enemy","neutral"]
	else: return fail(d,"Unsupported presence slot range.")
	return {"kind":"roster_presence" if found.excluded_state == 4 and factions == ["player"] else "presence","character":found.character,"factions":factions}

static func callback_command(d: RefCounted, address: int) -> Variant:
	if address < 0x08000001 or address & 1 == 0: return fail(d,"Invalid event callback.")
	var at := (address-0x08000000)&~1
	if Finale.recognized(at): return Finale.action(d,at)
	# Reviewed presentation helpers: background transitions and map visibility.
	var visual := {0x12798:[24,"26207f52a69eecd14c035d623ce0a9338a26a0b462e72e3c5f707d73653090f6"],0x12780:[24,"a8f0863cd803d51fb75e07785dc4154b5776663c388bb40383a3d8237f407795"],0x127b0:[24,"cb611401c2c32868402075baf5a45e8a4f1e68f885f4fa1ace84ab2952c089e7"],0x6cfb8:[24,"c2afaab161e25d1820e66693e47b70770774194601db440ac989ce030d0aaa0a"]}
	if visual.has(at):
		if not Pure.signature(d,at,visual[at][0],[],visual[at][1]): return fail(d,"Presentation callback changed.")
		return {"op":"nop"}
	if at == 0x6d3e0:
		if not Pure.signature(d,at,60,[],"14c73ccd449ea1be742a937bfd74b9250a5c8172b892ab4e4d5f722edb598e56"): return fail(d,"Ambush counter callback changed.")
		return {"op":"ambush_begin","normal_limit":d.u8(at+42),"hard_limit":d.u8(at+30),"flag":d.u8(at+46)}
	if at == 0x6d6b4:
		if not Pure.signature(d,at,36,[],"b3b23928272f0fd2125b0ecea6b63443e10d1ecf7af1a38409279f0fd21b4d68"): return fail(d,"Seize lottery callback changed.")
		var table := Groups.pointer(d,at+32)
		if table < 0: return null
		var flags: Array = []
		for i in range(d.u8(at+8)):
			if not d.require_range(table+i*4,4,"Seize flag table"): return null
			flags.append(d.u32(table+i*4))
		return {"op":"random_flag","flags":flags}
	return fail(d,"Unsupported event callback at %x." % at)

