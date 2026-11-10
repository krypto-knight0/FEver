extends RefCounted

static func describe(item: Dictionary) -> String:
	if item.is_empty(): return ""
	var lines: Array[String] = [str(item.get("name", "Item"))]
	var description := str(item.get("description", "")).strip_edges()
	if not description.is_empty(): lines.append(description)
	if item.has("might"):
		lines.append("%s · Range %s\nMt %d   Hit %d   Crit %d   Wt %d" % [weapon_type(item), range_text(item), int(item.get("might", 0)), int(item.get("hit", 0)), int(item.get("crit", 0)), int(item.get("weight", 0))])
	elif item.get("type", "") == "staff": lines.append(weapon_type(item) + " · Range " + range_text(item))
	elif description.is_empty() and int(item.get("healing", 0)) > 0: lines.append("Restores %d HP." % int(item.healing))
	return "\n".join(lines)

static func weapon_type(item: Dictionary) -> String:
	var kind := str(item.get("type", "Weapon")).capitalize()
	if not item.get("allowed_character_ids", []).is_empty(): return kind + " · Prf"
	if not item.has("required_rank"): return kind
	var points := int(item.required_rank)
	var rank := "Prf" if points > 251 else "E"
	if points <= 251:
		for entry in [["E", 1], ["D", 31], ["C", 71], ["B", 121], ["A", 181], ["S", 251]]:
			if points >= entry[1]: rank = entry[0]
	return "%s · %s" % [kind, rank]

static func range_text(item: Dictionary, effective: Vector2i = Vector2i(-1, -1)) -> String:
	if item.is_empty(): return "—"
	if effective.x < 0 and item.get("range_magic_half", false): return "%d–Mag/2" % int(item.get("min_range", 1))
	var minimum := effective.x if effective.x >= 0 else int(item.get("min_range", 1))
	var maximum := effective.y if effective.y >= 0 else int(item.get("max_range", minimum))
	return str(minimum) if minimum == maximum else "%d–%d" % [minimum, maximum]
