extends HBoxContainer
const Art = preload("res://runtime/art_textures.gd")
const Description = preload("res://ui/item_description.gd")
var records: Dictionary = {}
var list: ItemList
var detail: RichTextLabel
var search: LineEdit
var ready_catalog := false
var indexing := false
var acquisition_visible := false

func _ready() -> void:
	add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 290
	add_child(left)
	search = LineEdit.new()
	search.placeholder_text = "Search items"
	search.custom_minimum_size.y = 46
	search.text_changed.connect(func(_text): _filter())
	left.add_child(search)
	list = preload("res://ui/swipe_item_list.gd").new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(28, 28)
	list.add_theme_font_size_override("font_size", 20)
	list.item_selected.connect(_describe)
	left.add_child(list)
	detail = RichTextLabel.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("normal_font_size", 20)
	add_child(detail)

func configure(pack: Dictionary) -> void:
	acquisition_visible = false
	if not ready_catalog:
		var manifest = _read(str(pack.get("item_manifest", "res://content/fe7/item_manifest.json")))
		for item in manifest.get("items", []):
			if str(item.get("name", "")).strip_edges().is_empty(): continue
			_record(item)
		indexing = false
		ready_catalog = true
	_filter()

func _read(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _record(item: Dictionary) -> Dictionary:
	if item.is_empty(): return {}
	var id := str(int(item.rom_item_id)) if item.has("rom_item_id") else str(item.get("name", ""))
	if not records.has(id): records[id] = {"item":item.duplicate(true), "sources":[]}
	return records[id]

func _filter() -> void:
	list.clear()
	var entries: Array = records.values()
	entries.sort_custom(func(a,b): return str(a.item.get("name", "")) < str(b.item.get("name", "")))
	for record in entries:
		if not preload("res://runtime/text_replacements.gd").matches_search(str(record.item.get("name", "")), search.text): continue
		var path := str(record.item.get("icon", ""))
		list.add_item(str(record.item.get("name", "Item")), Art.texture(path) if ResourceLoader.exists(path) else null)
		list.set_item_metadata(list.item_count - 1, record)
	detail.text = "No matching items."
	if list.item_count > 0: list.select(0); _describe(0)

func _describe(index: int) -> void:
	var record: Dictionary = list.get_item_metadata(index)
	var item: Dictionary = record.item
	detail.text = Description.describe(item)
	detail.text += "\n\nPrice: %d G · %d uses" % [int(item.get("cost_per_use", 0)) * int(item.get("max_uses", item.get("uses", 0))), int(item.get("max_uses", item.get("uses", 0)))]
	if acquisition_visible: detail.text += "\n\nAcquisition\n" + ("\n".join(record.sources) if not record.sources.is_empty() else "Loading acquisition sources…" if indexing else "No acquisition recorded in the playable chapters.")
