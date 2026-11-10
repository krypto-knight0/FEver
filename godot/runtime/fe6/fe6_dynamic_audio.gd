extends RefCounted
## Logical engine cues use the FE6 ABI; samples, sequences and sound-room labels
## come from this cartridge, including relocated song and sound-room tables.
const MUSIC := {"title":1,"player_battle":0x48,"enemy_battle":0x49,"boss_battle":0x16,"victory":0x27,"dialogue":0x24}
const EFFECTS := {"select":0x67,"confirm":0x6d,"cancel":0x6b,"move":0x67,
	"hit":0xd4,"critical":0xd8,"no_damage":0xec,"miss":0xd7,"heal":0x10f,
	"level_up":0x5b,"stat_up":0x76,"item":0x76,"recruit":0x5b}

static func manifest(d: RefCounted) -> Variant:
	var result := {"schema_version":1,"game_id":"fe6","music":{},"sfx":{},"$rom_audio_labels":"fe6"}
	for cue in MUSIC: result.music[cue] = {"song_id":MUSIC[cue],"loop":true}
	for cue in EFFECTS: result.sfx[cue] = {"song_id":EFFECTS[cue],"loop":false}
	return preload("res://runtime/rom_labels.gd").audio(d,result,"fe6")
