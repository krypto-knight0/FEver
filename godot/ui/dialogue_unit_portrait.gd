extends "res://ui/unit_portrait.gd"
## Uses exactly the dialogue import's transform, including its facing convention.
const DialogueArt = preload("res://runtime/custom_portraits.gd")
var left_side := true
var viewport_extent := Vector2.ZERO
var fit_to_frame := false

func refresh_art() -> void:
	var path := str(unit.get("portrait", ""))
	set_meta("art_path", path)
	var context := unit.duplicate(true)
	context.portrait_id = path.get_file().get_basename().to_int()
	custom = DialogueArt.store.find_portrait(str(unit.get("name", "")), context)
	custom_texture = DialogueArt.store.texture(custom) if not custom.is_empty() else null
	texture = null
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if custom_texture else CanvasItem.TEXTURE_FILTER_NEAREST
	if not custom_texture and not path.is_empty() and ResourceLoader.exists(path):
		custom_texture = Art.region_texture(path, Rect2(Art.original_image(path).get_used_rect()))
	flip_h = left_side
	queue_redraw()

static func art_rect(dimensions: Vector2, config: Dictionary, viewport: Vector2, left: bool) -> Rect2:
	var gutter := minf(400, viewport.x * 0.29)
	var extent := dimensions * gutter * 1.13 / 96.0
	if not config.is_empty(): extent = dimensions * gutter * 1.13 * 80.0 / 96.0 / maxf(1, dimensions.y) * float(config.get("scale_percent", 100)) / 100.0
	var center_x := gutter * 0.5 if left else viewport.x - gutter * 0.5
	var offset := viewport * Vector2(float(config.get("x_percent", 0)) * (-1 if left else 1), float(config.get("y_percent", 0))) / 100.0
	return Rect2(Vector2(clampf(center_x - extent.x * 0.5, 0, maxf(0, viewport.x - extent.x)), viewport.y - extent.y) + offset, extent)

func custom_rect() -> Rect2:
	if fit_to_frame and custom_texture:
		var dimensions := custom_texture.get_size()
		var extent := dimensions * minf(size.x / dimensions.x, size.y / dimensions.y) * float(custom.get("scale_percent", 100)) / 100.0
		var offset := size * Vector2(float(custom.get("x_percent", 0)) * (-1 if left_side else 1), float(custom.get("y_percent", 0))) / 100.0
		return Rect2((size - extent) * 0.5 + offset, extent)
	return art_rect(custom_texture.get_size(), custom, viewport_extent if viewport_extent != Vector2.ZERO else size, left_side) if custom_texture else Rect2()

func _has_point(point: Vector2) -> bool:
	return custom_rect().has_point(point)

func _draw() -> void:
	if custom_texture == null: return
	var rect := custom_rect()
	if left_side != bool(custom.get("flip_h", false)): rect.size.x = -rect.size.x
	draw_texture_rect(custom_texture, rect, false)
