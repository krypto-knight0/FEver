extends RefCounted
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
## FE7 support policy, with shared FE6 catalog and lazy conversation readers.
const Shared = preload("res://runtime/dynamic_support_catalog.gd")
const Reader = Shared.Reader
const Pure = preload("res://runtime/fe7/fe7_dynamic_policy.gd")

static func catalog(d: RefCounted, prefix: String, assets: Dictionary) -> Dictionary:
	# Reviewed rank/gain/eligibility routines. Only the two threshold-table
	# pointers are relocatable operands; gameplay patches need their own adapter.
	for spec in [
		[0x26b20,80,[],"128b66f6f88bfa6d5271ac2f9338f0bb3df4f7039c340d4def77a1414a29a1f2"],
		[0x26b70,96,[92,93,94,95],"d9c3b2ec153023e61efe9783624cfe70817810a7ec191fe283b63e2818de6f88"],
		[0x26bd0,52,[],"e6370ebc8ebfb55bd347bbd37da158fb397be5f0b6d2334cb8bef2fdc65b8d78"],
		[0x26c04,124,[104,105,106,107],"89b942781ff3ac8574907bfe1b992c98033be1d9ab087b074dfe7918446e604d"],
		[0x26d24,248,[],"b1c9ed7c3ee4850a0750959e5bd180baf903359e7999a55a08e7919e6c1309d8"]]:
		if not Pure.signature(d,spec[0],spec[1],spec[2],spec[3]):
			d.fail("FE7 supports","Changed native support policy."); return {}
	var thresholds: Array = []
	for index in range(3): thresholds.append(d.u32(d.ptr(Policy.address(d,0x26bcc))+index*4))
	var eligibility: Array = []
	for index in range(3): eligibility.append(d.u32(d.ptr(Policy.address(d,0x26c6c))+index*4))
	if thresholds != [80,160,240] or eligibility != thresholds:
		d.fail("FE7 supports","Unsupported support rank thresholds."); return {}
	var rules := {"supports_enabled":true,"support_thresholds":thresholds,"support_total_cap":5,"support_range":3,
		"support_once_per_map":true,"support_rank_point_bonus":1,"support_chapter_gain_limit":0,"support_gain_counter_multiplier":2}
	return Shared.catalog(d,prefix,assets,"fe7",rules,Policy.address(d,0x26e24))
