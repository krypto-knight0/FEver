extends RefCounted
## US FE7 engine ABI. Values are native pointer operands, not copied asset data.
## Chapter records and event numbers differ from the Japanese release.
const VERSION := "fe7-us-native-3"
const LAYOUT := {
	"ai_primary":0xb989f0,"ai_secondary":0xb989e4,
	"game":"fe7","unicode_symbols":false,"event_variant":"fe7u",
	"record_layout":[0x9a274,52,1,0x178f0,84],"name_layout":[0x9a274,52,1,253],
	"characters":0x9a274,"character_stride":52,"character_count":253,
	"support_layout":[0x78a94,20,253,7],
	"arena_layout":[0x2eb58,0x2eb64,0x2ebb4,0x2f1c0,0x2eddc,0x178f0],
	"battle_layout":[0x178f0,84,52,0x541f4,0x541f8],"battle_terrain":0x4d100,
	"sound_room_layout":[0x1b468,16,12],"sound_room_pointers":false,
	"defeat_script_main":[0x79558,12],
	"quote_layouts":{"battle":[0x79454,12],"death":[0x79550,16],"defeat_script":[0x7955c,12]},"quote_all_chapters":0x43,
	"map_layout":[0x31580,152,67,0x3159c,0x191c8,0x315b8],
	"deployment_layout":[0x31580,152,67,120,0x315d4,0xd72c],"filtered_loads":[0x34,0x37],
	"world_images":0xb5bf4,"world_maps":0xb5bec,"world_palette":0xb5df4,"world_events":0xb561c,
	"chapters":0x31580,"chapter_stride":152,"chapter_title":116,"chapter_objective":142,
	"maps":0x3159c,"config":0x191c8,"graphics":0x19230,"palettes":0x19264,"changes":0x315b8,
	"portraits":0x6b30,"sprites":0x24da0,"sprite_palette":0x194594,"movement":0x6d574,
	"items":0x174d4,"icons":0x4e20,"icon_palette":0x4d40,"songs":0x3f50,
	"text":0x12cb8,"tree":0x6bc,"root":0x6b8,"backgrounds":0xb874,"cgs":0xb6b64,
	"tutorials":0x79000,"terrain_names":0x19b1c,"terrain_heal":0x19b2c,
}

# The international interpreter added two early text commands, removed three
# world-map commands, then removed further Japanese-only presentation commands.
static func opcode(native: int) -> int:
	if native <= 0x16: return native
	if native == 0x17: return 0x101 # Continued rating-advice text.
	if native == 0x18: return 0x17
	if native == 0x19: return 0x18
	if native == 0x1a: return 0x100 # Text selected by a flag, with a fresh portrait state.
	if native >= 0x1b and native <= 0xa8: return native-2
	if native == 0xa9: return 0xa9
	if native >= 0xaa and native <= 0xcc: return native+1
	if native == 0xcd: return 0xce
	if native >= 0xcf and native <= 0xdb: return native+3
	if native == 0xdc: return 0xe0
	if native >= 0xdd and native <= 0xe6: return native+5
	return -1
