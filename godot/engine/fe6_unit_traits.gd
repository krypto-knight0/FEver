extends RefCounted
## Standard FE6 character/class attribute ABI. Only dynamic definitions opt in.
static func apply(unit: Dictionary, class_flags: int, personal_flags: int) -> void:
	var flags := class_flags | personal_flags
	unit.fe6_class_flags = class_flags; unit.fe6_personal_flags = personal_flags; unit.fe6_unit_flags = flags
	unit.supply_provider = bool(flags & 0x200)
	unit.disable_experience = bool(flags & 0x1000000)
	unit.can_steal = bool(flags & 4); unit.can_lockpick = bool(flags & 8)
	unit.canto = bool(flags & 2); unit.flying = bool(flags & 0x1800)
	unit.mounted = bool(flags & 1); unit.lord = bool(flags & 0x2000)
	unit.gender = "female" if flags & 0x4000 else "male"
	unit.critical_bonus = 30 if flags & 0x40 else 0
	unit.can_play = bool(flags & 0x30)
	unit.refresh_action = "Play" if flags & 0x20 else "Dance"
	unit.play_experience = 10
	unit.aid_base = 20 if flags & 0x4000 else 25
	unit.aid = unit.aid_base - int(unit.get("con",0)) if unit.mounted else int(unit.get("con",0))-1
	if flags & 0x40000 and not unit.get_or_add("weapon_types",[]).has("other"): unit.weapon_types.append("other")
