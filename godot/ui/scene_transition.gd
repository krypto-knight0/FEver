extends Control
## Reusable presentation only. Change scenes between fade_out and fade_in.
var timing_scale := 1.0
var speed_multiplier := 1.0
var playing := false
var generation := 0
var shade := 0.0
var banner_text := ""
var banner_color := Color("bc3344")
var banner_progress := 0.0
var title: Label
var banner_gradient: GradientTexture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	banner_gradient = GradientTexture2D.new()
	banner_gradient.width = 256
	banner_gradient.height = 2
	banner_gradient.fill_from = Vector2.ZERO
	banner_gradient.fill_to = Vector2.RIGHT
	banner_gradient.gradient = Gradient.new()
	title = Label.new()
	title.mouse_filter = MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("fff2ce"))
	title.add_theme_color_override("font_shadow_color", Color("221923"))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	add_child(title)
	resized.connect(queue_redraw)
	hide()

func cancel() -> void:
	generation += 1
	playing = false
	shade = 0
	banner_text = ""
	hide()
	if title: title.hide()

func _exit_tree() -> void: cancel()

func fade_out(duration: float = 0.16) -> void:
	generation += 1
	var token := generation
	playing = true
	banner_text = ""
	show()
	if await _animate(duration, token, func(t): shade = t): playing = false

func fade_in(duration: float = 0.22) -> void:
	generation += 1
	var token := generation
	playing = true
	banner_text = ""
	shade = 1
	show()
	if await _animate(duration, token, func(t): shade = 1.0 - t):
		playing = false
		hide()

func phase_banner(text_value: String, color: Color = Color("bc3344")) -> void:
	generation += 1
	var token := generation
	playing = true
	shade = 0
	banner_text = text_value
	banner_color = color
	var bright := Color("267dff") if banner_color.b > banner_color.r else Color("f03e55")
	banner_gradient.gradient.offsets = PackedFloat32Array([0.0,0.5,1.0])
	banner_gradient.gradient.colors = PackedColorArray([Color(bright.darkened(0.68),0.5),Color(bright.lightened(0.22),0.95),Color(bright.darkened(0.68),0.5)])
	banner_progress = 0
	show()
	if not await _animate(0.18, token, func(t): banner_progress = t * 0.2): return
	if not await _animate(0.65, token, func(t): banner_progress = 0.2 + t * 0.6): return
	if not await _animate(0.18, token, func(t): banner_progress = 0.8 + t * 0.2): return
	if token == generation: cancel()

func _animate(duration: float, token: int, update: Callable) -> bool:
	var elapsed := 0.0
	duration = maxf(0.001, duration * timing_scale / maxf(0.1, speed_multiplier))
	while elapsed < duration:
		if token != generation or not is_inside_tree(): return false
		update.call(clampf(elapsed / duration, 0, 1))
		queue_redraw()
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if token != generation: return false
	update.call(1.0)
	queue_redraw()
	return true

func _draw() -> void:
	if not visible: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, shade))
	title.visible = not banner_text.is_empty()
	if banner_text.is_empty(): return
	var alpha := clampf(minf(banner_progress / 0.2, (1.0 - banner_progress) / 0.2), 0, 1)
	var stripe := Rect2(0, size.y * 0.5 - 62, size.x, 124)
	# Keep the phase recognizable at a glance with a bright faction-colored
	# center, soft edges, and the original game's narrow horizontal sweep.
	draw_texture_rect(banner_gradient, stripe, false, Color(1,1,1,alpha))
	var shine := Color(0.8,0.94,1.0,alpha * 0.18)
	var clear := Color(0.8,0.94,1.0,0.0)
	draw_polygon(PackedVector2Array([stripe.position, Vector2(stripe.end.x,stripe.position.y),stripe.end,Vector2(stripe.position.x,stripe.end.y)]),PackedColorArray([shine,shine,clear,clear]))
	draw_line(stripe.position, stripe.position + Vector2(size.x, 0), Color("e4d3a4") * Color(1,1,1,alpha), 3)
	draw_line(stripe.end - Vector2(size.x, 0), stripe.end, Color("e4d3a4") * Color(1,1,1,alpha), 3)
	title.text = banner_text
	title.position = stripe.position + Vector2((1.0 - alpha) * size.x * (1 if banner_progress < 0.5 else -1), 0)
	title.size = stripe.size
	title.modulate.a = alpha
