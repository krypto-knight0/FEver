extends SceneTree
## Cartridge-driven helpers shared by English FE7 and Flux Echo 7 tests.
const Assets = preload("res://runtime/rom_assets.gd")
const Profile = preload("res://runtime/fe7/fe7_dynamic_profile.gd")
const Data = preload("res://runtime/rom_data.gd")
const Names = preload("res://runtime/rom_names.gd")
const Prep = preload("res://engine/chapter_preparation.gd")
const Battle = preload("res://engine/battle_state.gd")
const NativeDifficulty = preload("res://runtime/fe7/fe7_dynamic_difficulty.gd")
var failures := 0
var checks := 0
var active_mode := "normal"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _initialize() -> void:
	call_deferred("run")

func port_battle(index: int, route: int) -> RefCounted:
	var prepared := Prep.read(Assets.dynamic_content.chapter_path(index,route),active_mode)
	var b := Battle.new(); b.load_chapter(prepared.chapter)
	b.set_promotion_catalog(Assets.dynamic_content.promotions)
	b._run_events("chapter_start"); b._run_events("turn")
	if b.chapter.events.any(func(e):return e.get("native_scene",false) and e.trigger == "preparations"):
		check(b.Army.deploy(b,b.Army.default_selection(b)).get("ok",false),"Native preparation completes")
		b._run_events("preparations")
	check(b.native_event_errors.is_empty(),"Opening %d route %d: %s" % [index,route,b.native_event_errors])
	return b

func media_checks(battle: RefCounted, next: RefCounted) -> void:
	var content: RefCounted = Assets.dynamic_content
	var title: Image = Assets.image(content.prefix+"rom/title/title_screen.png")
	check(title != null and title.get_size() == Vector2i(240,160),"Native completed title composition")
	if title != null: title.save_png("user://fe7-dynamic-title.png")
	var audio: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(content.prefix+"audio.json"))
	var parser := preload("res://runtime/m4a_sequence.gd").new(); parser.decoder = Assets.decoder
	var mixer := preload("res://runtime/m4a_player.gd").new(); mixer.decoder = Assets.decoder
	for category in ["music","sfx"]:
		for cue in audio[category]:
			var sequence := parser.song(int(audio[category][cue].song_id))
			check(not sequence.get("notes",[]).is_empty(),"Native audio sequence "+cue)
			if not sequence.get("notes",[]).is_empty():
				mixer.sequence = sequence
				var instrument := mixer.instrument(sequence.notes[0])
				var sample := mixer.sample(int(instrument[0]),64)
				check(sample != null and sample.data.size() > 0,"Native audio sample "+cue)
	mixer.free()
	var cutscene := preload("res://ui/battle_cutscene.gd").new()
	check(cutscene.configure(content.manifest.battle_animation_manifest),"Configure native battle animation manifest")
	for unit in battle.units+next.units:
		if unit.weapon.is_empty(): continue
		var profile := cutscene.profile_for(unit)
		check(not profile.is_empty(),"Native battle profile "+str(unit.id))
		if profile.is_empty(): continue
		check(Assets.image(profile.atlas.right) != null,"Render native battle atlas "+str(unit.id))
	check(cutscene.backdrop != null and cutscene.platform != null,"Native battle background and terrain platform")
	var hit := preload("res://runtime/rom_hit_effect.gd").read(Assets.decoder,"fe7")
	check(not hit.get("frames",[]).is_empty(),"Native hit effect frames")
	cutscene.free()

func place_test_unit(b: RefCounted, unit: Dictionary, cell: Vector2i) -> void:
	for other in b.units:
		if other.id != unit.id and int(other.x) == cell.x and int(other.y) == cell.y: other.benched = true; other.x = 0; other.y = 0
	unit.x = cell.x; unit.y = cell.y; unit.erase("benched")
