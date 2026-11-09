extends RefCounted
## Resolve native class/weapon mappings and animation/palette table pointers.
## Character/profile identities and palette choices remain engine adapters.
const Animations = preload("res://runtime/rom_animation_data.gd")
# Class table pointer/stride/mapping field, animation table, palette table.
const LAYOUTS := {"fe7":[0x178f0,84,52,0x541f4,0x541f8], "fe6":[0x176e0,72,48,0x4b0f8,0x4b11c]}
# FE7's native ballista routine uses a second, raw OBJ palette for each machine.
const BALLISTA_PALETTES := {52:0x1da224,53:0x1da204,54:0x1da244}

static func fail(decoder: RefCounted, reason: String) -> Dictionary:
	decoder.fail("ROM battle animation", reason)
	return {}

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == int(value)

static func select(decoder: RefCounted, game: String, spec: Variant) -> Dictionary:
	if not LAYOUTS.has(game) or not spec is Dictionary or spec.size() != 5:
		return fail(decoder, "Invalid battle selector.")
	if not integer(spec.get("class_id"),1,255) or not integer(spec.get("weapon_type"),0,255) or not integer(spec.get("palette_id"),0,255) or not integer(spec.get("bank"),0,2):
		return fail(decoder, "Invalid class, weapon or palette selector.")
	if not spec.get("item_ids") is Array or spec.item_ids.size() > 255:
		return fail(decoder, "Invalid item override list.")
	var seen := {}
	for id in spec.item_ids:
		if not integer(id,1,255) or seen.has(int(id)): return fail(decoder, "Invalid or duplicate item override.")
		seen[int(id)] = true
	var layout: Array = decoder.layout.get("battle_layout",LAYOUTS[game])
	var class_at: int = decoder.ptr(int(layout[0])) + int(spec.class_id) * int(layout[1])
	if not decoder.require_range(class_at,int(layout[1]),"Battle class record"): return {}
	var mapping: int = decoder.ptr(class_at + int(layout[2]))
	var fallback := 0
	var overrides := {}
	var terminated := false
	for index in range(64):
		var at := mapping + index*4
		if not decoder.require_range(at,4,"Class battle mapping"): return {}
		if decoder.u32(at) == 0:
			terminated = true
			break
		var key: int = decoder.u8(at)
		var kind: int = decoder.u8(at+1)
		var id: int = decoder.u16(at+2)
		if kind not in [0,1] or id == 0: return fail(decoder, "Invalid class battle mapping record.")
		if kind == 0 and not overrides.has(key): overrides[key] = id
		elif kind == 1 and key == int(spec.weapon_type): fallback = id
	if not terminated: return fail(decoder, "Unterminated class battle mapping.")
	var animation := fallback
	if not spec.item_ids.is_empty():
		animation = int(overrides.get(int(spec.item_ids[0]),fallback))
		for item in spec.item_ids:
			if int(overrides.get(int(item),fallback)) != animation:
				return fail(decoder, "Grouped item overrides require separate animation profiles.")
	if animation == 0: return fail(decoder, "Class has no animation for the selected weapon/item.")
	var record: int = decoder.ptr(int(layout[3])) + (animation-1)*32
	if not decoder.require_range(record,32,"Battle animation record"): return {}
	var palette: int = decoder.ptr(record+28)
	if int(spec.palette_id) != 0:
		var at: int = decoder.ptr(int(layout[4])) + (int(spec.palette_id)-1)*16
		if not decoder.require_range(at,16,"Battle palette record"): return {}
		palette = decoder.ptr(at+12)
	if not decoder.require_range(palette,4,"Battle palette"): return {}
	var result := {"animation_id":animation,"record":record,"palette":palette,"bank":int(spec.bank)}
	if game == "fe7" and animation == 140 and not spec.item_ids.is_empty() and BALLISTA_PALETTES.has(int(spec.item_ids[0])):
		var item := int(spec.item_ids[0])
		var pointers: Dictionary = decoder.layout.get("ballista_palette_pointers",{})
		result.secondary_palette = decoder.ptr(int(pointers[item])) if pointers.has(item) else BALLISTA_PALETTES[item]
		if not decoder.require_range(int(result.secondary_palette),32,"Ballista palette"): return {}
	return result if decoder.error.is_empty() else {}

static func profile(decoder: RefCounted, game: String, spec: Variant) -> Dictionary:
	var selected := select(decoder,game,spec)
	if selected.is_empty(): return {}
	var data := Animations.battle(decoder,int(selected.record),game)
	if not decoder.error.is_empty(): return {}
	data.erase("frames")
	data.animation_id = selected.animation_id
	data.source_record = "0x%x" % int(selected.record)
	data.source_palette = "0x%x" % int(selected.palette)
	data.secondary_palette = selected.get("secondary_palette",0)
	return data

static func atlas(decoder: RefCounted, recipe: Dictionary, game: String) -> Dictionary:
	if recipe.size() != 4 or recipe.get("kind") != "battle_rom" or recipe.get("game") != game or recipe.get("side") not in ["left","right"]:
		return fail(decoder, "Invalid battle atlas recipe.")
	var selected := select(decoder,game,recipe.get("selector"))
	if selected.is_empty(): return {}
	var data := Animations.battle(decoder,int(selected.record),game)
	if not decoder.error.is_empty(): return {}
	if data.frames.is_empty(): return fail(decoder, "Battle animation contains no drawable frames.")
	var oam: int = decoder.ptr(int(selected.record) + (20 if recipe.side == "right" else 24))
	if not decoder.require_range(oam,4,"Battle OAM"): return {}
	var result := {"kind":"battle", "frames":data.frames,"oam":oam,"palette":selected.palette,"bank":selected.bank}
	if selected.has("secondary_palette"): result.secondary_palette = selected.secondary_palette
	return result
