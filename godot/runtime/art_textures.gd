extends RefCounted
## Load project or ROM-backed textures and crop them in source-pixel coordinates.

static func texture(path: String) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path): return load(path)
	return null

static func region_texture(path: String, region: Rect2) -> Texture2D:
	var source := texture(path)
	if source == null: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas

static func original_image(path: String) -> Image:
	var source := texture(path)
	if source == null: return null
	var image := source.get_image()
	if image == null: return null
	if image.is_compressed() and image.decompress() != OK: return null
	image.convert(Image.FORMAT_RGBA8)
	return image
