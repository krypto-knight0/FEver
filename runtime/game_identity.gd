extends RefCounted
## Hash-isolated identities for runtime-generated cartridges.
static func save_path(game_id: String, rom_digest: String = "") -> String:
	if game_id not in ["fe6","fe7"] or not valid_digest(rom_digest): return ""
	return "user://saves/%s/suspend.json" % (game_id+("-"+rom_digest if not rom_digest.is_empty() else ""))

static func valid_digest(value: String) -> bool:
	return value.is_empty() or (value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower())

static func accepts(document: Dictionary, game_id: String, rom_digest: String = "") -> bool:
	return game_id in ["fe6", "fe7"] and valid_digest(rom_digest) and document.get("pack_id", "") == game_id and document.get("rom_sha256","") == rom_digest
