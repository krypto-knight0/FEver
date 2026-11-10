extends RefCounted
## Completed native FE7 title composition; pointer operands remain live.
const Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")

static func layers(d: RefCounted) -> Dictionary:
	var result := {}
	var us: bool = d.layout.get("event_variant","") == "fe7u"
	var backgrounds := [["background",0xb923c,0xba530,0xba520,false,false],["axe",0xba538,0xba544,0xba534,true,true]] if us else [["background",0xbb068,0xbb074,0xbb064,false,false],["axe",0xbb07c,0xbb088,0xbb078,false,true]]
	for row in backgrounds:
		result[row[0]] = {"kind":"scene","graphics":[[d.ptr(row[1])]],"tsa":d.ptr(row[2]),"palette":d.ptr(row[3]),"palette_size":32,"tsa_lz":row[4],"transparent":row[5],"crop":[0,0,240,160]}
	var ap: int = d.ptr(int(d.layout.get("title_ap",0xba4b8)))
	var modes: int = ap+d.u16(ap+2)
	for row in [["sword",0,72],["logo",1,72],["subtitle",3,48],["prompt",4,128],["copyright",6,144]]:
		if us and row[0] == "subtitle": continue
		var timeline: int = modes+d.u16(modes+int(row[1])*2)
		result[row[0]] = {"kind":"title_object","id":d.u16(timeline+2),"anchor":[120,76 if us and row[0] == "logo" else row[2]]}
	var base: Array = [result.background,result.axe,result.sword,result.logo]
	if result.has("subtitle"): base.append(result.subtitle)
	result.card = {"kind":"compose","layers":base}
	result.screen = {"kind":"compose","layers":base+[result.prompt,result.copyright]}
	return result if d.error.is_empty() else {}

static func manifest(d: RefCounted, prefix: String, assets: Dictionary) -> Dictionary:
	var entries: Array = []
	var recipes := layers(d)
	for key in recipes:
		var path := prefix+"rom/title/title_"+str(key)+".png"
		assets[path] = recipes[key]
		entries.append({"id":"title_"+str(key),"path":path,"kind":"title_layer"})
	return {"game_id":"fe7","image":prefix+"rom/title/title_screen.png","card":prefix+"rom/title/title_card.png","prompt":prefix+"rom/title/title_prompt.png","entries":entries}

static func card(bytes: PackedByteArray) -> Image:
	var d := Profile.decoder(bytes)
	var recipes := layers(d)
	return d.image(recipes.card) if recipes.has("card") else null
