extends "fe7_test_base.gd"
## Fast native-rule regressions, independent of chapter/art compilation.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): printerr("English FE7 or Flux Echo 7 ROM path required"); quit(2); return
	var path := args[0]
	var digest := FileAccess.get_sha256(path)
	Assets.decoder = Profile.decoder(FileAccess.get_file_as_bytes(path))
	var d: RefCounted = Assets.decoder
	check(d.error.is_empty() and d.layout.get("event_variant") == "fe7u","English FE7 item ABI")
	if failures: quit(1); return
	var data := preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); data.d = d
	var catalog := {}
	var table: int = d.ptr(int(d.layout.items))
	for id in range(1,256):
		if d.u8(table+id*36+6) != id: break
		if d.u16(table+id*36): catalog[id] = data.item(id,false)
	check(catalog.size() >= 149 and d.error.is_empty(),"Regional item catalog: "+str(d.error))
	if failures: quit(1); return
	special_item_checks([catalog]); mutation_checks()
	check(FileAccess.get_sha256(path) == digest,"Source cartridge untouched")
	print("FE7 special items: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func actor(id: String, faction: String, x: int, y: int) -> Dictionary:
	return {"id":id,"name":id,"game_id":"fe7","rom_character_id":1,"rom_class_id":1,"native_unit_flags":0xffffffff,"faction":faction,"x":x,"y":y,"max_hp":40,"hp":20,"str":17,"skill":15,"speed":12,"luck":10,"def":8,"res":5,"con":10,"mov":5,"level":10,"exp":0,"can_use_staves":true,
		"weapon_types":["sword","lance","axe","bow","anima","light","dark","staff","dragon"],"weapon_exp":{"sword":251,"lance":251,"axe":251,"bow":251,"anima":251,"light":251,"dark":251,"staff":251,"dragon":251},"weapon":{},"inventory":[],"growths":{"max_hp":50,"str":40,"skill":40,"speed":40,"luck":40,"def":20,"res":20}}

func fixture(item: Dictionary, other: Dictionary = {}, distance: int = 1) -> RefCounted:
	var first := actor("actor","player",1,1); var second := actor("target","enemy" if item.has("might") or item.has("inflict_status") else "player",1+distance,1)
	if item.has("allowed_character_ids") and not item.allowed_character_ids.is_empty(): first.rom_character_id = item.allowed_character_ids[0]
	# Dynamic personal locks and static selectors must select the same test user.
	if int(item.get("rom_item_id",0)) in [10,140]: first.rom_character_id = 3
	if int(item.get("rom_item_id",0)) == 141: first.rom_character_id = 2
	if item.has("might"): first.weapon = item
	else: first.inventory = [item]
	second.weapon = other.duplicate(true)
	if not second.weapon.is_empty(): second.weapon.uses = 1
	second.rom_class_id = 50; second.flying = true; second.status = "poison" if item.get("staff_effect") == "restore" else ""
	var b := Battle.new()
	b.load_chapter({"id":"fe7_comparison","terrain":["................","................","................","................"],"units":[first,second],"seed":91,"gold":10000,"rules":{"triangle_hit":15,"triangle_damage":1,"effectiveness_multiplier":2,"fog_radius":5,"supports_enabled":false},"objective":{"type":"seize","x":15,"y":3},"interactions":[{"id":"door","type":"door","x":2,"y":2,"requires_key":true}]})
	return b

func special_item_checks(catalogs: Array) -> void:
	var opening := Battle.new()
	for dynamic in [false,true]:
		opening.load_chapter({"id":"fe7_comparison","game_id":"fe7","dynamic_rom":dynamic,"terrain":["...",".D.","..."],"units":[],"interactions":[{"id":"door","type":"door","x":1,"y":1}],"initial_map_changes":[{"x":1,"y":1,"width":1,"height":1,"terrain":["_"]}]})
		check(opening.interactions[0].get("used",false),"Opening map change disables already opened door")
	for catalog in catalogs:
		var b := fixture(catalog[114])
		check(b.shop_price("actor",301) == 150,"Discount item 114 halves and rounds down shop price")
		b.get_unit("actor").inventory.clear()
		check(b.shop_price("actor",301) == 301,"Discount requires the card on the shopper")
		b.get_unit("actor").inventory = [b._normalize_item(catalog[114])]
		b.interactions.append({"type":"shop","x":1,"y":1,"stock":[{"item":catalog[1],"price":301}]})
		check(b.buy_item("actor",0).get("ok",false) and b.gold == 9850,"Shop purchase deducts discounted gold")
		var restored := Battle.new(); check(restored.restore(JSON.parse_string(JSON.stringify(b.serialize(false)))) and restored.shop_price("actor",301) == 150,"Discount survives suspend restore")
		for pair in [[9,1,0x10000000],[141,2,0x20000000],[10,3,0x40000000],[140,45,0x40000000],[132,1,0x10000000],[133,2,0x20000000],[60,39,0x80000000],[12,6,0x20000]]:
			var unit := actor("user","player",0,0); unit.rom_character_id = pair[1]; unit.native_unit_flags = pair[2]
			check(b.can_equip_weapon(unit,catalog[pair[0]]),"Personal weapon permits its lord "+str(pair[0]))
			unit.rom_character_id = 23; unit.native_unit_flags = 0
			check(not b.can_equip_weapon(unit,catalog[pair[0]]),"Personal weapon rejects other users "+str(pair[0]))
		b = fixture(catalog[74]); check(b.use_item("actor",0,"target").get("ok",false) and b.get_unit("target").hp > 20,"Recovery staff 74 restores ally HP")
		b = fixture(catalog[136]); check(b.use_item("actor",0,"actor").get("ok",false) and b.get_unit("actor").growths.str == 45,"Growth item 136 increases growths")
		b.get_unit("actor").acted = false; b.get_unit("actor").inventory = [b._normalize_item(catalog[136])]
		check(not b.use_item("actor",0,"actor").get("ok",false),"Growth item 136 cannot be applied twice")
		b = fixture(catalog[44],catalog[1]); var before: Dictionary = b.forecast("actor","target")
		b.get_unit("target").inventory = [b._normalize_item(catalog[112])]
		check(b.forecast("actor","target").attacker.damage < before.attacker.damage,"Effectiveness shield 112 blocks bow effectiveness")
		b = fixture(catalog[13],catalog[1]); b.get_unit("target").inventory = [b._normalize_item(catalog[123])]
		check(b.forecast("actor","target").attacker.crit == 0,"Critical shield 123 blocks critical hits")
		check(int(catalog[132].stat_bonuses.str) == 5 and int(catalog[133].stat_bonuses.def) == 5,"Legendary weapon stat bonuses")
		b = fixture(catalog[17],catalog[1])
		check(b.forecast("actor","target").attacker.damage == 16,"Magic sword 17 rounds half strength up and targets Resistance")
		for id in [80,81,82]:
			b = fixture(catalog[id]); var result: Dictionary = b.use_item("actor",0,"target")
			check(result.get("ok",false) and b.get_unit("target").status == catalog[id].inflict_status and b.get_unit("target").status_turns == 5,"Status staff applies five-turn effect "+str(id))
		for id in [124,125,126,127]:
			b = fixture(catalog[id]); check(not b.use_item("actor",0,"target").get("ok",false),"Ring rejects nondancer "+str(id))
			b.get_unit("actor").can_play = true
			check(b.use_item("actor",0,"target").get("ok",false) and b.get_unit("target").ring_bonuses == catalog[id].ring_bonuses,"Dancer applies ring effect "+str(id))
		for id in [121,122]:
			b = fixture(catalog[id]); check(b.use_item("actor",0,"",Vector2i(1,2)).get("ok",false),"Place trap "+str(id))
			check(b.chapter.get("placed_traps",[]).any(func(t):return t.kind == catalog[id].trap),"Trap appears on map "+str(id))

func mutation_checks() -> void:
	# Edited flags and the actual card operand drive item rules; changed
	# executable rules must fail instead of silently guessing.
	var original: PackedByteArray = Assets.decoder.rom
	var us: bool = Assets.decoder.layout.get("event_variant") == "fe7u"
	var d := Profile.decoder(original.duplicate())
	var at: int = d.ptr(int(d.layout.items))+9*36
	d.rom.encode_u32(at+8,(d.u32(at+8)&~0x40000)|0x80000)
	var data := preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); data.d = d
	check(data.item(9).get("required_unit_flags") == 0x20000000,"Edited personal lock follows weapon flags")
	d = Profile.decoder(original.duplicate()); d.rom[0xb1d56 if us else 0xb2b7a] = 113
	data = preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); data.d = d
	check(data.item(113).get("shop_discount") == 0.5 and not data.item(114).has("shop_discount"),"Discount follows edited native card ID")
	d = Profile.decoder(original.duplicate())
	var table: int = d.ptr(int(d.layout.items)); var moved: int = d.rom.size()
	d.rom.append_array(d.rom.slice(table,table+160*36))
	var lock_at := 0x161a4 if us else 0x16620
	for operand in [int(d.layout.items),lock_at+348,lock_at+424]: d.rom.encode_u32(operand,0x08000000+moved)
	data = preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); data.d = d
	check(data.item(9).get("required_unit_flags") == 0x10000000 and data.item(114).get("shop_discount") == 0.5,"Relocated item table retains locks and passives")
	for address in ([0x161d6,0xb1d6c] if us else [0x16652,0xb2b90]):
		d = Profile.decoder(original.duplicate()); d.rom[address] ^= 1
		data = preload("res://runtime/fe7/fe7_dynamic_data.gd").new(); data.d = d
		check(data.item(1).is_empty() and not d.error.is_empty(),"Reject changed item rule 0x%x" % address)
