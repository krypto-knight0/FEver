extends RefCounted
## Native chapter and campaign flags. Producer history prevents a cleared flag from
## being asserted again merely because its dead unit or opened door still exists.

static func game(chapter: Dictionary) -> String:
	return "fe6" if str(chapter.get("id","")).begins_with("fe6_") else "fe7"

static func empty_state(profile: String = "fe7") -> Dictionary:
	var state := {"flags":[], "permanent_flags":[], "defeats":[], "sites":[]}
	if profile == "fe6": state.game = profile
	return state

static func from_save(value: Dictionary, profile: String = "fe7") -> Dictionary:
	var state := value.duplicate(true)
	if profile == "fe6": state.game = profile
	# JSON numbers are floats; flag membership must use one canonical type.
	state.flags = state.flags.map(func(flag): return int(flag))
	state.flags.sort()
	state.permanent_flags = state.permanent_flags.map(func(flag): return int(flag))
	state.permanent_flags.sort()
	return state

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

# Native storage: FE6 has 4 local / 5 permanent bytes; FE7 uses IDs 1-99
# locally and 8 permanent bytes. Do not let FE6 writes spill outside its banks.
# Zero and 100 are native no-ops, never stored as state.
static func valid_id(value: Variant, scope: String = "any", profile: String = "fe7") -> bool:
	return (scope != "campaign" and integer(value,1,32 if profile == "fe6" else 99)) or (scope != "chapter" and integer(value,101,140 if profile == "fe6" else 164))

static func valid_flags(value: Variant, scope: String = "any", profile: String = "fe7") -> bool:
	if not value is Array or value.size() > 163: return false
	var seen := {}
	for flag in value:
		if not valid_id(flag,scope,profile) or seen.has(int(flag)): return false
		seen[int(flag)] = true
	return true

static func valid_state(value: Variant, profile: String = "fe7") -> bool:
	if not value is Dictionary or value.size() != (5 if profile == "fe6" else 4) or not valid_flags(value.get("flags"),"chapter",profile) or not valid_flags(value.get("permanent_flags"),"campaign",profile): return false
	if value.get("game",profile) != profile: return false
	for key in value:
		if key not in ["flags","permanent_flags","defeats","sites","game"]: return false
	for key in ["defeats","sites"]:
		if not value.get(key) is Array or value[key].size() > 16384: return false
		var seen := {}
		for id in value[key]:
			if not id is String or id.is_empty() or id.length() > 512 or seen.has(id): return false
			seen[id] = true
	return true

static func valid_bindings(value: Variant, profile: String = "fe7") -> bool:
	if not value is Dictionary: return false
	for key in value:
		if key not in ["defeats","sites"]: return false
	for key in ["defeats","sites"]:
		if not value.get(key,[]) is Array or value.get(key,[]).size() > 512: return false
		var seen := {}
		for entry in value.get(key,[]):
			if not entry is Dictionary or entry.size() != 2 or not valid_id(entry.get("flag"),"any",profile): return false
			var id: Variant = entry.get("character" if key == "defeats" else "id")
			if key == "defeats":
				if not integer(id,1,255): return false
			elif not id is String or id.is_empty(): return false
			if seen.has(str(id)): return false
			seen[str(id)] = true
	return true

static func valid_condition(value: Variant, profile: String = "fe7") -> bool:
	if not value is Dictionary or not valid_flags(value.get("flags"),"any",profile) or value.flags.is_empty(): return false
	for key in value:
		if key not in ["flags","min","max"]: return false
	return integer(value.get("min",0),0,value.flags.size()) and integer(value.get("max",value.flags.size()),0,value.flags.size()) and value.get("min",0) <= value.get("max",value.flags.size())

static func valid_event(event: Dictionary, profile: String = "fe7") -> bool:
	var conditions: Dictionary = event.get("conditions",{})
	if conditions.has("native_flag_count") and not valid_condition(conditions.native_flag_count,profile): return false
	for key in ["native_flags_all","native_flags_not"]:
		if not valid_flags(conditions.get(key,[]),"any",profile): return false
	var absent: Array = conditions.get("native_flags_not",[]).map(func(flag):return int(flag))
	for flag in conditions.get("native_flags_all",[]):
		if absent.has(int(flag)): return false
	if not valid_flags(event.get("native_flags_set",[]),"any",profile) or not valid_flags(event.get("native_flags_clear",[]),"any",profile): return false
	var cleared: Array = event.get("native_flags_clear",[]).map(func(flag): return int(flag))
	for flag in event.get("native_flags_set",[]):
		if cleared.has(int(flag)): return false
	return true

static func has_flag(state: Dictionary, flag: int) -> bool:
	return state.get("permanent_flags" if flag >= 101 else "flags",[]).has(flag) if valid_id(flag,"any",str(state.get("game","fe7"))) else false

static func set_flag(state: Dictionary, flag: int, enabled: bool = true) -> void:
	if not valid_id(flag,"any",str(state.get("game","fe7"))): return
	var bank: Array = state.get_or_add("permanent_flags" if flag >= 101 else "flags",[])
	if enabled and not bank.has(flag):
		bank.append(flag)
		bank.sort()
	elif not enabled: bank.erase(flag)

static func carry(previous, next) -> void:
	# Carry only permanent bits. Local flags and producer history belong to the map.
	if next.native_flags_inherited or game(previous.chapter) != game(next.chapter): return
	synchronize(previous)
	next.native_event_state.permanent_flags = previous.native_event_state.get("permanent_flags",[]).duplicate()
	next.native_flags_inherited = true

static func matches(state: Dictionary, condition: Dictionary) -> bool:
	var count := 0
	for flag in condition.flags:
		if has_flag(state,int(flag)): count += 1
	return count >= int(condition.get("min",0)) and count <= int(condition.get("max",condition.flags.size()))

static func defeat(b, unit: Dictionary) -> void:
	if int(unit.get("hp",1)) > 0 or unit.get("escaped",false) or unit.get("benched",false): return
	var id := str(unit.get("id",""))
	if id.is_empty() or b.native_event_state.defeats.has(id): return
	for binding in b.chapter.get("native_flag_bindings",{}).get("defeats",[]):
		if int(unit.get("rom_character_id",0)) != int(binding.character): continue
		if not b.native_event_state.defeats.has(id): b.native_event_state.defeats.append(id)
		set_flag(b.native_event_state,int(binding.flag))

static func site(b, interaction: Dictionary) -> void:
	if interaction.get("native_opened",false): return # Scripted terrain changes are not interactions.
	if interaction.get("native_visit_event",false): return # The visit program owns this flag.
	if not interaction.get("used",false) or interaction.get("destroyed",false) or interaction.get("closed_without_visit",false): return
	var id := str(interaction.get("id",""))
	if b.native_event_state.sites.has(id): return
	for binding in b.chapter.get("native_flag_bindings",{}).get("sites",[]):
		if binding.id != id: continue
		b.native_event_state.sites.append(id)
		set_flag(b.native_event_state,int(binding.flag))

static func synchronize(b) -> void:
	var bindings: Dictionary = b.chapter.get("native_flag_bindings",{})
	if not bindings.get("defeats",[]).is_empty():
		for unit in b.units: defeat(b,unit)
	if not bindings.get("sites",[]).is_empty():
		for interaction in b.interactions: site(b,interaction)

static func effects(state: Dictionary, event: Dictionary) -> void:
	for flag in event.get("native_flags_set",[]): set_flag(state,int(flag))
	for flag in event.get("native_flags_clear",[]): set_flag(state,int(flag),false)
