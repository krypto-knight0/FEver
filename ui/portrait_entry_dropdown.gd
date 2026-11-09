extends "res://ui/chapter_dropdown.gd"
## Reuse the touch-scrollable chapter picker for large portrait collections.
var selected := -1
var item_count: int:
	get: return entries.size()

func clear() -> void:
	entries.clear()
	selected = -1

func add_item(title: String) -> void:
	entries.append({"title":title})

func set_item_metadata(index: int, value: Variant) -> void:
	entries[index].metadata = value

func get_item_metadata(index: int) -> Variant:
	return entries[index].get("metadata")

func select(index: int) -> void:
	selected = index if index >= 0 and index < entries.size() else -1
	text = str(entries[selected].title) if selected >= 0 else "Select portrait"

func _select_entry(index: int) -> void:
	select(index)
	super._select_entry(index)

func entry_order() -> Array:
	# Sort presentation only: callers retain their original indices and IDs.
	var order := range(entries.size())
	var pinned := not entries.is_empty() and str(entries[0].title).begins_with("All ")
	if pinned: order.erase(0)
	order.sort_custom(func(a, b):
		var left := str(TranslationServer.translate(str(entries[a].title))).strip_edges()
		var right := str(TranslationServer.translate(str(entries[b].title))).strip_edges()
		return a < b if left == right else left.naturalnocasecmp_to(right) < 0)
	if pinned: order.push_front(0)
	return order
