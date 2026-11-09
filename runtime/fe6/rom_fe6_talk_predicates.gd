extends RefCounted
## Reviewed compound talk callbacks: flag, living-unit search and participant
## selection. Recognize complete Thumb bodies; never execute arbitrary ROM code.
const Pure = preload("res://runtime/rom_event_predicates.gd")
const Flags = preload("res://engine/native_event_flags.gd")
const EAST := "687f261b5c7a75062ffc681f466f3f3817b5dce57ff3008f232bba2fb5f46871"
const WEST := "4cb90e495b2c32e03b614e566dd7d8e4554164fb6fe512f2e1e92fe6efd4c12e"
const FLAG_GETTER := "ff7c3ec7bc08c73537819be46301aeb70d54019d9fd46b43e62b5dbedc762e60"
const PARTICIPANTS := "32e41b7d3c52a60644812e6c2b0c6d6b6c033cf99067c48254392994b71ecf2f"
const TWO_WAY := "55c64afb0931eaea40f95e3328a920c632e3206e6ca63b2cd93e6264813e89e7"

static func two_way(d: RefCounted, callback: int, reverse: bool) -> Variant:
	if callback & 1 == 0 or callback < 0x08000001: return fail(d,"Expected a Thumb talk callback.")
	var at := (callback-0x08000000)&~1
	if not Pure.signature(d,at,58,[4,5,6,7,16,18,20,21,22,23,32,34,36,37,38,39],TWO_WAY): return fail(d,"Unrecognized two-way talk callback.")
	var presence := Pure.call_target(d,at+4)
	var participants := Pure.call_target(d,at+20)
	if presence < 0 or participants < 0 or Pure.call_target(d,at+36) != participants: return fail(d,"Invalid two-way talk helpers.")
	if not Pure.signature(d,participants,40,[],PARTICIPANTS): return fail(d,"Unrecognized participant selector.")
	var query: Variant = Pure.describe(d,0x08000001+presence,"fe6")
	if query == null: return null
	if query.first != 1 or query.last != 63 or query.excluded_state != 12 or query.character == 0: return fail(d,"Unsupported two-way presence query.")
	var pair := at+(32 if reverse else 16)
	if d.u8(pair) == 0 or d.u8(pair+2) == 0: return fail(d,"Invalid two-way actors.")
	return {"from":"fe6_unit_%d" % d.u8(pair),"to":"fe6_unit_%d" % d.u8(pair+2),"conditions":{"native_unit_presence":[{"kind":"presence","character":query.character,"factions":["player"]}]}}

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("FE6 talk predicate",reason)
	return null

static func describe(d: RefCounted, callback: int) -> Variant:
	if callback & 1 == 0 or callback < 0x08000001: return fail(d,"Expected a Thumb callback.")
	var at := (callback-0x08000000)&~1
	if not d.require_range(at,48,"FE6 talk callback"): return null
	# The west compiler omits a redundant byte normalization after the presence
	# helper. All branches, stack handling and return paths remain fingerprinted.
	var participant_call := 32
	if at+52 > d.rom.size() or not Pure.signature(d,at,52,[4,6,7,8,9,15,16,17,18,19,28,30,32,33,34,35],EAST):
		if not d.error.is_empty(): return null
		participant_call = 30
		if not Pure.signature(d,at,48,[4,6,7,8,9,15,16,17,18,19,26,28,30,31,32,33],WEST):
			return fail(d,"Unrecognized compound talk callback.")
	var flag_getter := Pure.call_target(d,at+6)
	var presence := Pure.call_target(d,at+16)
	var participants := Pure.call_target(d,at+participant_call)
	if flag_getter < 0 or presence < 0 or participants < 0: return fail(d,"Invalid talk helper call.")
	if not Pure.signature(d,flag_getter,24,[],FLAG_GETTER): return fail(d,"Unrecognized flag getter.")
	# This helper checks from/to and selects the condition row's script and
	# completion flag. Those outputs are supplied by the ordinary talk importer.
	if not Pure.signature(d,participants,40,[],PARTICIPANTS): return fail(d,"Unrecognized participant selector.")
	var query: Variant = Pure.describe(d,0x08000000+presence+1,"fe6")
	if query == null: return null
	var factions: Array
	if query.first == 1 and query.last == 63: factions = ["player"]
	elif query.first == 65 and query.last == 191: factions = ["neutral","enemy"]
	else: return fail(d,"Unit search does not cover a supported faction bank.")
	if query.excluded_state != 4 or query.character == 0: return fail(d,"Unit search is not a living-character predicate.")
	var flag: int = d.u8(at+4)
	var branch: int = d.u8(at+15)
	var from_character: int = d.u8(at+participant_call-4)
	var to_character: int = d.u8(at+participant_call-2)
	if not Flags.valid_id(flag,"any","fe6") or branch not in [0xd0,0xd1] or from_character == 0 or to_character == 0:
		return fail(d,"Invalid flag or participant operand.")
	var conditions := {"native_unit_presence":[{"kind":"presence","character":query.character,"factions":factions}]}
	conditions["native_flags_all" if branch == 0xd0 else "native_flags_not"] = [flag]
	return {"from":"fe6_unit_%d" % from_character,"to":"fe6_unit_%d" % to_character,"conditions":conditions}
