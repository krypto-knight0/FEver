extends RefCounted
## Recognize a reviewed pure unit-presence query, without executing Thumb code.
const Data = preload("res://runtime/rom_data.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
# Digests cover complete instruction bodies, masking only decoded operands.
const WRAPPER := "13d953211a871d3b398ddda354fd5cee98c9cabd12f31bb600fbbd11a251c660"
const SEARCH := "0e2e22f4743af9c15d4ecd9d17a4da9f8355be3676fc6c94bdad810706a20f28"
# FE6 uses a halfword state load; fingerprint its complete 60-byte search body.
const FE6_SEARCH := "dc86073a3f292b34e1a7e50961569ed90236b520b5ded5df201ea583c6d21b08"
const GETTER := "d8b2113a7179ee9ccfe7fc2e6558015332e8866bd488c21b6acfce466fb268ad"
const AFFILIATION := "296d8d1d996308b1e91eafd2dd5770e145349efe6624771cebc7676fed992db5"

static func affiliation(d: RefCounted, callback: int) -> Variant:
	var at := (callback-0x08000000) & ~1
	if not signature(d,at,28,[2,4,5,6,7],AFFILIATION): return fail(d,"Unrecognized affiliation query.")
	var getter := call_target(d,at+4)
	# GetUnitByCharId searches slots 1..255, including dead units. The complete
	# body includes its unit-pointer-table literal; do not confuse it with the
	# living-player search used by recruitment conversations.
	if getter < 0 or not signature(d,getter,60,[],"72e9adeb74537bc9b53e6c91d6b232e2e6b178e2dd0ec09e839988d57e8427dd"): return fail(d,"Unrecognized character lookup.")
	var character: int = d.u8(at+2)
	if character == 0: return fail(d,"Affiliation query requires a character.")
	return {"kind":"affiliation","character":character,"faction":"player"}

static func fail(d: RefCounted, reason: String) -> Variant:
	d.fail("ROM event predicate", "Opaque or invalid unit predicate: " + reason)
	return null

static func signature(d: RefCounted, at: int, size: int, operands: Array, expected: String) -> bool:
	if not d.require_range(at,size,"Predicate instructions"): return false
	var bytes: PackedByteArray = d.rom.slice(at,at+size)
	for offset in operands: bytes[int(offset)] = 0
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode() == expected

static func call_target(d: RefCounted, at: int) -> int:
	if not d.require_range(at,4,"Predicate call"): return -1
	var high: int = d.u16(at)
	var low: int = d.u16(at+2)
	if high & 0xf800 != 0xf000 or low & 0xf800 != 0xf800: return -1
	var displacement := high & 0x7ff
	if displacement & 0x400: displacement -= 0x800
	var target := at+4+(displacement<<12)+((low & 0x7ff)<<1)
	return target if d.require_range(target,2,"Predicate call target") else -1

static func describe(d: RefCounted, callback: int, game: String = "fe7") -> Variant:
	if game not in ["fe6","fe7"]: return fail(d,"Unknown predicate layout.")
	if callback < 0x08000001 or callback >= 0x08000000+d.rom.size() or callback & 1 == 0: return fail(d,"Expected a ROM Thumb callback.")
	var at := (callback-0x08000000) & ~1
	if not signature(d,at,16,[2,4,5,6,7],WRAPPER): return fail(d,"Unrecognized query wrapper.")
	var search := call_target(d,at+4)
	var last_operand := 48 if game == "fe6" else 46
	if search < 0 or not signature(d,search,60 if game == "fe6" else 58,[6,10,11,12,13,26,last_operand],FE6_SEARCH if game == "fe6" else SEARCH): return fail(d,"Unrecognized unit search.")
	var getter := call_target(d,search+10)
	if getter < 0 or not signature(d,getter,14,[0],GETTER): return fail(d,"Unrecognized unit-slot lookup.")
	var literal := ((getter+4) & ~3)+int(d.u8(getter))*4
	if not d.require_range(literal,4,"Unit-slot table literal"): return null
	var table: int = d.ptr(literal)
	if table % 4 or not d.require_range(table,256*4,"Unit-slot table"): return fail(d,"Invalid unit-slot table.")
	var first: int = d.u8(search+6)
	var last: int = d.u8(search+last_operand)
	var mask: int = d.u8(search+26)
	if first == 0 or first > last or mask == 0: return fail(d,"Invalid unit search bounds or state mask.")
	var seen := {}
	for slot in range(first,last+1):
		var address: int = d.u32(table+slot*4)
		if address == 0: continue
		if address % 4 or not ((address >= 0x02000000 and address < 0x02040000) or (address >= 0x03000000 and address < 0x03008000)) or seen.has(address): return fail(d,"Unsupported unit-slot pointer or alias.")
		seen[address] = true
	return {"character":d.u8(at+2),"first":first,"last":last,"excluded_state":mask,"table":table}

static func snapshot(d: RefCounted, context: Dictionary) -> Variant:
	if context.has("units") == context.has("unit_groups"): return fail(d,"Provide exactly one explicit unit snapshot or canonical ROM group list.")
	var units: Variant = context.get("units",[])
	if context.has("unit_groups"):
		var groups: Variant = context.unit_groups
		if not groups is Array or groups.size() > 63: return fail(d,"Invalid canonical unit groups.")
		for group in groups:
			for at in Groups.group(d,group,"fe7"):
				if (int(d.u8(at+3))>>1) & 3 != 0: continue
				units.append({"slot":units.size()+1,"character":d.u8(at),"state":0})
			if not d.error.is_empty(): return null
		if units.size() > 63: return fail(d,"Canonical player roster exceeds native slots.")
	if not units is Array or units.size() > 255: return fail(d,"Invalid unit snapshot.")
	var slots := {}
	for unit in units:
		if not unit is Dictionary or unit.size() != 3 or not Data.integer(unit.get("slot"),1,255) or not Data.integer(unit.get("character"),0,255) or not Data.integer(unit.get("state"),0,0xffffffff): return fail(d,"Invalid unit snapshot entry.")
		if slots.has(int(unit.slot)): return fail(d,"Duplicate native unit slot.")
		slots[int(unit.slot)] = true
	return units

static func evaluate(d: RefCounted, callback: int, context: Dictionary) -> Variant:
	var query: Variant = describe(d,callback)
	if query == null: return null
	var units: Variant = snapshot(d,context)
	if units == null: return null
	if context.has("unit_groups"):
		for unit in units:
			if d.u32(int(query.table)+int(unit.slot)*4) == 0: return fail(d,"Canonical roster exceeds allocated native player slots.")
	for unit in units:
		var allocated: bool = d.u32(int(query.table)+int(unit.slot)*4) != 0
		if allocated and int(unit.slot) >= int(query.first) and int(unit.slot) <= int(query.last) and int(unit.character) != 0 and int(unit.character) == int(query.character) and (int(unit.state) & int(query.excluded_state)) == 0: return true
	return false
