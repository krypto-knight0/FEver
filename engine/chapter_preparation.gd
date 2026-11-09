extends RefCounted
## Data-only chapter preparation. No scene-tree or rendering calls in workers.
const Battle = preload("res://engine/battle_state.gd")
const Difficulty = preload("res://engine/campaign_difficulty.gd")
const Army = preload("res://engine/army_roster.gd")
const Rogue = preload("res://engine/rogue_mode.gd")

static func read(path: String, mode: String) -> Dictionary:
	if not preload("res://runtime/rom_assets.gd").ensure_resource(path): return {}
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary: return {}
	var chapter := Difficulty.chapter(source, mode)
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(chapter.get("map", ""))))
	if not map is Dictionary or map.is_empty(): return {}
	return {"chapter":chapter,"map":map}

static func handoff(chapter: Dictionary, previous: RefCounted, completed: int, promotions: Dictionary) -> RefCounted:
	var next := Battle.new()
	next.load_chapter(chapter, {}, previous.native_event_state.get("permanent_flags", []))
	Army.transfer(previous, next, bool(previous.rules.permadeath) if not Rogue.active(next) else true)
	if Rogue.active(next): Rogue.setup(next, previous, completed)
	if not chapter.get("campaign_reset", false):
		next.gold = previous.gold
		next.inventory = previous.inventory.duplicate(true)
	next.set_promotion_catalog(promotions)
	next.support_points.merge(previous.support_points, true)
	next.support_ranks.merge(previous.support_ranks, true)
	next.rng.state = previous.rng.state
	return next

static func start(state: RefCounted) -> Dictionary:
	state.apply_chapter_repairs()
	state._run_events("chapter_start")
	return state.serialize(false)
