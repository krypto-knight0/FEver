extends TextureRect
## ROM portraits use the usual atlas. Imported portraits draw inside this frame
## with their own transforms.
const Art = preload("res://runtime/art_textures.gd")
const Cards = preload("res://runtime/custom_card_portraits.gd")
var unit: Dictionary = {}
var custom: Dictionary = {}
var custom_texture: Texture2D
var rom_path := ""
var rom_texture: AtlasTexture

func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)

func present(value: Dictionary) -> void:
	unit = value.duplicate(true)
	refresh_art()

func refresh_art() -> void:
	var path := str(unit.get("portrait", ""))
	set_meta("art_path", path)
	var context := unit.duplicate(true)
	context.portrait_id = path.get_file().get_basename().to_int()
	custom = Cards.store.find_portrait(str(unit.get("name", "")), context)
	custom_texture = Cards.store.texture(custom) if not custom.is_empty() else null
	texture = null
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if custom_texture else CanvasItem.TEXTURE_FILTER_NEAREST
	if not custom_texture and not path.is_empty() and ResourceLoader.exists(path):
		var original := Art.texture(path)
		if rom_path != path or rom_texture == null or rom_texture.atlas != original:
			rom_path = path
			rom_texture = AtlasTexture.new()
			rom_texture.atlas = original
			rom_texture.region = Art.original_image(path).get_used_rect()
		texture = rom_texture
	queue_redraw()

func has_portrait() -> bool:
	return texture != null or custom_texture != null

func custom_rect() -> Rect2:
	if custom_texture == null: return Rect2()
	var dimensions := custom_texture.get_size()
	var fitted := dimensions * minf(size.x / dimensions.x, size.y / dimensions.y) * float(custom.get("scale_percent", 100)) / 100.0
	var offset := size * Vector2(float(custom.get("x_percent", 0)), float(custom.get("y_percent", 0))) / 100.0
	return Rect2((size - fitted) / 2 + offset, fitted)

func _draw() -> void:
	if custom_texture == null: return
	var rect := custom_rect()
	if bool(custom.get("flip_h", false)) != flip_h:
		rect.size.x = -rect.size.x
	draw_texture_rect(custom_texture, rect, false)
