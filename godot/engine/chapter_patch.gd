extends RefCounted
## Structural chapter changes. Entity lists address a snapshot by ID, allowing
## atomic renames without letting an insertion redirect somebody else's patch.
const MAX_LIST := 16384
const MAX_DEPTH := 128

static func copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

static func apply(value: Variant, delta: Variant) -> Dictionary:
	var errors: Array[String] = []
	var result: Variant = _apply(copy(value), delta, errors, 0)
	return {"value":result if errors.is_empty() else null, "error":"" if errors.is_empty() else errors[0]}

static func fail(errors: Array[String], reason: String) -> Variant:
	if errors.is_empty(): errors.append(reason)
	return null

static func integer(value: Variant, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= high and value == int(value)

static func ids(values: Variant) -> bool:
	if not values is Array or values.size() > MAX_LIST: return false
	var seen := {}
	for id in values:
		if not id is String or id.is_empty() or seen.has(id): return false
		seen[id] = true
	return true

static func _apply(value: Variant, delta: Variant, errors: Array[String], depth: int) -> Variant:
	if not errors.is_empty(): return null
	if depth > MAX_DEPTH or not delta is Dictionary: return fail(errors, "Invalid or excessively nested chapter patch.")
	if delta.is_empty(): return value
	match delta.get("kind"):
		"replace":
			if delta.size() != 2 or not delta.has("value"): return fail(errors, "Invalid replacement patch.")
			return copy(delta.value)
		"dict":
			if delta.size() != 3 or not value is Dictionary or not delta.get("set") is Dictionary or not ids(delta.get("remove")):
				return fail(errors, "Invalid dictionary patch.")
			for key in delta.remove: value.erase(key)
			for key in delta.set:
				if not key is String or key in delta.remove: return fail(errors, "Conflicting dictionary patch fields.")
				value[key] = _apply(value.get(key), delta.set[key], errors, depth + 1)
			return value
		"list":
			if delta.size() != 3 or not value is Array or not integer(delta.get("length"), MAX_LIST) or not delta.get("items") is Dictionary:
				return fail(errors, "Invalid positional list patch.")
			value.resize(int(delta.length))
			for key in delta.items:
				if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= value.size():
					return fail(errors, "Positional patch index exceeds its list.")
				value[int(key)] = _apply(value[int(key)], delta.items[key], errors, depth + 1)
			return value
		"entities":
			return _entities(value, delta, errors, depth)
	return fail(errors, "Unknown chapter patch operation.")

static func _entities(value: Variant, delta: Dictionary, errors: Array[String], depth: int) -> Variant:
	if delta.size() != 5 or not value is Array or value.size() > MAX_LIST or not delta.get("set") is Dictionary or not delta.get("add") is Array or not ids(delta.get("remove")) or not ids(delta.get("order")):
		return fail(errors, "Invalid identity list patch.")
	if delta.set.size() > MAX_LIST or delta.add.size() > MAX_LIST:
		return fail(errors, "Identity patch exceeds the list limit.")
	for id in delta.set:
		if not id is String or id.is_empty() or id in delta.remove: return fail(errors, "Conflicting identity patch fields.")
	var input_ids := {}
	var output_ids := {}
	var order: Array[String] = []
	for entry in value:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or input_ids.has(entry.id):
			return fail(errors, "Identity patch requires unique source IDs.")
		var id: String = entry.id
		input_ids[id] = true
		if id in delta.remove: continue
		var changed: Variant = _apply(entry, delta.set[id], errors, depth + 1) if delta.set.has(id) else entry
		if not errors.is_empty(): return null
		if not _append_entity(changed, output_ids, order): return fail(errors, "Identity patch produces missing or duplicate IDs.")
	# An absent source ID is skipped: never patch a neighbouring unit or revive
	# a member removed from its ROM group. Explicit additions remain independent.
	for entry in delta.add:
		if not _append_entity(copy(entry), output_ids, order): return fail(errors, "Identity patch addition has a missing or duplicate ID.")
	if order.size() > MAX_LIST: return fail(errors, "Identity patch exceeds the list limit.")
	var result: Array = []
	for id in delta.order:
		if output_ids.has(id):
			result.append(output_ids[id])
			output_ids.erase(id)
	# New ROM members have no authored order entry. Preserve their relative order
	# after known members rather than truncating them to the stock list length.
	for id in order:
		if output_ids.has(id): result.append(output_ids[id])
	return result

static func _append_entity(entry: Variant, indexed: Dictionary, order: Array[String]) -> bool:
	if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or indexed.has(entry.id): return false
	indexed[entry.id] = entry
	order.append(entry.id)
	return true
