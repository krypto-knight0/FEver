extends RefCounted
## Reviewed capital chapter adapters. Scripts supply operands and dialogue;
## fingerprinted callbacks supply the bargaining contract and route boundary.
const Native = preload("res://runtime/fe6/rom_fe6_unit_29.gd")
const Groups = preload("res://runtime/rom_deployments.gd")
const Pure = preload("res://runtime/rom_event_predicates.gd")

static func fail(d: RefCounted, reason: String) -> bool:
	d.fail("FE6 capital events",reason)
	return false

static func cmd(d: RefCounted, chapter: int, source: Dictionary, index: int, op: int, words: int) -> int:
	return Native.command(d,chapter,source,index,op,words)

static func story(chapter: int, source: Dictionary, indices: Array) -> Dictionary:
	var parts: Array = []
	for index in indices:
		var selector := source.duplicate()
		selector.command = index; selector.opcode = 7
		parts.append({"source":selector})
	return {"$rom_fe6_story":{"chapter":chapter,"parts":parts}}

static func fe6_unit_39(d: RefCounted, input: Dictionary, chapter: int = 16, source: Dictionary = {"event":"talk","condition":0}) -> bool:
	# Validate the choices' control flow, not just their price operands.
	var jumps := {3:[0x1f,10],4:[0x1f,16],5:[0x1f,24],6:[0x1f,32],9:[0x1c,51],13:[0x20,16],15:[0x1c,44],21:[0x20,24],23:[0x1c,44],29:[0x20,32],31:[0x1c,44],37:[0x20,40],39:[0x1c,44],43:[0x1c,51]}
	for index in jumps:
		var op := int(jumps[index][0])
		var jump := cmd(d,chapter,source,index,op,2 if op == 0x1c else 3)
		var label := cmd(d,chapter,source,int(jumps[index][1]),0x1b,2)
		if jump < 0 or label < 0 or d.u32(jump+4) != d.u32(label+4): return fail(d,"Bargaining branch structure changed.")
	var payment := cmd(d,chapter,source,49,0x17,2)
	var recruit := cmd(d,chapter,source,48,0x2b,3)
	if payment < 0 or recruit < 0: return false
	var callback: int = d.u32(payment+4)
	if callback & 1 == 0 or callback < 0x08000001: return fail(d,"Invalid bargaining callback.")
	var at := (callback-0x08000000)&~1
	var mask: Array = [2,20,46,76,32,58,64,88,94,100,38]
	mask.append_array(range(116,128))
	if not Pure.signature(d,at,128,mask,"839ff6f074d47d8e4dfcfd8e3e50ff0f16acba325a929e512ee916a5f07cbdf5"): return fail(d,"Unrecognized bargaining payment routine.")
	var weaken := Pure.call_target(d,at+34)
	var remove_gold := Pure.call_target(d,at+16)
	if weaken < 0 or remove_gold < 0 or not Pure.signature(d,weaken,16,[],"1007a64b5f66edf6102d5b1ea3ded389e40717701e52910680a46cdbe8194c8b") or not Pure.signature(d,remove_gold,24,[],"9724462a91b51148c3d01a00a0b318f50b912146b8387a27a612e123136341d2"): return fail(d,"Unrecognized bargaining helper.")
	if not Pure.signature(d,0x6bffc,108,[],"48d792aa61620ec0911068a4b47bfc1dff7dad30bbebf7797670a81f1a89ee79"): return fail(d,"Unrecognized recruitment stat adjustment.")
	var character: int = d.u32(recruit+4)
	if character < 1 or character > 255 or d.u32(recruit+8) != 0: return fail(d,"Invalid paid recruit.")
	for offset in [32,58,64,88,94,100]:
		if d.u8(at+offset) != character: return fail(d,"Payment weakens a different character.")
	var costs: Array = [d.u32(at+116),d.u8(at+38)<<5,d.u32(at+120),d.u32(at+124)]
	var entry: Dictionary = input.talks[0]
	entry.erase("offer_dialogue")
	entry.dialogue = story(chapter,source,[1])
	entry.decline_dialogue = story(chapter,source,[41])
	entry.insufficient_dialogue = story(chapter,source,[7])
	entry.recruitment_offers = []
	for i in range(4):
		var query := cmd(d,chapter,source,3+i,0x1f,3)
		var flag := cmd(d,chapter,source,[14,22,30,38][i],0x34,2)
		var choice := cmd(d,chapter,source,[13,21,29,37][i],0x20,3)
		if query < 0 or flag < 0 or choice < 0: return false
		var address: int = d.u32(query+8)
		if address & 1 == 0 or address < 0x08000001: return fail(d,"Invalid price query.")
		var threshold := (address-0x08000000)&~1
		if not Pure.signature(d,threshold,28,[2,3,4,5,16,17,18,19],"12394dc2b44d6b0dd596cfe08f1186f2a2e46f8351565b6ba6d86d5ad1544589"): return fail(d,"Unrecognized gold threshold.")
		var getter := Pure.call_target(d,threshold+2)
		if getter < 0 or not Pure.signature(d,getter,12,[],"08b26ccade12218728daeed46b9f81db972d83c798490d8647dcb747d920a2cf"): return fail(d,"Unrecognized gold getter.")
		if costs[i] != d.u32(threshold+16)+1 or costs[i] < 1 or costs[i] > 999999 or (i > 0 and costs[i] >= costs[i-1]): return fail(d,"Inconsistent bargaining prices.")
		var choice_address: int = d.u32(choice+8)
		if choice_address & 1 == 0 or choice_address < 0x08000001 or not Pure.signature(d,(choice_address-0x08000000)&~1,20,[],"4904c68869c7f4b2cd1c121242a28c16e097872cf3c0b6dc54f6986f770ffa6c"): return fail(d,"Unrecognized bargaining choice.")
		var flag_id: int = d.u32(flag+4)
		if flag_id != d.u8(at+[2,20,46,76][i]) or flag_id < 1 or flag_id >= 100: return fail(d,"Inconsistent bargaining flag.")
		entry.recruitment_offers.append({"cost":costs[i],"stat_penalty":i,"native_flags_set":[flag_id],"dialogue":story(chapter,source,[[11,46],[17,19,46],[25,27,46],[33,35,46]][i])})
	return true

