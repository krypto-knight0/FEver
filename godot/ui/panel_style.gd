extends RefCounted
## Shared readable gradient panels with optional translucent map backgrounds.
static func create(enemy: bool = false, opacity: float = 0.91) -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.26, 0.10, 0.24, opacity), Color(0.68, 0.18, 0.28, opacity), Color(0.90, 0.34, 0.38, opacity)] if enemy else [Color(0.08, 0.12, 0.36, opacity), Color(0.12, 0.29, 0.65, opacity), Color(0.18, 0.49, 0.84, opacity)])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0.35, 1.0)
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 12)
	return style
