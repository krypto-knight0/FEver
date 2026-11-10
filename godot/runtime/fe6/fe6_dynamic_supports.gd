extends RefCounted
## FE6 policies around the shared runtime support catalog.
const Shared = preload("res://runtime/dynamic_support_catalog.gd")
const Reader = Shared.Reader
const AFFINITIES = Shared.AFFINITIES
const STATS = Shared.STATS
const RULES := {"supports_enabled":true,"support_thresholds":[60,120,200],"support_total_cap":5,"support_range":3,
	"support_once_per_map":false,"support_rank_point_bonus":1,"support_chapter_gain_limit":250,"support_gain_counter_multiplier":2}

static func catalog(d: RefCounted, prefix: String, assets: Dictionary) -> Dictionary:
	return Shared.catalog(d,prefix,assets,"fe6",RULES,0x22dbc)
