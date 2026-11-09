extends RefCounted
## Campaign results for dynamic FE7. Store actual play, evaluate ROM thresholds.
const Policy = preload("res://runtime/fe7/fe7_dynamic_policy.gd")
const Army = preload("res://engine/army_roster.gd")
const Flags = preload("res://engine/native_event_flags.gd")

static func active(b) -> bool:
	return b.chapter.get("dynamic_rom",false) and Flags.game(b.chapter) == "fe7" and int(b.chapter.get("native_route",1)) in [2,3] and Flags.integer(b.chapter.get("rom_chapter_index",-1),12,47)

static func combat(b, first: Dictionary, second: Dictionary) -> void:
	if not active(b): return
	for pair in [[first,second],[second,first]]:
		if pair[0].get("faction","") != "player": continue
		b.chapter.fe7_rank_battles = int(b.chapter.get("fe7_rank_battles",0))+1
		if int(pair[1].get("hp",1)) <= 0:
			b.chapter.fe7_rank_wins = int(b.chapter.get("fe7_rank_wins",0))+1

static func item_value(item: Dictionary) -> int:
	return maxi(0,int(item.get("cost_per_use",0)))*(1 if item.get("native_asset_once",false) else maxi(0,int(item.get("uses",0))))

static func record(b) -> void:
	if not active(b): return
	var ledger: Dictionary = b.chapter.get_or_add("fe7_rank_records",{})
	var key := str(int(b.chapter.get("rom_chapter_index",0)))
	if ledger.has(key): return
	var assets := int(b.gold)
	var deaths: Dictionary = b.chapter.get_or_add("fe7_rank_deaths",{})
	for item in b.inventory: assets += item_value(item)
	for unit in Army.all_units(b):
		if unit.get("faction","") != "player" or unit.get("escaped",false): continue
		if int(unit.get("hp",0)) <= 0:
			if b.rules.get("permadeath",true) or unit.get("casualty_mode","") == "permanent": deaths[str(unit.id)] = true
			continue
		for item in unit.get("inventory",[]): assets += item_value(item)
		assets += item_value(unit.get("weapon",{}))
	ledger[key] = {"turns":int(b.turn),"experience":int(b.chapter.get("fe7_earned_experience",0)),"battles":int(b.chapter.get("fe7_rank_battles",0)),"wins":int(b.chapter.get("fe7_rank_wins",0))}
	b.chapter.fe7_rank_assets = mini(9999999,assets)

static func evaluate(b, d) -> Dictionary:
	var records: Dictionary = b.chapter.get("fe7_rank_records",{})
	var tactics: Array = [0,0,0,0]
	var experience: Array = [0,0,0,0]
	var turns := 0; var earned := 0; var battles := 0; var wins := 0; var budget := 0
	var table: int = d.ptr(int(d.layout.chapters))
	for key in records:
		var id := int(key)
		if id < 12 or id > 47: continue
		var row: Dictionary = records[key]
		turns += int(row.turns); earned += int(row.experience); battles += int(row.battles); wins += int(row.wins)
		var stride: int = d.layout.get("chapter_stride",148)
		var at := table+id*stride
		if not d.require_range(at,stride,"FE7 ranking chapter"): return {}
		# FE7's native selector is Normal=0 / Hard=1 on both routes.
		var mode := int(preload("res://engine/campaign_difficulty.gd").is_hard(b.chapter.get("difficulty","normal")))
		for index in range(4):
			tactics[index] += d.u8(at+[0x39,0x35,0x31,0x2d][index]+mode)
			experience[index] += d.u16(at+[0x56,0x4e,0x46,0x3e][index]+mode*2)
		budget += d.u32(at+0x60+mode*4)
	var deaths: int = b.chapter.get("fe7_rank_deaths",{}).size()
	var assets := int(b.chapter.get("fe7_rank_assets",0))
	var rate := floori(100.0*wins/battles) if battles else 0
	var grades: Array = [0,0,0,0,0]
	for index in range(4):
		if turns <= int(tactics[index]): grades[0] += 1
		else: break
	for index in range(4):
		if deaths < d.u8(d.ptr(Policy.address(d,0xb722c))+index): grades[1] += 1
		else: break
	for index in range(4):
		if assets*100 >= budget*(20+index*20): grades[2] += 1
		else: break
	for index in range(4):
		if earned >= int(experience[index]): grades[3] += 1
		else: break
	for index in range(4):
		if rate >= d.u8(d.ptr(Policy.address(d,0xb7358))+index): grades[4] += 1
		else: break
	var points := 0
	for index in range(5): points += d.u8(d.ptr(Policy.address(d,0xb7440))+index*5+int(grades[index]))
	var overall := 0
	for index in range(5):
		if points < d.u16(d.ptr(Policy.address(d,0xb7444))+index*2): break
		overall += 1
	return {"grades":grades,"overall":overall,"turns":turns,"experience":earned,"assets":assets,"battles":battles,"wins":wins,"deaths":deaths}

static func page(b, d) -> Dictionary:
	var result := evaluate(b,d)
	if result.is_empty(): return {}
	var grade := int(result.overall)
	var title: String = d.text(d.u32(Policy.address(d,0xb9358 if grade > 3 else (0xb9368 if grade > 1 else 0xb939c)))).strip_edges()
	var body: String = d.text(d.u32(Policy.address(d,0xb988c if grade > 3 else (0xb9898 if grade > 1 else 0xb98a0)))).strip_edges()
	var labels := ["Tactics","Survival","Funds","Experience","Combat"]
	var lines: Array[String] = []
	for index in range(5): lines.append("%s  %s" % [labels[index],"★".repeat(int(result.grades[index])+1)])
	body += "\n\n"+"\n".join(lines)+"\n\n%d turns · %d EXP · %d G\n%d wins / %d battles · %d fallen" % [result.turns,result.experience,result.assets,result.wins,result.battles,result.deaths]
	return {"title":title,"text":body,"units":[],"ranking":result}

static func valid(chapter: Dictionary) -> bool:
	for key in ["fe7_rank_battles","fe7_rank_wins","fe7_rank_assets"]:
		if not Flags.integer(chapter.get(key,0),0,99999999): return false
	var records: Variant = chapter.get("fe7_rank_records",{})
	var deaths: Variant = chapter.get("fe7_rank_deaths",{})
	if not records is Dictionary or records.size() > 48 or not deaths is Dictionary or deaths.size() > 255: return false
	for id in deaths:
		if not id is String or deaths[id] != true: return false
	for id in records:
		if not id is String or not id.is_valid_int() or int(id) < 12 or int(id) > 47: return false
		if not records[id] is Dictionary: return false
		for field in ["turns","experience","battles","wins"]:
			if not Flags.integer(records[id].get(field,-1),0,99999999): return false
		if int(records[id].wins) > int(records[id].battles): return false
	return true
