extends RefCounted
## ENDB enters preparations on chapters whose native header enables it.
## Scene actors are replaced by the native battle army; the carried party is retained.
static func apply(b, command: Dictionary) -> String:
	if b.turn != 1 or b.phase != "player": return "Native preparations require the first player turn."
	for unit in command.players+command.enemies:
		if int(unit.x) >= b.width or int(unit.y) >= b.height: return "Native preparation placement is outside the map."
	# Direct chapter entry has no carried army or playable opening LOAD. Seed
	# the native preparation party only then; never revive a carried casualty.
	if b.Army.all_units(b).is_empty() and b.chapter.get("campaign_roster",{}).is_empty():
		for unit in command.players: b._spawn_unit(unit,true)
	var party: Array = b.Army.all_units(b).filter(func(u):return u.faction == "player")
	b.units = party
	b.chapter.reserve_units = []
	for unit in party: unit.x = 0; unit.y = 0; unit.benched = true
	for unit in command.enemies: b._spawn_unit(unit,true)
	b.chapter.deployment = {"slots":command.players.map(func(u):return {"unit_id":u.id,"x":u.x,"y":u.y}),"forced":["fe7_unit_%d" % {1:3,2:1,3:2}.get(int(b.chapter.get("native_route",1)),3)]}
	b.chapter.deployment_complete = false
	b.Rogue.configure_deployment(b)
	var result: Dictionary = b.Army.deploy(b,b.Army.default_selection(b))
	if not result.get("ok",false): return str(result.get("reason","Invalid preparation formation."))
	b.chapter.deployment_complete = false
	b.chapter.native_preparations_ready = true
	return ""

static func lyn_assets(previous, next) -> void:
	next.chapter.get_or_add("story_flags",{}).fe7_lyn_completed = true
	var spec: Dictionary = next.chapter.lyn_handoff
	var value: int = previous.gold
	var items: Array = previous.inventory.duplicate()
	for unit in previous.Army.all_units(previous):
		if unit.faction != "player" or int(unit.hp) <= 0 or unit.get("escaped",false): continue
		items.append_array(unit.inventory)
		if not unit.weapon.is_empty(): items.append(unit.weapon)
	for item in items:
		value += int(item.get("cost_per_use",0))*(1 if item.get("native_asset_once",false) else int(item.get("uses",0)))
	var flags = preload("res://engine/native_event_flags.gd")
	for flag in spec.clear_flags: flags.set_flag(next.native_event_state,int(flag),false)
	if value > int(spec.thresholds[1]): flags.set_flag(next.native_event_state,int(spec.flags[1]))
	if value > int(spec.thresholds[2]) or (value > int(spec.thresholds[0]) and value <= int(spec.thresholds[1])): flags.set_flag(next.native_event_state,int(spec.flags[0]))
