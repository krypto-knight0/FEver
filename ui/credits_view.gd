extends ColorRect
## Draw the ROM's 240-pixel viewport over its native scrolling staff artwork.
signal finished
signal advanced(position: float)
var roll: Dictionary = {}
var position_in_roll := 0.0
var paused := false
var texture: Texture2D
var viewport_rect := Rect2()
var save_clock := 0.0
var ending_hold := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.BLACK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ImageTexture.create_from_image(roll.image)
	var buttons := HBoxContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.offset_top = -68; buttons.offset_left = 20; buttons.offset_right = -20; buttons.offset_bottom = -12
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(buttons)
	var pause := Button.new(); pause.text = "Pause"; pause.custom_minimum_size = Vector2(140,52)
	pause.pressed.connect(func(): paused = not paused; pause.text = "Resume" if paused else "Pause")
	buttons.add_child(pause)
	var skip := Button.new(); skip.text = "Continue"; skip.custom_minimum_size = Vector2(140,52)
	skip.pressed.connect(func(): finished.emit()); buttons.add_child(skip)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if paused: return
	if position_in_roll < float(roll.distance):
		position_in_roll = minf(float(roll.distance),position_in_roll+delta*float(roll.speed))
	else:
		ending_hold += delta
		if ending_hold >= 10.0:
			set_process(false); finished.emit(); return
	save_clock += delta
	if save_clock >= 2.0:
		save_clock = 0.0; advanced.emit(position_in_roll)
	queue_redraw()

func _draw() -> void:
	if texture == null: return
	var scale_factor := minf(size.x/240.0,maxf(1.0,size.y-88.0)/160.0)
	var extent := Vector2(240,160)*scale_factor
	viewport_rect = Rect2(Vector2((size.x-extent.x)/2.0,(size.y-88.0-extent.y)/2.0),extent)
	# Native BG3 starts 160 pixels above the first strip: staff enters from below.
	var source_y := float(roll.closing_offset) if ending_hold >= 5.0 else floorf(position_in_roll)-160.0
	var blank_rows := maxf(0.0,-source_y)
	var visible_rows := minf(160.0-blank_rows,float(texture.get_height())-maxf(0.0,source_y))
	if visible_rows <= 0.0: return
	var destination := Rect2(viewport_rect.position+Vector2(0,blank_rows*scale_factor),Vector2(extent.x,visible_rows*scale_factor))
	draw_texture_rect_region(texture,destination,Rect2(0,maxf(0.0,source_y),240,visible_rows))
