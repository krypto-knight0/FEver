extends "res://ui/battle_board.gd"
const Army = preload("res://engine/army_roster.gd")
const State = preload("res://engine/battle_state.gd")
var placements: Dictionary = {}
var required: Array = []
var drag_id := ""
var pointer := -2
var drag_cell := Vector2.ZERO
var focus_formation := true

func _ready() -> void:
	super._ready()
	resized.connect(_fit_formation)

func configure(source: RefCounted, selection: Array, data: Dictionary) -> void:
	battle = State.new()
	battle.restore(source.serialize())
	battle.chapter.deployment_complete = false
	Army.deploy(battle, selection, placements)
	placements.clear()
	required = Army.forced_ids(source)
	for unit in battle.units:
		if unit.faction == "player" and Army.eligible(unit): placements[str(unit.id)] = battle.position(unit)
	set_map(data)
	_fit_formation.call_deferred()

func _fit_formation() -> void:
	if not focus_formation: return
	if not battle or size.x <= 0 or size.y <= 0: return
	var slots: Array = battle.chapter.get("deployment", {}).get("slots", [])
	if slots.is_empty(): return
	var low := Vector2(slots[0].x, slots[0].y)
	var high := low
	for slot in slots:
		low = low.min(Vector2(slot.x, slot.y))
		high = high.max(Vector2(slot.x, slot.y))
	var span := high - low + Vector2(3, 3)
	var tile := minf(size.x / span.x, size.y / span.y)
	var dimensions := Vector2(battle.width, battle.height)
	zoom = maxf(1.0, tile / minf(size.x / dimensions.x, size.y / dimensions.y))
	tile = minf(size.x / dimensions.x, size.y / dimensions.y) * zoom
	pan = (dimensions * 0.5 - (low + high + Vector2.ONE) * 0.5) * tile
	_view_updated()

func _draw() -> void:
	super._draw()
	if not battle: return
	var tile := map_rect().size.x / float(battle.width)
	for slot in battle.chapter.get("deployment", {}).get("slots", []):
		var occupant: Dictionary = battle.unit_at(Vector2i(slot.x, slot.y))
		if required.has(str(occupant.get("id", ""))): continue
		draw_rect(Rect2(cell_screen_position(Vector2i(slot.x, slot.y)) - Vector2.ONE * tile * 0.46, Vector2.ONE * tile * 0.92), Color("ffff95"), false, 2)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var motion_id: int = event.index if event is InputEventScreenDrag else -1
		if pointer == motion_id and not drag_id.is_empty():
			drag_cell = (event.position - map_rect().position) / (map_rect().size.x / battle.width) - Vector2.ONE * 0.5
			queue_redraw()
			accept_event()
		return
	var pos := Vector2.ZERO
	var id := -1
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		pos = event.position
		id = event.index
		down = event.pressed
		up = not down
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		down = event.pressed
		up = not down
	else: return
	var cell := cell_at(pos)
	if down:
		var unit: Dictionary = battle.unit_at(cell)
		drag_id = str(unit.get("id", ""))
		if not placements.has(drag_id) or required.has(drag_id): drag_id = ""
		drag_cell = Vector2(cell)
		pointer = id
		selected_id = drag_id
	elif up and pointer == id:
		swap_to(drag_id, cell)
		pointer = -2
		drag_id = ""
		selected_id = ""
	queue_redraw()
	accept_event()

func unit_display_cell(unit_id: String) -> Vector2:
	if unit_id == drag_id and not drag_id.is_empty(): return drag_cell
	return super.unit_display_cell(unit_id)

func swap_to(id: String, cell: Vector2i) -> bool:
	if not placements.has(id) or required.has(id): return false
	if not battle.chapter.deployment.slots.any(func(slot): return cell == Vector2i(slot.x, slot.y)): return false
	var other: Dictionary = battle.unit_at(cell)
	var other_id := str(other.get("id", ""))
	if not other.is_empty() and (not placements.has(other_id) or required.has(other_id)): return false
	var actor: Dictionary = battle.get_unit(id)
	var origin: Vector2i = placements[id]
	if battle.movement_cost(actor, cell) <= 0 or (not other.is_empty() and battle.movement_cost(other, origin) <= 0): return false
	actor.x = cell.x
	actor.y = cell.y
	placements[id] = cell
	if not other.is_empty():
		other.x = origin.x
		other.y = origin.y
		placements[other_id] = origin
	queue_redraw()
	return true
