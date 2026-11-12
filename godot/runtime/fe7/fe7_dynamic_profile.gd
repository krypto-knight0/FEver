extends RefCounted
## FE7 regional engine ABIs, read from native pointer operands.
## Tables can relocate; engine rewrites need review.
const VERSION := "fe7-jp-native-29"
const MAX_CHAPTERS := 67
const US = preload("res://runtime/fe7/fe7_dynamic_us_profile.gd")
const US_CODES := ["AE7E", "FX7E"]
const GAME_CODES := ["AE7J", "AE7E", "FX7E"]
const LAYOUT := {
	"support_layout":[0x79264,20,253,7],
	"arena_layout":[0x2f024,0x2f030,0x2f080,0x2f288,0x2f2a8,0x17ce0],
	"game":"fe7","unicode_symbols":true,"event_variant":"fe7j",
	"record_layout":[0x9ac50,52,1,0x17ce0,84],"name_layout":[0x9ac50,52,1,253],
	"characters":0x9ac50,"character_stride":52,"character_count":253,
	"battle_layout":[0x17ce0,84,52,0x549dc,0x549e0],"battle_terrain":0x4d8dc,"hit_effect":0x62f64,
	"ballista_palette_pointers":{52:0x53a64,53:0x53a6c,54:0x53a74},
	"sound_room_layout":[0x1b844,16,12],"sound_room_pointers":true,"title_graphics":0xbaff4,"title_palette":0xbaff0,"title_ap":0xbaffc,
	"defeat_script_main":[0x79d28,12],
	"quote_layouts":{"battle":[0x79c24,12],"death":[0x79d20,16],"defeat_script":[0x79d2c,12]},"quote_all_chapters":0x45,
	"map_layout":[0x31a6c,148,MAX_CHAPTERS,0x31abc,0x195b0,0x31ae8],
	"deployment_layout":[0x31a6c,148,MAX_CHAPTERS,116,0x31b18,0xd63c],"filtered_loads":[0x32,0x35],
	"world_images":0xb6a14,"world_maps":0xb6a0c,"world_palette":0xb6c00,"world_events":0xb643c,
	"chapters":0x31a6c,"chapter_stride":148,"maps":0x31abc,"config":0x195b0,
	"graphics":0x19618,"palettes":0x1964c,"changes":0x31ae8,
	"portraits":0x69c0,"sprites":0x2522c,"sprite_palette":0x1900e8,"movement":0x6dd60,
	"items":0x164dc,"icons":0x4cfc,"icon_palette":0x4c1c,"songs":0x3e2c,
	"text":0x13370,"tree":0x6e0,"root":0x6dc,"backgrounds":0xb7b0,"cgs":0xb7978,"tutorials":0x797d0,"terrain_names":0x19efc,"terrain_heal":0x19f0c,
}

static func detect(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 0xa0000 or bytes.size() > 32*1024*1024: return {"error":"Unsupported FE7 cartridge size."}
	var code := bytes.slice(0xac,0xb0).get_string_from_ascii()
	if code not in GAME_CODES: return {"error":"Dynamic FE7 supports Japanese (AE7J) and US/English (AE7E or FX7E) layouts."}
	var selected := layout_for(bytes)
	var pointers: Array = []
	for key in ["characters","items","text","tree","root","chapters","maps","config","graphics","palettes","changes","portraits","sprites","icons","icon_palette"]: pointers.append(selected[key])
	pointers.append_array([selected.record_layout[3],selected.deployment_layout[4],selected.deployment_layout[5]])
	for operand in pointers:
		var value := bytes.decode_u32(operand)
		if value < 0x08000000 or value-0x08000000+4 > bytes.size() or value%4:
			return {"error":"FE7 compatibility: invalid table pointer at 0x%x." % operand}
	for record in [[selected.characters,0,52,4],[selected.record_layout[3],84,84,4],[selected.items,36,36,6]]:
		var at := bytes.decode_u32(record[0])-0x08000000+int(record[1])
		if at+int(record[2]) > bytes.size() or bytes[at+int(record[3])] != 1:
			return {"error":"FE7 compatibility: incompatible character, class, or item table."}
	var dispatch := bytes.decode_u32(int(selected.deployment_layout[5]))-0x08000000
	var commands := [[10,1],[0xd,2],[0x24,3],[0x30,2],[0x37,3],[0x3c,2],[0x7f,1]] if code == "AE7J" else [[10,1],[0xd,2],[0x26,3],[0x32,2],[0x39,3],[0x3e,2],[0x81,1]]
	for entry in commands:
		if dispatch+int(entry[0])*8+8 > bytes.size() or bytes.decode_u32(dispatch+int(entry[0])*8+4) != entry[1]:
			return {"error":"FE7 compatibility: incompatible %s event command layout." % code}
	return {"error":"","game_id":"fe7","version":US.VERSION if code in US_CODES else VERSION,"region":code}

static func layout_for(bytes: PackedByteArray) -> Dictionary:
	return (US.LAYOUT if bytes.size() >= 0xb0 and bytes.slice(0xac,0xb0).get_string_from_ascii() in US_CODES else LAYOUT).duplicate(true)

static func decoder(bytes: PackedByteArray) -> RefCounted:
	var result := preload("res://runtime/fe7/fe7_dynamic_decoder.gd").new()
	result.rom = bytes; result.layout = layout_for(bytes)
	result.configure_text()
	return result
