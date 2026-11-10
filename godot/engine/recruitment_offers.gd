extends RefCounted
## A paid conversation is one atomic action; inspecting offers changes no state.
const Data = preload("res://runtime/rom_data.gd")
const Flags = preload("res://engine/native_event_flags.gd")

static func valid(talk: Dictionary, game: String) -> bool:
	if not talk.has("recruitment_offers"): return true
	var offers: Variant = talk.recruitment_offers
	if not offers is Array or offers.is_empty() or offers.size() > 8: return false
	var last := 1000000
	for offer in offers:
		if not offer is Dictionary or not Data.integer(offer.get("cost"),1,last-1) or not Data.integer(offer.get("stat_penalty"),0,20): return false
		if not offer.get("dialogue") is Array or not Flags.valid_flags(offer.get("native_flags_set",[]),"any",game): return false
		last = int(offer.cost)
	return talk.get("decline_dialogue") is Array and talk.get("insufficient_dialogue") is Array

static func select(talk: Dictionary, choice: int, gold: int) -> Dictionary:
	if choice < 0 or choice > talk.recruitment_offers.size(): return {}
	var result := talk.duplicate(true)
	if choice == talk.recruitment_offers.size():
		result.erase("change_faction")
		result.cost = 0
		result.dialogue.append_array(talk.insufficient_dialogue if gold < int(talk.recruitment_offers.back().cost) else talk.decline_dialogue)
	else:
		var offer: Dictionary = talk.recruitment_offers[choice]
		if gold < int(offer.cost): return {}
		result.cost = offer.cost
		result.stat_penalty = offer.stat_penalty
		result.get_or_add("native_flags_set",[]).append_array(offer.get("native_flags_set",[]))
		result.dialogue.append_array(offer.dialogue)
	return result

static func weaken(unit: Dictionary, amount: int) -> void:
	for stat in ["max_hp","str","skill","speed","def","res","luck"]:
		unit[stat] = maxi(1 if stat == "max_hp" else 0,int(unit[stat])-amount)
	unit.hp = mini(int(unit.hp),int(unit.max_hp))
