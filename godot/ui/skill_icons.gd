extends RefCounted
## Vector badges are generated from the stable skill ID, shared by all skill views.
static var cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if cache.has(id): return cache[id]
	var hue := float(absi(id.hash()) % 360) / 360.0
	var color := Color.from_hsv(hue, 0.55, 0.8).to_html(false)
	var marks := ["M16 7 L22 16 L16 25 L10 16 Z", "M8 16 L24 16 M16 8 L16 24", "M8 24 L16 7 L24 24 Z", "M8 10 L24 10 L21 22 L16 26 L11 22 Z", "M8 23 L24 7 M9 7 L25 23 M12 26 L7 21", "M7 16 L12 11 L16 16 L21 7 L25 12 L18 25 Z"]
	@warning_ignore("integer_division") # Intentional integer truncation.
	var mark: String = marks[absi(id.hash() / 360) % marks.size()]
	var dots := ""
	@warning_ignore("integer_division") # Intentional integer truncation.
	for i in range(1 + absi(id.hash() / 2160) % 4): dots += '<circle cx="%d" cy="29" r="1" fill="#fff4d7"/>' % (10 + i * 4)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect x="1" y="1" width="30" height="30" rx="6" fill="#%s" stroke="#f1d58b" stroke-width="2"/><path d="%s" fill="none" stroke="#fff4d7" stroke-width="2.5" stroke-linejoin="round"/>%s</svg>' % [color, mark, dots]
	var image := Image.new()
	image.load_svg_from_string(svg)
	cache[id] = ImageTexture.create_from_image(image)
	return cache[id]

static func records(unit: Dictionary) -> Array:
	var result: Array = []
	var personal: Dictionary = unit.get("rogue_personal", {})
	if not personal.is_empty():
		result.append({"id": "personal_" + str(unit.get("id", "")), "name": str(personal.get("name", unit.get("name", "Personal skill"))), "description": str(personal.get("description", "+%s %s" % [personal.get("amount", 0), personal.get("stat", "")])), "count": 1, "personal": true})
	var rogue = preload("res://engine/rogue_mode.gd")
	var skills: Dictionary = unit.get("rogue_skills", {}).duplicate()
	if skills.has("vampire"):
		skills.sol = int(skills.get("sol", 0)) + int(skills.vampire)
		skills.erase("vampire")
	for id in skills:
		if int(skills[id]) <= 0: continue
		result.append({"id": id, "name": rogue.title(id), "description": rogue.UNIT_TEXT.get(id, rogue.ARMY_TEXT.get(id, "")), "count": int(skills[id])})
	var fe7_unit_39_bonus := int(unit.get("rogue_personal_state", {}).get("fe7_unit_39_bonus", 0))
	if fe7_unit_39_bonus > 0:
		var name := preload("res://engine/personal_skill_config.gd").display_name("fe7_unit_39","an ally")
		result.append({"id":"fe7_unit_39_blessing", "name":name, "description":"Granted by %s: +%d Atk/Spd/Def/Res. Resets when the granting ally deals damage or uses an assist." % [name,fe7_unit_39_bonus], "count":1})
	return result

static func details(unit: Dictionary, record: Dictionary, state = null) -> String:
	var text := str(record.description)
	if int(record.count) > 1: text += "\nStacks: %d" % int(record.count)
	if record.get("personal", false):
		var data: Dictionary = unit.get("rogue_personal_state", {})
		var id := preload("res://engine/rogue_personals.gd").effect_id(unit)
		if id in ["fe7_unit_3", "fe7_unit_1", "fe7_unit_2"]:
			var personal = preload("res://engine/rogue_personals.gd")
			var maximum := ceili(float(personal.parameter(unit,"cap",20)) / maxi(1,personal.parameter(unit,"amount",2)))
			text += "\nStacks: %d / %d" % [mini(maximum, int(data.get("combats", 0))), maximum]
		if id == "fe7_unit_44": text += "\nDecay stacks: %d" % int(data.get("decay", 0))
		if id in ["fe7_unit_35", "fe7_unit_54"]: text += "\nActive until injured" if data.get("ready", true) else "Inactive · requires an uninjured turn"
		if id == "fe7_unit_16":
			text += "\nDouble healing: " + ("Ready" if data.get("double_heal", false) else "Not charged")
			text += "\nHealing combat bonus: " + ("Active" if data.get("healing_boost", false) else "Inactive")
		text += personal_details(unit, state)
	if unit.get("rogue_used", {}).has(record.id): text += "\nUsed this turn" if unit.rogue_used[record.id] else "\nReady"
	elif record.id in ["galeforce", "fury", "mercy", "busy", "guardian"]: text += "\nReady this turn"
	for effect in unit.get("rogue_effects", []):
		if effect.get("source", "") != record.id: continue
		for stat in effect.get("stats", {}): text += "\n%s %+d (expires turn %d)" % [str(stat).capitalize(), int(effect.stats[stat]), int(effect.expires)]
	var rogue = preload("res://engine/rogue_mode.gd")
	for stat in ["str", "magic", "speed", "def", "res", "hit", "avoid", "crit", "mov"]:
		var bonus: int = rogue.Personal.temporary(unit, stat, false) if record.get("personal", false) else 0
		if record.get("personal", false) and unit.get("rogue_personal", {}).get("stat", "") == stat: bonus += int(unit.rogue_personal.get("amount", 0))
		var boost: String = {"str": "str_up", "magic": "mag_up", "speed": "spd_up", "def": "def_up", "res": "res_up", "mov": "haste"}.get(stat, "")
		if record.id == boost: bonus = int(record.count) * (1 if stat == "mov" else 2)
		if bonus != 0: text += "\nCurrent %s bonus: %+d" % [stat.capitalize(), bonus]
	var flat: Dictionary = {"hit_up": "Hit", "avd_up": "Avoid", "crit_up": "Crit", "wary": "Crit Avoid", "sharpshooter": "maximum range"}
	if flat.has(record.id): text += "\nCurrent %s bonus: +%d" % [flat[record.id], int(record.count) * (1 if record.id == "sharpshooter" else 20 if record.id == "wary" else 10)]
	return text

static func army_records(state) -> Array:
	var result: Array = []
	if state == null: return result
	var rogue = preload("res://engine/rogue_mode.gd")
	for id in state.chapter.get("rogue", {}).get("army", {}):
		if id == "shatter_morale": continue
		var count := int(state.chapter.rogue.army[id])
		if count > 0: result.append({"id":id,"name":rogue.title(id),"description":rogue.ARMY_TEXT.get(id,""),"count":count})
	return result

static func army_details(record: Dictionary, state) -> String:
	var text := str(record.description)
	if int(record.count) > 1: text += "\nStacks: %d" % int(record.count)
	if state == null: return text
	var rogue = preload("res://engine/rogue_mode.gd")
	if record.id == "guidance_of_fe7_unit_39": text += "\nUndo uses remaining: %d" % rogue.remaining(state,"undo")
	if record.id == "gladiators_will": text += "\nArena entries remaining: %d" % rogue.remaining(state,"arena")
	if record.id == "extra_training": text += "\nStat rerolls remaining: %d" % int(state.chapter.get("rogue",{}).get("training",0))
	return text

static func personal_details(unit: Dictionary, state = null) -> String:
	var personal = preload("res://engine/rogue_personals.gd")
	var id := preload("res://engine/rogue_personals.gd").effect_id(unit)
	var data: Dictionary = unit.get("rogue_personal_state", {})
	var text := ""
	if id == "fe7_unit_36": text += "\nActive until injured" if data.get("ready", true) else "\nInactive · requires an uninjured turn"
	if id in ["fe7_unit_5", "fe7_unit_39"]: text += "\nStacks: %d / %d" % [mini(personal.parameter(unit,"cap",5), int(data.get("stacks", 0))),personal.parameter(unit,"cap",5)]
	if id == "fe7_unit_20": text += "\nAttached skill stacks: %d · Current bonus: +%d / +%d" % [personal.attached_skills(unit), personal.temporary(unit,"str",false),personal.parameter(unit,"cap",10)]
	if id == "fe7_unit_56": text += "\nNext bonus: +%d Atk with %s" % [personal.parameter(unit,"amount",2),str(data.next_weapon).capitalize()] if data.has("next_weapon") else "\nNext bonus: Not charged"
	if id == "fe7_unit_7" and data.has("critical"): text += "\nThis battle: Critical delivered" if data.critical else "\nThis battle: No critical yet"
	if state == null: return text
	if id == "fe7_unit_31": text += "\nCurrent initiating Luck bonus: +%d / +%d" % [int(personal.combat_bonus(state, unit, true).luck),personal.parameter(unit,"cap",10)]
	if id == "fe7_unit_33":
		var radius: int = personal.parameter(unit,"radius",3)
		var foes: int = personal.nearby_foes(state, unit, radius).size()
		text += "\nFoes within %d tiles: %d · Combat bonus: +%d Atk/Spd/Def/Res" % [radius,foes,foes * personal.parameter(unit,"amount",1)]
	if id == "fe7_unit_18": text += "\nCurrent Mag bonus from support ranks: +%d" % personal.state_stat(state, unit, "magic")
	if id in ["fe7_unit_21", "fe7_unit_15"]:
		var partner_id := "fe7_unit_15" if id == "fe7_unit_21" else "fe7_unit_21"
		var partner: Dictionary = state._support_unit(partner_id)
		var in_range: bool = state._on_map(unit) and state._on_map(partner) and state.rules.get("supports_enabled", true) and state._distance(state.position(unit), state.position(partner)) <= int(state.rules.support_range)
		var rank := int(state.support_ranks.get(state._pair_key(state._support_identity(str(unit.id)), partner_id), 0))
		text += "\nPartner support: " + ("Doubled" if in_range and rank > 0 else "Inactive")
	return text
