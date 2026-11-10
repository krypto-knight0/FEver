extends RefCounted
## Standard FE6 title layout, following live pointer operands (including repoints).
const Decoder = preload("res://runtime/fe6/fe6_decoder.gd")

static func layers(d: RefCounted) -> Dictionary:
	var result := {"background":{"kind":"fe6_title_bg","graphics":d.ptr(0x9b494),"palette":d.ptr(0x9b498)}}
	for entry in [["logo",0x9b484],["shadow",0x9b488],["sword",0x9b48c]]:
		result[entry[0]] = {"kind":"fe6_title_bg","graphics":d.ptr(0x9b480),"palette":d.ptr(0x9b490),"tsa":d.ptr(entry[1])}
	for recipe in result.values():
		if not d.require_range(recipe.graphics,4,"Title graphics") or not d.require_range(recipe.palette,256 if recipe.has("tsa") else 32,"Title palette"): return {}
		if recipe.has("tsa") and not d.require_range(recipe.tsa,4,"Title tilemap"): return {}
	if not d.require_range(d.ptr(0x9b524),4,"Title objects") or not d.require_range(d.ptr(0x9b52c),32,"Title object palette"): return {}
	var ap: int = d.ptr(0x9b530)
	var modes: int = ap+d.u16(ap+2)
	for entry in [["subtitle",0,[120,85]],["prompt",1,[120,120]],["copyright",2,[120,152]],["sparkle",3,[163,27]]]:
		var timeline: int = modes+d.u16(modes+int(entry[1])*2)
		result[entry[0]] = {"kind":"fe6_title_object","id":d.u16(timeline+2),"anchor":entry[2]}
	if not d.error.is_empty(): return {}
	var base: Array = [result.background,result.sword,result.shadow.merged({"opacity":0.5}),result.logo,result.subtitle,result.sparkle]
	result.card = {"kind":"compose","layers":base}
	result.screen = {"kind":"compose","layers":base+[result.prompt,result.copyright]}
	return result

static func manifest(bytes: PackedByteArray, prefix: String, assets: Dictionary) -> Dictionary:
	# Missing title pointer tables must not poison the campaign decoder.
	var d := Decoder.new(); d.rom = bytes
	var recipes := layers(d)
	if recipes.is_empty(): return {"game_id":"fe6","label":"FE6"}
	var entries: Array = []
	for name in recipes:
		var path := prefix+"rom/title/title_"+str(name)+".png"
		assets[path] = recipes[name]
		entries.append({"id":"title_"+str(name),"path":path,"kind":"title_layer"})
	return {"game_id":"fe6","image":prefix+"rom/title/title_screen.png","card":prefix+"rom/title/title_card.png","prompt":prefix+"rom/title/title_prompt.png","entries":entries}

static func card(bytes: PackedByteArray) -> Image:
	var d := Decoder.new(); d.rom = bytes
	var recipes := layers(d)
	return d.image(recipes.card) if recipes.has("card") else null
