class_name BattleRules
extends RefCounted
## Content-independent, deliberately small SRPG ruleset. Values are overridable by a pack.
## This is a prototype ruleset, not an exact implementation of any game.

static func defaults() -> Dictionary:
	return {
		"double_threshold": 4,
		"permadeath": true,
		"triangle_damage": 1,
		"triangle_hit": 15,
		"critical_multiplier": 3,
		"effectiveness_multiplier": 2,
		"two_roll_hit": true,
		"inventory_capacity": 5,
		"durability_mode": "normal",
		"item_durability_mode": "normal",
		"supply_access": "lords",
		"supply_range": 1,
		"chest_unlock_mode": "normal",
		"door_unlock_mode": "normal",
		"wait_enemy_reinforcements": false,
		"weapon_rank_thresholds": {"E": 1, "D": 31, "C": 71, "B": 121, "A": 181, "S": 251},
		"weapon_exp_unpromoted_cap": 181,
		"weapon_exp_cap": 251,
		"weapon_exp_kill_multiplier": 2,
		"promotion_minimum_level": 10,
		"promotion_catalog": {"classes": {}, "promotions": []},
		"allied_factions": [["player", "neutral"]],
		"carrying_stat_divisor": 2,
		# Prototype progression formulas, deliberately separate from game-specific tables.
		"experience_per_level": 100,
		"max_level": 20,
		"combat_experience": 10,
		"miss_experience": 1,
		"kill_experience": 20,
		"level_difference_experience": 1,
		"kill_level_difference_experience": 2,
		"staff_experience": 11,
		"staff_promoted_experience_divisor": 2,
		"stat_caps": {"max_hp": 60, "str": 30, "skill": 30, "speed": 30, "luck": 30, "def": 30, "res": 30, "con": 25, "mov": 15},
		"supports_enabled": true,
		"support_thresholds": [80, 160, 240],
		"support_total_cap": 5,
		"support_range": 3,
		"support_affinities": {
			"fire": {"atk": 0.5, "def": 0.0, "hit": 2.5, "avo": 2.5, "crit": 2.5, "ddg": 0.0},
			"thunder": {"atk": 0.0, "def": 0.5, "hit": 0.0, "avo": 2.5, "crit": 2.5, "ddg": 2.5},
			"wind": {"atk": 0.5, "def": 0.0, "hit": 2.5, "avo": 0.0, "crit": 2.5, "ddg": 2.5},
			"ice": {"atk": 0.0, "def": 0.5, "hit": 2.5, "avo": 2.5, "crit": 0.0, "ddg": 2.5},
			"dark": {"atk": 0.0, "def": 0.0, "hit": 2.5, "avo": 2.5, "crit": 2.5, "ddg": 2.5},
			"light": {"atk": 0.5, "def": 0.5, "hit": 2.5, "avo": 0.0, "crit": 2.5, "ddg": 0.0},
			"anima": {"atk": 0.5, "def": 0.5, "hit": 0.0, "avo": 2.5, "crit": 0.0, "ddg": 2.5}
		},
		"triangle": {"sword": "axe", "axe": "lance", "lance": "sword", "anima": "light", "light": "dark", "dark": "anima"},
		"magic_types": ["anima", "light", "dark", "magic"],
		"terrain": {
			".": {"terrain_id": 1, "name": "Plain", "cost": 1, "defense": 0, "avoid": 0},
			"R": {"terrain_id": 2, "name": "Road", "cost": 1, "defense": 0, "avoid": 0},
			"F": {"terrain_id": 12, "name": "Forest", "cost": 2, "defense": 1, "avoid": 20},
			"M": {"terrain_id": 17, "name": "Mountain", "cost": 3, "defense": 1, "avoid": 30},
			"T": {"terrain_id": 31, "name": "Throne", "cost": 1, "defense": 2, "avoid": 20, "heal": 0.2},
			"H": {"terrain_id": 10, "name": "Fort", "cost": 2, "defense": 2, "avoid": 20, "heal": 0.2},
			"V": {"terrain_id": 5, "name": "Village", "cost": 1, "defense": 0, "avoid": 0},
			"C": {"terrain_id": 32, "name": "Chest", "cost": 1, "defense": 0, "avoid": 0},
			"W": {"terrain_id": 21, "name": "Water", "cost": -1, "defense": 0, "avoid": 0},
			"#": {"terrain_id": 26, "name": "Wall", "cost": -1, "defense": 0, "avoid": 0}
		}
	}
