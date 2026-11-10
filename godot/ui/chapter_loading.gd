extends Control
## The overlay stays on the main thread while data-only work runs off-thread.
var elapsed := 0.0
var caption: Label
var worker: Thread

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := TextureRect.new()
	background.texture = preload("res://art/branding/start.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	caption = Label.new()
	caption.text = "loading..."
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -58
	caption.offset_bottom = -20
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", Color("fff2ce"))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	add_child(caption)
	hide()

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	caption.text = "loading" + ".".repeat(1 + int(elapsed / 0.4) % 3)

func run(job: Callable) -> Dictionary:
	assert(worker == null)
	worker = Thread.new()
	var error := worker.start(job)
	if error != OK:
		worker = null
		return {"error":"Could not start the chapter loading worker (%d)." % error}
	while worker.is_alive(): await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	worker = null
	return {"value":result}

func _exit_tree() -> void:
	if worker != null: worker.wait_to_finish()
