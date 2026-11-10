extends RefCounted
## Logical cues are FE7 engine policy; sequences/samples and sound-room labels
## are decoded from this ROM, with no rendered audio cache on disk.
const MUSIC := {"title":0x5a,"player_phase":0x30,"enemy_phase":0xc,"dialogue":0x3f,"victory":0x38,"worldmap":0x25,"player_battle":0x1f,"enemy_battle":0x20,"boss_battle":0x14,"boss_final":0x15}
const EFFECTS := {"select":0xcc,"confirm":0xc9,"cancel":0xcd,"move":0xcc,"hit":0xd2,"miss":0xd7,"critical":0xd8,"heal":0x89,"level_up":0x37b,"recruit":0x37b,"item":0x2cd,"stat_up":0x2cd,"no_damage":0x2ce}

static func manifest(d: RefCounted) -> Dictionary:
	var result := {"schema_version":1,"game_id":"fe7","music":{},"sfx":{},"$rom_audio_labels":"fe7"}
	for cue in MUSIC: result.music[cue] = {"song_id":MUSIC[cue],"loop":true}
	for cue in EFFECTS: result.sfx[cue] = {"song_id":EFFECTS[cue],"loop":false}
	var labeled: Variant = preload("res://runtime/rom_labels.gd").audio(d,result,"fe7")
	return labeled if labeled is Dictionary else {}
