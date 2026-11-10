extends RefCounted
## Recognize the native timed-map constructor and import its table and patches.
## Only operands vary; an unknown callback fails import instead of guessing.
const Groups = preload("res://runtime/rom_deployments.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Data = preload("res://runtime/rom_data.gd")
const INITIALIZER := "3a55d30afea5d01ffb7abaf82953477459098c1e5d0bba431bb150a62b0d395e"
const HELPER := "a1ed424303abbc252c2377c2605d5898062dd7afbe213f72dd46655e8dc701ad"
const CORE := "1abd34636f50597b587d0ced6d4dbcef4c36b89989e608771664a06768c957fb"

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("FE6 timed map changes",reason)
	return null

static func read(d: RefCounted, chapter: int, opening: int) -> Variant:
	var command := Groups.command(d,opening,0,"fe6")
	if command.is_empty(): return null
	if command.opcode != 0x17 or command.words != 2: return fail(d,"Missing timed-map initialization callback.")
	var callback: int = d.u32(int(command.offset)+4)
	if callback < 0x08000001 or callback & 1 == 0: return fail(d,"Invalid timed-map callback.")
	var at := (callback-0x08000000)&~1
	if not Pure.signature(d,at,34,[4,8,16,17,18,19,24],INITIALIZER): return fail(d,"Unrecognized timed-map initializer.")
	var helper := Pure.call_target(d,at+16)
	if helper < 0 or not Pure.signature(d,helper,26,[16,17,18,19],HELPER): return fail(d,"Unrecognized timed-map constructor.")
	var core := Pure.call_target(d,helper+16)
	if core < 0 or not Pure.signature(d,core,26,[],CORE): return fail(d,"Unrecognized timed-trap writer.")
	var table := Groups.pointer(d,((at+8)&~3)+d.u8(at+4)*4)
	var count: int = d.u8(at+24)+1
	var off_base: int = d.u8(at+8)
	if table < 0 or count > 32 or off_base < count or off_base+count > 255: return fail(d,"Invalid timed-map range.")
	if not d.require_range(table,count*8,"Timed-map schedule"): return null
	var result: Array = []
	for i in range(count):
		var first: int = d.u32(table+i*8)
		var period: int = d.u32(table+i*8+4)
		if first < 1 or first > 255 or period < 1 or period > 255: return fail(d,"Invalid timed-map delay or interval.")
		var cycle := {"id":"fe6_map_cycle_%d" % i,"first_turn":first,"period":period}
		for side in ["off","on"]:
			var change := off_base+i if side == "off" else i
			var patch: Variant = Data.map_fields(d,{"chapter":chapter,"change":change,"fields":["x","y","width","height","terrain","mask"]},"fe6")
			if patch == null: return null
			patch.id = change
			patch.cycle_id = cycle.id
			patch.image = "res://content/fe6/maps/chapter%d_change_%d.png" % [chapter,change]
			cycle[side] = patch
		result.append(cycle)
	return result

