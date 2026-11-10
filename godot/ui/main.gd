extends Control
const NativeEvents = preload("res://engine/native_event_runner.gd")

const Battle = preload("res://engine/battle_state.gd")
const Army = preload("res://engine/army_roster.gd")
const Rogue = preload("res://engine/rogue_mode.gd")
var rogue_overlay: Control
const Difficulty = preload("res://engine/campaign_difficulty.gd")
const Board = preload("res://ui/battle_board.gd")
const Art = preload("res://runtime/art_textures.gd")
var PACK_PATH := "res://content/fe7/manifest.json"
const SaveCodec = preload("res://engine/save_codec.gd")
var save_codec = SaveCodec.new()
var background_save_codec = SaveCodec.new()
var save_worker: Thread
var pending_save: Dictionary = {}
var SAVE_PATH := ""
const GOLD:= Color("e5c78e")
const INK:= Color("dae4e5")

var stats_panel: PanelContainer
var portrait_import_worker: Thread
var portrait_import_panel: ColorRect
var actions_panel: PanelContainer
var forecast_panel: PanelContainer
var dialogue_panel: PanelContainer
var info_overlay: ColorRect
var cheats_overlay: ColorRect
var quality_overlay: ColorRect
var cheats_message: Label
var difficulty_menu: OptionButton
var difficulty_message: Label
var last_map_tap:= Vector2i(-999, -999)
var last_map_tap_time:= 0
var last_map_tap_kind:= ""
var last_map_tap_battle: RefCounted
var settings_overlay: ColorRect
var info_button: Button
var settings_button: Button
var skip_button: Button
var dialogue_pointer_button: Button
var command_menu_open:= false
var pending_weapon:= ""
var queued_attack:= false
var weapon_buttons: VBoxContainer
var trade_button: Button
var trade_menu: Control
var trade_partner:= ""
var trade_partners: Array = []
var details_overlay: ColorRect
var skills_overlay: ColorRect
var details_label: RichTextLabel
var details_portrait: TextureRect
var details_supply_button: Button
var advanced_overlay: ColorRect
var advanced_message: Label
var item_glossary: Control
var shop_overlay: ColorRect
var shop_heading: Label
var shop_list: ItemList
var shop_message: Label
var shop_mode:= "buy"
var shop_slots: Array = []
var shop_battle: RefCounted
var objective_label: Label
var settings_message: Label
var music_toggle: CheckButton
var library_categories: OptionButton
var music_library: ItemList
var library_previous_music:= ""
var music_library_active:= false
var sound_toggle: CheckButton
var music_slider: HSlider
var sound_slider: HSlider
var music_value: Label
var sound_value: Label
var text_speed_menu: OptionButton
var cutscene_toggle: OptionButton
var battle_cutscene_mode := 0
var unlimited_supports := false
var unlimited_supports_toggle: CheckButton
var shatter_morale := false
var shatter_morale_toggle: CheckButton
var pending_unlock := Vector2i(-1, -1)
var text_speed: int = 2
var battle_cutscenes: bool = true
var dialogue_view: Control
var dialogue_right_portrait: TextureRect
var dialogue_background: TextureRect
var grid_toggle: CheckButton
var audio_manager: Node
var voice_player: Node
var voice_library: Control
var skill_library: Control
var voice_overlay: ColorRect
var custom_overlay: ColorRect
var translations_overlay: ColorRect
var translations_panel: Control
var voice_import_worker: Thread
var voice_status: Label
var voice_import_button: Button
var voice_clear_button: Button
var voice_delete_prompt: ConfirmationDialog
var dialogue_touch_id: int = -1
var busy: bool = false
var animations_enabled: bool = true
var auto_turn_enabled: bool = true
var transition_pending: bool = false
var campaign: Dictionary = {"completed_chapters": []}
var chapter_start: Dictionary = {}
var enemy_phase_checkpoint: Dictionary = {}
var pack: Dictionary
var chapter: Dictionary
var chapter_path: String = ""
var outcome_presented: String = ""
var battle: RefCounted
var board: Control
var cutscene: Control
var catalog: Array = []
var selected_id: String = ""
var pending_target: String = ""
var browsing: bool = false
var title_label: Label
var subtitle_label: Label
var phase_label: Label
var status_label: Label
var unit_label: RichTextLabel
var unit_portrait: TextureRect
var forecast_label: RichTextLabel
var log_label: RichTextLabel
var wait_button: Button
var attack_button: Button
var interact_button: Button
var support_button: Button
var end_button: Button
var auto_button: Button
var steal_button: Button
var save_button: Button
var dialogue_overlay: ColorRect
var dialogue_speaker: Label
var dialogue_text: Label
var dialogue_portrait: TextureRect
var dialogue_portrait_path: String = ""
var dialogue_lines: Array = []
var library_overlay: ColorRect
var library_list: ItemList
var library_filter: LineEdit
var library_ids: Array = []
var viewed_map: Dictionary = {}
var items_button: Button
var items_overlay: ColorRect
var items_list: ItemList
var items_target: OptionButton
var items_heading: Label
var items_message: Label
var item_target_ids: Array = []
var inventory_menu: Control
var rescue_button: Button
var give_button: Button
var take_button: Button
var drop_button: Button
var talk_button: Button
var choice_overlay: ColorRect
var choice_heading: Label
var choice_list: VBoxContainer
var choice_mode:= ""
var choice_ids: Array[String] = []
var last_unit_tap:= ""
var last_unit_tap_msec:= 0
var tutorial_toggle: CheckButton
var skip_all_tutorials:= false
var scene_transition: Control
var dialogue_transition:= false
var dialogue_generation:= 0
var pending_story_actions: Array = []
var initial_phase_pending:= false
var undo_history: Array = []
var undo_overlay: ColorRect
var undo_list: ItemList
var undo_detail: Label
var help_overlay: ColorRect
var recruit_label: Label
var terrain_panel: PanelContainer
var terrain_cell:= Vector2i(-1, -1)
var details_view: Control
var movement_speed_menu: OptionButton
var battle_speed_menu: OptionButton
var durability_menu: OptionButton
var movement_speed:= 1.0
var battle_speed:= 1.0
var durability_mode:= "normal"
var panel_motion = preload("res://ui/panel_motion.gd").new()
var weapon_pointer_button: Button
var weapon_pointer_id:= -1
var weapon_pointer_origin:= Vector2.ZERO
var weapon_pointer_canceled:= false
var chapter_cover: ColorRect
var chapter_loading: Control
var chapter_handoff:= false
var record_overlay: ColorRect
var record_button: Button
var info_commands: GridContainer
var actions_scroll: ScrollContainer
var actions_list: VBoxContainer
var weapon_pointer_key:= ""
var weapon_pointer_battle: RefCounted
var weapon_pointer_actor:= ""
var weapon_pointer_target:= ""
var weapon_touch_msec:= -1000
var weapon_pointer_rect:= Rect2()
var weapon_pointer_scroll:= 0
var weapon_pointer_scrolling:= false
var end_turn_overlay: ColorRect
var end_turn_message: Label
var end_turn_confirm_button: Button
var end_turn_cancel_button: Button
var end_turn_battle: RefCounted
var end_turn_number:= -1
var weapon_pointer_bounds: Dictionary = {}
var backdrop_overlay: ColorRect
var backdrop_view: VBoxContainer
var backdrop_button: Button
var supports_overlay: ColorRect
var supports_view: VBoxContainer
var supports_button: Button
var details_support_button: Button
var details_unit_id:= ""
var support_manifest: Dictionary = {}
var supports_return_to_details:= false
var supply_button: Button
var play_button: Button
var supply_overlay: ColorRect
var supply_view: Control
var supply_access_menu: OptionButton
var chest_unlock_menu: OptionButton
var supply_access:= "lords"
var chest_unlock_mode:= "normal"
var all_enemy_ranges:= false
var title_screen: Control
var route_select: Control
var route_selection_context:= ""
var shake_strength:= 1.0
var shake_menu: OptionButton
var door_unlock_mode:= "normal"
var door_unlock_menu: OptionButton
var staff_button: Button
var selected_staff:= -1
var pending_assist: Dictionary = {}
var queued_assist:= false
var assist_choices: VBoxContainer
var terrain_overlay: ColorRect
var terrain_heading: Label
var terrain_costs: RichTextLabel
var gold_cheat_button: Button
var promotion_manifest: Dictionary = {}
var promotion_panel: Control
var promotion_battle: RefCounted
var auto_best_weapon:= false
var optional_convoy_merchant:= false
var support_library: Control
var support_any_distance:= false
var unlock_staff_chests:= false
var wait_enemy_reinforcements := false
var reinforcement_wait_toggle: OptionButton
var reinforcement_mode := 0
var unlock_staff_toggle: CheckButton
var support_distance_toggle: CheckButton
var epilogue_view: Control
var convoy_merchant_toggle: CheckButton
var auto_weapon_toggle: CheckButton
var permadeath:= true
var auto_promote_lords := false
var auto_promote_toggle: CheckButton
var permadeath_toggle: CheckButton
var deployment_overlay: ColorRect
var deployment_heading: Label
var deployment_list: VBoxContainer
var deployment_message: Label
var deployment_start: Button
var deployment_selection: Array = []
var deployment_checks: Dictionary = {}
var deployment_battle: RefCounted
var loot_overlay: ColorRect
var loot_keep_button: Button
var loot_name: Label
var loot_icon: TextureRect
var loot_battle: RefCounted
var item_durability_mode:= "normal"
var item_durability_menu: OptionButton
var conversation_log: Array = []
var record_heading: Label
var active_reward: Dictionary = {}
var loot_item: Dictionary = {}
var loot_actor:= ""
var loot_supply_button: Button
var loot_in_unit:= false
var deployment_map: Control
var deployment_scroll: ScrollContainer
var pending_site:= -1

func _ready() -> void:
	var selected_game: String = preload("res://runtime/rom_assets.gd").game_id
	PACK_PATH = "res://content/" + selected_game + "/manifest.json"
	SAVE_PATH = preload("res://runtime/game_identity.gd").save_path(selected_game,preload("res://runtime/rom_assets.gd").rom_digest)
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	get_tree().quit_on_go_back = false
	_build_theme()
	_build_interface()
	pack = _read_json(PACK_PATH)
	save_codec.configure(pack)
	background_save_codec.configure(pack)
	promotion_manifest = _read_json(str(pack.get("promotion_manifest", ""))) if pack.has("promotion_manifest") else {}
	support_manifest = _read_json(str(pack.get("support_manifest", ""))) if pack.has("support_manifest") else {}
	backdrop_view.configure(_read_json(str(pack.get("scene_manifest", ""))), false)
	dialogue_view.configure_animations(str(pack.get("portrait_animation_manifest", "")))
	board.configure_animations(str(pack.get("map_animation_manifest", "res://content/fe7/rom/animations.json")))
	if ResourceLoader.exists("res://audio/audio_manager.gd"):
		audio_manager = load("res://audio/audio_manager.gd").new()
		add_child(audio_manager)
		audio_manager.configure(str(pack.get("audio_manifest", "")), false)
	voice_player = preload("res://audio/voice_player.gd").new()
	voice_player.store = preload("res://runtime/voice_store.gd").new(str(pack.id))
	add_child(voice_player)
	board.rom_sound_requested.connect(func(id):
		if audio_manager: audio_manager.play_rom_sfx(id))
	board.voice_requested.connect(func(unit, action): voice_player.play_unit(unit, action))
	board.strike_presented.connect(func(strike): _sfx("miss" if not strike.get("hit", false) else ("no_damage" if int(strike.get("damage", 0)) == 0 else ("critical" if strike.get("critical", false) else "hit"))))
	var catalog_data:= _read_json(pack.get("map_catalog", ""))
	catalog = catalog_data.get("maps", [])
	cutscene = load("res://ui/battle_cutscene.gd").new()
	add_child(cutscene)
	cutscene.configure(str(pack.get("battle_animation_manifest", "")))
	cutscene.strike_presented.connect(func(strike): _sfx("miss" if not strike.get("hit", false) else ("no_damage" if int(strike.get("damage", 0)) == 0 else ("critical" if strike.get("critical", false) else "hit"))))
	cutscene.level_presented.connect(func(_id, _entry): _sfx("level_up"))
	cutscene.stat_upgraded.connect(func(_id, _stat, _gain): _sfx("stat_up"))
	cutscene.sound_requested.connect(_sfx)
	cutscene.voice_requested.connect(func(unit, action): voice_player.play_unit(unit, action))
	cutscene.visibility_changed.connect(func():
		var covers_map: bool = cutscene.visible and not cutscene.actors.is_empty()
		board.visible = not covers_map
		board.set_process(not covers_map))
	if audio_manager:
		cutscene.level_fanfare_duration = float(audio_manager.manifest.get("sfx", {}).get("level_up", {}).get("duration_seconds", 1.45))
	scene_transition = load("res://ui/scene_transition.gd").new()
	add_child(scene_transition)
	chapter_cover = ColorRect.new()
	chapter_cover.color = Color.BLACK
	chapter_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chapter_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(chapter_cover)
	chapter_cover.hide()
	chapter_loading = preload("res://ui/chapter_loading.gd").new()
	add_child(chapter_loading)
	_load_preferences()
	_start_battle()
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_smoke_test")
	else:
		call_deferred("_startup_title")

func _startup_title() -> void:

	if get_tree().current_scene != self: return
	_open_title()

func _open_title() -> void:
	if route_select: route_select.hide()
	route_selection_context = ""
	busy = false
	if not title_screen:
		title_screen = load("res://ui/title_screen.gd").new()
		add_child(title_screen)
		title_screen.start_requested.connect(func(): _open_route_selection("new_game"))
		title_screen.continue_requested.connect(_title_continue)
		title_screen.back_requested.connect(_return_to_library)
	_cancel_scene_presentation()
	dialogue_overlay.hide()
	board.hide()
	for panel in [info_button, skip_button, actions_panel, forecast_panel, stats_panel, terrain_panel]: panel.hide()
	if audio_manager: audio_manager.stop_music()
	title_screen.configure(str(pack.get("title_manifest", "res://content/fe7/title_manifest.json")), FileAccess.file_exists(SAVE_PATH))
	title_screen.show()
	move_child(title_screen, get_child_count() - 1)
	_music("title")

func _return_to_library() -> void:
	if audio_manager: audio_manager.stop_music()
	get_tree().change_scene_to_file("res://runtime/rom_start.tscn")

func _open_route_selection(context: String) -> void:
	if not route_select:
		route_select = preload("res://ui/route_select.gd").new()
		add_child(route_select)
		route_select.selected.connect(_select_story_route)
		route_select.cancelled.connect(func(): busy = false;route_selection_context = "";_open_title())
	if route_select.visible: return
	route_selection_context = context
	busy = true
	route_select.present(context == "after_tutorial", str(pack.id))
	move_child(route_select, get_child_count() - 1)

func _select_story_route(route: String) -> void:
	if route not in (["fe6_unit_1"] if pack.id == "fe6" else ["fe7_unit_3", "fe7_unit_1", "fe7_unit_2"]): return
	var context:= route_selection_context
	route_selection_context = ""
	busy = false
	if context == "after_tutorial":
		if route == "fe7_unit_3": return
		campaign.route = route
		_transition_chapter()
	else:
		_title_new_game(route, Difficulty.MODES[route_select.difficulty_picker.selected])

func _title_new_game(route: String = "fe7_unit_3", difficulty: String = "normal") -> void:
	title_screen.hide()
	board.show()
	info_button.show()
	campaign = {"completed_chapters": [], "route": route, "difficulty": Difficulty.normalize(difficulty)}
	_start_battle(str(pack.get("campaign_starts", {}).get(route, pack.get("start_chapter", ""))))

func _title_continue() -> void:
	var previous = battle
	_load_game()
	if battle != previous:
		title_screen.hide()
		board.show()
		info_button.show()
	else:
		var notice:= AcceptDialog.new()
		notice.dialog_text = status_label.text
		title_screen.add_child(notice)
		notice.popup_centered(Vector2i(520, 180))
		var dismiss:= func():
			if notice.is_queued_for_deletion(): return
			notice.queue_free()
			_open_title()
		notice.confirmed.connect(dismiss)
		notice.canceled.connect(dismiss)
		notice.close_requested.connect(dismiss)

func _read_json(path: String) -> Dictionary:
	if path.is_empty(): return {}
	if not preload("res://runtime/rom_assets.gd").ensure_resource(path): return {}
	if not FileAccess.file_exists(path):
		push_error("Missing content: " + path)
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		push_error("Expected JSON object: " + path)
		return {}
	return value

func _build_theme() -> void:
	theme = preload("res://ui/app_theme.gd").create()

func _build_interface() -> void:
	board = Board.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.cell_pressed.connect(_on_cell_pressed)
	board.cell_hovered.connect(_on_cell_hovered)
	board.cell_held.connect(_on_cell_held)
	board.view_changed.connect(_position_floating_panels)
	add_child(board)
	stats_panel = load("res://ui/unit_status_panel.gd").new()
	add_child(stats_panel)
	unit_portrait = stats_panel.portrait
	unit_label = stats_panel.unit_label
	stats_panel.unit_pressed.connect(_open_unit_details)
	stats_panel.hide()
	terrain_panel = load("res://ui/terrain_panel.gd").new()
	add_child(terrain_panel)
	terrain_panel.hide()
	terrain_panel.inspect_requested.connect(_open_terrain_costs)
	actions_panel = _panel()
	actions_panel.custom_minimum_size.x = 160
	add_child(actions_panel)

	actions_scroll = ScrollContainer.new()
	actions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	actions_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	actions_panel.add_child(actions_scroll)
	var actions:= VBoxContainer.new()
	actions_list = actions
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 4)
	actions_scroll.add_child(actions)
	attack_button = _button(actions, "Attack", _open_attack)
	attack_button.hide()
	play_button = _button(actions, "Play", func(): _open_choice("play"))
	talk_button = _button(actions, "Talk", func(): _open_choice("talk"))
	actions.move_child(talk_button, 0)
	interact_button = _button(actions, "Interact", _interact)
	weapon_buttons = VBoxContainer.new()
	weapon_buttons.add_theme_constant_override("separation", 4)
	actions.add_child(weapon_buttons)
	assist_choices = VBoxContainer.new()
	assist_choices.add_theme_constant_override("separation", 4)
	actions.add_child(assist_choices)
	support_button = _button(actions, "Support", _support)
	items_button = _button(actions, "Items", _open_items)
	staff_button = _button(actions, "Staff", _open_staff)
	trade_button = _button(actions, "Trade", _open_trade)
	supply_button = _button(actions, "Supply", _open_supply)
	rescue_button = _button(actions, "Rescue", func(): _open_choice("rescue"))
	give_button = _button(actions, "Give", func(): _open_choice("give"))
	take_button = _button(actions, "Take", func(): _open_choice("take"))
	drop_button = _button(actions, "Drop", func(): _open_choice("drop"))
	steal_button = _button(actions, "Steal", _open_steal)
	wait_button = _button(actions, "Wait", _wait_unit)
	actions_panel.hide()
	forecast_panel = load("res://ui/combat_forecast.gd").new()
	add_child(forecast_panel)
	forecast_label = forecast_panel.forecast_label
	_ignore_pointer(forecast_panel)
	forecast_panel.hide()
	for floating in [stats_panel, actions_panel, forecast_panel]:
		floating.minimum_size_changed.connect(func(): call_deferred("_position_floating_panels"))
	info_button = _icon_button("res://ui/icons/info.svg", "Chapter information", Vector2(-64, -64), _open_info)
	terrain_panel.visibility_changed.connect(_position_info_button)
	skip_button = _icon_button("res://ui/icons/skip.svg", "Skip to the next scene", Vector2(-120, -64), _skip_dialogue)
	skip_button.hide()
	for button in [info_button, skip_button]:
		button.anchor_left = 1.0
		button.anchor_right = 1.0
		button.anchor_top = 1.0
		button.anchor_bottom = 1.0
	_build_info()
	_build_settings()
	_build_terrain_costs()
	_build_supply()
	_build_help()
	_build_record()
	_build_end_turn_confirmation()
	_build_library()
	_build_backdrops()
	board.unit_drag_started.connect(func(id):
		if not busy and not dialogue_overlay.visible:
			_select_unit(battle.get_unit(id))
			command_menu_open = false
			_refresh())
	board.unit_dropped.connect(func(_id, cell): _on_cell_pressed(cell))
	_build_supports()
	_build_items()
	_build_trade()
	_build_unit_details()
	_build_shop()
	_build_choices()
	_build_undo()
	_build_preparation_and_loot()
	promotion_panel = load("res://ui/promotion_result_panel.gd").new()
	promotion_panel.sound_requested.connect(_sfx)
	add_child(promotion_panel)
	promotion_panel.dismissed.connect(_finish_promotion)
	_build_dialogue()
	resized.connect(_position_floating_panels)

func _icon_button(path: String, hint: String, at: Vector2, action: Callable) -> Button:
	var button:= _button(self, "", action)
	button.icon = load(path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 25)
	button.tooltip_text = hint
	button.position = at
	button.size = Vector2(48, 48)
	return button

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func _modal(width: float, height: float, blurred: bool = false) -> Array:
	var overlay:= ColorRect.new()
	overlay.color = Color(0.01, 0.02, 0.04, 0.65)
	if blurred:
		var blur_material:= ShaderMaterial.new()
		blur_material.shader = preload("res://ui/soft_blur.gdshader")
		overlay.material = blur_material
		overlay.color = Color.WHITE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var panel:= _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = - width / 2
	panel.offset_right = width / 2
	panel.offset_top = - height / 2
	panel.offset_bottom = height / 2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)
	var fit:= func():
		var extent:= Vector2(minf(width, size.x - 32), minf(height, size.y - 32))
		panel.offset_left = - extent.x / 2
		panel.offset_right = extent.x / 2
		panel.offset_top = - extent.y / 2
		panel.offset_bottom = extent.y / 2
	resized.connect(fit)
	overlay.tree_exiting.connect(func():
		if resized.is_connected(fit): resized.disconnect(fit))
	fit.call()
	var column:= VBoxContainer.new()
	panel.add_child(column)
	overlay.gui_input.connect(func(event):
		if overlay == deployment_overlay or overlay == loot_overlay: return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_set_panel_visible(overlay, false))
	overlay.hide()
	return [overlay, column]

func _build_info() -> void:
	var modal:= _modal(760, 550, true)
	info_overlay = modal[0]
	var column: VBoxContainer = modal[1]
	column.add_child(_label(str(ProjectSettings.get_setting("application/config/name")) + "  ·  v" + str(ProjectSettings.get_setting("application/config/version")), 16, GOLD))
	title_label = _label("", 28)
	column.add_child(title_label)
	subtitle_label = _label("", 15, Color("91a9ae"))
	column.add_child(subtitle_label)
	phase_label = _label("", 19, GOLD)
	column.add_child(phase_label)
	objective_label = _label("", 19)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(objective_label)
	recruit_label = _label("", 17, GOLD)
	recruit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(recruit_label)
	status_label = _label("", 16, GOLD)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacer:= Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	info_commands = GridContainer.new()
	info_commands.columns = 2
	info_commands.add_theme_constant_override("h_separation", 12)
	info_commands.add_theme_constant_override("v_separation", 8)
	column.add_child(info_commands)
	record_button = _menu_button(info_commands, "Log", "record", _open_record)
	_menu_button(info_commands, "Undo…", "undo", _open_undo)
	supports_button = _menu_button(info_commands, "Supports", "support", func(): _open_supports())
	auto_button = _menu_button(info_commands, "Auto Turn", "end_turn", _auto_turn)
	_menu_button(info_commands, "Help", "help", _open_help)
	end_button = _menu_button(info_commands, "End Turn", "end_turn", _request_end_turn)
	_menu_button(info_commands, "Close", "close", func(): _set_panel_visible(info_overlay, false))
	settings_button = _menu_button(info_commands, "Settings", "settings", _open_settings)

func _build_record() -> void:
	var modal:= _modal(760, 580)
	record_overlay = modal[0]
	record_heading = _label("BATTLE RECORD", 25, GOLD)
	modal[1].add_child(record_heading)
	log_label = _rich(240)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(log_label)
	_menu_button(modal[1], "Back to Info", "info", func(): _set_panel_visible(record_overlay, false);_open_info())

func _build_end_turn_confirmation() -> void:
	var modal:= _modal(600, 320)
	end_turn_overlay = modal[0]
	modal[1].add_child(_label("END PLAYER TURN?", 25, GOLD))
	end_turn_message = _label("", 20)
	end_turn_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_turn_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(end_turn_message)
	end_turn_confirm_button = _button(modal[1], "End turn", _confirm_end_turn)
	end_turn_cancel_button = _button(modal[1], "Keep playing", func():
		end_turn_battle = null
		_set_panel_visible(end_turn_overlay, false))

func _request_end_turn() -> void:
	if deployment_overlay.visible: return
	if busy or dialogue_transition or not battle or dialogue_overlay.visible or battle.phase != "player" or not battle.outcome.is_empty(): return
	_set_panel_visible(info_overlay, false)
	var remaining: Array[String] = []
	for unit in battle.units:
		if unit.faction == "player" and int(unit.hp) > 0 and str(unit.get("rescued_by", "")).is_empty() and ( not unit.acted or unit.get("canto_active", false)):
			remaining.append(str(unit.get("name", unit.id)))
	if remaining.is_empty():
		_end_turn()
		return
	end_turn_battle = battle
	end_turn_number = battle.turn
	end_turn_message.text = "%d %s still %s actions or movement remaining. End their turn?\n\n%s" % [remaining.size(), "unit" if remaining.size() == 1 else "units", "has" if remaining.size() == 1 else "have", ", ".join(remaining)]
	_set_panel_visible(end_turn_overlay, true)
	move_child(end_turn_overlay, get_child_count() - 1)

func _confirm_end_turn() -> void:
	var valid: bool = battle != null and end_turn_battle == battle and end_turn_number == battle.turn and battle.phase == "player"
	end_turn_battle = null
	panel_motion.forget(end_turn_overlay)
	end_turn_overlay.hide()
	if valid: _end_turn()

func _record_text() -> String:
	if dialogue_overlay.visible: return "\n\n".join(conversation_log)
	var text := "\n".join(battle.events_log)
	if not Rogue.active(battle): return text
	for id in battle.chapter.rogue.get("history", {}):
		var entry: Dictionary = battle.chapter.rogue.history[id]
		var original: Array = entry.get("original_offer", [])
		var offered: Array = original.map(func(skill): return Rogue.title(str(skill)))
		text += "\n\n%s: %s" % [entry.get("chapter_title", str(id).replace("fe7_", "").replace("_", " ").capitalize()), ", ".join(offered)]
		if entry.get("offer", original) != original:
			var rerolled: Array = entry.offer.map(func(skill): return Rogue.title(str(skill)))
			text += "\nRerolled: " + ", ".join(rerolled)
		var choice := Rogue.title(str(entry.chosen)) if entry.has("chosen") else "Not chosen"
		var names: Array[String] = []
		for key in ["recipient", "second_recipient"]:
			var recipient := str(entry.get(key, ""))
			if not recipient.is_empty(): names.append(str(battle.get_unit(recipient).get("name", recipient.capitalize())))
		if not names.is_empty(): choice += " -> " + " / ".join(names)
		if not str(entry.get("weapon_type", "")).is_empty(): choice += " (" + str(entry.weapon_type).capitalize() + ")"
		text += "\nChosen: " + choice
	return text

func _open_record() -> void:
	if busy and not deployment_overlay.visible: return
	record_heading.text = "CONVERSATION LOG" if dialogue_overlay.visible else "BATTLE RECORD"
	log_label.text = _record_text()

	_set_panel_visible(info_overlay, false)
	_set_panel_visible(record_overlay, true)
	move_child(record_overlay, get_child_count() - 1)

func _menu_button(parent: Node, title: String, icon_name: String, action: Callable) -> Button:
	var button:= _button(parent, title, action)
	button.icon = load("res://ui/icons/" + icon_name + ".svg")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.add_theme_constant_override("h_separation", 12)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

func _build_settings() -> void:
	var modal:= _modal(820, 700, true)
	settings_overlay = modal[0]
	var column: VBoxContainer = modal[1]
	column.add_child(_label("SETTINGS", 23, GOLD))
	var columns:= HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll:= preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var inset:= MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 18)
	scroll.add_child(inset)
	inset.add_child(columns)
	var preferences:= VBoxContainer.new()
	preferences.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preferences.add_theme_constant_override("separation", 8)
	columns.add_child(preferences)
	var commands:= VBoxContainer.new()
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_theme_constant_override("separation", 6)
	columns.add_child(commands)
	grid_toggle = CheckButton.new()
	grid_toggle.text = "Show grid"
	grid_toggle.custom_minimum_size.y = 48
	grid_toggle.toggled.connect(func(enabled): board.show_grid = enabled;board.queue_redraw();_save_preferences())
	preferences.add_child(grid_toggle)
	music_toggle = CheckButton.new()
	music_toggle.text = "Music"
	music_toggle.button_pressed = true
	music_toggle.custom_minimum_size.y = 48
	music_toggle.toggled.connect(_set_music_enabled)
	preferences.add_child(music_toggle)
	var music_controls:= _volume_control(preferences, 50)
	music_slider = music_controls[0]
	music_value = music_controls[1]
	music_slider.value_changed.connect(func(value):
		music_value.text = "%d%%" % int(value)
		_apply_audio_preferences()
		_save_preferences())
	sound_toggle = CheckButton.new()
	sound_toggle.text = "Sound effects"
	sound_toggle.button_pressed = true
	sound_toggle.custom_minimum_size.y = 48
	sound_toggle.toggled.connect(_set_sound_enabled)
	preferences.add_child(sound_toggle)
	var sound_controls:= _volume_control(preferences, 80)
	sound_slider = sound_controls[0]
	sound_value = sound_controls[1]
	sound_slider.value_changed.connect(func(value):
		sound_value.text = "%d%%" % int(value)
		_apply_audio_preferences()
		_save_preferences())
	preferences.add_child(_label("Text speed", 18, GOLD))
	text_speed_menu = OptionButton.new()
	for option in ["Slow", "Normal", "Fast", "Instant"]: text_speed_menu.add_item(option)
	text_speed_menu.selected = text_speed
	text_speed_menu.custom_minimum_size.y = 48
	text_speed_menu.item_selected.connect(func(index):
		text_speed = index
		dialogue_view.text_speed = index
		if text_speed == 3: dialogue_view.reveal()
		_save_preferences())
	preferences.add_child(text_speed_menu)
	preferences.add_child(_label("Battle cutscenes", 18, GOLD))
	cutscene_toggle = OptionButton.new()
	for option in ["Always", "Player phase", "Never"]: cutscene_toggle.add_item(option)
	cutscene_toggle.custom_minimum_size.y = 48
	cutscene_toggle.item_selected.connect(func(index): battle_cutscene_mode = index; battle_cutscenes = index != 2; _save_preferences())
	preferences.add_child(cutscene_toggle)
	tutorial_toggle = CheckButton.new()
	tutorial_toggle.text = "Skip all tutorials"
	tutorial_toggle.custom_minimum_size.y = 48
	tutorial_toggle.toggled.connect(func(enabled): skip_all_tutorials = enabled;_save_preferences())
	preferences.add_child(_label("Map movement", 18, GOLD))
	movement_speed_menu = _speed_option(preferences, func(value): movement_speed = value;_apply_speed_preferences();_save_preferences())
	preferences.add_child(_label("Battle animations", 18, GOLD))
	battle_speed_menu = _speed_option(preferences, func(value): battle_speed = value;_apply_speed_preferences();_save_preferences())
	preferences.add_child(_label("Battle screen shake", 18, GOLD))
	shake_menu = OptionButton.new()
	for title in ["Off", "Subtle", "Normal", "Strong"]: shake_menu.add_item(title)
	shake_menu.custom_minimum_size.y = 48
	shake_menu.item_selected.connect(func(index): shake_strength = [0.0, 0.5, 1.0, 1.5][index];_apply_speed_preferences();_save_preferences())
	preferences.add_child(shake_menu)
	var quality_fields:= _settings_subpanel("Quality of Life", false)
	quality_fields.add_child(tutorial_toggle)
	permadeath_toggle = CheckButton.new()
	permadeath_toggle.text = "Permadeath"
	permadeath_toggle.custom_minimum_size.y = 48
	permadeath_toggle.button_pressed = permadeath
	permadeath_toggle.toggled.connect(func(enabled):
		if Rogue.active(battle):
			permadeath_toggle.set_pressed_no_signal(true)
			return
		permadeath = enabled
		if battle: battle.rules.permadeath = enabled
		_save_preferences())
	quality_fields.add_child(permadeath_toggle)
	var death_hint:= _label("Off: defeated allies miss the next battle, then return. Lords and required allies must still survive.", 14)
	death_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_fields.add_child(death_hint)
	auto_promote_toggle = CheckButton.new()
	auto_promote_toggle.text = "Lords auto-promote at level 20"
	auto_promote_toggle.custom_minimum_size.y = 48
	auto_promote_toggle.toggled.connect(func(enabled):
		auto_promote_lords = enabled
		if battle: battle.rules.auto_promote_lords = enabled
		_save_preferences())
	quality_fields.add_child(auto_promote_toggle)
	auto_weapon_toggle = CheckButton.new()
	auto_weapon_toggle.text = "Auto-select best weapon"
	auto_weapon_toggle.custom_minimum_size.y = 48
	auto_weapon_toggle.toggled.connect(func(enabled): auto_best_weapon = enabled;_save_preferences())
	quality_fields.add_child(auto_weapon_toggle)
	support_distance_toggle = CheckButton.new()
	support_distance_toggle.text = "Grow supports anywhere on the map"
	support_distance_toggle.custom_minimum_size.y = 48
	support_distance_toggle.tooltip_text = "Deployed support partners gain support each turn, regardless of distance."
	support_distance_toggle.toggled.connect(func(enabled):
		support_any_distance = enabled
		_apply_supply_preferences()
		_save_preferences())
	quality_fields.add_child(support_distance_toggle)
	unlock_staff_toggle = CheckButton.new()
	unlock_staff_toggle.text = "Unlock staff also opens chests"
	unlock_staff_toggle.toggled.connect(func(enabled): unlock_staff_chests = enabled;_apply_supply_preferences();_save_preferences())
	quality_fields.add_child(unlock_staff_toggle)
	quality_fields.add_child(_label("Enemy reinforcements", 18, GOLD))
	reinforcement_wait_toggle = OptionButton.new()
	for option in ["Same turn attack", "Same turn with warning", "Attack next turn"]: reinforcement_wait_toggle.add_item(option)
	reinforcement_wait_toggle.custom_minimum_size.y = 48
	reinforcement_wait_toggle.tooltip_text = "Warnings mark possible enemy arrival tiles before the next enemy phase."
	reinforcement_wait_toggle.item_selected.connect(func(index): reinforcement_mode = index; wait_enemy_reinforcements = index == 2; _apply_supply_preferences(); _save_preferences(); _refresh())
	quality_fields.add_child(reinforcement_wait_toggle)
	unlimited_supports_toggle = CheckButton.new()
	unlimited_supports_toggle.text = "Unlimited support conversations (five bonus ranks)"
	unlimited_supports_toggle.toggled.connect(func(enabled): unlimited_supports = enabled; _apply_supply_preferences(); _save_preferences())
	quality_fields.add_child(unlimited_supports_toggle)
	shatter_morale_toggle = CheckButton.new()
	shatter_morale_toggle.text = "Defeat the strongest enemy to win route/survive chapters"
	shatter_morale_toggle.toggled.connect(func(enabled): shatter_morale = enabled; _apply_supply_preferences(); _save_preferences())
	quality_fields.add_child(shatter_morale_toggle)
	convoy_merchant_toggle = CheckButton.new()
	convoy_merchant_toggle.text = "Allow Convoy Merchant to stay behind"
	convoy_merchant_toggle.custom_minimum_size.y = 48
	convoy_merchant_toggle.toggled.connect(func(enabled):
		optional_convoy_merchant = enabled
		_apply_supply_preferences()
		_save_preferences())
	quality_fields.add_child(convoy_merchant_toggle)
	quality_fields.add_child(_label("Weapon durability", 18, GOLD))
	durability_menu = OptionButton.new()
	for option in ["Normal", "Repair at start · pay", "Repair at start · free", "Unlimited durability"]: durability_menu.add_item(option)
	durability_menu.custom_minimum_size.y = 48
	durability_menu.item_selected.connect(func(index):
		durability_mode = ["normal", "repair_paid", "repair_free", "infinite"][index]
		if battle: battle.set_durability_mode(durability_mode)
		_save_preferences()
		_refresh())
	quality_fields.add_child(durability_menu)
	quality_fields.add_child(_label("Item durability", 18, GOLD))
	item_durability_menu = OptionButton.new()
	for option in ["Normal", "Repair at start · pay", "Repair at start · free", "Unlimited durability"]: item_durability_menu.add_item(option)
	item_durability_menu.custom_minimum_size.y = 48
	item_durability_menu.item_selected.connect(func(index):
		item_durability_mode = ["normal", "repair_paid", "repair_free", "infinite"][index]
		if battle: battle.rules.item_durability_mode = item_durability_mode
		_save_preferences())
	quality_fields.add_child(item_durability_menu)
	var repair_hint:= _label("Repairs apply next chapter. Paid repairs can take gold below zero.", 14)
	repair_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_fields.add_child(repair_hint)
	quality_fields.add_child(_label("Supply access", 18, GOLD))
	supply_access_menu = OptionButton.new()
	for option in ["Lords and adjacent allies", "Any unit · anytime in player phase"]: supply_access_menu.add_item(option)
	supply_access_menu.custom_minimum_size.y = 48
	supply_access_menu.item_selected.connect(func(index):
		supply_access = ["lords", "anywhere"][index]
		_apply_supply_preferences()
		_save_preferences())
	quality_fields.add_child(supply_access_menu)
	quality_fields.add_child(_label("Chest keys", 18, GOLD))
	chest_unlock_menu = OptionButton.new()
	for option in ["Carry keys normally", "Also use chest keys from Supply", "Open ordinary chests for free"]: chest_unlock_menu.add_item(option)
	chest_unlock_menu.custom_minimum_size.y = 48
	chest_unlock_menu.item_selected.connect(func(index):
		chest_unlock_mode = ["normal", "supply_keys", "free"][index]
		_apply_supply_preferences()
		_save_preferences())
	quality_fields.add_child(chest_unlock_menu)
	quality_fields.add_child(_label("Ordinary doors", 18, GOLD))
	door_unlock_menu = OptionButton.new()
	for option in ["Carry door keys normally", "Also use door keys from Supply", "Open ordinary doors for free"]: door_unlock_menu.add_item(option)
	door_unlock_menu.custom_minimum_size.y = 48
	door_unlock_menu.item_selected.connect(func(index): door_unlock_mode = ["normal", "supply_keys", "free"][index];_apply_supply_preferences();_save_preferences())
	quality_fields.add_child(door_unlock_menu)
	var lock_hint:= _label("Mission gates and special locks still require their associated key or trigger.", 14)
	lock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_fields.add_child(lock_hint)
	var advanced_modal:= _modal(640, 650)
	advanced_overlay = advanced_modal[0]
	advanced_overlay.visibility_changed.connect(_sync_settings_scroll)
	var advanced: VBoxContainer = advanced_modal[1]
	advanced.add_child(_label("ADVANCED", 25, GOLD))
	_button(advanced, "Export Save", func(): _advanced_file("export_save"))
	_button(advanced, "Import Save", func(): _advanced_file("import_save"))
	_button(advanced, "Export Personal Skill Config", func(): _advanced_file("export_skills"))
	_button(advanced, "Import Personal Skill Config", func(): _advanced_file("import_skills"))
	_button(advanced, "Reset Personal Skills to Defaults", func():
		preload("res://engine/personal_skill_config.gd").reset()
		_refresh_personal_config()
		advanced_message.text = "Default personal skills restored.")
	_button(advanced, "Export diagnostics", func(): get_node("/root/Diagnostics").show_export(self))
	_button(advanced, "Third-party notices", func(): preload("res://ui/third_party_notices.gd").show_notices(self))
	advanced_message = _label("", 16, GOLD)
	advanced_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advanced.add_child(advanced_message)
	_button(advanced, "Back to Settings", func(): advanced_overlay.hide())
	save_button = _button(commands, "Save", func(): _save_game();settings_message.text = status_label.text)
	_button(commands, "Resume", func(): _load_game();settings_message.text = status_label.text)
	_button(commands, "Restart Chapter", _confirm_restart)
	backdrop_button = _button(commands, "Library", _open_backdrops)
	_button(commands, "Custom", _open_custom)
	var chapters:= preload("res://ui/chapter_dropdown.gd").new()
	chapters.name = "ChapterDropdown"
	chapters.entries = pack.get("chapters", [])
	chapters.pressed.connect(func(): chapters.entries = pack.get("chapters", []))
	chapters.item_selected.connect(func(index):
		var entry: Dictionary = pack.get("chapters", [])[index]
		_confirm_chapter(entry.path, entry.title))
	var cheat_fields:= _settings_subpanel("Cheats", true)
	cheat_fields.add_child(_label("Campaign difficulty", 19, GOLD))
	difficulty_menu = OptionButton.new()
	for label in Difficulty.LABELS: difficulty_menu.add_item(label)
	difficulty_menu.custom_minimum_size.y = 48
	difficulty_menu.item_selected.connect(func(index): _set_campaign_difficulty(Difficulty.MODES[index]))
	cheat_fields.add_child(difficulty_menu)
	cheat_fields.add_child(chapters)
	difficulty_message = _label("", 16)
	difficulty_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cheat_fields.add_child(difficulty_message)
	gold_cheat_button = _button(cheat_fields, "+10,000 gold", _grant_gold)
	_button(cheat_fields, "Free movement · this turn", _cheat_movement)
	_button(cheat_fields, "Deal 99 / take 0 damage · this turn", _cheat_combat)
	_button(cheat_fields, "Defeat all current enemies", _cheat_defeat)
	_button(cheat_fields, "Clear Fog of War · this chapter", func(): _cheat_environment("clear_fog"))
	_button(cheat_fields, "Ignore weather movement · this chapter", func(): _cheat_environment("ignore_weather"))
	cheats_message = _label("Free movement refreshes player actions and allows moving to any open tile for this turn. Enemy drops go to Supply. Cheats can be undone.", 16)
	cheats_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cheat_fields.add_child(cheats_message)
	_button(commands, "Quality of Life", func():
		quality_overlay.show();move_child(quality_overlay, get_child_count() - 1))
	_button(commands, "Cheats", func(): _refresh_difficulty_setting();cheats_overlay.show();move_child(cheats_overlay, get_child_count() - 1))
	_button(commands, "Advanced", func(): advanced_overlay.show();move_child(advanced_overlay, get_child_count() - 1))
	_button(commands, "Main Menu", _exit_game)
	settings_message = _label("", 15, GOLD)
	settings_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(settings_message)
	_button(column, "Close", func(): _set_panel_visible(settings_overlay, false))

func _advanced_file(action: String) -> void:
	var picker:= FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action.begins_with("export") else FileDialog.FILE_MODE_OPEN_FILE
	picker.use_native_dialog = true
	var app_name := str(ProjectSettings.get_setting("application/config/name"))
	picker.filters = PackedStringArray(["*.json ; " + app_name + " JSON"])
	picker.current_file = app_name + "-" + str(pack.id) + "-save.json" if action.ends_with("save") else app_name + "-personal-skills.json"
	add_child(picker)
	picker.file_selected.connect(func(path): _advanced_selected(action, path);picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)

func _advanced_selected(action: String, path: String) -> void:
	var config = preload("res://engine/personal_skill_config.gd")
	if action == "import_skills":
		var error: String = config.import_file(path)
		if error.is_empty(): _refresh_personal_config()
		advanced_message.text = config.report.summary("personal skill overrides") if error.is_empty() else error
		return
	if action == "import_save":
		var input:= FileAccess.open(path, FileAccess.READ)
		if not input or input.get_length() > 134217728:
			advanced_message.text = "Could not read save (maximum 128 MB).";return
		var parsed_data = JSON.parse_string(input.get_as_text())
		if not parsed_data is Dictionary:
			advanced_message.text = "Invalid save JSON; current battle preserved.";return
		parsed_data = save_codec.decode(parsed_data, 16 if OS.has_feature("mobile") else 64, true)
		if not save_codec.error.is_empty():
			advanced_message.text = save_codec.error;return
		var previous = battle
		_restore_game_data(parsed_data)
		if battle == previous:
			advanced_message.text = status_label.text;return
		undo_history = parsed_data.get("undo_history", []).slice(-16 if OS.has_feature("mobile") else -64).filter(_valid_undo_entry) if parsed_data.get("undo_history", []) is Array else []
		_save_game()
		advanced_overlay.hide()
		return
	var data: Dictionary
	if action == "export_save":
		data = _action_snapshot()
		data.undo_history = undo_history
		data = save_codec.encode(data)
		if not save_codec.error.is_empty():
			advanced_message.text = save_codec.error;return
	else:
		config.ensure_loaded()
		var characters:= {}
		for id in config.defaults:
			characters[id] = config.definition(id).duplicate(true)
			characters[id].description = config.description(id)
		data = {"schema_version": 1, "characters": characters}
	var output:= FileAccess.open(path, FileAccess.WRITE)
	if not output:
		advanced_message.text = "Could not create the export.";return
	output.store_string(JSON.stringify(data, "" if action == "export_save" else "\t"))
	output.flush()
	advanced_message.text = "Export saved." if output.get_error() == OK else "Could not finish the export."
	output.close()

func _refresh_personal_config() -> void:
	if battle:
		for unit in Army.all_units(battle): Rogue.Personal.initialize(unit)
	if deployment_overlay.visible: deployment_overlay._refresh()
	_refresh()

func _settings_subpanel(title: String, cheat: bool) -> VBoxContainer:
	var modal:= _modal(640, 650 if not cheat else 530)
	var overlay: ColorRect = modal[0]
	if cheat: cheats_overlay = overlay
	else: quality_overlay = overlay
	overlay.visibility_changed.connect(_sync_settings_scroll)
	modal[1].add_child(_label(title, 25, GOLD))
	var scroll:= preload("res://ui/swipe_scroll.gd").new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(scroll)
	var margin:= MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var fields:= VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	margin.add_child(fields)
	_button(modal[1], "Back to Settings", func(): overlay.hide())
	return fields

func _set_campaign_difficulty(value: String) -> void:
	if Rogue.active(battle): return
	campaign.difficulty = Difficulty.normalize(value)
	_refresh_difficulty_setting()
	_save_game()

func _refresh_difficulty_setting() -> void:
	for button in cheats_overlay.find_children("*", "Button", true, false):
		if button.text in ["+10,000 gold", "Free movement · this turn", "Defeat all current enemies", "Clear Fog of War · this chapter", "Ignore weather movement · this chapter"]:
			button.disabled = deployment_overlay != null and deployment_overlay.visible
	var selected:= Difficulty.normalize(campaign.get("difficulty", "normal"))
	var current:= Difficulty.normalize(chapter.get("difficulty", "normal"))
	difficulty_menu.disabled = Rogue.active(battle)
	difficulty_menu.select(Difficulty.MODES.find(selected))
	difficulty_message.text = "Current chapter: %s. %s" % [Difficulty.label(current), "Changes apply after restarting or entering a new chapter." if selected == current else Difficulty.label(selected) + " is selected for the next restart or chapter."]

func _cheat_environment(key: String) -> void:
	if busy or browsing or not battle: return
	var checkpoint:= _action_snapshot()
	battle.rules[key] = true
	if key == "clear_fog": battle.rules.fog_radius = 0
	_remember_action(checkpoint, "Clear fog" if key == "clear_fog" else "Ignore weather movement")
	cheats_message.text = "Applied for the current chapter."
	_refresh()

func _cheat_movement() -> void:
	if busy or browsing or not battle or battle.phase != "player" or not battle.outcome.is_empty():
		cheats_message.text = "Use this cheat during an active player turn.";return
	var checkpoint:= _action_snapshot()
	if battle.enable_free_movement():
		_deselect()
		_remember_action(checkpoint, "Free movement this turn")
		cheats_message.text = "Player units can move to any open tile this turn."
		_refresh()

func _cheat_combat() -> void:
	if busy or browsing or not battle or battle.phase != "player" or not battle.outcome.is_empty():
		cheats_message.text = "Use this cheat during an active player turn."; return
	var checkpoint := _action_snapshot()
	if battle.enable_combat_cheat():
		_remember_action(checkpoint, "Deal 99 / take 0 damage this turn")
		cheats_message.text = "Player units have 100% hit, deal 99 damage, and take 0 damage until the next player turn."
		_refresh()

func _cheat_defeat() -> void:
	if busy or browsing or not battle or battle.phase != "player" or not battle.outcome.is_empty():
		cheats_message.text = "Use this cheat during an active player turn.";return
	var checkpoint:= _action_snapshot()
	var count: int = battle.defeat_current_enemies()
	_remember_action(checkpoint, "Defeat %d enemies" % count)
	_deselect()
	cheats_overlay.hide();settings_overlay.hide()
	status_label.text = "Defeated %d enemies." % count
	_refresh()
	_check_outcome()

func _grant_gold() -> void:
	if busy or browsing or not battle: return
	var checkpoint:= _action_snapshot()
	battle.gold += 10000
	_remember_action(checkpoint, "Grant 10,000 gold")
	settings_message.text = "Added 10,000 gold. Treasury: %d G." % battle.gold
	cheats_message.text = settings_message.text
	_sfx("select")
	_refresh()

func _import_portraits(kind: String = "dialogue") -> void:
	if portrait_import_worker and portrait_import_worker.is_started(): return
	if not portrait_import_panel:
		portrait_import_panel = preload("res://ui/portrait_import_panel.gd").new()
		add_child(portrait_import_panel)
		portrait_import_panel.visibility_changed.connect(_sync_settings_scroll)
		portrait_import_panel.import_requested.connect(_choose_portrait_zip)
		portrait_import_panel.background_import_requested.connect(func(): _choose_portrait_zip("backgrounds"))
		portrait_import_panel.map_import_requested.connect(func(): _choose_portrait_zip("maps"))
		portrait_import_panel.sprite_import_requested.connect(func(): _choose_portrait_zip("sprites"))
		portrait_import_panel.originals_requested.connect(_restore_original_art)
		portrait_import_panel.delete_art_requested.connect(_delete_custom_art)
		portrait_import_panel.defaults_saved.connect(_refresh_custom_portraits)
	move_child(portrait_import_panel, get_child_count() - 1)
	portrait_import_panel.open_panel(kind)

func _choose_portrait_zip(kind: String = "combined") -> void:
	if portrait_import_worker and portrait_import_worker.is_started(): return
	var picker:= FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.zip ; Custom artwork pack"])
	picker.use_native_dialog = true
	add_child(picker)
	picker.file_selected.connect(func(path):
		_import_portrait_file(path, kind)
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)

func _import_portrait_file(path: String, kind: String = "combined") -> void:
	if portrait_import_worker and portrait_import_worker.is_started(): return
	var store = preload("res://runtime/custom_card_portraits.gd").store if kind == "cards" else preload("res://runtime/custom_portraits.gd").store
	if kind == "backgrounds": store = preload("res://runtime/custom_backdrops.gd").store
	elif kind == "maps": store = preload("res://runtime/custom_maps.gd").store
	elif kind == "sprites": store = preload("res://runtime/custom_sprites.gd").store
	settings_message.text = "Importing artwork…"
	if portrait_import_panel: portrait_import_panel.set_importing(true)
	portrait_import_worker = Thread.new()
	var started:= portrait_import_worker.start( func():
		return preload("res://runtime/character_art_import.gd").import_pack(path) if kind == "combined" else store.import_pack(path, false))
	if started != OK:
		settings_message.text = "Cannot start portrait import. Try again."
		if portrait_import_panel:
			portrait_import_panel.set_importing(false)
			portrait_import_panel.status.text = settings_message.text
		return
	while portrait_import_worker.is_alive(): await get_tree().process_frame
	var failure: String = portrait_import_worker.wait_to_finish()
	if failure.is_empty():
		store.reload()
		if kind == "combined": preload("res://runtime/custom_card_portraits.gd").store.reload()
	settings_message.text = ("Backgrounds imported." if kind == "backgrounds" else "Character art imported." if kind == "combined" else ("Unit-card portraits imported." if kind == "cards" else "Dialogue portraits imported.")) if failure.is_empty() else failure
	if kind == "maps" and failure.is_empty(): settings_message.text = "Battle maps imported."
	if kind == "sprites" and failure.is_empty(): settings_message.text = "Map sprites imported."
	var import_report = preload("res://runtime/character_art_import.gd").report if kind == "combined" else store.report
	if failure.is_empty(): settings_message.text = import_report.summary("artwork entries")
	if portrait_import_panel:
		portrait_import_panel.set_importing(false)
		portrait_import_panel.refresh_values()
		portrait_import_panel.status.text = settings_message.text
	get_node("/root/Diagnostics").record("portrait_import", {"ok": failure.is_empty(), "error": failure, "skipped":import_report.warnings})
	_refresh_custom_portraits()

func _refresh_custom_portraits() -> void:
	if cutscene: cutscene.refresh_art()
	board.refresh_art()
	if deployment_overlay and deployment_overlay.map: deployment_overlay.map.refresh_art()
	dialogue_view.refresh_art()
	for card in [stats_panel, deployment_overlay.status_card]:
		if card and not card.unit.is_empty():
			var was_visible: bool = card.visible
			card.present(card.unit)
			card.visible = was_visible
	if details_view: details_view.portrait.refresh_art()
	if forecast_panel.visible: forecast_panel.present(forecast_panel.attacker, forecast_panel.defender, forecast_panel.forecast)
	if supports_view: supports_view.refresh_art()
	_update_custom_library()
	_select_library_category(library_categories.selected)

func _restore_original_art(kind: String) -> void:
	if portrait_import_worker and portrait_import_worker.is_started(): return
	var store = preload("res://runtime/custom_portraits.gd").store
	if kind == "cards": store = preload("res://runtime/custom_card_portraits.gd").store
	elif kind == "backgrounds": store = preload("res://runtime/custom_backdrops.gd").store
	elif kind == "maps": store = preload("res://runtime/custom_maps.gd").store
	elif kind == "sprites": store = preload("res://runtime/custom_sprites.gd").store
	store.set_enabled( not store.enabled)
	_refresh_custom_portraits()
	portrait_import_panel.refresh_values()
	portrait_import_panel.status.text = "Custom artwork enabled." if store.enabled else "Original artwork enabled."

func _delete_custom_art() -> void:
	if portrait_import_worker and portrait_import_worker.is_started(): return
	var failed:= false
	for store in portrait_import_panel.art_stores().values():
		if store.delete_all() != OK: failed = true
	preload("res://runtime/custom_backdrops.gd").store.set_enabled(false)
	_refresh_custom_portraits()
	portrait_import_panel.refresh_values()
	portrait_import_panel.status.text = "Some files could not be deleted. Please try again." if failed else "All custom art deleted. Original artwork restored."

func _sync_settings_scroll() -> void:
	var blocked:= (custom_overlay and custom_overlay.visible) or (translations_overlay and translations_overlay.visible) or (voice_overlay and voice_overlay.visible) or (advanced_overlay and advanced_overlay.visible) or (portrait_import_panel and portrait_import_panel.visible) or (cheats_overlay and cheats_overlay.visible) or (quality_overlay and quality_overlay.visible)
	for scroll in settings_overlay.find_children("*", "ScrollContainer", true, false):
		if scroll.has_method("cancel_gesture"): scroll.cancel_gesture()
		scroll.set_process_input( not blocked)

func _exit_tree() -> void:
	_flush_background_save()
	if voice_import_worker and voice_import_worker.is_started(): voice_import_worker.wait_to_finish()
	if portrait_import_worker and portrait_import_worker.is_started(): portrait_import_worker.wait_to_finish()

func _volume_control(parent: Node, initial: float) -> Array:
	var row:= HBoxContainer.new()
	parent.add_child(row)
	var slider:= HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 48)
	row.add_child(slider)
	var value:= _label("%d%%" % int(initial), 18)
	value.custom_minimum_size.x = 50
	row.add_child(value)
	return [slider, value]

func _open_info() -> void:
	if is_instance_valid(epilogue_view) or (title_screen and title_screen.visible): return
	if busy and not deployment_overlay.visible: return
	for button in info_commands.get_children():
		if button is Button and button.text in ["Undo…", "Auto Turn", "End Turn"]: button.disabled = deployment_overlay.visible or (button.text != "Undo…" and (battle == null or not battle.outcome.is_empty()))
	_set_panel_visible(settings_overlay, false)
	_set_panel_visible(record_overlay, false)
	recruit_label.text = _recruitment_text()
	record_button.text = "Log"
	_set_panel_visible(info_overlay, true)
	move_child(info_overlay, get_child_count() - 1)

func _open_settings() -> void:
	if busy and not deployment_overlay.visible: return
	_set_panel_visible(info_overlay, false)
	settings_message.text = ""
	_set_panel_visible(settings_overlay, true)
	move_child(settings_overlay, get_child_count() - 1)

func _exit_game() -> void:
	_save_game()
	get_tree().change_scene_to_file("res://runtime/rom_start.tscn")

func _set_music_enabled(_enabled: bool) -> void:
	_apply_audio_preferences()
	_save_preferences()

func _set_sound_enabled(_enabled: bool) -> void:
	_apply_audio_preferences()
	_save_preferences()

func _apply_audio_preferences() -> void:
	if not audio_manager or not music_slider or not sound_slider: return
	audio_manager.set_music_volume(music_slider.value / 100.0 if music_toggle.button_pressed else 0.0, false)
	audio_manager.set_sfx_volume(sound_slider.value / 100.0 if sound_toggle.button_pressed else 0.0, false)
	if voice_player:
		voice_player.master_muted = not sound_toggle.button_pressed
		voice_player.update_volume()

func _save_preferences() -> void:
	if not music_slider or not sound_slider or not text_speed_menu or not cutscene_toggle: return
	var config:= ConfigFile.new()
	config.set_value("display", "grid", board.show_grid)
	config.set_value("audio", "music", music_toggle.button_pressed)
	config.set_value("audio", "sound", sound_toggle.button_pressed)
	config.set_value("audio", "music_volume", music_slider.value)
	config.set_value("audio", "sound_volume", sound_slider.value)
	config.set_value("display", "text_speed", text_speed)
	config.set_value("display", "battle_cutscenes", battle_cutscenes)
	config.set_value("display", "battle_cutscene_mode", battle_cutscene_mode)
	config.set_value("gameplay", "unlimited_supports", unlimited_supports)
	config.set_value("gameplay", "shatter_morale", shatter_morale)
	config.set_value("display", "skip_all_tutorials", skip_all_tutorials)
	config.set_value("display", "movement_speed", movement_speed)
	config.set_value("display", "battle_speed", battle_speed)
	config.set_value("display", "shake_strength", shake_strength)
	config.set_value("gameplay", "durability_mode", durability_mode)
	config.set_value("gameplay", "item_durability_mode", item_durability_mode)
	config.set_value("gameplay", "auto_best_weapon", auto_best_weapon)
	config.set_value("gameplay", "optional_convoy_merchant", optional_convoy_merchant)
	config.set_value("gameplay", "support_any_distance", support_any_distance)
	config.set_value("gameplay", "unlock_staff_chests", unlock_staff_chests)
	config.set_value("gameplay", "wait_enemy_reinforcements", wait_enemy_reinforcements)
	config.set_value("gameplay", "reinforcement_mode", reinforcement_mode)
	config.set_value("gameplay", "permadeath", permadeath)
	config.set_value("gameplay", "auto_promote_lords", auto_promote_lords)
	config.set_value("gameplay", "supply_access", supply_access)
	config.set_value("gameplay", "chest_unlock_mode", chest_unlock_mode)
	config.set_value("gameplay", "door_unlock_mode", door_unlock_mode)
	config.save("user://settings.cfg")

func _load_preferences() -> void:
	var config:= ConfigFile.new()
	config.load("user://settings.cfg")
	item_durability_mode = str(config.get_value("gameplay", "item_durability_mode", "normal"))
	if item_durability_mode not in Battle.DURABILITY_MODES: item_durability_mode = "normal"
	item_durability_menu.selected = Battle.DURABILITY_MODES.find(item_durability_mode)
	auto_best_weapon = bool(config.get_value("gameplay", "auto_best_weapon", false))
	auto_weapon_toggle.set_pressed_no_signal(auto_best_weapon)
	optional_convoy_merchant = bool(config.get_value("gameplay", "optional_convoy_merchant", false))
	convoy_merchant_toggle.set_pressed_no_signal(optional_convoy_merchant)
	support_any_distance = bool(config.get_value("gameplay", "support_any_distance", false))
	support_distance_toggle.set_pressed_no_signal(support_any_distance)
	unlock_staff_chests = bool(config.get_value("gameplay", "unlock_staff_chests", false))
	unlock_staff_toggle.set_pressed_no_signal(unlock_staff_chests)
	wait_enemy_reinforcements = bool(config.get_value("gameplay", "wait_enemy_reinforcements", false))
	reinforcement_mode = clampi(int(config.get_value("gameplay", "reinforcement_mode", 2 if wait_enemy_reinforcements else 0)), 0, 2)
	wait_enemy_reinforcements = reinforcement_mode == 2
	reinforcement_wait_toggle.select(reinforcement_mode)
	permadeath = bool(config.get_value("gameplay", "permadeath", true))
	permadeath_toggle.set_pressed_no_signal(permadeath)
	auto_promote_lords = bool(config.get_value("gameplay", "auto_promote_lords", false))
	auto_promote_toggle.set_pressed_no_signal(auto_promote_lords)
	board.show_grid = bool(config.get_value("display", "grid", false))
	grid_toggle.set_pressed_no_signal(board.show_grid)
	music_toggle.set_pressed_no_signal(bool(config.get_value("audio", "music", true)))
	sound_toggle.set_pressed_no_signal(bool(config.get_value("audio", "sound", true)))
	music_slider.set_value_no_signal(clampf(float(config.get_value("audio", "music_volume", 50)), 0, 100))
	sound_slider.set_value_no_signal(clampf(float(config.get_value("audio", "sound_volume", 80)), 0, 100))
	music_value.text = "%d%%" % int(music_slider.value)
	sound_value.text = "%d%%" % int(sound_slider.value)
	text_speed = clampi(int(config.get_value("display", "text_speed", 2)), 0, 3)
	text_speed_menu.selected = text_speed
	dialogue_view.text_speed = text_speed
	battle_cutscenes = bool(config.get_value("display", "battle_cutscenes", true))
	battle_cutscene_mode = clampi(int(config.get_value("display", "battle_cutscene_mode", 0 if battle_cutscenes else 2)), 0, 2)
	battle_cutscenes = battle_cutscene_mode != 2
	cutscene_toggle.select(battle_cutscene_mode)
	unlimited_supports = bool(config.get_value("gameplay", "unlimited_supports", false))
	unlimited_supports_toggle.set_pressed_no_signal(unlimited_supports)
	shatter_morale = bool(config.get_value("gameplay", "shatter_morale", false))
	shatter_morale_toggle.set_pressed_no_signal(shatter_morale)
	skip_all_tutorials = bool(config.get_value("display", "skip_all_tutorials", false))
	tutorial_toggle.set_pressed_no_signal(skip_all_tutorials)
	movement_speed = _valid_speed(config.get_value("display", "movement_speed", 1.0))
	battle_speed = _valid_speed(config.get_value("display", "battle_speed", 1.0))
	var saved_shake: Variant = config.get_value("display", "shake_strength", 1.0)
	shake_strength = float(saved_shake) if (saved_shake is float or saved_shake is int) and [0.0, 0.5, 1.0, 1.5].has(float(saved_shake)) else 1.0
	shake_menu.selected = [0.0, 0.5, 1.0, 1.5].find(shake_strength)
	movement_speed_menu.selected = [1.0, 1.5, 2.0, 3.0].find(movement_speed)
	battle_speed_menu.selected = [1.0, 1.5, 2.0, 3.0].find(battle_speed)
	durability_mode = str(config.get_value("gameplay", "durability_mode", "normal"))
	if not ["normal", "repair_paid", "repair_free", "infinite"].has(durability_mode): durability_mode = "normal"
	durability_menu.selected = ["normal", "repair_paid", "repair_free", "infinite"].find(durability_mode)
	supply_access = str(config.get_value("gameplay", "supply_access", "lords"))
	if not ["lords", "anywhere"].has(supply_access): supply_access = "lords"
	chest_unlock_mode = str(config.get_value("gameplay", "chest_unlock_mode", "normal"))
	if not ["normal", "supply_keys", "free"].has(chest_unlock_mode): chest_unlock_mode = "normal"
	supply_access_menu.selected = ["lords", "anywhere"].find(supply_access)
	chest_unlock_menu.selected = ["normal", "supply_keys", "free"].find(chest_unlock_mode)
	door_unlock_mode = str(config.get_value("gameplay", "door_unlock_mode", "normal"))
	if not ["normal", "supply_keys", "free"].has(door_unlock_mode): door_unlock_mode = "normal"
	door_unlock_menu.selected = ["normal", "supply_keys", "free"].find(door_unlock_mode)
	if cutscene: cutscene.refresh_art()
	_apply_speed_preferences()
	_apply_audio_preferences()

func _sfx(cue_name: String) -> void:
	if audio_manager: audio_manager.play_sfx(cue_name)

func _music(cue_name: String) -> void:
	if cue_name.is_empty(): return
	if audio_manager:
		var track:= str(chapter.get("music", {}).get(cue_name, cue_name))
		if not audio_manager.play_music(track): audio_manager.play_music(cue_name)

func _position_floating_panels() -> void:
	_position_terrain()
	if not board or not stats_panel or _selected().is_empty(): return
	var selected := _selected()
	var at: Vector2 = board.cell_screen_position(Vector2i(selected.x, selected.y))
	stats_panel.size = stats_panel.get_combined_minimum_size()
	var extent: Vector2 = stats_panel.size
	var corners:= [Vector2(16, 16), Vector2(size.x - extent.x - 16, 16)]
	var best: Vector2 = corners[0]
	for corner in corners:
		if (corner + extent * 0.5).distance_squared_to(at) > (best + extent * 0.5).distance_squared_to(at): best = corner
	if not busy: panel_motion.relocate(stats_panel, best)
	var natural: Vector2 = actions_list.get_combined_minimum_size()
	var menu_width:= minf(maxf(160, natural.x + 24), size.x - 64)
	var menu_height:= minf(natural.y, maxf(48, size.y - 64))
	actions_scroll.custom_minimum_size = Vector2(menu_width, menu_height)
	actions_panel.size = actions_panel.get_combined_minimum_size()
	var tile: float = board.map_rect().size.x / float(board.map_data.get("width", 15))
	var right_side: bool = at.x < size.x * 0.5
	var desired:= Vector2(at.x + tile * 0.65 if right_side else at.x - tile * 0.65 - actions_panel.size.x, at.y - actions_panel.size.y * 0.5)
	var opposite:= Vector2(at.x - tile * 0.65 - actions_panel.size.x if right_side else at.x + tile * 0.65, desired.y)
	var candidates:= [desired, opposite, Vector2(desired.x, at.y + tile * 0.65), Vector2(desired.x, at.y - actions_panel.size.y - tile * 0.65), Vector2(opposite.x, at.y + tile * 0.65), Vector2(opposite.x, at.y - actions_panel.size.y - tile * 0.65)]
	for offset in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
		candidates.append(at + offset * Vector2(actions_panel.size.x + tile, actions_panel.size.y + tile) - actions_panel.size * 0.5)
	var best_menu:= desired
	var best_score:= INF
	for index in range(candidates.size()):
		var candidate: Vector2 = candidates[index].clamp(Vector2(12, 12), (size - actions_panel.size - Vector2(12, 12)).max(Vector2(12, 12)))
		var score:= float(index)
		var menu_rect:= Rect2(candidate, actions_panel.size)
		for unit in battle.units + battle.destructibles:
			if int(unit.hp) <= 0 or not str(unit.get("rescued_by", "")).is_empty(): continue
			var center: Vector2 = board.cell_screen_position(Vector2i(unit.x, unit.y))
			if menu_rect.intersects(Rect2(center - Vector2.ONE * tile * 0.45, Vector2.ONE * tile * 0.9)):
				score += 10000.0 if unit.id == pending_target or unit.id == pending_assist.get("target", "") or unit.id == selected_id or unit.get("faction", "") == "enemy" or unit.get("kind", "") == "structure" else 100.0
		if score < best_score:
			best_score = score
			best_menu = candidate
	panel_motion.relocate(actions_panel, best_menu)
	forecast_panel.size = forecast_panel.get_combined_minimum_size()
	var forecast_position:= Vector2(size.x - forecast_panel.size.x - 16 if at.x < size.x * 0.5 else 16.0, maxf(16, (size.y - forecast_panel.size.y) * 0.5))
	if stats_panel.visible and Rect2(forecast_position, forecast_panel.size).intersects(stats_panel.get_rect()):
		var below:= stats_panel.position.y + stats_panel.size.y + 12
		var above:= stats_panel.position.y - forecast_panel.size.y - 12
		if below + forecast_panel.size.y <= size.y - 16: forecast_position.y = below
		elif above >= 16: forecast_position.y = above
	panel_motion.relocate(forecast_panel, forecast_position)
	_position_terrain()
	if inventory_menu and inventory_menu.visible: _position_inventory()

func _label(text_value: String, font_size: int = 18, color: Color = INK) -> Label:
	var label:= Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _rich(height: float) -> RichTextLabel:
	var label:= RichTextLabel.new()
	label.bbcode_enabled = true
	label.custom_minimum_size.y = height
	label.scroll_active = true
	label.add_theme_font_size_override("normal_font_size", 17)
	return label

func _button(parent: Node, text_value: String, action: Callable) -> Button:
	var button:= Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _panel() -> PanelContainer:
	var panel:= PanelContainer.new()
	var style:= StyleBoxTexture.new()
	style.texture = load("res://ui/panel.svg")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 8)
		style.set_content_margin(side, 20 if side in [SIDE_LEFT, SIDE_RIGHT] else 16)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _build_dialogue() -> void:
	dialogue_view = load("res://ui/dialogue_view.gd").new()
	add_child(dialogue_view)
	dialogue_view.native_choice_selected.connect(_answer_native_choice)
	dialogue_overlay = dialogue_view
	dialogue_panel = dialogue_view.panel
	dialogue_speaker = dialogue_view.speaker_label
	dialogue_text = dialogue_view.text_label
	dialogue_portrait = dialogue_view.left_portrait
	dialogue_right_portrait = dialogue_view.right_portrait
	dialogue_background = dialogue_view.background

func _advance_dialogue() -> void:
	if dialogue_transition: return
	if dialogue_view.is_typing(): dialogue_view.reveal()
	elif dialogue_view.current.get("native_choice",false): return
	else: _next_dialogue()

func _answer_native_choice(answer: bool) -> void:
	if dialogue_transition or not battle or not dialogue_view.current.get("native_choice",false): return
	var identity := str(dialogue_view.current.get("native_choice_id",""))
	if not preload("res://engine/native_event_runner.gd").answer_choice(battle,identity,answer):
		status_label.text = "This choice could not be completed. Export diagnostics for details."
		return
	dialogue_view.current.erase("native_choice")
	dialogue_view.choice_row.hide()
	transition_pending = battle.outcome == "victory" and (not _next_chapter_path().is_empty() or not chapter.get("route_choices",{}).is_empty())
	_flush_dialogue()
	_next_dialogue()

func _input(event: InputEvent) -> void:
	if details_overlay and details_overlay.visible:
		var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if pressed:
			var panel: Control = details_view.get_parent().get_parent().get_parent()
			if panel.get_global_rect().has_point(event.position):
				details_overlay.move_child(details_portrait, 0)
	if portrait_import_panel and portrait_import_panel.visible: return
	if title_screen and title_screen.visible: return
	if _weapon_pointer_input(event): return
	if (cutscene and cutscene.visible) or (scene_transition and scene_transition.visible): return
	if not dialogue_overlay or not dialogue_overlay.visible: return
	if terrain_overlay.visible or supply_overlay.visible or (title_screen and title_screen.visible) or settings_overlay.visible or info_overlay.visible or help_overlay.visible or record_overlay.visible or end_turn_overlay.visible or library_overlay.visible or backdrop_overlay.visible or supports_overlay.visible or (undo_overlay and undo_overlay.visible): return


	if event is InputEventScreenTouch:
		if event.pressed and dialogue_touch_id < 0:
			dialogue_touch_id = event.index
			dialogue_pointer_button = _dialogue_button_at(event.position)
		elif not event.pressed and event.index == dialogue_touch_id:
			dialogue_touch_id = -1
			if not event.canceled: _finish_dialogue_pointer(event.position)
			dialogue_pointer_button = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: dialogue_pointer_button = _dialogue_button_at(event.position)
			else: _finish_dialogue_pointer(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
		_advance_dialogue()
		get_viewport().set_input_as_handled()

func _dialogue_button_at(point: Vector2) -> Button:
	for button in dialogue_view.choice_buttons:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return button
	for button in [skip_button, info_button]:
		if button.visible and button.get_global_rect().has_point(point): return button
	return null

func _finish_dialogue_pointer(point: Vector2) -> void:
	var button:= dialogue_pointer_button
	dialogue_pointer_button = null
	if button:
		if button.get_global_rect().has_point(point): button.pressed.emit()
	else: _advance_dialogue()

func _dialogue_boundary(page: Dictionary, previous: Dictionary) -> bool:
	for key in ["background", "background_color", "scene_type", "skip_group", "source_event_offset"]:
		if page.has(key) and page.get(key) != previous.get(key): return true
	return bool(page.get("skip_stop", false))

var enemy_phase_running := false
var skip_enemy_animations := false

func _skip_dialogue() -> void:
	if enemy_phase_running and not dialogue_overlay.visible:
		skip_enemy_animations = true
		board.skip_phase_animations = true
		cutscene.skip_combat_animations = true
		return
	if not dialogue_overlay.visible or dialogue_transition: return
	if dialogue_view.current.get("native_choice",false): return
	var previous: Dictionary = dialogue_view.current.duplicate(true)
	var tutorial:= bool(previous.get("tutorial", false))
	var group:= str(previous.get("skip_group", ""))
	while not dialogue_lines.is_empty():
		var next = dialogue_lines[0]
		var page: Dictionary = next if next is Dictionary else {"text": str(next)}
		if page.get("native_choice",false): break
		if not _dialogue_page_allowed(page):
			dialogue_lines.pop_front()
			continue
		if tutorial:
			if not page.get("tutorial", false) or str(page.get("skip_group", "")) != group: break
		elif _dialogue_boundary(page, previous): break
		dialogue_lines.pop_front()
		_dialogue_audio(page, false)
		board.apply_story(page.get("scene_actions", []))
		if not str(page.get("text", "")).is_empty():
			conversation_log.append("%s\n%s" % [str(page.get("speaker", "")), str(page.text)])
		dialogue_view.present(page, dialogue_lines)
		previous = page
	_next_dialogue()

func _raise_dialogue_controls() -> void:
	for button in [skip_button, info_button]: move_child(button, get_child_count() - 1)
	for panel in [info_overlay, settings_overlay, quality_overlay, cheats_overlay, custom_overlay, voice_overlay, translations_overlay]:
		if panel and panel.visible: move_child(panel, get_child_count() - 1)
	skip_button.visible = dialogue_overlay.visible or enemy_phase_running
	skip_button.tooltip_text = "Skip enemy movement and battle animations" if enemy_phase_running and not dialogue_overlay.visible else "Skip to the next scene"

func _show_dialogue(lines: Array) -> void:
	dialogue_view.portrait_context.clear()
	if battle:
		for unit in Army.all_units(battle): dialogue_view.portrait_context[str(unit.get("name", "")).to_lower()] = unit
	dialogue_view.set_process(true)
	dialogue_view.route.set_process(true)
	dialogue_generation += 1
	dialogue_transition = false
	if scene_transition: scene_transition.cancel()
	pending_story_actions.clear()
	board.clear_story()
	if initial_phase_pending and lines.any(func(page): return page is Dictionary and page.get("scene_actions", []).any(func(action): return action.get("type") == "begin")):
		board.story_active = true
	dialogue_lines = lines.duplicate(true)
	dialogue_view.animations_enabled = animations_enabled
	dialogue_view.reset()
	var route_id := 1 if pack.id == "fe6" else (2 if str(chapter.get("id", "")).contains("fe7_hec_") else 1 if str(chapter.get("id", "")).contains("fe7_eli_") else 3)
	var assets = preload("res://runtime/rom_assets.gd")
	dialogue_view.left_speakers = [preload("res://runtime/rom_names.gd").character(assets.decoder,str(pack.id),route_id)]
	dialogue_view.text_speed = text_speed
	dialogue_view.prepare(lines)
	move_child(dialogue_overlay, get_child_count() - 1)
	# Dynamic FE7 events own their music, including saving the current phase
	# track before a temporary conversation song. A generic cue would overwrite it.
	if not lines.is_empty() and not (pack.id == "fe7" and chapter.get("dynamic_rom",false)):
		_music("victory" if battle and battle.outcome == "victory" else "dialogue")
	_next_dialogue()

func _dialogue_audio(page: Dictionary, sound_effects: bool = true) -> void:
	if not audio_manager: return
	if page.get("save_music",false): audio_manager.save_event_music()
	if page.get("restore_music",false):
		if not audio_manager.restore_event_music(): _music("player_phase")
	if page.has("music"):
		if str(page.music).is_empty(): audio_manager.stop_music()
		else: _music(str(page.music))
	if sound_effects and page.has("rom_sound"): audio_manager.play_rom_sfx(int(page.rom_sound))

func _next_dialogue() -> void:
	if dialogue_transition: return
	get_node("/root/Diagnostics").record("dialogue_advance", {"remaining": dialogue_lines.size()})
	var token:= dialogue_generation
	while not dialogue_lines.is_empty():
		var line = dialogue_lines[0]
		var page: Dictionary = line if line is Dictionary else {"text": str(line)}
		if not _dialogue_page_allowed(page):
			dialogue_lines.pop_front()
			continue
		if skip_all_tutorials and page.get("tutorial", false):
			dialogue_lines.pop_front()
			_dialogue_audio(page, false)
			board.apply_story(page.get("scene_actions", []))
			continue
		var changed: bool = not page.has("scripted_combat") and not dialogue_view.current.is_empty() and _scene_changed(page)
		dialogue_transition = true
		if animations_enabled and changed:
			move_child(scene_transition, get_child_count() - 1)
			await scene_transition.fade_out()
			if token != dialogue_generation: return
		dialogue_lines.pop_front()
		page = page.duplicate(true)
		_dialogue_audio(page)
		if page.has("scripted_combat"):
			dialogue_view.set_content_visible(false)
			dialogue_overlay.hide()
			if animations_enabled: await _play_scripted_combat(page.scripted_combat)
			if token != dialogue_generation: return
			dialogue_overlay.show()
			dialogue_transition = false
			continue
		pending_story_actions = page.get("scene_actions", []).duplicate(true)
		dialogue_portrait_path = str(page.get("portrait", ""))
		dialogue_view.set_content_visible(pending_story_actions.is_empty())
		dialogue_view.present(page, dialogue_lines)
		end_button.disabled = true
		_raise_dialogue_controls()
		stats_panel.hide()
		terrain_panel.hide()
		actions_panel.hide()
		forecast_panel.hide()
		if animations_enabled and changed:
			move_child(scene_transition, get_child_count() - 1)
			await scene_transition.fade_in()
			if token != dialogue_generation: return
		var actions: Array = page.get("scene_actions", [])
		pending_story_actions.clear()
		if not actions.is_empty():
			dialogue_view.set_content_visible(false)
			dialogue_view.continue_mark.hide()
			if animations_enabled: await board.play_story(actions)
			else: board.apply_story(actions)
			if token != dialogue_generation: return
			dialogue_view.set_content_visible(true)
			dialogue_view.continue_mark.show()
		dialogue_transition = false
		if not str(page.get("background", "")).is_empty() and str(page.get("text", "")).is_empty():
			if _image_needs_acknowledgment(str(page.background)): return
		if not str(page.get("text", "")).is_empty():
			conversation_log.append("%s\n%s" % [page.get("speaker", ""), page.text])
			return

	dialogue_transition = true
	if animations_enabled and dialogue_overlay.visible:
		if battle and battle.outcome == "victory" and transition_pending:
			chapter_cover.show()
			move_child(chapter_cover, dialogue_overlay.get_index())
		await dialogue_view.close_presentation()
		if token != dialogue_generation: return
		move_child(scene_transition, get_child_count() - 1)
		await scene_transition.fade_out()
		if token != dialogue_generation: return
	dialogue_overlay.hide()
	skip_button.hide()
	board.clear_story()
	# Chapter-start and native event dialogue must drain before preparation,
	# rewards, or a final-chapter transition can take over the screen.
	if battle and not battle.dialogue_queue.is_empty():
		dialogue_transition = false
		scene_transition.cancel()
		_flush_dialogue()
		return
	if battle and battle.outcome.is_empty(): _music("player_phase" if battle.phase == "player" else "enemy_phase")
	if battle and not battle.chapter.get("reward_notices", []).is_empty():
		dialogue_transition = false
		scene_transition.cancel()
		_show_next_reward()
		return
	if battle and battle.outcome == "victory" and transition_pending:
		dialogue_transition = false
		_transition_chapter(true)
		return
	if animations_enabled and scene_transition.visible:
		await scene_transition.fade_in()
		if token != dialogue_generation: return
	dialogue_transition = false
	if initial_phase_pending and battle and battle.outcome.is_empty():
		if _offer_deployment(): return
		initial_phase_pending = false
		battle._run_events("preparations")
		if not battle.dialogue_queue.is_empty(): _flush_dialogue(); return
		if animations_enabled:
			busy = true
			await _phase_banner("PLAYER PHASE", Color("304da8"))
			if token != dialogue_generation: return
			busy = false
	_refresh()
	if battle and battle.outcome.is_empty(): _music("player_phase" if battle.phase == "player" else "enemy_phase")
	if battle and _show_next_reward(): return
	call_deferred("_settle_battle")

func _image_needs_acknowledgment(path: String) -> bool:

	for line in dialogue_lines:
		var page: Dictionary = line if line is Dictionary else {"text": str(line)}
		if not _dialogue_page_allowed(page) or (skip_all_tutorials and page.get("tutorial", false)): continue
		if (page.has("background") and str(page.background) != path) or page.get("scene_type", "") == "map": return true
		if not str(page.get("text", "")).is_empty(): return false
	return true

func _scene_changed(page: Dictionary) -> bool:
	if page.has("background") and str(page.background) != dialogue_view.background_path: return true
	if page.has("background_color") and str(page.background_color) != dialogue_view.background_color: return true
	return page.has("scene_type") and str(page.scene_type) != str(dialogue_view.current.get("scene_type", ""))

func _dialogue_page_allowed(page: Dictionary) -> bool:
	return not page.has("conditions") or (battle != null and battle._valid_event_definition(page) and battle._event_conditions(page))

func _cancel_scene_presentation() -> void:
	enemy_phase_running = false
	skip_enemy_animations = false
	if board: board.skip_phase_animations = false
	if cutscene: cutscene.skip_combat_animations = false
	enemy_phase_checkpoint = {}
	if board: board.incremental_phase = false
	if voice_player: voice_player.stop()
	if voice_overlay: voice_overlay.hide()
	if translations_overlay: translations_overlay.hide()
	if custom_overlay: custom_overlay.hide()
	active_reward.clear()
	pending_site = -1
	if deployment_overlay: deployment_overlay.hide()
	deployment_battle = null
	if loot_overlay: loot_overlay.hide()
	loot_battle = null
	if promotion_panel: promotion_panel.cancel()
	promotion_battle = null
	if terrain_overlay: terrain_overlay.hide()
	_clear_assist()
	dialogue_generation += 1
	panel_motion.cancel()
	end_turn_battle = null
	if end_turn_overlay: end_turn_overlay.hide()
	if backdrop_overlay: backdrop_overlay.hide()
	if supports_overlay: supports_overlay.hide()
	if supply_overlay: supply_overlay.hide()
	dialogue_transition = false
	pending_story_actions.clear()
	if scene_transition: scene_transition.cancel()
	if chapter_cover and not chapter_handoff: chapter_cover.hide()
	if weapon_pointer_id != -1: weapon_pointer_canceled = true
	if board: board.clear_story()
	if board: board.staff_cells.clear()
	if choice_overlay:
		choice_mode = ""
		choice_ids.clear()
		board.set_ally_choices([])
		choice_overlay.hide()

func _phase_banner(text: String, color: Color) -> void:
	_sfx("phase_change")
	if not animations_enabled: return
	move_child(scene_transition, get_child_count() - 1)
	await scene_transition.phase_banner("Turn %d - %s" % [battle.turn if battle else 1, text.capitalize()], color)

func _set_dialogue_portrait(path: String) -> void:
	dialogue_portrait_path = path
	dialogue_view.restore_state({"left": path})

func _build_library() -> void:
	library_overlay = ColorRect.new()
	library_overlay.color = Color(0.01, 0.02, 0.04, 0.88)
	library_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(library_overlay)
	var panel:= _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_top = 60
	panel.offset_right = -70
	panel.offset_bottom = -60
	library_overlay.add_child(panel)
	var column:= VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label("MAP ARCHIVE", 24, GOLD))
	column.add_child(_label("Supplied chapter maps, variants and cutscenes. Campaign events are not yet attached.", 17))
	library_filter = LineEdit.new()
	library_filter.placeholder_text = "Search maps by chapter or route"
	library_filter.custom_minimum_size.y = 48
	library_filter.text_changed.connect(func(_value): _filter_maps())
	column.add_child(library_filter)
	library_list = preload("res://ui/swipe_item_list.gd").new()
	library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_list.add_theme_constant_override("line_separation", 12)
	library_list.item_activated.connect(_choose_map)
	column.add_child(library_list)
	var row:= HBoxContainer.new()
	column.add_child(row)
	_button(row, "View selected map", func():
		var items:= library_list.get_selected_items()
		if not items.is_empty(): _choose_map(items[0]))
	_button(row, "Return to battle", func(): _set_panel_visible(library_overlay, false);_return_to_battle())
	_button(row, "Close", func(): _set_panel_visible(library_overlay, false))
	library_overlay.hide()

func _build_backdrops() -> void:
	var modal:= _modal(1000, 700)
	backdrop_overlay = modal[0]
	var heading:= HBoxContainer.new()
	modal[1].add_child(heading)
	heading.add_child(_label("LIBRARY", 25, GOLD))
	var categories:= OptionButton.new()
	library_categories = categories
	categories.custom_minimum_size = Vector2(300, 48)
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(categories)
	categories.item_selected.connect(_select_library_category)
	_update_custom_library()
	backdrop_view = load("res://ui/backdrop_viewer.gd").new()
	backdrop_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(backdrop_view)
	music_library = preload("res://ui/swipe_item_list.gd").new()
	music_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	music_library.add_theme_font_size_override("font_size", 22)
	music_library.add_theme_constant_override("line_separation", 16)
	music_library.item_selected.connect(func(index): audio_manager.play_music(str(music_library.get_item_metadata(index))))
	modal[1].add_child(music_library)
	music_library.hide()
	item_glossary = preload("res://ui/item_glossary.gd").new()
	item_glossary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(item_glossary)
	item_glossary.hide()
	support_library = preload("res://ui/support_library.gd").new()
	support_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(support_library)
	support_library.hide()
	voice_library = preload("res://ui/voice_library.gd").new()
	voice_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(voice_library)
	voice_library.hide()
	skill_library = preload("res://ui/skill_library.gd").new()
	skill_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(skill_library)
	skill_library.hide()
	backdrop_overlay.visibility_changed.connect(func():
		if not backdrop_overlay.visible:
			_restore_library_music()
			if voice_player: voice_player.stop())
	_button(modal[1], "Back to Settings", func(): _set_panel_visible(backdrop_overlay, false);_open_settings())

func _update_custom_library() -> void:
	if not library_categories: return
	var selected:= ""
	if library_categories.selected >= 0: selected = str(library_categories.get_item_metadata(library_categories.selected))
	library_categories.clear()
	for entry in [["Original backgrounds / CGs", "backgrounds"], ["Original portraits", "portraits"], ["Original maps", "maps"], ["Music listener", "music"], ["Items glossary", "items"], ["Supports", "supports"], ["Character voices", "voices"], ["Rogue skills", "skills"]]:
		library_categories.add_item(entry[0])
		library_categories.set_item_metadata(library_categories.item_count - 1, entry[1])
	for kind in ["dialogue", "cards", "backgrounds", "maps"]:
		if preload("res://runtime/rom_assets.gd").game_id == "fe6" and kind == "maps": continue
		var store = preload("res://runtime/custom_backdrops.gd").store if kind == "backgrounds" else preload("res://runtime/custom_card_portraits.gd").store if kind == "cards" else preload("res://runtime/custom_portraits.gd").store
		if kind == "maps": store = preload("res://runtime/custom_maps.gd").store
		if not store.loaded: store.reload()
		if store.entries.is_empty() or not store.enabled: continue
		var title:= "maps" if kind == "maps" else "backgrounds / CG / battle / title art" if kind == "backgrounds" else "unit-card portraits" if kind == "cards" else "dialogue portraits"
		library_categories.add_item("Imported " + title)
		library_categories.set_item_metadata(library_categories.item_count - 1, "custom_" + kind)
	for index in range(library_categories.item_count):
		if library_categories.get_item_metadata(index) == selected:
			library_categories.select(index)
			break

func _select_library_category(index: int) -> void:
	if not backdrop_view or index < 0: return
	library_categories.select(index)
	var music_selected:= str(library_categories.get_item_metadata(index)) == "music"
	var items_selected:= str(library_categories.get_item_metadata(index)) == "items"
	var skills_selected:= str(library_categories.get_item_metadata(index)) == "skills"
	skill_library.visible = skills_selected
	var voices_selected:= str(library_categories.get_item_metadata(index)) == "voices"
	voice_library.visible = voices_selected
	var supports_selected:= str(library_categories.get_item_metadata(index)) == "supports"
	support_library.visible = supports_selected
	backdrop_view.visible = not music_selected and not items_selected and not supports_selected and not voices_selected and not skills_selected
	item_glossary.visible = items_selected
	music_library.visible = music_selected
	if not music_selected: _restore_library_music()
	match str(library_categories.get_item_metadata(index)):
		"skills": skill_library.configure()
		"voices": voice_library.configure(voice_player)
		"supports": support_library.configure(support_manifest)
		"items": item_glossary.configure(pack)
		"music": _open_music_library()
		"backgrounds", "portraits", "maps", "custom_backgrounds": _configure_art_library(str(library_categories.get_item_metadata(index)))
		"custom_maps": backdrop_view.configure_custom_maps()
		"custom_cards": backdrop_view.configure_custom(true)
		"custom_dialogue": backdrop_view.configure_custom(false)

func _configure_art_library(kind: String) -> void:
	if pack.get("dynamic_rom",false):
		backdrop_view.configure_dynamic("backgrounds" if kind == "custom_backgrounds" else kind,kind == "custom_backgrounds")
		return
	match kind:
		"backgrounds", "custom_backgrounds": backdrop_view.configure(_read_json(str(pack.get("scene_manifest",""))),kind == "custom_backgrounds")
		"portraits": backdrop_view.configure_portraits(str(pack.get("portrait_library","res://content/fe7/portrait_library.json")))
		"maps": backdrop_view.configure_maps(catalog)

func _open_backdrops() -> void:
	_update_custom_library()
	_set_panel_visible(settings_overlay, false)
	_select_library_category(library_categories.selected)
	_set_panel_visible(backdrop_overlay, true)
	move_child(backdrop_overlay, get_child_count() - 1)

func _open_portraits() -> void:
	_update_custom_library()
	library_categories.select(1)
	_select_library_category(1)
	_set_panel_visible(settings_overlay, false)
	_set_panel_visible(backdrop_overlay, true)
	move_child(backdrop_overlay, get_child_count() - 1)

func _build_supply() -> void:
	var modal:= _modal(940, 600)
	supply_overlay = modal[0]
	supply_overlay.color.a = 0.3
	modal[0].get_child(0).add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.92))
	modal[1].add_child(_label("SUPPLY", 25, GOLD))
	supply_view = load("res://ui/supply_menu.gd").new()
	supply_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(supply_view)
	supply_view.transfer_requested.connect(_supply_transfer)
	_button(modal[1], "Done", func(): _set_panel_visible(supply_overlay, false);_after_noncombat())

func _open_supply() -> void:
	if (busy and not deployment_overlay.visible) or browsing or not battle.can_access_supply(selected_id): return
	supply_view.present(_selected(), battle.inventory_slots(selected_id), battle.inventory)
	_set_panel_visible(supply_overlay, true)
	move_child(supply_overlay, get_child_count() - 1)

func _supply_transfer(direction: String, index: int) -> void:
	var checkpoint:= {} if deployment_overlay.visible else _action_snapshot()
	var result: Dictionary = battle.supply_store(selected_id, index) if direction == "store" else battle.supply_take(selected_id, index)
	if not result.get("ok", false):
		supply_view.message.text = result.get("reason", "Transfer unavailable.")
		return
	if not deployment_overlay.visible: _remember_action(checkpoint, "Supply · " + direction.capitalize())
	else:
		deployment_overlay._refresh()
		details_view.present(battle.get_unit(details_unit_id), battle)
	_sfx("select")
	supply_view.present(_selected(), battle.inventory_slots(selected_id), battle.inventory)

	if not battle.dialogue_queue.is_empty() or not battle.outcome.is_empty():
		supply_overlay.hide()
		_after_noncombat()
		_flush_dialogue()

func _apply_supply_preferences(refresh: bool = true) -> void:
	if battle:
		battle.rules["support_any_distance"] = support_any_distance
		battle.rules["unlock_staff_chests"] = unlock_staff_chests
		battle.rules["wait_enemy_reinforcements"] = wait_enemy_reinforcements
		battle.rules["warn_enemy_reinforcements"] = reinforcement_mode == 1
		battle.rules["unlimited_supports"] = unlimited_supports
		battle.rules["shatter_morale"] = shatter_morale
		Rogue.prepare_morale(battle)
		battle.rules["optional_convoy_merchant"] = true if Rogue.active(battle) else optional_convoy_merchant
		battle.rules["supply_access"] = supply_access
		battle.rules["chest_unlock_mode"] = chest_unlock_mode
		battle.rules["door_unlock_mode"] = door_unlock_mode
		if refresh: _refresh()

func _attach_supply_providers(units: Array) -> void:
	for unit in units:
		if pack.get("supply_provider_ids", []).has(str(unit.get("id", ""))): unit["supply_provider"] = true

func _build_supports() -> void:
	var modal:= _modal(940, 650)
	supports_overlay = modal[0]
	modal[1].add_child(_label("SUPPORTS", 25, GOLD))
	supports_view = load("res://ui/supports_view.gd").new()
	supports_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(supports_view)
	_button(modal[1], "Back", func():
		_set_panel_visible(supports_overlay, false)
		if supports_return_to_details: _open_unit_details(details_unit_id)
		else: _open_info())

func _open_supports(character_id: String = "", from_details: bool = false) -> void:
	if (busy and not deployment_overlay.visible) or not battle: return
	if from_details: character_id = details_unit_id
	supports_return_to_details = from_details
	_set_panel_visible(info_overlay, false)
	_set_panel_visible(details_overlay, false)
	supports_view.present(battle, support_manifest, character_id)
	_set_panel_visible(supports_overlay, true)
	move_child(supports_overlay, get_child_count() - 1)

func _open_library() -> void:
	library_categories.select(2)
	_open_backdrops()

func _filter_maps() -> void:
	library_list.clear()
	library_ids.clear()
	var query:= library_filter.text.to_lower()
	for entry in catalog:
		var title: String = entry.get("title", entry.get("id", "Map"))
		if not preload("res://runtime/text_replacements.gd").matches_search(title, query):
			continue
		library_ids.append(entry)
		library_list.add_item("%s    ·    %s × %s" % [title, entry.width, entry.height])
	if library_list.item_count > 0:
		library_list.select(0)

func _choose_map(index: int) -> void:
	library_overlay.hide()
	_open_library()
	if index >= 0 and index < backdrop_view.entries.size():
		backdrop_view.select_image(index)

func _start_battle(path: String = "", preserve_history: bool = false, permanent_flags: Array = [], prepared: Dictionary = {}) -> void:
	var target_path := path if not path.is_empty() else str(pack.get("start_chapter",""))
	var assets = preload("res://runtime/rom_assets.gd")
	if not assets.ensure_resource(target_path):
		status_label.text = assets.progress
		return
	if pack.get("dynamic_rom",false):
		board.configure_animations(str(pack.map_animation_manifest))
		cutscene.configure(str(pack.battle_animation_manifest))
	deployment_overlay.hide()
	deployment_battle = null
	if cheats_overlay: cheats_overlay.hide()
	if route_select: route_select.hide()
	get_node("/root/Diagnostics").record("chapter_load", {"path": path})
	_cancel_scene_presentation()
	undo_history.clear()
	conversation_log.clear()
	active_reward.clear()
	_clear_assist()
	terrain_overlay.hide()
	terrain_cell = Vector2i(-1, -1)
	terrain_panel.hide()
	help_overlay.hide()
	record_overlay.hide()
	initial_phase_pending = true
	if cutscene: cutscene.cancel()
	busy = false
	transition_pending = false
	chapter_path = path if not path.is_empty() else str(pack.get("start_chapter", ""))
	chapter = prepared.chapter if not prepared.is_empty() else Difficulty.chapter(_read_json(chapter_path), Difficulty.normalize(campaign.get("difficulty", "normal")))
	var map: Dictionary = prepared.map if not prepared.is_empty() else _read_json(chapter.get("map", ""))
	if chapter.is_empty() or map.is_empty():
		status_label.text = "Chapter data is missing. Return to the cartridge library and load your cartridge again."
		get_node("/root/Diagnostics").record("chapter_data_missing", {"chapter": path, "map": chapter.get("map", "")})
		return
	if prepared.is_empty(): _configure_chapter_definition(chapter, map)
	battle = prepared.state if not prepared.is_empty() else Battle.new()
	if Difficulty.is_rogue(chapter.get("difficulty", "")) and not preserve_history:
		var random:= RandomNumberGenerator.new()
		random.randomize()
		chapter.seed = random.randi()
	if prepared.is_empty():
		battle.load_chapter(chapter, {}, permanent_flags)
		if Rogue.active(battle): Rogue.setup(battle, null, campaign.get("completed_chapters", []).size())
	if rogue_overlay: rogue_overlay.hide()
	battle.rules.auto_promote_lords = auto_promote_lords
	battle.rules.permadeath = true if Rogue.active(battle) else permadeath
	battle.set_promotion_catalog(promotion_manifest)
	battle.set_durability_mode(durability_mode)
	battle.rules.item_durability_mode = item_durability_mode
	_apply_supply_preferences(false)
	if not preserve_history:
		battle.apply_chapter_repairs()
		battle._run_events("chapter_start")
	if not chapter_handoff: chapter_start = battle.serialize(false)
	outcome_presented = ""
	selected_id = ""
	pending_target = ""
	library_overlay.hide()
	items_overlay.hide()
	trade_menu.hide()
	shop_overlay.hide()
	details_overlay.hide()
	queued_attack = false
	settings_overlay.hide()
	info_overlay.hide()
	board.battle = battle
	_return_to_battle()
	if not chapter_handoff:
		_preload_intro(chapter.get("intro", []))
		_show_chapter_opening()
	if not chapter_handoff and not dialogue_overlay.visible: _music("player_phase")

func _configure_chapter_definition(data: Dictionary, map: Dictionary, just_completed: String = "") -> void:
	for variant in data.get("campaign_variants", []):
		var required: Array = variant.get("completed_chapters", [variant.get("completed_chapter", "")])
		if not required.all( func(id): return campaign.completed_chapters.has(str(id)) or (not just_completed.is_empty() and str(id) == just_completed)): continue
		data.units = data.units.filter( func(unit): return not variant.get("remove_units", []).has(str(unit.id)))
		data.units.append_array(variant.get("units", []).duplicate(true))
		for event in data.get("events", []):
			if event.get("trigger", "") == "victory" and event.has("dialogue") and variant.has("victory_dialogue"): event.dialogue = variant.victory_dialogue.duplicate(true)
		for key in ["intro"]:
			if variant.has(key):
				var world: Array = data.get(key, []).filter( func(line): return line.get("scene_type", "") == "worldmap")
				data[key] = world + variant[key].duplicate(true)
	_apply_support_catalog(data)
	data["width"] = map.width
	data["height"] = map.height
	if not data.has("terrain"):
		data["terrain"] = map.terrain
	_apply_art(data.get("units", []))
	for event in data.get("events", []):
		_apply_art(NativeEvents.spawn_templates(event))

func _apply_art(units: Array) -> void:
	_attach_supply_providers(units)
	for unit in units:
		var art: Dictionary = pack.get("art_overrides", {}).get(unit.id, {})
		for key in ["portrait", "sprite"]:
			if art.has(key):
				unit[key] = art[key]

func _apply_support_catalog(data: Dictionary) -> void:
	if support_manifest.is_empty() or str(data.get("support_profile", "")).is_empty(): return
	var pairs: Array = []
	for original in support_manifest.get("pairs", []):
		var pair: Dictionary = {}
		for key in original:
			if key != "dialogue": pair[key] = original[key]
		pair["dialogue_reference"] = true
		pairs.append(pair)
	data["support_pairs"] = pairs
	var combined: Dictionary = support_manifest.get("rules", {}).duplicate(true)
	Battle.new()._merge(combined, data.get("rules", {}))
	data["rules"] = combined
	_attach_support_identities(data)

func _attach_support_identities(value: Variant) -> void:
	if value is Array:
		for child in value: _attach_support_identities(child)
	elif value is Dictionary:
		if value.has("rom_character_id") or (value.has("id") and value.has("faction")):
			for character in support_manifest.get("characters", []):
				var alias_match: bool = character.get("rom_character_ids", []).any( func(id): return int(id) == int(value.get("rom_character_id", -1)))
				if str(value.get("id", "")) == str(character.id) or alias_match:
					value["support_id"] = str(character.id)
					value["affinity"] = str(character.affinity)
					break
		for child in value.values():
			if child is Array or child is Dictionary: _attach_support_identities(child)

func _return_to_battle() -> void:
	browsing = false
	terrain_cell = Vector2i(-1, -1)
	terrain_panel.hide()
	board.spectator = false
	board.set_map(_read_json(chapter.get("map", "")))
	title_label.text = chapter.get("title", "Battle")
	subtitle_label.text = chapter.get("subtitle", "")
	_deselect()
	status_label.text = _objective_text() + " Tap a blue unit to begin."
	_refresh()

func _show_battle_cutscenes(action_phase: String = "") -> bool:
	if action_phase.is_empty() and battle: action_phase = battle.phase
	return pack.get("battle_cutscenes_supported", true) and battle_cutscenes and battle_cutscene_mode != 2 and (battle_cutscene_mode == 0 or action_phase == "player")

func _objective_text() -> String:
	if battle and shatter_morale and chapter.get("objective", {}).get("type", "") in ["rout", "survive"]:
		Rogue.prepare_morale(battle)
		var enemy: Dictionary = battle.chapter.get("rogue", {}).get("morale_enemy", {})
		if not enemy.is_empty():
			var normal := "Survive %d turns" % int(chapter.objective.get("turns", 1)) if chapter.objective.type == "survive" else "Rout the enemy"
			return "%s or defeat %s (%s)." % [normal, enemy.get("name", "commander"), enemy.get("class_name", "Unknown")]
	var objective: Dictionary = chapter.get("objective", {})
	var seize_name := str(objective.get("terrain_name",battle.terrain_at(Vector2i(int(objective.get("x",0)),int(objective.get("y",0)))).get("name","objective"))) if battle else "objective"
	if str(objective.get("type", "")) in ["seize","native_seize"] and not str(chapter.get("objective_text", "")).is_empty():
		return str(chapter.objective_text)
	match str(objective.get("type", "rout")):
		"native_event": return str(chapter.get("objective_text","Complete the chapter objective."))
		"native_seize": return ("Seize each %s in sequence with %s." if objective.get("multiple",false) else "Find and seize the true %s with %s.") % [seize_name,str(battle.get_unit(objective.get("unit_id", "")).get("name", "your lord"))]
		"seize": return "Seize the %s with %s." % [seize_name,str(battle.get_unit(objective.get("unit_id", "")).get("name", "your lord"))]
		"defeat_boss": return "Defeat the enemy commander."
		"survive": return "Survive %d turns." % int(objective.get("turns", 1))
		"activate":
			var completed:= 0
			for event_id in objective.get("event_ids", []):
				if battle.fired_events.has(event_id): completed += 1
			return "Wait on every switch to activate it. %d / %d activated." % [completed, objective.get("event_ids", []).size()]
	return "Rout the enemy."

func _selected() -> Dictionary:
	if battle:
		var unit: Dictionary = battle.get_unit(selected_id)
		if int(unit.get("hp", 0)) > 0: return unit
	return {}

func _cancel_tentative() -> void:
	if not battle or not battle.pending_moves.has(selected_id): return
	var id:= selected_id
	var origin: Dictionary = battle.pending_moves[id]
	var path: Array = origin.get("path", []).map( func(cell): return Vector2i(int(cell[0]), int(cell[1])))
	path.reverse()
	if path.is_empty(): path = battle.movement_path(id, Vector2i(origin.x, origin.y))
	if battle.cancel_move(id): _animate_move(id, path)

func _animate_move(id: String, path: Array) -> void:
	if not animations_enabled or path.size() < 2: return
	var action_battle = battle
	busy = true
	panel_motion.forget(stats_panel)
	stats_panel.hide()
	panel_motion.forget(actions_panel)
	actions_panel.hide()
	_refresh()
	await board.play_movement(id, path)

	if battle != action_battle: return
	busy = false
	_refresh()
	if battle.chapter.has("fe7_tutorials") and not battle.dialogue_queue.is_empty(): _flush_dialogue(); return
	if queued_attack and not pending_target.is_empty():
		queued_attack = false
		_confirm_attack()
	elif queued_assist and not pending_assist.is_empty():
		queued_assist = false
		_confirm_assist()

func _preview_move(id: String, destination: Vector2i) -> bool:
	var path: Array = battle.movement_path(id, destination) if battle.pending_moves.has(id) else []
	# A normal preview is reversible and creates no Undo entry. Only a Mine
	# can commit it here, so large armies need no full snapshot on every tap.
	var mine_possible: bool = battle.Traps.interrupts(battle.get_unit(id)) and battle.chapter.get("placed_traps", []).any(func(t): return t.get("kind", "") == "mine")
	var checkpoint: Dictionary = _action_snapshot() if mine_possible else {}
	if not battle.preview_move(id, destination): return false
	if path.is_empty(): path = battle.last_preview_path.duplicate()
	if not battle.last_movement_effect.is_empty():
		var actual: Vector2i = battle.position(battle.get_unit(id))
		if path.has(actual): path = path.slice(0, path.find(actual) + 1)
		_remember_action(checkpoint, "Mine")
		_present_mine_move(id, path, battle.last_movement_effect.duplicate(true))
		return false
	preload("res://engine/fe7_tutorial.gd").notify(battle,"action",id)
	_animate_move(id, path)
	if battle.chapter.has("fe7_tutorials") and not busy and not battle.dialogue_queue.is_empty(): _flush_dialogue()
	return true

func _present_mine_move(id: String, path: Array, result: Dictionary) -> void:
	var action_battle = battle
	battle.pending_trap_effects.clear()
	busy = true
	queued_attack = false
	queued_assist = false
	_refresh()
	if animations_enabled:
		await board.play_phase([{"type": "move", "unit_id": id, "path": path}, {"type": "trap", "result": result}])
	if battle != action_battle: return
	busy = false
	status_label.text = "%s triggered a Mine: %d damage. Action ended." % [battle.get_unit(id).name, result.damage]
	battle.last_movement_effect.clear()
	_after_noncombat()

func _deselect() -> void:
	pending_site = -1
	all_enemy_ranges = false
	last_unit_tap = ""
	_clear_assist()
	_cancel_tentative()
	selected_id = ""
	pending_target = ""
	pending_weapon = ""
	queued_attack = false
	command_menu_open = false
	_refresh()

func _can_command(unit: Dictionary) -> bool:
	return battle != null and not busy and not browsing and not unit.is_empty() and unit.get("faction", "") == "player" and not unit.get("benched", false) and not unit.get("acted", false) and unit.get("status", "") != "sleep" and str(unit.get("rescued_by", "")).is_empty() and battle.phase == "player" and battle.outcome.is_empty()

func _select_unit(unit: Dictionary) -> void:
	all_enemy_ranges = false
	_clear_assist()
	_sfx("select")
	var same:= selected_id == str(unit.id)
	if not same and voice_player: voice_player.play_unit(unit, "select")
	if not same: _cancel_tentative()
	selected_id = unit.id
	_update_terrain(battle.position(unit))
	pending_target = ""
	pending_weapon = ""
	queued_attack = false
	command_menu_open = same
	if _can_command(unit):
		status_label.text = "Tap a blue tile to move %s, or tap the unit again for commands." % unit.name
		var lessons = preload("res://engine/fe7_tutorial.gd")
		if lessons.notify(battle,"action" if same else "select",str(unit.id)): _flush_dialogue()
	else:
		status_label.text = "Inspecting %s. Select a ready ally to give orders." % unit.name

func _on_cell_held(cell: Vector2i) -> void:
	if busy or browsing or not battle or dialogue_overlay.visible or (title_screen and title_screen.visible): return
	var enemy: Dictionary = battle.unit_at(cell)
	if not enemy.is_empty() and not battle.visible_to_player(enemy): return
	if enemy.get("faction", "") != "enemy": return
	if not choice_mode.is_empty(): _cancel_choice()
	_select_unit(enemy)
	all_enemy_ranges = true
	status_label.text = "Showing every enemy's movement and attack range. Select a unit to clear it."
	_refresh()

func _map_double_tap(cell: Vector2i) -> bool:
	if not choice_mode.is_empty(): return false
	var now:= Time.get_ticks_msec()
	var unit: Dictionary = battle.unit_at(cell)
	if not unit.is_empty() and not battle.visible_to_player(unit): unit = {}
	var kind:= "empty" if unit.is_empty() else str(unit.get("faction", ""))

	if kind == "enemy" and _selected().get("faction", "") == "player" and not pending_target.is_empty():
		last_map_tap_kind = ""
		return false
	if unit.is_empty() and not battle.target_at(cell).is_empty(): kind = "object"

	if unit.is_empty() and battle.interactions.any( func(site): return not site.get("used", false) and Vector2i(site.get("x", -1), site.get("y", -1)) == cell): kind = "interaction"
	if battle == last_map_tap_battle and (kind == "empty" or cell == last_map_tap) and kind == last_map_tap_kind and now - last_map_tap_time < 380 and last_map_tap_kind in ["empty", "enemy"]:
		kind = last_map_tap_kind
		last_map_tap_time = 0
		last_map_tap_kind = ""
		queued_attack = false
		_finish_map_double_tap(cell, kind, battle)
		return true
	last_map_tap = cell
	last_map_tap_battle = battle
	last_map_tap_time = now
	last_map_tap_kind = kind
	return false

func _finish_map_double_tap(cell: Vector2i, kind: String, state: RefCounted) -> void:
	while busy and battle == state: await get_tree().process_frame
	if battle != state or dialogue_overlay.visible: return
	if kind == "enemy": _on_cell_held(cell)
	else: _open_info()

func _on_cell_pressed(cell: Vector2i) -> void:
	if title_screen and title_screen.visible: return
	_update_terrain(cell)
	if browsing:
		_on_cell_hovered(cell)
		return
	if not battle or dialogue_overlay.visible: return
	if not battle.outcome.is_empty():
		if battle.outcome == "defeat" and battle.unit_at(cell).is_empty(): _map_double_tap(cell)
		return
	if not busy and choice_mode == "unlock_confirm":
		if cell == pending_unlock: _confirm_map_unlock()
		else: _cancel_choice()
		return
	if not busy and choice_mode in ["staff_destination", "trap_destination"]:
		_choose_staff_destination(cell)
		return
	if _map_double_tap(cell): return
	if busy:


		var queued_target: Dictionary = battle.target_at(cell)
		if not pending_target.is_empty() and queued_target.get("id", "") == pending_target:
			queued_attack = true
		elif not pending_assist.is_empty() and queued_target.get("id", "") == pending_assist.get("target", ""):
			queued_assist = true
		return
	var unit: Dictionary = battle.target_at(cell)
	if not unit.is_empty() and not battle.visible_to_player(unit): unit = {}
	if not choice_mode.is_empty():
		if choice_mode == "drop": _choose_drop(cell)
		elif choice_ids.has(str(unit.get("id", ""))): _choose_ally(str(unit.id))
		else: _cancel_choice()
		return
	var selected := _selected()
	if _offer_map_unlock(cell): return


	if _can_command(selected) and battle.position(selected) == cell:
		var site: Dictionary = battle.interaction_at_unit(selected_id)
		if site.get("type", "") == "chest":
			var now:= Time.get_ticks_msec()
			if last_unit_tap == selected_id and now - last_unit_tap_msec < 380:
				last_unit_tap = ""
				_interact()
			else:
				last_unit_tap = selected_id
				last_unit_tap_msec = now
				command_menu_open = true
				_refresh()
			return
	if _can_command(selected) and (unit.is_empty() or str(unit.get("id", "")) == selected_id):
		var approach: Dictionary = battle.interaction_approach(selected_id, cell)
		if approach.get("ok", false):
			if pending_site == int(approach.index) and battle.position(selected) == approach.cell:
				_interact()
				return
			pending_site = int(approach.index)
			_clear_assist()
			pending_target = ""
			command_menu_open = true
			if battle.position(selected) != approach.cell: _preview_move(selected_id, approach.cell)
			_refresh()
			return
	pending_site = -1
	if str(unit.get("id", "")) != selected_id: last_unit_tap = ""
	if not unit.is_empty() and str(unit.get("id", "")) != selected_id and _can_command(selected) and not selected.get("canto_active", false):
		if pending_assist.get("target", "") == str(unit.id):
			_confirm_assist()
			return
		var assists: Array = battle.assist_options(selected_id, str(unit.id))
		if not assists.is_empty():
			_begin_assist(str(unit.id), assists[0])
			return
	if not unit.is_empty() and unit.get("faction", "") == "player":
		var now:= Time.get_ticks_msec()
		if selected_id == str(unit.id) and last_unit_tap == selected_id and now - last_unit_tap_msec < 380 and _can_command(unit):
			last_unit_tap = ""
			if battle.can_interact(selected_id): _interact()
			else: _wait_unit()
			return
		last_unit_tap = str(unit.id) if selected_id == str(unit.id) else ""
		last_unit_tap_msec = now
		_select_unit(unit)
	elif not unit.is_empty():
		if _can_command(selected) and not selected.get("canto_active", false) and (unit.get("faction", "") == "enemy" or unit.get("kind", "") == "structure"):
			if pending_target == str(unit.id):
				_confirm_attack()
				return
			var approach: Dictionary = battle.best_attack_approach(selected_id, str(unit.id))
			if approach.get("ok", false):
				_clear_assist()
				pending_target = str(unit.id)
				pending_weapon = str(approach.get("weapon_key", ""))
				command_menu_open = true
				var destination: Vector2i = approach.cell
				if destination == Vector2i(selected.x, selected.y) or _preview_move(selected_id, destination):
					status_label.text = "Choose a weapon, or tap %s again to attack with the last used weapon in range." % unit.name
				else: _deselect()
			else:
				if not battle.get_unit(str(unit.id)).is_empty(): _select_unit(unit)
				else: _deselect()
				status_label.text = "%s is out of reach." % unit.name
		else:
			if not battle.get_unit(str(unit.id)).is_empty(): _select_unit(unit)
			else: _deselect()
	elif _can_command(selected):
		_clear_assist()
		pending_target = ""
		pending_weapon = ""
		command_menu_open = true
		if _preview_move(selected_id, cell):
			_sfx("move")
			status_label.text = "Choose a command. Tap an unreachable tile to undo this move."
		else:
			_deselect()
			_sfx("cancel")
			status_label.text = "Selection cleared. Any tentative movement was undone."
	else: _deselect()
	_refresh()

func _on_cell_hovered(cell: Vector2i) -> void:
	if not browsing:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= int(viewed_map.get("width", 0)) or cell.y >= int(viewed_map.get("height", 0)):
		return
	status_label.text = "Tile %d, %d." % [cell.x, cell.y]

func _clear_assist() -> void:
	pending_assist.clear()
	queued_assist = false

func _begin_assist(target_id: String, option: Dictionary) -> void:
	if not _can_command(_selected()): return
	var approach: Dictionary = option.get("approach", {})
	if not approach.get("ok", false): return
	pending_target = ""
	pending_weapon = ""
	queued_attack = false
	pending_assist = {"target": target_id, "kind": str(option.kind), "index": int(option.get("index", -1))}
	command_menu_open = true
	var destination: Vector2i = approach.cell
	if destination != battle.position(_selected()) and not _preview_move(selected_id, destination):
		_deselect()
		return
	status_label.text = "Tap %s again to %s, or confirm below." % [battle.get_unit(target_id).name, str(option.get("label", "assist")).to_lower()]
	_refresh()

func _refresh_assist_choices(actionable: bool) -> void:
	for child in assist_choices.get_children():
		assist_choices.remove_child(child)
		child.queue_free()
	assist_choices.visible = actionable and not pending_assist.is_empty()
	if not assist_choices.visible: return
	for button in [play_button, talk_button, interact_button, steal_button, support_button, items_button, staff_button, trade_button, supply_button, rescue_button, give_button, take_button, drop_button, wait_button]: button.hide()
	var target: Dictionary = battle.get_unit(str(pending_assist.get("target", "")))
	var heading:= _label("Assist · " + str(target.get("name", "Ally")), 19, Color("a8f6bc"))
	assist_choices.add_child(heading)
	for option in battle.assist_options(selected_id, str(target.get("id", ""))):
		var text:= str(option.get("label", "Assist"))
		var item: Dictionary = option.get("item", {})
		if option.kind == "play": text += " · Act again"
		elif int(item.get("healing", 0)) > 0 or item.get("healing_full", false):
			var hp:= int(target.hp)
			var gain:= int(item.get("healing", 0)) + int(_selected().get("magic", _selected().get("str", 0)))
			var after:= int(target.max_hp) if item.get("healing_full", false) else mini(int(target.max_hp), hp + gain)
			text += " · HP %d → %d" % [hp, after]
		var choice: Dictionary = option.duplicate(true)
		_button(assist_choices, text, func(): _confirm_assist(choice))
	_button(assist_choices, "Cancel move", _deselect)

func _confirm_assist(choice: Dictionary = {}) -> void:
	if not _can_command(_selected()) or pending_assist.is_empty(): return
	var target_id:= str(pending_assist.target)
	var kind:= str(choice.get("kind", pending_assist.kind))
	var index:= int(choice.get("index", pending_assist.index))
	var approach: Dictionary = battle.assist_approach(selected_id, target_id, index, kind)
	if not approach.get("ok", false):
		_clear_assist()
		_refresh()
		return
	if approach.cell != battle.position(_selected()):
		_begin_assist(target_id, {"kind": kind, "index": index, "approach": approach, "label": choice.get("label", "assist")})
		return
	if kind == "staff":
		await _use_inventory_item(index, target_id)
	else:
		await _play_for_ally(target_id)

func _play_native_sounds() -> void:
	if not battle: return
	# Consume even muted cues, so unmuting never replays an earlier event.
	for sound in battle.take_native_sounds():
		if audio_manager: audio_manager.play_rom_sfx(int(sound))

func _refresh() -> void:
	if convoy_merchant_toggle:
		convoy_merchant_toggle.disabled = Rogue.active(battle)
		convoy_merchant_toggle.set_pressed_no_signal(true if Rogue.active(battle) else optional_convoy_merchant)
	if permadeath_toggle:
		permadeath_toggle.disabled = Rogue.active(battle)
		permadeath_toggle.set_pressed_no_signal(true if Rogue.active(battle) else permadeath)
	if not battle or not board: return
	_play_native_sounds()
	if not busy: board.reinforcement_warnings = preload("res://engine/reinforcement_warnings.gd").cells(battle)
	get_node("/root/Diagnostics").set_context({"chapter": chapter.get("id", ""), "turn": battle.turn, "phase": battle.phase, "busy": busy, "deployment": deployment_overlay.visible if deployment_overlay else false, "dialogue": dialogue_overlay.visible, "selection": selected_id})
	skip_button.visible = dialogue_overlay.visible or enemy_phase_running
	var selected:= _selected()
	var actionable: bool = _can_command(selected)
	if terrain_cell.x < 0 and not selected.is_empty(): _update_terrain(battle.position(selected))
	var canto: bool = selected.get("canto_active", false)
	var was_visible:= stats_panel.visible
	stats_panel.present(selected)
	stats_panel.visible = was_visible
	_position_floating_panels()
	if busy:
		panel_motion.forget(stats_panel)
		stats_panel.hide()
	else:
		_set_panel_visible(stats_panel, not selected.is_empty() and not browsing and not dialogue_overlay.visible, Vector2.LEFT if stats_panel.position.x < size.x * 0.5 else Vector2.RIGHT)
	_set_panel_visible(terrain_panel, terrain_cell.x >= 0 and not browsing and not busy and not dialogue_overlay.visible, Vector2.LEFT if terrain_panel.position.x < size.x * 0.5 else Vector2.RIGHT)
	wait_button.disabled = not actionable
	wait_button.visible = actionable
	items_button.disabled = not actionable or canto
	items_button.visible = actionable and not canto and ( not selected.get("inventory", []).is_empty() or not selected.get("weapon", {}).is_empty())
	rescue_button.visible = actionable and not canto and not battle.rescue_targets(selected_id).is_empty()
	give_button.visible = actionable and not canto and not battle.transfer_targets(selected_id, true).is_empty()
	take_button.visible = actionable and not canto and not battle.transfer_targets(selected_id).is_empty()
	drop_button.visible = actionable and not canto and not battle.drop_cells(selected_id).is_empty()
	steal_button.visible = actionable and not canto and not battle.steal_options(selected_id).is_empty()
	talk_button.visible = actionable and not canto and not battle.talk_targets(selected_id).is_empty()
	trade_button.visible = actionable and not canto and not battle.trade_partners(selected_id).is_empty()
	supply_button.visible = not busy and not browsing and battle.can_access_supply(selected_id)
	play_button.visible = actionable and not canto and not battle.play_targets(selected_id).is_empty()
	staff_button.visible = actionable and not canto and not battle.staff_options(selected_id).is_empty()
	interact_button.disabled = not actionable or canto
	interact_button.visible = actionable and not canto and battle.can_interact(selected_id)
	interact_button.text = "Seize" if actionable and battle._can_seize(selected) else "Interact"
	if actionable and not battle._can_seize(selected) and battle.has_method("interaction_at_unit"):
		var site: Dictionary = battle.interaction_at_unit(selected_id)
		if site.get("type", "") in ["door", "chest", "arena", "capture"]: interact_button.text = str(site.type).capitalize()
	var eligible_support:= false
	if actionable and not canto:
		for other in battle.units:
			if battle.can_support(selected_id, other.id): eligible_support = true
	support_button.disabled = not actionable or canto
	support_button.visible = eligible_support
	end_button.disabled = busy or browsing or dialogue_overlay.visible or not battle.outcome.is_empty()
	auto_button.disabled = end_button.disabled or battle.phase != "player"
	save_button.disabled = (busy and not deployment_overlay.visible) or browsing
	objective_label.text = "Map archive · Settings → Map library → Return to battle" if browsing else _objective_text()
	board.selected_id = selected_id
	board.pending_target = str(pending_assist.get("target", pending_target))
	board.pending_target_beneficial = not pending_assist.is_empty()
	var overlay: Dictionary = battle.range_overlay(selected_id) if not selected.is_empty() and not browsing else {"movement": {}, "attack": []}
	if all_enemy_ranges and not browsing: overlay = battle.enemy_range_overlay()
	board.reachable_cells = overlay.movement
	board.target_cells = overlay.attack
	board.beneficial_cells = overlay.get("beneficial", [])
	board.queue_redraw()
	phase_label.text = "MAP ARCHIVE" if browsing else "%s · TURN %d · %d G" % [battle.phase.to_upper(), battle.turn, battle.gold]
	attack_button.visible = actionable and not canto and pending_target.is_empty() and pending_assist.is_empty() and not _available_attack_targets().is_empty()
	attack_button.disabled = not attack_button.visible
	if not actionable or canto or pending_target.is_empty(): _set_panel_visible(forecast_panel, false)
	for child in weapon_buttons.get_children():
		weapon_buttons.remove_child(child)
		child.queue_free()
	if actionable and not canto and not pending_target.is_empty():
		if auto_best_weapon:
			pending_weapon = battle.preferred_weapon(selected_id, pending_target)
			var automatic_index: int = battle._weapon_index(pending_weapon)
			if automatic_index >= 0 and battle.equip_item(selected_id, automatic_index, false):
				pending_weapon = "equipped"
				stats_panel.present(_selected())
		var choices: Array = battle.weapon_options(selected_id, pending_target, false)
		var available: Array = []
		for choice in choices:
			if not choice.get("can_attack", false): continue
			available.append(str(choice.key))
			var key:= str(choice.key)
			var button:= Button.new()
			button.text = "%s  ·  %d" % [choice.weapon.get("name", "Weapon"), int(choice.weapon.get("uses", 0))]
			button.custom_minimum_size.y = 48
			weapon_buttons.add_child(button)


			button.gui_input.connect(func(event):
				if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]:
					_confirm_attack(key)
					button.accept_event())
			button.set_meta("weapon_key", key)
			button.mouse_entered.connect(func(): _preview_weapon(key))
			button.button_down.connect(func(): _preview_weapon(key))
			button.focus_entered.connect(func(): _preview_weapon(key))
		if not available.is_empty():
			attack_button.disabled = false
			if not available.has(pending_weapon):
				pending_weapon = battle.preferred_weapon(selected_id, pending_target) if auto_best_weapon else available[0]
			_preview_weapon(pending_weapon)
	_refresh_assist_choices(actionable and not canto)
	_position_floating_panels()
	_set_panel_visible(actions_panel, (actionable or supply_button.visible) and command_menu_open and choice_mode.is_empty() and not dialogue_overlay.visible)
	call_deferred("_position_floating_panels")
	log_label.text = _record_text()

	log_label.scroll_to_line(maxi(0, log_label.get_line_count() - 1))
	if not battle.outcome.is_empty() and not browsing:
		phase_label.text = battle.outcome.to_upper()
		status_label.text = "Victory! Chapter complete." if battle.outcome == "victory" else "Defeat. Restart to try again."

func _preview_weapon(key: String) -> void:
	if not _can_command(_selected()) or pending_target.is_empty(): return
	var preview: Dictionary = battle.forecast_with_weapon(selected_id, pending_target, key)
	if not preview.get("attacker", {}).get("can_attack", false): return
	pending_weapon = key
	var attacker: Dictionary = battle._unit_with_weapon(selected_id, key)
	var was_visible:= forecast_panel.visible
	forecast_panel.present(attacker, battle.get_target(str(preview.get("guardian_id", pending_target))), preview)
	forecast_panel.visible = was_visible
	_set_panel_visible(forecast_panel, not dialogue_overlay.visible)

func _confirm_attack(weapon_key: String = "") -> void:
	if not _can_command(_selected()) or pending_target.is_empty(): return
	if weapon_key.is_empty() and auto_best_weapon:
		weapon_key = battle.preferred_weapon(selected_id, pending_target)

	if weapon_key.is_empty():
		for option in battle.weapon_options(selected_id, pending_target, false):
			if option.get("can_attack", false):
				weapon_key = str(option.key)
				break
	var action_battle = battle
	var checkpoint:= _action_snapshot()
	var result: Dictionary = battle.attack_with_weapon(selected_id, pending_target, weapon_key)
	if result.get("ok", false):
		_remember_action(checkpoint, "Attack")
		pending_target = ""
		pending_weapon = ""
		queued_attack = false
		busy = true
		_refresh()
		if animations_enabled:
			await _play_combat(result.get("strikes", []), not result.get("experience", []).is_empty())
			if battle != action_battle: return
			await _play_rewards(result.get("experience", []))
		if battle != action_battle: return
		busy = false
		_deselect()
		_check_outcome()

	elif _selected().get("acted", false):
		_remember_action(checkpoint, "Movement blocked")
		_deselect()
		_check_outcome()

func _available_attack_targets() -> Array:
	var targets: Array = []
	if not battle or not _can_command(_selected()) or _selected().get("canto_active", false): return targets
	for target in battle.units + battle.destructibles:
		if battle.can_attack_with_any_weapon(selected_id, str(target.id)):
			targets.append(target)
	return targets

func _open_attack() -> void:
	var targets:= _available_attack_targets()
	if targets.size() == 1:
		_choose_attack_target(str(targets[0].id))
	elif targets.size() > 1:
		_open_choice("attack")

func _choose_attack_target(id: String) -> void:
	if not _available_attack_targets().any( func(target): return str(target.id) == id): return
	pending_target = id
	pending_weapon = ""
	command_menu_open = true
	_refresh()

func _play_rewards(rewards: Array) -> void:
	if rewards.is_empty(): return
	move_child(cutscene, get_child_count() - 1)
	await cutscene.play_rewards(battle, rewards, battle_cutscenes and cutscene.held_for_rewards)
	for reward in rewards:
		if not reward.has("auto_promotion"): continue
		promotion_panel.animations_enabled = animations_enabled
		promotion_panel.present(battle.get_unit(str(reward.unit_id)), reward.auto_promotion)
		move_child(promotion_panel, get_child_count() - 1)
		await promotion_panel.dismissed

func _play_scripted_combat(payload: Dictionary) -> void:
	var generation := dialogue_generation
	var state := preload("res://engine/battle_state.gd").new()
	state.load_chapter({"id":"fe7_event_combat","game_id":"fe7","units":payload.units,"terrain":payload.terrain,"rules":payload.rules,"native_battle_terrain":payload.native_battle_terrain})
	if payload.has("ring"):
		if _show_battle_cutscenes(state.phase):
			move_child(cutscene,get_child_count()-1)
			await cutscene.play_assist(state,str(payload.units[0].id),str(payload.units[1].id),payload.ring,{"ok":true,"temporary_bonuses":payload.ring.ring_bonuses})
		return
	var strikes: Array = payload.strikes
	if strikes.is_empty(): return
	state.phase = str(strikes[0].phase)
	var previous_music: String = audio_manager.current_music if audio_manager else ""
	if _show_battle_cutscenes(state.phase) and cutscene.can_present(state,strikes):
		_music("player_battle" if state.get_unit(str(strikes[0].attacker_id)).faction == "player" else "enemy_battle")
		move_child(cutscene,get_child_count()-1)
		await cutscene.play(state,strikes)
	else:
		var previous: RefCounted = board.battle
		board.battle = state
		await board.play_combat(strikes)
		if board.battle == state: board.battle = previous
	if generation == dialogue_generation and audio_manager:
		if previous_music.is_empty(): audio_manager.stop_music()
		else: audio_manager.play_music(previous_music)

func _play_combat(strikes: Array, hold_for_rewards: bool = false) -> void:
	if skip_enemy_animations: return
	if voice_player: voice_player.begin_battle()
	get_node("/root/Diagnostics").record("combat_presentation", {"chapter": chapter.get("id", ""), "strikes": strikes.size(), "static_bytes": OS.get_static_memory_usage()})
	var current_battle = battle
	var previous_music: String = audio_manager.current_music if audio_manager else ""
	if not strikes.is_empty() and not strikes[0].get("structure", false) and _show_battle_cutscenes(str(strikes[0].get("phase", battle.phase))) and cutscene.can_present(battle, strikes):
		var initiator: Dictionary = battle.get_unit(str(strikes[0].attacker_id))
		var target: Dictionary = battle.get_unit(str(strikes[0].defender_id))
		_music("boss_final" if target.get("id", "") == "fe7_unit_197" or initiator.get("id", "") == "fe7_unit_197" else ("boss_battle" if initiator.get("boss", false) or target.get("boss", false) else ("player_battle" if initiator.get("faction", "") == "player" else "enemy_battle")))
		move_child(cutscene, get_child_count() - 1)
		if enemy_phase_running: move_child(skip_button, get_child_count() - 1)
		await cutscene.play(battle, strikes, hold_for_rewards or board.presentation_rewards_pending)
	else:
		cutscene.cancel()
		await board.play_combat(strikes)
	if battle == current_battle and audio_manager and not previous_music.is_empty(): audio_manager.play_music(previous_music)

func _wait_unit() -> void:
	if not _can_command(_selected()):
		return
	var checkpoint:= _action_snapshot()
	battle.wait_unit(selected_id)
	_remember_action(checkpoint, "Wait")
	if not _selected().get("acted", true) and battle.shop_at(selected_id).get("discovered", false):
		_open_shop()
		return
	_deselect()
	_check_outcome()

func _interact() -> void:
	if not _can_command(_selected()):
		return
	if battle.interaction_at_unit(selected_id).get("type", "") == "arena":
		_open_arena()
		return
	if not battle.shop_at(selected_id).is_empty():
		_open_shop()
		return
	var checkpoint:= _action_snapshot()
	var result: Dictionary = battle.interact(selected_id, pending_site)
	pending_site = -1
	if result.get("ok", false):
		_remember_action(checkpoint, "Interact")
		loot_actor = selected_id
		_after_noncombat()
	else:
		status_label.text = _objective_text() if chapter.get("objective", {}).get("type", "") in ["seize", "native_seize"] else "Move onto an available chest, village, or objective to interact."

func _open_arena() -> void:
	var arena = preload("res://engine/arena.gd").new()
	var offer: Dictionary = arena.offer(battle, selected_id, auto_best_weapon)
	if not offer.get("ok", false): status_label.text = offer.get("reason", "Arena unavailable.");return
	var modal:= _modal(540, 230)
	var overlay: Control = modal[0]
	var column: VBoxContainer = modal[1]
	var title:= _label("Arena · " + str(offer.difficulty), 25, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var opponent:= _label("%s · Level %d · %s\nYour weapon: %s" % [offer["class"], offer.level, offer.weapon, offer.player_weapon], 21)
	opponent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(opponent)
	var wager:= _button(column, "Wager %d G" % offer.wager, func(): overlay.queue_free();_fight_arena(arena))
	wager.disabled = battle.gold < int(offer.wager)
	overlay.show()
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: overlay.queue_free())

func _fight_arena(arena: RefCounted) -> void:
	var assets = preload("res://runtime/rom_assets.gd")
	if assets.dynamic_content != null and not cutscene.prepare_arena(arena.duel,str(assets.dynamic_content.manifest.battle_animation_manifest)):
		status_label.text = "The arena battle animation could not be loaded. Your gold and unit are unchanged."
		return
	var checkpoint:= _action_snapshot()
	if not arena.begin(): return
	var current_battle = battle
	busy = true
	_remember_action(checkpoint, "Arena")
	_save_game(true)
	_refresh()
	var yielded:= {"value": false}
	var yield_button:= Button.new()
	yield_button.text = "Yield"
	yield_button.custom_minimum_size = Vector2(300, 56)
	yield_button.pressed.connect(func(): yielded.value = true;yield_button.disabled = true;yield_button.text = "Yielding…")
	add_child(yield_button)
	yield_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	yield_button.offset_left = -150
	yield_button.offset_right = 150
	yield_button.offset_top = 8
	yield_button.offset_bottom = 64
	move_child(cutscene, get_child_count() - 1)
	move_child(yield_button, get_child_count() - 1)
	var previous_music: String = audio_manager.current_music if audio_manager else ""
	_music("player_battle")
	var continuing:= false
	if voice_player: voice_player.begin_battle()
	while arena.active and battle == current_battle:


		if yielded.value: arena.finish("yield");break
		var strike: Dictionary = arena.next_strike()
		if strike.is_empty(): break
		if cutscene.can_present(arena.duel, [strike]):
			await cutscene.play(arena.duel, [strike], true, continuing)
			continuing = true
		else:
			status_label.text = "Arena: %s · HP %d · Challenger HP %d" % [arena.map.get_unit(arena.unit_id).name, arena.duel.get_unit(arena.unit_id).hp, arena.duel.get_unit("arena_opponent").hp]
			await get_tree().create_timer(0.65).timeout
		if int(arena.duel.get_unit(arena.unit_id).hp) <= 0 or int(arena.duel.get_unit("arena_opponent").hp) <= 0: arena.finish()



		if arena.active: await get_tree().create_timer(0.12 / maxf(0.1, battle_speed)).timeout
	if arena.active: arena.finish("yield")
	yield_button.queue_free()
	cutscene.cancel()
	if battle != current_battle: return
	if not arena.rewards.is_empty(): await _play_rewards(arena.rewards)
	if audio_manager and not previous_music.is_empty(): audio_manager.play_music(previous_music)
	busy = false
	_deselect()
	status_label.text = "Arena won! Received %d G." % (arena.wager * 2) if arena.result == "victory" else "Arena defeat. Your unit has fallen permanently." if arena.result == "defeat" else "Yielded after a weapon broke. Wager lost." if arena.result == "exhausted" else "Yielded. Wager lost."
	_save_game(true)
	_check_outcome()

func _support() -> void:
	if not _can_command(_selected()): return
	var partners: Array = battle.support_partners(selected_id)
	if partners.size() == 1: _confirm_support(str(partners[0].id))
	elif partners.size() > 1: _open_choice("support")

func _confirm_support(other_id: String) -> void:
	var checkpoint:= _action_snapshot()
	if battle.support(selected_id, other_id):
		_remember_action(checkpoint, "Support")
		_after_noncombat()

func _end_turn() -> void:
	if busy or dialogue_transition or not battle or dialogue_overlay.visible or not battle.outcome.is_empty(): return
	enemy_phase_running = true
	skip_enemy_animations = false
	board.skip_phase_animations = false
	cutscene.skip_combat_animations = false
	get_node("/root/Diagnostics").record("enemy_phase_begin", {"chapter": chapter.get("id", ""), "turn": battle.turn, "units": battle.units.size()})
	var action_battle = battle
	var checkpoint:= _action_snapshot()
	enemy_phase_checkpoint = checkpoint
	_clear_assist()
	busy = true
	selected_id = ""
	pending_target = ""
	_refresh()
	_music("enemy_phase")
	await _phase_banner("ENEMY PHASE", Color("aa3444"))
	if battle != action_battle: return
	board.incremental_phase = true
	var actions: Array = battle.begin_enemy_phase()
	while true:
		if animations_enabled and not actions.is_empty(): await board.play_phase(actions, _play_combat, _play_rewards, _play_phase_assist)
		if battle != action_battle: return
		if battle.chapter.has("native_pending_choice"):
			_flush_dialogue()
			while battle == action_battle and (battle.chapter.has("native_pending_choice") or dialogue_overlay.visible or dialogue_transition):
				await get_tree().process_frame
			if battle != action_battle: return
		if battle._turn_sequence.is_empty(): break
		await get_tree().process_frame
		if battle != action_battle: return
		actions = battle.step_enemy_phase()
	enemy_phase_checkpoint = {}
	board.incremental_phase = false
	enemy_phase_running = false
	skip_enemy_animations = false
	board.skip_phase_animations = false
	cutscene.skip_combat_animations = false
	_remember_action(checkpoint, "End turn")
	if battle != action_battle: return
	if battle.outcome.is_empty():
		_music("player_phase")
		await _phase_banner("PLAYER PHASE", Color("304da8"))
		if battle != action_battle: return
	busy = false
	status_label.text = "Enemy phase complete. Select an ally."
	_refresh()
	_check_outcome()

func _auto_turn() -> void:
	if deployment_overlay.visible: return
	if busy or browsing or dialogue_transition or dialogue_overlay.visible or not battle or battle.phase != "player" or not battle.outcome.is_empty(): return
	var action_battle = battle
	var checkpoint:= _action_snapshot()
	_set_panel_visible(info_overlay, false)
	_clear_assist()
	selected_id = ""
	pending_target = ""
	busy = true
	_refresh()
	var actions: Array = battle.auto_player_turn()
	_remember_action(checkpoint, "Auto Turn")
	if animations_enabled: await board.play_phase(actions, _play_combat, _play_rewards, _play_phase_assist)
	if battle != action_battle: return
	busy = false
	_refresh()


	_check_outcome()

func _open_steal() -> void:
	if not _can_command(_selected()): return
	choice_mode = "steal"
	choice_ids.clear()
	for child in choice_list.get_children():
		choice_list.remove_child(child)
		child.queue_free()
	choice_heading.text = "Steal an item"
	for option in battle.steal_options(selected_id):
		var target:= str(option.target_id)
		var slot:= int(option.index)
		_button(choice_list, "%s · %s" % [option.name, option.item.name], func():
			var checkpoint:= _action_snapshot()
			if battle.steal_item(selected_id, target, slot).get("ok", false):
				_remember_action(checkpoint, "Steal")
				_cancel_choice()
				_after_noncombat())
	actions_panel.hide()
	_set_panel_visible(choice_overlay, true)
	move_child(choice_overlay, get_child_count() - 1)
	_position_choice_panel()

func _check_outcome() -> void:
	if not battle or busy: return
	if not battle.pending_skill_effects.is_empty():
		var action_battle = battle
		var effects: Array = battle.pending_skill_effects.duplicate(true)
		battle.pending_skill_effects.clear()
		busy = true
		await board.play_phase(effects)
		if battle != action_battle: return
		busy = false
	if not battle.pending_trap_effects.is_empty():
		var action_battle = battle
		var effects: Array = battle.pending_trap_effects.duplicate(true)
		battle.pending_trap_effects.clear()
		battle.last_movement_effect.clear()
		busy = true
		_refresh()
		if animations_enabled: await board.play_phase(effects.map( func(trap_effect): return {"type": "trap", "result": trap_effect}))
		if battle != action_battle: return
		busy = false
		var effect: Dictionary = effects.back()
		status_label.text = "%s recovered a Mine." % battle.get_unit(str(effect.unit_id)).name if effect.get("recovered", false) else "%s triggered a %s: %d damage." % [battle.get_unit(str(effect.unit_id)).name, effect.get("trap_name","Mine"), effect.damage]
		_refresh()
	if not battle.experience_queue.is_empty():
		var action_battle = battle
		var rewards: Array = battle.experience_queue.duplicate(true)
		battle.experience_queue.clear()
		if animations_enabled:
			busy = true
			_refresh()
			await _play_rewards(rewards)
			if battle != action_battle: return
			busy = false
	if not battle.outcome.is_empty() and outcome_presented != battle.outcome:
		outcome_presented = battle.outcome
		if battle.outcome == "victory":
			_music("victory")
			transition_pending = not _next_chapter_path().is_empty() or not chapter.get("route_choices",{}).is_empty() or _is_final_chapter()
			if not transition_pending:
				battle.dialogue_queue.append({"speaker": "Chapter complete", "text": chapter.get("completion_message", "This encounter is complete. Further campaign chapters are still being ported.")})
		elif battle.outcome == "defeat":
			battle.dialogue_queue.append({"speaker": "Defeat", "text": "Your army has fallen. Resume a saved battle or restart the encounter."})
	_flush_dialogue()
	if not dialogue_overlay.visible and _show_next_reward(): return
	call_deferred("_settle_battle")

func _settle_battle() -> void:
	if title_screen and title_screen.visible: return
	if busy or dialogue_transition or not battle or dialogue_overlay.visible or browsing: return
	if deployment_overlay.visible or loot_overlay.visible or (rogue_overlay and rogue_overlay.visible): return
	if not battle.dialogue_queue.is_empty(): _flush_dialogue(); return
	if _show_next_reward(): return
	if battle.outcome == "victory" and _is_final_chapter():
		_show_epilogue()
		return
	if initial_phase_pending and battle.outcome.is_empty():
		if _offer_deployment(): return
		initial_phase_pending = false
		battle._run_events("preparations")
		if not battle.dialogue_queue.is_empty(): _flush_dialogue();return
		var starting_battle = battle
		busy = true
		await _phase_banner("PLAYER PHASE", Color("304da8"))
		if battle != starting_battle: return
		busy = false
		_refresh()
		if _show_next_reward(): return
	if battle.outcome == "victory" and transition_pending:
		_transition_chapter()
	elif auto_turn_enabled and battle.all_players_acted():
		_end_turn()

func _next_chapter_path() -> String:
	var progress: Dictionary = battle.chapter if battle else chapter
	if progress.has("route_choices") and progress.route_choices.has(str(campaign.get("route", ""))):
		return str(progress.route_choices[str(campaign.route)])
	for option in progress.get("next_chapter_options", []):
		if battle._event_conditions(option): return str(option.get("path", ""))
	return str(progress.get("next_chapter", ""))

func _transition_chapter(_already_covered: bool = false) -> void:
	if battle and battle.chapter.has("native_pending_choice"): return
	if chapter_loading.visible: return
	if _is_final_chapter():
		_show_epilogue()
		return
	if chapter.has("route_choices") and not chapter.route_choices.has(str(campaign.get("route", ""))):
		_save_game()
		_open_route_selection("after_tutorial")
		return
	var next_path:= _next_chapter_path()
	if next_path.is_empty() or not FileAccess.file_exists(next_path): return
	var previous = battle
	var previous_music: String = audio_manager.current_music if audio_manager else ""
	busy = true
	dialogue_transition = true
	transition_pending = false
	if audio_manager: audio_manager.suspend_for_loading(true)
	if voice_player: voice_player.stop()
	chapter_loading.elapsed = 0
	chapter_loading.show()
	move_child(chapter_loading, get_child_count() - 1)
	board.set_process(false)
	dialogue_view.set_process(false)
	dialogue_view.route.set_process(false)
	# Draw the loading screen before starting expensive parsing and normalization.
	await get_tree().process_frame
	var preparation = preload("res://engine/chapter_preparation.gd")
	var result: Dictionary = await chapter_loading.run(preparation.read.bind(next_path, Difficulty.normalize(campaign.get("difficulty", "normal"))))
	var prepared: Dictionary = result.get("value", {})
	if result.has("error") or prepared.is_empty():
		var compatibility = preload("res://runtime/rom_assets.gd").dynamic_content
		_chapter_loading_failed(compatibility.error if compatibility != null and not compatibility.error.is_empty() else str(result.get("error", "Chapter data is missing.")), previous_music)
		return
	var old_id := str(chapter.id)
	_configure_chapter_definition(prepared.chapter, prepared.map, old_id)
	var completed: int = campaign.completed_chapters.size() + (0 if campaign.completed_chapters.has(old_id) else 1)
	result = await chapter_loading.run(preparation.handoff.bind(prepared.chapter, previous, completed, promotion_manifest))
	if result.has("error"):
		_chapter_loading_failed(str(result.error), previous_music)
		return
	prepared.state = result.value
	if not campaign.completed_chapters.has(old_id): campaign.completed_chapters.append(old_id)
	chapter_handoff = true
	_start_battle(next_path, true, [], prepared)
	chapter_handoff = false
	busy = true
	dialogue_transition = true
	# _start_battle refreshes UI panels; keep the loading overlay above them.
	move_child(chapter_loading, get_child_count() - 1)
	result = await chapter_loading.run(preparation.start.bind(battle))
	if result.has("error"):
		_chapter_loading_failed(str(result.error), previous_music)
		return
	chapter_start = result.value
	for page in chapter.get("intro", []):
		_preload_intro([page])
		await get_tree().process_frame
	_music("player_phase")
	_show_chapter_opening()
	_save_game(true)
	chapter_cover.hide()
	scene_transition.cancel()
	chapter_loading.hide()
	board.set_process(true)
	dialogue_view.set_process(true)
	dialogue_view.route.set_process(true)
	dialogue_transition = false
	busy = false
	if audio_manager: audio_manager.suspend_for_loading(false)
	if not dialogue_overlay.visible: _music("player_phase")
	_refresh()

func _chapter_loading_failed(reason: String, previous_music: String) -> void:
	get_node("/root/Diagnostics").record("chapter_load_failed", {"reason":reason})
	chapter_loading.hide()
	chapter_cover.hide()
	scene_transition.cancel()
	board.set_process(true)
	dialogue_view.set_process(true)
	dialogue_view.route.set_process(true)
	dialogue_transition = false
	busy = false
	status_label.text = reason + " Reload your last save or return to the title screen."
	if audio_manager:
		audio_manager.suspend_for_loading(false)
		audio_manager.play_music(previous_music)

func _is_final_chapter() -> bool:
	return (battle.chapter.get("dynamic_rom",false) and battle.chapter.get("campaign_end",false)) or str(chapter.get("id", "")) in ["fe7_eli_chapterfinal2", "fe7_hec_chapterfinal2"]

func _show_epilogue() -> void:
	if is_instance_valid(epilogue_view): return
	if battle.chapter.get("dynamic_rom",false) and str(chapter.id).begins_with("fe7_"):
		_show_fe7_ending(); return
	if str(chapter.id).begins_with("fe6_") and not campaign.get("fe6_ending_story_started",false):
		var ending: Array = preload("res://engine/fe6_epilogue.gd").story(battle,preload("res://runtime/rom_assets.gd").decoder)
		if not preload("res://runtime/rom_assets.gd").decoder.error.is_empty():
			status_label.text = "The ending could not be read from the cartridge. Export diagnostics for details."
			return
		var prepared: Variant = preload("res://runtime/rom_assets.gd").prepare_story_art(ending)
		if prepared == null:
			status_label.text = "The ending art could not be read from the cartridge. Export diagnostics for details."
			return
		ending = prepared
		campaign.fe6_ending_story_started = true
		if not ending.is_empty():
			busy = false
			transition_pending = true
			_show_dialogue(ending)
			_save_game()
			return
	transition_pending = false
	busy = false
	dialogue_transition = false
	scene_transition.cancel()
	chapter_cover.hide()
	dialogue_overlay.hide()
	for panel in [info_overlay, settings_overlay, actions_panel, forecast_panel, stats_panel, skip_button, info_button]: panel.hide()
	board.hide()
	epilogue_view = preload("res://ui/epilogue_view.gd").new()
	add_child(epilogue_view)
	if str(chapter.id).begins_with("fe6_"):
		epilogue_view.game_title = "FE6"
		epilogue_view.pages = preload("res://engine/fe6_epilogue.gd").pages(battle,preload("res://runtime/rom_assets.gd").decoder)
	else:
		audio_manager.play_music("song_045")
		epilogue_view.pages = preload("res://engine/epilogue.gd").pages(battle, "fe7_unit_2" if int(battle.chapter.get("native_route",0)) == 3 or str(chapter.id).contains("fe7_hec_") else "fe7_unit_1", preload("res://runtime/rom_assets.gd").decoder)
	epilogue_view.index = clampi(int(campaign.get("ending_index", 0)), 0, epilogue_view.pages.size())
	epilogue_view.advanced.connect(func(index): campaign.ending_index = index;_save_game())
	epilogue_view.finished.connect(func():
		campaign.completed = true
		if not campaign.completed_chapters.has(str(chapter.id)): campaign.completed_chapters.append(str(chapter.id))
		_save_game()
		epilogue_view.queue_free()
		epilogue_view = null
		_open_title())
	epilogue_view.present()
	_save_game()

func _advance_fe7_ending(stage: int) -> void:
	if is_instance_valid(epilogue_view):
		remove_child(epilogue_view); epilogue_view.queue_free(); epilogue_view = null
	campaign.fe7_ending_stage = stage+1
	campaign.ending_index = 0
	_save_game()
	_show_epilogue()

func _show_fe7_ending() -> void:
	var Ending = preload("res://runtime/fe7/fe7_dynamic_ending.gd")
	var decoder: RefCounted = preload("res://runtime/rom_assets.gd").decoder
	var stage := clampi(int(campaign.get("fe7_ending_stage",0)),0,5)
	if stage in [0,4]:
		var lines: Array = Ending.story(battle,"farewell" if stage == 0 else "teaser",decoder)
		var prepared: Variant = preload("res://runtime/rom_assets.gd").prepare_story_art(lines) if decoder.error.is_empty() else null
		if prepared == null:
			status_label.text = "The ending could not be read from the cartridge. Export diagnostics for details."
			return
		# Advance before saving the dialogue cursor so a resumed conversation does
		# not replay the stage after it finishes (or the player skips it).
		campaign.fe7_ending_stage = stage+1
		campaign.ending_index = 0
		if not prepared.is_empty():
			busy = false; transition_pending = true
			_show_dialogue(prepared); _save_game(); return
		_show_fe7_ending(); return
	transition_pending = false; busy = false; dialogue_transition = false
	scene_transition.cancel(); chapter_cover.hide(); dialogue_overlay.hide()
	for panel in [info_overlay,settings_overlay,actions_panel,forecast_panel,stats_panel,skip_button,info_button]: panel.hide()
	board.hide()
	if stage == 1:
		var roll := Ending.credits(decoder)
		if roll.is_empty():
			status_label.text = "The credits could not be read from the cartridge. Export diagnostics for details."
			return
		epilogue_view = preload("res://ui/credits_view.gd").new()
		epilogue_view.roll = roll
		epilogue_view.position_in_roll = clampf(float(campaign.get("fe7_credits_position",0.0)),0.0,float(roll.distance))
		epilogue_view.advanced.connect(func(offset): campaign.fe7_credits_position = offset)
		epilogue_view.finished.connect(func(): _advance_fe7_ending(stage))
		add_child(epilogue_view)
		audio_manager.play_music(str(roll.music))
	else:
		var pages: Array = []
		if stage == 2:
			var records: Dictionary = battle.chapter.get("fe7_rank_records",{})
			var lines: Array[String] = []
			for key in records:
				var at: int = decoder.ptr(int(decoder.layout.chapters))+int(key)*148
				var chapter_name: String = decoder.text(decoder.u16(at+(114 if int(battle.chapter.native_route) == 3 else 112))).strip_edges()
				lines.append("%s   ·   %d turns" % [chapter_name,int(records[key].turns)])
				if lines.size() == 8:
					pages.append({"title":"Campaign record","text":"\n".join(lines),"units":[]}); lines.clear()
			if not lines.is_empty(): pages.append({"title":"Campaign record","text":"\n".join(lines),"units":[]})
		elif stage == 3:
			pages = preload("res://engine/epilogue.gd").pages(battle,"fe7_unit_2" if int(battle.chapter.native_route) == 3 else "fe7_unit_1",decoder)
		if not decoder.error.is_empty():
			status_label.text = "The epilogue could not be read from the cartridge. Export diagnostics for details."
			return
		var cursor := clampi(int(campaign.get("ending_index",0)),0,pages.size())
		if stage < 5 and cursor == pages.size(): _advance_fe7_ending(stage); return
		epilogue_view = preload("res://ui/epilogue_view.gd").new()
		epilogue_view.pages = pages; epilogue_view.index = cursor; epilogue_view.completion_page = stage == 5
		if stage == 2:
			var background: Image = Ending.ranking_background(decoder)
			if background != null: epilogue_view.background_texture = ImageTexture.create_from_image(background)
		epilogue_view.advanced.connect(func(index): campaign.ending_index = index; _save_game())
		epilogue_view.finished.connect(func():
			if stage < 5: _advance_fe7_ending(stage); return
			campaign.completed = true
			if not campaign.completed_chapters.has(str(chapter.id)): campaign.completed_chapters.append(str(chapter.id))
			_save_game()
			remove_child(epilogue_view); epilogue_view.queue_free(); epilogue_view = null
			_open_title())
		add_child(epilogue_view); epilogue_view.present()
		if stage == 3: audio_manager.play_music("song_045")
	_save_game()

func _preload_intro(lines: Array) -> void:
	for page in lines:
		if not page is Dictionary: continue
		for key in ["background", "portrait", "left_portrait", "right_portrait"]:
			var path:= str(page.get(key, ""))
			if not path.is_empty() and ResourceLoader.exists(path): Art.texture(path)

func _show_chapter_opening() -> void:
	var lines: Array = chapter.get("intro", []).duplicate(true)
	lines.append_array(_resolve_support_dialogue(battle.dialogue_queue))
	battle.dialogue_queue.clear()
	_show_dialogue(lines)

func _flush_dialogue() -> void:
	if not battle.dialogue_queue.is_empty():
		var lines: Array = _resolve_support_dialogue(battle.dialogue_queue)
		battle.dialogue_queue.clear()
		if dialogue_overlay.visible:
			dialogue_lines.append_array(lines)
			dialogue_view.prepare(lines)
		else:
			_show_dialogue(lines)

func _resolve_support_dialogue(queued: Array) -> Array:
	var lines: Array = []
	for page in queued:
		if not page is Dictionary or not page.has("support_conversation"):
			lines.append(page.duplicate(true) if page is Dictionary else page)
			continue
		var request: Dictionary = page.support_conversation
		for pair in support_manifest.get("pairs", []):
			var ids: Array[String] = [str(pair.a), str(pair.b)]
			ids.sort()
			if "|".join(ids) == str(request.get("pair", "")):
				lines.append_array(preload("res://runtime/support_conversations.gd").pages(pair,str(request.get("rank",1))))
				break
	return lines

func _save_game(background: bool = false) -> void:
	if title_screen and title_screen.visible: return
	if not battle:
		return
	get_node("/root/Diagnostics").record("save_begin", {"chapter": chapter.get("id", ""), "undo_count": undo_history.size()})
	# A mobile suspend between enemy actions saves the deterministic pre-phase
	# checkpoint, never an incomplete enemy turn that cannot be resumed.
	var data: Dictionary = enemy_phase_checkpoint.duplicate(true) if not enemy_phase_checkpoint.is_empty() else _action_snapshot()

	# Undo entries and chapter_start are immutable checkpoints; detach the
	# changing history list before handing it to the writer.
	data["undo_history"] = undo_history.duplicate()
	if background:
		pending_save = data
		_start_background_save()
		return
	_flush_background_save(false)
	var result := _write_save(data, save_codec, SAVE_PATH)
	status_label.text = str(result.message)
	get_node("/root/Diagnostics").record("save_end", result)

func _write_save(data: Dictionary, codec: RefCounted, path: String) -> Dictionary:
	data = codec.encode(data)
	if not codec.error.is_empty(): return {"error": ERR_INVALID_DATA, "message": codec.error}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		return {"error": FileAccess.get_open_error(), "message": "Could not write the save file."}
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error:= file.get_error()
	var written:= file.get_position()
	file.close()
	var result := DirAccess.rename_absolute(path + ".tmp", path) if write_error == OK else write_error
	return {"error": result, "bytes": written, "message": "Battle saved on this device." if result == OK else "Could not replace the save file."}

func _start_background_save() -> void:
	if save_worker != null or pending_save.is_empty(): return
	var data := pending_save
	pending_save = {}
	var worker := Thread.new()
	save_worker = worker
	var error := worker.start(_write_save.bind(data, background_save_codec, SAVE_PATH))
	if error != OK:
		save_worker = null
		status_label.text = str(_write_save(data, background_save_codec, SAVE_PATH).message)
		return

func _process(_delta: float) -> void:
	if save_worker == null or save_worker.is_alive(): return
	var result: Dictionary = save_worker.wait_to_finish()
	save_worker = null
	if int(result.error) != OK: status_label.text = str(result.message)
	get_node("/root/Diagnostics").record("save_end", result)
	_start_background_save()

func _flush_background_save(write_pending: bool = true) -> void:
	if save_worker != null:
		save_worker.wait_to_finish()
		save_worker = null
	if write_pending and not pending_save.is_empty(): _write_save(pending_save, background_save_codec, SAVE_PATH)
	pending_save = {}

func _load_game() -> void:
	_flush_background_save()
	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "No saved battle on this device yet."
		return
	var diagnostics := get_node("/root/Diagnostics")
	var began := Time.get_ticks_msec()
	diagnostics.record("save_load_begin", {"game": pack.id, "static_bytes": OS.get_static_memory_usage()})
	# Bound reconstruction before expanding saves containing long histories.
	var data: Dictionary = save_codec.decode(_read_json(SAVE_PATH), 16 if OS.has_feature("mobile") else 64, true)
	if not save_codec.error.is_empty():
		diagnostics.record("save_load_failed", {"reason": save_codec.error})
		status_label.text = save_codec.error;return
	diagnostics.record("save_decoded", {"elapsed_ms": Time.get_ticks_msec() - began, "undo_count": data.get("undo_history", []).size(), "static_bytes": OS.get_static_memory_usage()})
	var previous = battle
	_restore_game_data(data)
	if battle != previous:
		if data.get("undo_history", []) is Array:
			undo_history = data.get("undo_history", []).slice(-16 if OS.has_feature("mobile") else -64).filter(_valid_undo_entry)
	diagnostics.record("save_load_end", {"restored": battle != previous, "elapsed_ms": Time.get_ticks_msec() - began, "static_bytes": OS.get_static_memory_usage()})

func _valid_undo_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("snapshot") is Dictionary: return false
	var snapshot: Dictionary = entry.snapshot
	if SaveCodec.is_compact(snapshot):
		# Validate the selected checkpoint fully when restoring it, not all 16
		# (or 64 desktop) chapters just to populate the undo list.
		return snapshot.get("schema_version") == save_codec.SCHEMA_VERSION and preload("res://runtime/game_identity.gd").accepts(snapshot,pack.id,pack.get("rom_sha256","")) and snapshot.get("chapter_id", "") == chapter.get("id", "") and snapshot.get("shared") is Array and snapshot.get("data") is Dictionary
	if not snapshot.get("state") is Dictionary or not snapshot.state.get("chapter") is Dictionary: return false
	if snapshot.get("chapter_id", "") != chapter.get("id", "") or snapshot.state.chapter.get("id", "") != chapter.get("id", ""): return false
	if not snapshot.get("selection_ui", {}) is Dictionary or not snapshot.get("dialogue_ui", {}) is Dictionary: return false
	var probe = Battle.new()
	var valid: bool = probe.restore(snapshot.state)
	if not valid:
		get_node("/root/Diagnostics").record("undo_checkpoint_rejected", {"chapter": snapshot.chapter_id, "turn": snapshot.state.get("turn", 0), "action": entry.get("action", "")})
	return valid

func _restore_game_data(data: Dictionary) -> void:
	if SaveCodec.is_compact(data):
		data = save_codec.decode(data, 16 if OS.has_feature("mobile") else 64, true)
		if not save_codec.error.is_empty():
			status_label.text = save_codec.error;return
	if data.get("schema_version", 0) != 1 or not preload("res://runtime/game_identity.gd").accepts(data,pack.id,pack.get("rom_sha256","")):
		status_label.text = "This save belongs to a different content version."
		return
	var saved_path:= chapter_path if data.get("chapter_id", "") == chapter.id else ""
	for entry in pack.get("chapters", []):
		if entry.id == data.get("chapter_id", ""):
			saved_path = entry.path
	if saved_path.is_empty() or not data.get("state") is Dictionary or not data.state.get("chapter") is Dictionary or data.state.chapter.get("id", "") != data.get("chapter_id", ""):
		status_label.text = "This save belongs to an unavailable chapter."
		return
	if not data.get("selection_ui", {}) is Dictionary or not data.get("dialogue_ui", {}) is Dictionary or not data.get("dialogue_ui", {}).get("remaining", []) is Array:
		status_label.text = "The save is invalid; the current battle was preserved."
		return
	var selection_state: Dictionary = data.get("selection_ui", {})
	var dialogue_state: Dictionary = data.get("dialogue_ui", {})
	for page in dialogue_state.get("remaining", []):
		if page is Dictionary and not board.valid_story_actions(page.get("scene_actions", [])):
			status_label.text = "The save is invalid; the current battle was preserved."
			return
	if dialogue_state.has("scene") and not _valid_dialogue_scene(dialogue_state.scene):
		status_label.text = "The save is invalid; the current battle was preserved."
		return
	if not board.valid_story_snapshot(data.get("story_ui", {})):
		status_label.text = "The save is invalid; the current battle was preserved."
		return
	if not data.get("campaign", {}) is Dictionary or not data.get("campaign", {}).get("completed_chapters", []) is Array:
		status_label.text = "The save is invalid; the current battle was preserved."
		return
	var restored = Battle.new()
	var restored_start = Battle.new()
	if data.has("chapter_start") and ( not data.chapter_start is Dictionary or not restored_start.restore(data.chapter_start) or restored_start.chapter.get("id", "") != data.get("chapter_id", "")):
		status_label.text = "The save is invalid; the current battle was preserved."
		return
	if restored.restore(data.get("state", {})):
		var assets = preload("res://runtime/rom_assets.gd")
		if not assets.ensure_resource(saved_path):
			status_label.text = assets.progress
			return
		if pack.get("dynamic_rom",false):
			board.configure_animations(str(pack.map_animation_manifest))
			cutscene.configure(str(pack.battle_animation_manifest))
		if route_select: route_select.hide()
		route_selection_context = ""
		restored.set_promotion_catalog(promotion_manifest)
		if data.has("chapter_start"):
			restored_start.set_promotion_catalog(promotion_manifest)
		var restored_selected:= str(selection_state.get("selected_id", ""))


		if not restored.pending_moves.is_empty():
			restored_selected = str(restored.pending_moves.keys()[0])
		var restored_unit: Dictionary = restored.get_unit(restored_selected)
		if restored_unit.is_empty() or int(restored_unit.hp) <= 0 or not str(restored_unit.get("rescued_by", "")).is_empty():
			restored_selected = ""
		var restored_target:= str(selection_state.get("pending_target", ""))
		var restored_weapon:= str(selection_state.get("pending_weapon", ""))
		if not restored.forecast_with_weapon(restored_selected, restored_target, restored_weapon).get("attacker", {}).get("can_attack", false):
			restored_target = ""
		if cutscene: cutscene.cancel()
		_cancel_scene_presentation()
		if rogue_overlay: rogue_overlay.hide()
		deployment_overlay.hide()
		deployment_battle = null
		battle = restored
		battle.rules.auto_promote_lords = auto_promote_lords
		battle.rules.permadeath = true if Rogue.active(battle) else permadeath
		battle.set_durability_mode(durability_mode)
		battle.rules.item_durability_mode = item_durability_mode
		_apply_supply_preferences(false)
		busy = false
		campaign = data.get("campaign", {"completed_chapters": []}).duplicate(true)
		campaign.difficulty = Difficulty.normalize(campaign.get("difficulty", restored.chapter.get("difficulty", "normal")))
		initial_phase_pending = bool(data.get("initial_phase_pending", false))
		conversation_log = data.get("conversation_log", []).filter( func(line): return line is String) if data.get("conversation_log", []) is Array else []
		if data.get("active_reward", {}) is Dictionary and not data.get("active_reward", {}).is_empty():
			battle.chapter.get_or_add("reward_notices", []).push_front(data.active_reward.duplicate(true))
		if not campaign.has("completed_chapters"): campaign.completed_chapters = []
		chapter = battle.chapter


		chapter_start = restored_start.serialize(false) if data.has("chapter_start") else {}
		chapter_path = saved_path
		board.battle = battle
		outcome_presented = str(data.get("outcome_presented", battle.outcome))
		transition_pending = battle.outcome == "victory" and ( not _next_chapter_path().is_empty() or not chapter.get("route_choices",{}).is_empty() or _is_final_chapter())
		dialogue_overlay.hide()
		items_overlay.hide()
		trade_menu.hide()
		shop_overlay.hide()
		details_overlay.hide()
		queued_attack = false
		_cancel_choice()
		undo_overlay.hide()
		library_overlay.hide()
		settings_overlay.hide()
		info_overlay.hide()
		help_overlay.hide()
		record_overlay.hide()
		selected_id = ""
		pending_target = ""
		_return_to_battle()
		selected_id = restored_selected
		pending_target = restored_target
		pending_weapon = restored_weapon
		_clear_assist()
		var saved_assist: Variant = selection_state.get("pending_assist", {})
		if saved_assist is Dictionary and not saved_assist.is_empty():
			for option in battle.assist_options(selected_id, str(saved_assist.get("target", ""))):
				if str(option.kind) == str(saved_assist.get("kind", "")) and int(option.get("index", -1)) == int(saved_assist.get("index", -1)):
					pending_assist = saved_assist.duplicate(true)
					break
		command_menu_open = bool(selection_state.get("command_menu_open", not restored.pending_moves.is_empty()))
		_refresh()
		status_label.text = "Saved battle resumed."
		if dialogue_state.get("visible", false) and dialogue_state.get("remaining", []) is Array:
			dialogue_lines = dialogue_state.get("remaining", []).duplicate(true)
			dialogue_speaker.text = str(dialogue_state.get("speaker", "Field report"))
			dialogue_text.text = str(dialogue_state.get("text", ""))
			if dialogue_state.get("scene", null) is Dictionary:
				dialogue_view.animations_enabled = animations_enabled
				dialogue_view.restore_state(dialogue_state.scene)
			else:
				_set_dialogue_portrait(str(dialogue_state.get("portrait", "")))
			move_child(dialogue_overlay, get_child_count() - 1)
			dialogue_overlay.show()
			_raise_dialogue_controls()
		if data.get("story_ui", {}) is Dictionary:
			var remaining: Array = board.restore_story(data.get("story_ui", {}))
			if not remaining.is_empty(): _resume_story(remaining)
		_check_outcome()
		_refresh()
		_music("victory" if battle.outcome == "victory" else ("dialogue" if dialogue_overlay.visible else "player_phase"))
		call_deferred("_settle_battle")
	else:
		status_label.text = "The save is invalid; the current battle was preserved."

func _valid_dialogue_scene(scene: Variant) -> bool:
	if not scene is Dictionary or not scene.get("lord_paths", []) is Array or not scene.get("current", {}) is Dictionary: return false
	if scene.has("route"):
		if not scene.route is Dictionary or not scene.route.get("route_key", "") is String: return false
		var elapsed = scene.route.get("elapsed", 0.0)
		if not (elapsed is int or elapsed is float) or not is_finite(float(elapsed)) or float(elapsed) < 0: return false
		if not scene.route.get("actor_elapsed", {}) is Dictionary: return false
		for actor_id in scene.route.get("actor_elapsed", {}):
			if not actor_id is String: return false
			var clock_value = scene.route.actor_elapsed[actor_id]
			if not (clock_value is int or clock_value is float) or not is_finite(float(clock_value)) or float(clock_value) < 0: return false
	var count = scene.get("visible_characters", -1)
	if not (count is int or count is float) or not is_finite(float(count)): return false
	var current: Dictionary = scene.get("current", {})
	if not board.valid_story_actions(current.get("scene_actions", [])): return false
	if not current.get("worldmap", {}) is Dictionary: return false
	var route: Dictionary = current.get("worldmap", {})
	for key in ["from", "to", "viewport"]:
		if not route.has(key): continue
		var point = route[key]
		if not point is Array or point.size() != (4 if key == "viewport" else 2): return false
		for value in point:
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if key == "viewport" and (float(point[2]) <= 0 or float(point[3]) <= 0): return false
	if not route.get("source_route", []) is Array: return false
	for point in route.get("source_route", []):
		if not point is Array or point.size() != 2: return false
		for value in point:
			if not (value is int or value is float) or not is_finite(float(value)): return false
	for key in ["page_index", "page_count"]:
		if route.has(key) and ( not (route[key] is int or route[key] is float) or not is_finite(float(route[key]))): return false
	if not route.get("animation_manifest", "") is String or not route.get("actors", []) is Array: return false
	for actor in route.get("actors", []):
		if not actor is Dictionary or not actor.get("source_route", []) is Array: return false
		for key in ["id", "faction", "sprite", "sprite_idle"]:
			if not actor.get(key, "") is String: return false
		for key in ["rom_class_id", "style", "start_page"]:
			var number = actor.get(key, 0)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0 or float(number) != floorf(float(number)): return false
		for point in actor.get("source_route", []):
			if not point is Array or point.size() != 2: return false
			for number in point:
				if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

func _confirm_restart() -> void:
	var confirmation:= ConfirmationDialog.new()
	confirmation.title = "Restart chapter"
	confirmation.dialog_text = "Restart this chapter? Units return to their state at the start of this chapter."
	confirmation.confirmed.connect(func(): confirmation.queue_free();_restart_battle())
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(480, 180))

func _restart_battle() -> void:
	var rogue_costs:= {}
	if Rogue.active(battle):
		if Rogue.remaining(battle, "undo") <= 0:
			status_label.text = "No Undo uses remain this chapter."
			return
		rogue_costs = {"undo_used": int(battle.chapter.rogue.get("undo_used", 0)) + 1, "arena_used": int(battle.chapter.rogue.get("arena_used", 0)), "training": int(battle.chapter.rogue.get("training", 0))}
		chapter_start = chapter_start.duplicate(true)
		for key in rogue_costs: chapter_start.chapter.rogue[key] = rogue_costs[key]
	if rogue_overlay: rogue_overlay.hide()
	deployment_overlay.hide()
	deployment_battle = null
	conversation_log.clear()
	active_reward.clear()
	_cancel_scene_presentation()
	undo_history.clear()
	initial_phase_pending = true
	if cutscene: cutscene.cancel()
	var restored = Battle.new()
	if chapter_start.is_empty() or not restored.restore(chapter_start):
		_start_battle(chapter_path)
		return
	if Difficulty.normalize(campaign.get("difficulty", "normal")) != Difficulty.normalize(restored.chapter.get("difficulty", "normal")):
		chapter_handoff = true
		_start_battle(chapter_path, true, restored.native_event_state.get("permanent_flags", []))
		chapter_handoff = false
		Difficulty.preserve_starting_army(restored, battle)
		chapter_start = battle.serialize(false)
		restored = battle
	battle = restored
	battle._run_events("chapter_start")
	battle.rules.auto_promote_lords = auto_promote_lords
	battle.rules.permadeath = true if Rogue.active(battle) else permadeath
	battle.set_durability_mode(durability_mode)
	battle.rules.item_durability_mode = item_durability_mode
	_apply_supply_preferences(false)
	board.battle = battle
	chapter = battle.chapter
	busy = false
	transition_pending = false
	outcome_presented = ""
	selected_id = ""
	pending_target = ""
	settings_overlay.hide()
	info_overlay.hide()
	help_overlay.hide()
	record_overlay.hide()
	items_overlay.hide()
	trade_menu.hide()
	shop_overlay.hide()
	details_overlay.hide()
	queued_attack = false
	_return_to_battle()
	_show_chapter_opening()
	if not dialogue_overlay.visible: _music("player_phase")
	if Rogue.active(battle): _save_game()

func _confirm_chapter(path: String, chapter_title: String) -> void:
	var confirmation:= ConfirmationDialog.new()
	confirmation.title = "Start chapter"
	confirmation.dialog_text = "Start %s? Unsaved battle progress will be replaced. Your saved battle will remain available." % chapter_title
	confirmation.confirmed.connect(func(): confirmation.queue_free();_load_chapter_preview(path))
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(460, 180))

func _load_chapter_preview(path: String) -> void:
	if not preload("res://runtime/rom_assets.gd").ensure_resource(path):
		status_label.text = preload("res://runtime/rom_assets.gd").progress
		return
	campaign = {"completed_chapters": [], "difficulty": Difficulty.normalize(campaign.get("difficulty", "normal"))}
	chapter_handoff = true
	_start_battle(path, true)
	chapter_handoff = false
	var previous: Array = []
	for entry in pack.get("chapters", []):
		if pack.get("dynamic_rom",false): break
		if str(entry.path) == path: break

		if path.get_file().begins_with("hec") and str(entry.path).get_file().begins_with("eli"): continue
		if path.get_file().begins_with("eli") and str(entry.path).get_file().begins_with("hec"): continue
		var earlier:= str(entry.path).get_basename()
		if earlier.ends_with("b") or path.get_basename() == earlier + "b": continue
		previous.append(Difficulty.chapter(_read_json(str(entry.path)), campaign.difficulty))
	preload("res://engine/chapter_preview.gd").prepare(battle, previous)
	battle.apply_chapter_repairs()
	battle._run_events("chapter_start")
	chapter_start = battle.serialize(false)
	chapter_cover.hide()
	_preload_intro(chapter.get("intro", []))
	_show_chapter_opening()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for overlay in [translations_overlay, portrait_import_panel, voice_overlay, custom_overlay]:
			if is_instance_valid(overlay) and overlay.visible:
				overlay.hide()
				return
		if is_instance_valid(epilogue_view):
			epilogue_view.finished.emit()
		elif title_screen and title_screen.visible:
			_return_to_library()
		elif not busy:
			_open_info()
	if what == NOTIFICATION_APPLICATION_PAUSED and battle and not browsing and not (chapter_loading and chapter_loading.visible):
		_save_game()

func _build_unit_details() -> void:
	var modal:= _modal(700, 680, true)
	details_overlay = modal[0]
	modal[0].get_child(0).add_theme_stylebox_override("panel", preload("res://ui/panel_style.gd").create(false, 0.91))
	var column: VBoxContainer = modal[1]
	var scroll:= preload("res://ui/swipe_scroll.gd").new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	details_view = load("res://ui/unit_details.gd").new()
	details_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details_view)
	skills_overlay = preload("res://ui/skill_details_panel.gd").new()
	add_child(skills_overlay)
	details_view.skills_requested.connect(func(unit, record):
		skills_overlay.present(unit, str(record.id), battle)
		move_child(skills_overlay, get_child_count() - 1))
	details_overlay.visibility_changed.connect(func():
		if not details_overlay.visible:
			skills_overlay.hide()
			if voice_player: voice_player.fade_status(details_unit_id))
	details_view.item_requested.connect(func(index):
		selected_id = details_unit_id
		details_overlay.hide()
		_open_items(true)
		if index < 0: inventory_menu._select_equipped()
		else: inventory_menu.item_list.select(index);inventory_menu._describe())
	details_portrait = details_view.portrait
	details_portrait.reparent(details_overlay)
	details_overlay.move_child(details_portrait, 0)
	details_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_portrait.show()
	resized.connect(_layout_unit_details)
	_layout_unit_details.call_deferred()
	details_label = details_view.summary
	var buttons:= HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	details_support_button = _menu_button(buttons, "Supports", "support", func(): _open_supports(details_unit_id, true))
	details_support_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	details_support_button.text = ""
	details_support_button.tooltip_text = "Supports"
	var support_center:= CenterContainer.new()
	support_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	support_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_support_button.add_child(support_center)
	var support_content:= HBoxContainer.new()
	support_content.add_theme_constant_override("separation", 10)
	support_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	support_center.add_child(support_content)
	var support_icon:= TextureRect.new()
	support_icon.texture = details_support_button.icon
	details_support_button.icon = null
	support_icon.custom_minimum_size = Vector2(22, 22)
	support_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	support_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	support_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	support_content.add_child(support_icon)
	var support_caption:= _label("Supports", 20)
	support_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	support_content.add_child(support_caption)
	details_supply_button = _button(buttons, "Supply", func(): selected_id = details_unit_id;_open_supply())
	details_supply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(buttons, "Close", func(): _set_panel_visible(details_overlay, false)).size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _layout_unit_details() -> void:
	if not details_overlay: return
	var panel: Control = details_view.get_parent().get_parent().get_parent()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(minf(700, size.x - 32), minf(680, size.y - 32))
	var full_art: bool = not details_portrait.custom.is_empty()
	details_portrait.visible = full_art
	panel.position = Vector2(lerpf((size.x - panel.size.x) * 0.5, size.x - panel.size.x - 20, 0.65) if full_art else (size.x - panel.size.x) * 0.5, (size.y - panel.size.y) * 0.5)
	details_portrait.queue_redraw()

func _open_unit_details(id: String) -> void:
	if (busy and not deployment_overlay.visible) or dialogue_overlay.visible: return
	var unit: Dictionary = battle.get_unit(id)
	if unit.is_empty(): return
	if voice_player: voice_player.play_unit(unit, "status")
	details_unit_id = id
	details_support_button.visible = unit.faction == "player"
	details_view.present(unit, battle)
	details_supply_button.visible = deployment_overlay.visible and unit.faction == "player"
	details_overlay.move_child(details_portrait, details_overlay.get_child_count() - 1)
	_layout_unit_details()
	_set_panel_visible(details_overlay, true)
	move_child(details_overlay, get_child_count() - 1)

func _build_trade() -> void:
	trade_menu = load("res://ui/trade_menu.gd").new()
	add_child(trade_menu)
	trade_menu.slot_pressed.connect(_trade_slot_pressed)
	trade_menu.partner_changed.connect(func(id):
		trade_partner = id
		trade_menu.selected_side = -1
		_present_trade())
	trade_menu.closed.connect(_after_noncombat)

func _open_trade() -> void:
	if not _can_command(_selected()) or _selected().get("canto_active", false): return
	trade_partners = battle.trade_partners(selected_id)
	if trade_partners.is_empty(): return
	if trade_partners.size() > 1:
		_open_choice("trade")
		return
	trade_partner = str(trade_partners[0].id)
	trade_menu.selected_side = -1
	trade_menu.selected_slot = -2
	_present_trade()
	move_child(trade_menu, get_child_count() - 1)

func _present_trade() -> void:
	trade_menu.animations_enabled = animations_enabled
	trade_menu.present(_selected(), battle.get_unit(trade_partner), battle.inventory_slots(selected_id), battle.inventory_slots(trade_partner), trade_partners)

func _trade_slot_pressed(side: int, slot: int) -> void:
	if not trade_menu.visible or not battle.can_trade(selected_id, trade_partner): return
	if trade_menu.selected_side < 0 or trade_menu.selected_side == side:
		trade_menu.selected_side = side
		trade_menu.selected_slot = slot
		_present_trade()
		return
	var left_slot: int = slot if side == 0 else trade_menu.selected_slot
	var right_slot: int = slot if side == 1 else trade_menu.selected_slot
	var checkpoint:= _action_snapshot()
	var succeeded: bool = battle.swap_items(selected_id, trade_partner, left_slot, right_slot)
	trade_menu.selected_side = -1
	trade_menu.selected_slot = -2
	_present_trade()
	trade_menu.message.text = "Items exchanged. Choose another pair or Done." if succeeded else "These slots cannot be exchanged. An equipped item must be usable by its recipient."
	if succeeded:
		_remember_action(checkpoint, "Trade")
		_sfx("select")
		_refresh()
		if _selected().get("acted", false):
			trade_menu.hide()
			_after_noncombat()

func _after_noncombat() -> void:
	if deployment_overlay.visible: return
	var unit:= _selected()
	_clear_assist()
	pending_target = ""
	pending_weapon = ""
	if unit.get("canto_active", false):
		command_menu_open = false
		status_label.text = "%s can move %d more spaces. Tap a blue tile, then Wait." % [unit.name, int(unit.canto_remaining)]
	elif not _can_command(unit): _deselect()
	else:
		command_menu_open = true
		if unit.get("traded", false):
			status_label.text = "%s can still act%s." % [unit.name, " or use remaining movement" if unit.get("canto", false) else " from this tile"]
	_refresh()
	_check_outcome()

func _build_shop() -> void:
	var modal:= _modal(660, 600)
	shop_overlay = modal[0]
	var column: VBoxContainer = modal[1]
	shop_heading = _label("ARMORY", 26, GOLD)
	column.add_child(shop_heading)
	var modes:= HBoxContainer.new()
	column.add_child(modes)
	_button(modes, "Buy", func(): shop_mode = "buy";_refresh_shop())
	_button(modes, "Sell", func(): shop_mode = "sell";_refresh_shop())
	_button(modes, "Sell from Supply", func(): shop_mode = "supply";_refresh_shop())
	shop_list = preload("res://ui/swipe_item_list.gd").new()
	shop_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("line_separation", 16)
	column.add_child(shop_list)
	shop_list.item_selected.connect(_describe_shop)
	shop_message = _label("", 18)
	shop_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(shop_message)
	var commands:= HBoxContainer.new()
	column.add_child(commands)
	_button(commands, "Confirm", _shop_action)
	_button(column, "Buy and send to Supply", func(): _shop_action(true))
	_button(commands, "Done", func(): _set_panel_visible(shop_overlay, false))
	shop_overlay.visibility_changed.connect(func():
		if not shop_overlay.visible and battle == shop_battle and not _selected().is_empty(): call_deferred("_after_noncombat"))

func _open_shop() -> void:
	if not _can_command(_selected()) or _selected().get("canto_active", false): return
	if battle.shop_at(selected_id).is_empty(): return
	shop_battle = battle
	shop_mode = "buy"
	_refresh_shop()
	_set_panel_visible(shop_overlay, true)
	move_child(shop_overlay, get_child_count() - 1)

func _refresh_shop() -> void:
	shop_heading.text = "ARMORY · %d G" % battle.gold
	shop_list.clear()
	shop_slots.clear()
	if shop_mode == "buy":
		for stock in battle.shop_at(selected_id).get("stock", []):
			shop_list.add_item("%s    %d uses    %d G" % [stock.item.get("name", "Item"), int(stock.item.get("uses", 0)), battle.shop_price(selected_id, int(stock.get("price", 0)))])
	elif shop_mode == "supply":
		for index in range(battle.inventory.size()):
			var item: Dictionary = battle.inventory[index]
			shop_slots.append(index)
			shop_list.add_item("%s    %d G" % [item.get("name", "Item"), battle.sell_price(item)])
	else:
		for entry in battle.inventory_slots(selected_id):
			if entry.item.is_empty(): continue
			shop_slots.append(int(entry.slot))
			var price: int = battle.sell_price(entry.item)
			shop_list.add_item("%s%s    %s" % ["◆ " if entry.get("equipped", false) else "", entry.item.get("name", "Item"), "%d G" % price if price > 0 else "Cannot sell"])
	shop_message.text = ""
	if shop_list.item_count > 0:
		shop_list.select(0)
		_describe_shop(0)

func _describe_shop(index: int) -> void:
	var item: Dictionary = {}
	if shop_mode == "buy": item = battle.shop_at(selected_id).get("stock", [])[index].item
	elif shop_mode == "supply": item = battle.inventory[shop_slots[index]]
	else:
		for entry in battle.inventory_slots(selected_id):
			if int(entry.slot) == int(shop_slots[index]): item = entry.item;break
	shop_message.text = preload("res://ui/item_description.gd").describe(item)

func _shop_action(to_supply: bool = false) -> void:
	if to_supply and shop_mode != "buy": return
	var chosen:= shop_list.get_selected_items()
	if chosen.is_empty(): return
	var checkpoint:= _action_snapshot()
	var result: Dictionary = battle.buy_item(selected_id, chosen[0], to_supply) if shop_mode == "buy" else battle.sell_item(selected_id, int(shop_slots[chosen[0]]), shop_mode == "supply")
	_refresh_shop()
	shop_message.text = str(result.get("reason", "Purchased." if shop_mode == "buy" else "Sold.")) + "\n" + shop_message.text
	if result.get("ok", false):
		_remember_action(checkpoint, "Shop")
		_sfx("select")
		_refresh()
		if _selected().get("acted", false): shop_overlay.hide()

func _build_items() -> void:
	inventory_menu = load("res://ui/inventory_menu.gd").new()
	add_child(inventory_menu)
	items_overlay = inventory_menu
	items_list = inventory_menu.item_list
	items_heading = inventory_menu.heading
	items_target = inventory_menu.target
	items_message = inventory_menu.message
	inventory_menu.action_requested.connect(_item_action)
	inventory_menu.sound_requested.connect(_sfx)
	inventory_menu.selection_changed.connect(_refresh_item_targets)

func _open_items(inspect_only: bool = false) -> void:
	var unit:= _selected()
	if unit.is_empty() or ( not inspect_only and ( not _can_command(unit) or unit.get("canto_active", false))): return
	inventory_menu.read_only = not _can_command(unit) or unit.get("canto_active", false)
	inventory_menu.animations_enabled = animations_enabled
	inventory_menu.present(unit, battle)
	_position_inventory()
	_refresh_item_targets()
	items_message.text = ""
	move_child(items_overlay, get_child_count() - 1)
	items_overlay.show()

func _position_inventory() -> void:
	if _selected().is_empty(): return
	var avoid: Array = []
	for panel in [stats_panel, terrain_panel]:
		if panel and panel.visible: avoid.append(panel.get_global_rect().grow(8))
	inventory_menu.configure_placement(board.cell_screen_position(battle.position(_selected())), 110, 110, avoid)

func _refresh_item_targets() -> void:
	if not inventory_menu: return
	var unit:= _selected()
	if unit.is_empty(): return
	var index:= -1 if inventory_menu.equipped_selected else (items_list.get_selected_items()[0] if not items_list.get_selected_items().is_empty() else -1)
	var item: Dictionary = unit.get("weapon", {}) if index < 0 else battle._inventory_item(unit, index)
	items_target.clear()
	item_target_ids.clear()
	var valid: Array = battle.helpful_targets(selected_id, index) if item.get("kind", "") == "staff" else []
	var ordered_targets: Array = battle.units.duplicate()
	ordered_targets.sort_custom(func(a,b): return str(TranslationServer.translate(str(a.name))).naturalnocasecmp_to(str(TranslationServer.translate(str(b.name)))) < 0)
	for ally in ordered_targets:
		if not battle._on_map(ally): continue
		var eligible:= valid.has(str(ally.id)) if item.get("kind", "") == "staff" else str(ally.id) == selected_id
		if item.has("ring_bonuses"):
			eligible = unit.get("can_play", false) and ally.faction == "player" and ally.id != unit.id and battle._distance(battle.position(unit), battle.position(ally)) == 1
		if not eligible: continue
		item_target_ids.append(str(ally.id))
		items_target.add_item("%s · HP %d/%d" % [ally.name, ally.hp, ally.max_hp])
	items_target.visible = items_target.item_count > 0

func _item_action(action: String) -> void:
	if not _can_command(_selected()):
		return
	var indexes:= items_list.get_selected_items()
	if indexes.is_empty():
		items_message.text = "Select an inventory item first."
		return
	var target_id: String = item_target_ids[items_target.selected] if items_target.selected >= 0 else selected_id
	var checkpoint:= _action_snapshot()
	if action == "use":
		await _use_inventory_item(indexes[0], target_id)
	elif action == "equip":
		if battle.equip_item(selected_id, indexes[0]):
			_remember_action(checkpoint, "Equip")
			_refresh()
			_open_items()
			inventory_menu.show_equipped_confirmation()
			_sfx("item_equip")
			_flush_dialogue()
		else:
			items_message.text = "This unit cannot equip that item."
	elif action == "trade":
		if battle.trade_item(selected_id, target_id, indexes[0]):
			_remember_action(checkpoint, "Trade")
			_refresh()
			_open_items()
			items_message.text = "Item transferred."
			_flush_dialogue()
		else:
			items_message.text = "Choose an adjacent ally with room in their inventory."

func _smoke_test() -> void:
	assert (battle != null)
	assert (catalog.size() > 100)
	assert (board.map_texture != null)
	dialogue_overlay.hide()
	_on_cell_pressed(battle.position(battle.get_unit("fe7_unit_3")))
	assert (selected_id == "fe7_unit_3")
	assert ( not board.reachable_cells.is_empty())
	var current_map: Dictionary = board.map_data.duplicate(true)
	var current_battle = battle
	_open_library()
	assert (backdrop_view.entries.size() == catalog.size())
	_choose_map(0)
	assert (backdrop_view.picture.texture != null)
	assert ( not browsing and battle == current_battle and board.map_data == current_map)
	backdrop_overlay.hide()
	print("UI smoke test passed: battle, selection, read-only map Library and preserved scene.")
	get_tree().quit(0)

func _use_inventory_item(index: int, target_id: String, destination: Vector2i = Vector2i(-1, -1), repair_slot: int = -2) -> void:
	if not _can_command(_selected()) or _selected().get("canto_active", false): return
	var checkpoint:= _action_snapshot()
	var item: Dictionary = _selected().inventory[index]
	if item.get("kind", "") == "trap" and destination.x < 0:
		selected_staff = index
		_open_trap_destination()
		return
	if item.get("staff_effect", "") in ["warp", "rescue", "repair", "torch", "unlock"] and destination.x < 0 and repair_slot == -2:
		selected_staff = index
		_open_staff_detail(target_id)
		return
	var assist_cutscene: bool = animations_enabled and _show_battle_cutscenes() and _assist_has_other_target(selected_id, target_id, item)
	var result: Dictionary = battle.use_item(selected_id, index, target_id, destination, repair_slot)
	if result.get("ok", false):
		_remember_action(checkpoint, "Use item")
		items_overlay.hide()
		if result.get("promotion", false):
			status_label.text = "%s promoted to %s." % [_selected().get("name", "Unit"), result.get("class_name", "new class")]
			_sfx("level_up")
			promotion_battle = battle
			busy = true
			_refresh()
			promotion_panel.animations_enabled = animations_enabled
			promotion_panel.present(battle.get_unit(str(result.target_id)), result)
			move_child(promotion_panel, get_child_count() - 1)
			return
		elif result.has("growth_boost"):
			status_label.text = "Used %s. Stat growth rates +%d percentage points." % [result.item_name,int(result.growth_boost)]
			_sfx("stat_up")
		elif not result.get("stat_gains", {}).is_empty():
			var gains: Array[String] = []
			for stat in result.stat_gains:
				gains.append("%s +%d" % ["Max HP" if stat == "max_hp" else str(stat).capitalize(), int(result.stat_gains[stat])])
			status_label.text = "Used %s. %s." % [result.get("item_name", "item"), ", ".join(gains)]
			_sfx("stat_up")
		elif not result.get("temporary_bonuses", {}).is_empty():
			var bonuses: Array[String] = []
			for stat in result.temporary_bonuses:
				bonuses.append("%s +%d" % [str(stat).capitalize(), int(result.temporary_bonuses[stat])])
			status_label.text = "Used %s. %s (temporary)." % [result.get("item_name", "item"), ", ".join(bonuses)]
			_sfx("stat_up")
		elif result.has("status_hit"):
			status_label.text = "%s: %s." % [result.get("item_name", "Staff"), str(result.status).capitalize() if result.status_hit else "Miss"]
			if not assist_cutscene: _sfx("heal" if result.status_hit else "miss")
		elif result.get("relocated", false):
			status_label.text = "Used %s. %s relocated." % [result.item_name, battle.get_unit(str(result.target_id)).name]
			if not assist_cutscene: _sfx("heal")
		elif result.has("repaired"):
			status_label.text = "%s fully repaired." % result.repaired
			if not assist_cutscene: _sfx("heal")
		elif result.has("placed_trap"):
			status_label.text = "Placed %s.%s" % [result.item_name, " Blocks movement for three turns." if result.placed_trap == "light_rune" else " Stops movement and deals 10 damage."]
			_sfx("select")
		elif result.get("illuminated", false):
			status_label.text = "Torch lit. Its light fades by one space each turn."
			if not assist_cutscene: _sfx("heal")
		elif result.get("restored", false):
			status_label.text = "Used %s. Status restored." % result.get("item_name", "staff")
			if not assist_cutscene: _sfx("heal")
		else:
			status_label.text = "Used %s. Restored %d HP." % [result.get("item_name", "item"), result.get("healed", 0)]
			if not assist_cutscene: _sfx("heal")
		if animations_enabled and (item.get("type", "") == "staff" or item.has("ring_bonuses") or int(result.get("healed", 0)) > 0 or not result.get("experience", []).is_empty()):
			var action_battle = battle
			busy = true
			_refresh()
			if assist_cutscene:
				move_child(cutscene, get_child_count() - 1)
				await cutscene.play_assist(battle, selected_id, target_id, item, result)
			elif int(result.get("healed", 0)) > 0: await board.play_healing(result)
			if battle != action_battle: return
			if not result.get("experience", []).is_empty():
				await _play_rewards(result.experience)
				if battle != action_battle: return
			busy = false
		_after_noncombat()
	else:
		items_message.text = result.get("reason", "This item cannot be used now.")
		status_label.text = items_message.text

func _finish_promotion() -> void:
	if battle != promotion_battle: return
	promotion_battle = null
	busy = false
	_after_noncombat()

func _build_choices() -> void:
	var modal:= _modal(410, 220)
	choice_overlay = modal[0]
	choice_overlay.color = Color.TRANSPARENT
	choice_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_heading = _label("Choose an ally", 25, GOLD)
	modal[1].add_child(choice_heading)
	choice_list = VBoxContainer.new()
	modal[1].add_child(choice_list)
	_button(modal[1], "Cancel", _cancel_choice)
	resized.connect(_position_choice_panel)
	modal[1].minimum_size_changed.connect(func(): _position_choice_panel.call_deferred())

func _offer_map_unlock(cell: Vector2i) -> bool:
	var unit := _selected()
	if not unlock_staff_chests or not _can_command(unit) or unit.get("canto_active", false) or unit.get("rogue_fury", false): return false
	for index in range(unit.inventory.size()):
		var item: Dictionary = unit.inventory[index]
		if item.get("staff_effect", "") != "unlock" or not battle.can_use_staff(unit, item): continue
		if not preload("res://engine/staff_actions.gd").destinations(battle, unit, item, unit).has(cell): continue
		selected_staff = index
		pending_unlock = cell
		choice_mode = "unlock_confirm"
		for child in choice_list.get_children():
			choice_list.remove_child(child)
			child.queue_free()
		choice_heading.text = "Use Unlock?"
		_button(choice_list, "Unlock", _confirm_map_unlock)
		_set_panel_visible(choice_overlay, true)
		move_child(choice_overlay, get_child_count() - 1)
		_position_choice_panel()
		return true
	return false

func _confirm_map_unlock() -> void:
	var destination := pending_unlock
	var index := selected_staff
	_cancel_choice()
	await _use_inventory_item(index, selected_id, destination)

func _open_staff() -> void:
	if not _can_command(_selected()) or _selected().get("canto_active", false): return
	var options: Array = battle.staff_options(selected_id)
	if options.is_empty(): return
	if options.size() == 1:
		_begin_staff(int(options[0].index))
		return
	choice_mode = "staff_item"
	choice_ids.clear()
	for child in choice_list.get_children():
		choice_list.remove_child(child)
		child.queue_free()
	choice_heading.text = "Choose a staff"
	for option in options:
		var index:= int(option.index)
		_button(choice_list, "%s · %d" % [option.item.name, int(option.item.uses)], func(): _begin_staff(index))
	board.set_ally_choices([], true)
	actions_panel.hide()
	_set_panel_visible(choice_overlay, true)
	move_child(choice_overlay, get_child_count() - 1)
	_position_choice_panel()

func _begin_staff(index: int) -> void:
	selected_staff = index
	if _selected().inventory[index].get("staff_effect", "") in ["torch", "unlock"]: _open_staff_detail(selected_id)
	else: _open_choice("staff")

func _open_choice(mode: String) -> void:
	if not _can_command(_selected()): return
	if mode == "talk":
		var speakers: Array = battle.talk_targets(selected_id)
		if speakers.size() == 1:
			choice_mode = mode
			choice_ids.assign([str(speakers[0].id)])
			_choose_ally(str(speakers[0].id))
			return
	choice_mode = mode
	choice_ids.clear()
	for child in choice_list.get_children():
		choice_list.remove_child(child)
		child.queue_free()
	choice_heading.text = "Choose an ally to " + mode
	if mode == "attack": choice_heading.text = "Choose a target"
	if mode == "staff": choice_heading.text = "Choose a target · " + str(_selected().inventory[selected_staff].name)
	if mode == "give": choice_heading.text = "Give rescued ally to…"
	if mode == "take": choice_heading.text = "Take rescued ally from…"
	if mode == "drop":
		choice_heading.text = "Drop %s" % battle.get_unit(str(_selected().get("carrying_id", ""))).get("name", "ally")
		for cell in battle.drop_cells(selected_id):
			var destination: Vector2i = cell
			var delta: Vector2i = destination - battle.position(_selected())
			var direction:= "Right" if delta.x > 0 else ("Left" if delta.x < 0 else ("Below" if delta.y > 0 else "Above"))
			_button(choice_list, direction, func(): _choose_drop(destination))
	else:
		var targets: Array
		match mode:
			"attack": targets = _available_attack_targets()
			"trade": targets = battle.trade_partners(selected_id)
			"talk": targets = battle.talk_targets(selected_id)
			"support": targets = battle.support_partners(selected_id)
			"play": targets = battle.play_targets(selected_id)
			"give": targets = battle.transfer_targets(selected_id, true)
			"take": targets = battle.transfer_targets(selected_id)
			"staff":
				for id in battle.helpful_targets(selected_id, selected_staff): targets.append(battle.get_unit(str(id)))
			_: targets = battle.rescue_targets(selected_id)
		for ally in targets:
			var id:= str(ally.id)
			choice_ids.append(id)
			var suffix:= " · Con %d / Aid %d" % [int(ally.con), battle.rescue_aid(_selected())] if mode == "rescue" else " · HP %d/%d" % [int(ally.hp), int(ally.max_hp)]
			if mode == "give": suffix = " · Aid %d" % battle.rescue_aid(ally)
			elif mode == "take": suffix = " · Carrying " + str(battle.get_unit(str(ally.carrying_id)).name)
			_button(choice_list, str(ally.name) + suffix, func(): _choose_ally(id))
	board.set_ally_choices(choice_ids, true)
	actions_panel.hide()
	_set_panel_visible(choice_overlay, true)
	move_child(choice_overlay, get_child_count() - 1)
	_position_choice_panel()

func _position_choice_panel() -> void:
	if not choice_overlay or not choice_overlay.visible or _selected().is_empty(): return

	var panel: Control = choice_overlay.get_child(0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(410, 0)
	var at: Vector2 = board.cell_screen_position(battle.position(_selected()))
	panel.position = Vector2(size.x - 430 if at.x < size.x * 0.5 else 20.0, maxf(12, (size.y - panel.get_combined_minimum_size().y) * 0.5))

func _cancel_choice() -> void:
	choice_mode = ""
	choice_ids.clear()
	if board:
		board.staff_cells.clear()
		board.set_ally_choices([])
	if choice_overlay: choice_overlay.hide()
	if battle: _refresh()

func _choose_ally(id: String) -> void:
	if not choice_ids.has(id): return
	var mode:= choice_mode
	_cancel_choice()
	if mode == "attack":
		_choose_attack_target(id)
		return
	if mode == "staff":
		await _use_inventory_item(selected_staff, id)
		return
	if mode == "support":
		_confirm_support(id)
		return
	if mode == "play":
		await _play_for_ally(id)
		return
	if mode == "trade":
		trade_partner = id
		trade_partners = battle.trade_partners(selected_id)
		trade_menu.selected_side = -1
		trade_menu.selected_slot = -2
		_present_trade()
		move_child(trade_menu, get_child_count() - 1)
		return
	if mode == "talk":
		for talk in battle.chapter.get("talks", []):
			if talk.get("from", "") != selected_id or talk.get("to", "") != id: continue
			if talk.has("recruitment_offers"):
				_show_recruitment_offer(talk,id,selected_id,0)
				return
			if int(talk.get("cost", 0)) <= 0 and not talk.get("duel_recruit", false): continue
			var prompt:= ConfirmationDialog.new()
			var cost:= int(talk.get("cost", 0))
			prompt.title = "Recruit " + str(battle.get_unit(id).name)
			prompt.dialog_text = "Hire %s for %d G?\nYou have %d G." % [battle.get_unit(id).name,cost,battle.gold] if cost > 0 else "Challenge this recruit to one round of combat?\nBoth units must survive for her to join."
			prompt.ok_button_text = "Pay %d G" % cost if cost > 0 else "Duel"
			add_child(prompt)
			prompt.get_ok_button().disabled = battle.gold < cost
			var actor_id:= selected_id
			prompt.confirmed.connect(func(): prompt.queue_free();_perform_ally_action(mode, id, actor_id))
			prompt.canceled.connect(prompt.queue_free)
			prompt.popup_centered(Vector2i(520, 200))
			return
	_perform_ally_action(mode, id, selected_id)

func _show_recruitment_offer(talk: Dictionary, id: String, actor_id: String, index: int) -> void:
	var offers: Array = talk.recruitment_offers
	while index < offers.size() and battle.gold < int(offers[index].cost): index += 1
	if index == offers.size():
		_perform_ally_action("talk",id,actor_id,index)
		return
	var prompt := ConfirmationDialog.new()
	var offer: Dictionary = offers[index]
	prompt.title = "Recruit " + str(battle.get_unit(id).name)
	prompt.dialog_text = "Pay %d G? You have %d G.\nStat reduction: %d to HP, strength, skill, speed, defense, resistance and luck." % [offer.cost,battle.gold,offer.stat_penalty]
	prompt.ok_button_text = "Pay %d G" % int(offer.cost)
	prompt.add_button("Bargain" if index+1 < offers.size() else "Decline recruitment",false,"bargain")
	add_child(prompt)
	var selected_offer := index
	prompt.confirmed.connect(func(): prompt.hide();prompt.queue_free();_perform_ally_action("talk",id,actor_id,selected_offer))
	prompt.custom_action.connect(func(_action):
		prompt.hide();prompt.queue_free()
		if selected_offer+1 < offers.size(): _show_recruitment_offer(talk,id,actor_id,selected_offer+1)
		else: _perform_ally_action("talk",id,actor_id,offers.size()))
	prompt.canceled.connect(prompt.queue_free)
	prompt.popup_centered(Vector2i(580,240))

func _perform_ally_action(mode: String, id: String, actor_id: String, offer_index: int = -1) -> void:
	if selected_id != actor_id or not _can_command(_selected()): return
	var checkpoint:= _action_snapshot()
	var result: Dictionary
	match mode:
		"rescue": result = battle.rescue_unit(selected_id, id)
		"give", "take": result = battle.transfer_rescue(selected_id, id, mode == "give")
		_: result = battle.talk_unit(selected_id,id,offer_index)
	if result.get("ok", false):
		_remember_action(checkpoint, mode.capitalize())
		_sfx("select")
		if not result.get("strikes", []).is_empty() and animations_enabled:
			var current_battle = battle
			busy = true
			_refresh()
			await _play_combat(result.strikes)
			if battle != current_battle: return
			busy = false
		_after_noncombat()
	else: status_label.text = str(result.get("reason", "This action is unavailable."))

func _play_for_ally(id: String) -> void:
	var checkpoint:= _action_snapshot()
	var result: Dictionary = battle.play(selected_id, id)
	if not result.get("ok", false): return
	_remember_action(checkpoint, "Play")
	_sfx("select")
	if animations_enabled and not result.get("experience", []).is_empty():
		var action_battle = battle
		busy = true
		_refresh()
		cutscene.cancel()
		if _show_battle_cutscenes():
			move_child(cutscene, get_child_count() - 1)
			await cutscene.play_assist(battle, selected_id, id, {}, result)
			if battle != action_battle: return
		await _play_rewards(result.experience)
		if battle != action_battle: return
		busy = false
	_after_noncombat()

func _choose_drop(cell: Vector2i) -> void:
	var checkpoint:= _action_snapshot()
	var result: Dictionary = battle.drop_unit(selected_id, cell)
	if result.get("ok", false):
		_cancel_choice()
		_remember_action(checkpoint, "Drop")
		_sfx("select")
		_after_noncombat()
	else: status_label.text = str(result.get("reason", "Choose an adjacent empty tile."))

func _build_preparation_and_loot() -> void:
	rogue_overlay = preload("res://ui/rogue_choice.gd").new()
	add_child(rogue_overlay)
	rogue_overlay.chosen.connect(func():
		_save_game()
		if not rogue_overlay.visible:
			busy = false
			_settle_battle())
	deployment_overlay = preload("res://ui/preparation_view.gd").new()
	add_child(deployment_overlay)
	deployment_overlay.confirmed.connect(_confirm_deployment)
	deployment_overlay.inspect_requested.connect(_open_unit_details)
	deployment_overlay.unit_selected.connect(func(unit):
		if voice_player: voice_player.play_unit(unit, "select"))
	deployment_overlay.info_requested.connect(_open_info)
	deployment_overlay.inspection_blocked = func(): return [details_overlay, info_overlay, settings_overlay, record_overlay, help_overlay, supports_overlay, supply_overlay, backdrop_overlay, quality_overlay, cheats_overlay, advanced_overlay, inventory_menu].any( func(panel): return panel != null and panel.visible)
	deployment_overlay.pointer_exclusion = func(point): return info_button.visible and info_button.get_global_rect().has_point(point)
	deployment_map = deployment_overlay.map
	deployment_list = deployment_overlay.roster
	deployment_scroll = deployment_overlay.scroll
	deployment_message = deployment_overlay.message
	deployment_start = deployment_overlay.start
	deployment_overlay.hide()
	var modal:= _modal(460, 0)
	loot_overlay = modal[0]
	modal[1].get_parent().minimum_size_changed.connect(func(): _fit_loot.call_deferred())
	modal[1].add_child(_label("RECEIVED", 24, GOLD))
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	modal[1].add_child(row)
	loot_icon = TextureRect.new()
	loot_icon.custom_minimum_size = Vector2(44, 44)
	loot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(loot_icon)
	loot_name = _label("", 24)
	loot_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(loot_name)
	loot_keep_button = _button(modal[1], "Keep", _close_chest_loot)
	loot_supply_button = _button(modal[1], "Send to Supply", _send_loot_to_supply)

func _offer_deployment() -> bool:
	if Rogue.active(battle) and not battle.chapter.get("deployment_complete", false) and not battle.chapter.rogue.get("chosen", false):
		if not rogue_overlay.visible:
			_music("song_053")
			rogue_overlay.present(battle)
			if not chapter_start.get("chapter", {}).get("rogue", {}).has("offer"):
				chapter_start = battle.serialize(false)
			_save_game()
			move_child(rogue_overlay, get_child_count() - 1)
		busy = true
		return true
	if not battle or battle.turn != 1 or battle.chapter.get("deployment_complete", false) or battle.chapter.get("deployment", {}).get("slots", []).is_empty(): return false
	if deployment_overlay.visible: return true
	deployment_battle = battle
	deployment_selection = Army.default_selection(battle)
	var required:= Army.forced_ids(battle)
	var optional:= false
	for unit in Army.all_units(battle):
		if Army.eligible(unit) and not required.has(str(unit.id)): optional = true
	if not optional:
		Army.deploy(battle, deployment_selection)
		deployment_battle = null
		return false
	_music("player_phase" if pack.id == "fe6" else "song_042")
	deployment_overlay.present(battle, board.map_data)
	get_node("/root/Diagnostics").record("deploy_begin", {"chapter": chapter.get("id", ""), "selection": deployment_overlay.selection})
	deployment_selection = deployment_overlay.selection
	busy = true
	_refresh()
	deployment_overlay.show()
	move_child(deployment_overlay, get_child_count() - 1)
	info_button.show()
	move_child(info_button, get_child_count() - 1)
	return true

func _update_deployment_count() -> void:
	var limit: int = battle.chapter.get("deployment", {}).get("slots", []).size()
	deployment_message.text = "%d / %d deployed" % [deployment_selection.size(), limit]
	for id in deployment_checks:
		var check: CheckButton = deployment_checks[id]
		check.disabled = check.get_meta("locked") or (deployment_selection.size() >= limit and not check.button_pressed)
	deployment_start.disabled = deployment_selection.is_empty() or deployment_selection.size() > limit

func _confirm_deployment() -> void:
	if deployment_battle != battle: return
	get_node("/root/Diagnostics").record("deploy_confirm", {"selection": deployment_overlay.selection})
	var result:= Army.deploy(battle, deployment_overlay.selection, deployment_overlay.placements)
	if not result.ok:
		deployment_message.text = str(result.reason)
		return
	board.zoom = deployment_map.zoom
	board.pan = deployment_map.pan
	board._view_updated()
	deployment_overlay.hide()
	deployment_battle = null
	busy = false


	initial_phase_pending = false
	battle._run_events("preparations")
	_save_game()
	if not battle.dialogue_queue.is_empty():
		_flush_dialogue()
		return
	if animations_enabled:
		var current = battle
		busy = true
		await _phase_banner("PLAYER PHASE", Color("304da8"))
		if battle != current: return
		busy = false
	_refresh()
	_music("player_phase")
	_show_next_reward()

func _show_chest_loot(result: Dictionary) -> void:
	_sfx("recruit" if result.has("recruit") else "item")
	loot_keep_button.text = "Continue" if result.has("recruit") else "Keep"
	active_reward = result.duplicate(true)
	var reward: Variant = result.get("reward", {})
	var item: Dictionary = result.get("give_item", {})
	if item.is_empty() and reward is Dictionary:
		var reward_item: Variant = reward.get("item", {})
		item = reward_item if reward_item is Dictionary else {"name": str(reward_item)}
	loot_item = item.duplicate(true)
	loot_actor = str(result.get("item_delivery", {}).get("unit_id", result.get("unit_id", loot_actor)))
	loot_in_unit = result.get("item_delivery", {}).get("destination", "") == "unit"
	loot_supply_button.visible = not loot_item.is_empty() and loot_in_unit
	loot_name.text = "Obtained %s!" % item.get("name", "%d gold" % int(reward.get("gold", 0)) if reward is Dictionary else str(reward))
	if result.has("recruit"):
		var names: Array = result.get("recruits", [result.recruit])
		loot_name.text = "%s joined the party!" % ", ".join(names)
	var path:= str(item.get("icon", ""))
	loot_icon.texture = Art.texture(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	loot_icon.visible = loot_icon.texture != null
	loot_battle = battle
	busy = true
	_refresh()
	_set_panel_visible(loot_overlay, true)
	move_child(loot_overlay, get_child_count() - 1)
	_fit_loot.call_deferred()

func _fit_loot() -> void:
	if not loot_overlay: return
	var panel: PanelContainer = loot_overlay.get_child(0)
	var height:= panel.get_combined_minimum_size().y
	panel.offset_top = - height * 0.5
	panel.offset_bottom = height * 0.5

func _show_next_reward() -> bool:
	if not battle or dialogue_overlay.visible or loot_overlay.visible: return false
	var notices: Array = battle.chapter.get("reward_notices", [])
	if notices.is_empty(): return false
	var notice: Dictionary = notices.pop_front()
	if notice.has("recruit"):
		notice = notice.duplicate(true)
		notice.recruits = [notice.recruit]
		while not notices.is_empty() and notices[0].has("recruit"):
			var recruit_name:= str(notices.pop_front().recruit)
			if not notice.recruits.has(recruit_name): notice.recruits.append(recruit_name)
	_show_chest_loot(notice)
	return true

func _send_loot_to_supply() -> void:
	if loot_battle != battle or not loot_in_unit: return
	var unit: Dictionary = battle.get_unit(loot_actor)


	for index in range(unit.get("inventory", []).size() - 1, -1, -1):
		if battle._weapon_signature(unit.inventory[index]) == battle._weapon_signature(loot_item):
			battle.inventory.append(unit.inventory[index])
			unit.inventory.remove_at(index)
			break
	_close_chest_loot()

func _close_chest_loot() -> void:
	loot_overlay.hide()
	if loot_battle != battle: return
	loot_battle = null
	active_reward.clear()
	busy = false
	_after_noncombat()

func _build_undo() -> void:
	var modal:= _modal(760, 600)
	undo_overlay = modal[0]
	modal[1].add_child(_label("UNDO ACTIONS", 26, GOLD))
	modal[1].add_child(_label("Choose where to return. Your battle changes only after confirmation.", 17))
	undo_list = preload("res://ui/swipe_item_list.gd").new()
	undo_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	undo_list.add_theme_constant_override("line_separation", 14)
	undo_list.item_selected.connect(_preview_undo)
	modal[1].add_child(undo_list)
	undo_detail = _label("", 19)
	undo_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal[1].add_child(undo_detail)
	var row:= HBoxContainer.new()
	modal[1].add_child(row)
	_button(row, "Undo to here", _confirm_undo)
	_button(row, "Cancel", func(): _set_panel_visible(undo_overlay, false))

func _remember_action(snapshot: Dictionary, label: String) -> void:
	get_node("/root/Diagnostics").record("action", {"action": label, "chapter": chapter.get("id", ""), "turn": battle.turn, "phase": battle.phase, "unit": selected_id})
	if snapshot.get("chapter_id", "") != chapter.get("id", ""): return
	var actor: Dictionary = {}
	for unit in snapshot.state.get("units", []):
		if unit.id == snapshot.selection_ui.selected_id: actor = unit;break
	undo_history.append({"action": label, "label": "Turn %d · %s%s" % [int(snapshot.state.get("turn", 1)), str(actor.get("name", "")) + " · " if not actor.is_empty() else "", label], "snapshot": snapshot})
	if undo_history.size() > (16 if OS.has_feature("mobile") else 64): undo_history.pop_front()

func _open_undo() -> void:
	if deployment_overlay.visible: return
	if busy: return
	undo_history = undo_history.filter(_valid_undo_entry)
	_set_panel_visible(info_overlay, false)
	undo_list.clear()
	for index in range(undo_history.size() - 1, -1, -1):
		undo_list.add_item(str(undo_history[index].get("label", "Previous action")))
		undo_list.set_item_metadata(undo_list.item_count - 1, index)
	if not chapter_start.is_empty() and chapter_start.get("chapter", {}).get("id", "") == chapter.get("id", ""):
		undo_list.add_item("Beginning of this chapter")
		undo_list.set_item_metadata(undo_list.item_count - 1, -1)
	undo_detail.text = "There are no committed actions to undo yet."
	if undo_list.item_count > 0:
		undo_list.select(0)
		_preview_undo(0)
	_set_panel_visible(undo_overlay, true)
	move_child(undo_overlay, get_child_count() - 1)

func _preview_undo(index: int) -> void:
	var history_index:= int(undo_list.get_item_metadata(index))
	if history_index < 0:
		undo_detail.text = "Return to the beginning of %s with the army and items you brought into this chapter. Cancel keeps the current battle." % chapter.get("title", "this chapter")
		return
	var entry: Dictionary = undo_history[history_index]
	var snapshot: Dictionary = entry.get("snapshot", {})
	undo_detail.text = "Return to before %s in %s. Later actions will be removed. Cancel keeps the current battle." % [str(entry.get("label", "this action")), str(snapshot.get("state", {}).get("chapter", {}).get("title", chapter.get("title", "this chapter")))]
	if Rogue.active(battle): undo_detail.text += "\n%d Undo uses remaining." % Rogue.remaining(battle, "undo")

func _confirm_undo() -> void:
	var selected:= undo_list.get_selected_items()
	if selected.is_empty(): return
	var index:= int(undo_list.get_item_metadata(selected[0]))
	if index < 0:
		undo_overlay.hide()
		_restart_battle()
		return
	if index >= undo_history.size() or not _valid_undo_entry(undo_history[index]): return
	if Rogue.active(battle) and Rogue.remaining(battle, "undo") <= 0:
		undo_detail.text = "No Undo uses remain this chapter."
		return
	var rogue_costs:= {}
	if Rogue.active(battle): rogue_costs = {"undo_used": int(battle.chapter.rogue.get("undo_used", 0)) + 1, "arena_used": int(battle.chapter.rogue.get("arena_used", 0)), "training": int(battle.chapter.rogue.get("training", 0))}
	var entry: Dictionary = undo_history[index]
	var resume_enemy:= str(entry.get("action", "")) == "End turn" or str(entry.get("label", "")).ends_with("End turn")
	# Restore validates and copies the selected snapshot; compact tables remain shared.
	var snapshot: Dictionary = entry.get("snapshot", {})
	var before = battle
	_restore_game_data(snapshot)
	if battle != before:
		for key in rogue_costs:
			battle.chapter.rogue[key] = rogue_costs[key]
			if chapter_start.has("chapter"):
				chapter_start = chapter_start.duplicate(true)
				chapter_start.chapter.rogue[key] = rogue_costs[key]
		undo_history.resize(index)
		undo_overlay.hide()
		if Rogue.active(battle): _save_game()
		status_label.text = "Action undone."
		if resume_enemy: call_deferred("_end_turn")

func _action_snapshot() -> Dictionary:
	var data:= {"schema_version": 1, "pack_id": pack.id, "chapter_id": chapter.id, "state": battle.serialize(false), "outcome_presented": outcome_presented, "selection_ui": {"selected_id": selected_id, "pending_target": pending_target, "pending_weapon": pending_weapon, "command_menu_open": command_menu_open}, "dialogue_ui": {"visible": dialogue_overlay.visible, "speaker": dialogue_speaker.text, "text": dialogue_text.text, "portrait": dialogue_portrait_path, "remaining": dialogue_lines.duplicate(true)}}
	if pack.has("rom_sha256"): data.rom_sha256 = pack.rom_sha256
	data["dialogue_ui"]["scene"] = dialogue_view.capture_state()
	data["selection_ui"]["pending_assist"] = pending_assist.duplicate(true)
	data["story_ui"] = board.capture_story()
	if not pending_story_actions.is_empty(): data["story_ui"]["remaining"] = pending_story_actions.duplicate(true)
	data["initial_phase_pending"] = initial_phase_pending
	data["conversation_log"] = conversation_log.duplicate()
	data["active_reward"] = active_reward.duplicate(true)
	data["campaign"] = campaign.duplicate(true)
	data["transition_pending"] = transition_pending


	if not chapter_start.is_empty(): data["chapter_start"] = chapter_start
	return data

func _resume_story(actions: Array) -> void:
	var token:= dialogue_generation
	dialogue_transition = true
	dialogue_view.set_content_visible(false)
	if animations_enabled: await board.play_story(actions)
	else: board.apply_story(actions)
	if token != dialogue_generation: return
	dialogue_transition = false
	dialogue_view.set_content_visible(true)
	if str(dialogue_view.current.get("text", "")).is_empty(): _next_dialogue()

func _set_panel_visible(control: Control, showing: bool, edge: Vector2 = Vector2.ZERO) -> void:
	if not control: return
	panel_motion.configure(animations_enabled, 1.0)
	panel_motion.present(control, showing, edge)

func _speed_option(parent: Node, changed: Callable) -> OptionButton:
	var option:= OptionButton.new()
	for title in ["Normal · 1×", "Quick · 1.5×", "Fast · 2×", "Very fast · 3×"]: option.add_item(title)
	option.custom_minimum_size.y = 48
	option.item_selected.connect(func(index): changed.call([1.0, 1.5, 2.0, 3.0][index]))
	parent.add_child(option)
	return option

func _valid_speed(value: Variant) -> float:
	if not (value is float or value is int): return 1.0
	return float(value) if [1.0, 1.5, 2.0, 3.0].has(float(value)) else 1.0

func _apply_speed_preferences() -> void:
	board.movement_speed = movement_speed
	board.battle_speed = battle_speed
	if cutscene: cutscene.animation_time_scale = battle_speed
	if cutscene: cutscene.shake_strength = shake_strength
	if scene_transition: scene_transition.speed_multiplier = 1.0
	if dialogue_view:
		dialogue_view.transition_speed = 1.0
		dialogue_view.movement_speed = movement_speed
	for menu in [inventory_menu, trade_menu]:
		if menu:
			menu.transition_speed = 1.0
			menu.animations_enabled = animations_enabled

func _build_help() -> void:
	var modal:= _modal(740, 560)
	help_overlay = modal[0]
	modal[1].add_child(_label("HELP", 25, GOLD))
	modal[1].add_child(status_label)
	var text:= _rich(380)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = "[b]Move & act[/b]\nTap a unit to inspect it, then tap a blue tile to move. Tap the selected unit again for commands; double-tap it to Wait. An unreachable empty tile cancels a tentative move.\n\n[b]Battle[/b]\nHold an enemy to show every enemy's movement and attack ranges; select another unit to clear them. Tap an enemy to approach and preview combat. Hold a weapon choice to preview its forecast, slide between choices, and release on a weapon to attack with it. Slide outside the weapon list to cancel. Double-tap an enemy to show all enemy ranges. Double-tap an empty tile to open Info.\n\n[b]Items & allies[/b]\nDouble-tap an inventory item to use or equip it. Lords and adjacent allies can use Supply to store or take items. Supply and Trade leave your action available. Foot units stay on that tile; mounted units can use remaining movement. Rescue carries an adjacent ally; Drop places them beside the carrier. Use Door or Chest beside a lock with the appropriate key, or a lockpick. Wait on switches to activate them. Select a healer or performer, then tap an ally who needs healing or has acted to approach and preview an assist. Tap the ally again to Heal or Play. Play lets that ally act again. Promotion items can change an eligible unit's class once they reach the required level.\n\n[b]Camera & turns[/b]\nDrag to pan. Pinch or use the mouse wheel to zoom. Turns end automatically when everyone has acted; End turn in Info asks for confirmation if actions remain. Undo previews an earlier checkpoint in the current chapter before you confirm. Tap the terrain card to compare movement costs. The Info button sits beside the terrain card.\n\n[b]Dialogue[/b]\nTap to reveal text, then tap again to continue. The skip icon advances to the next scene or tutorial boundary. Settings includes tutorial skipping and separate movement/battle speeds."
	text.text += "\n\n[b]Rescue transfers & traps[/b]\nGive and Take pass a rescued ally between adjacent carriers with enough Aid. They leave your action available, so you can Take then Drop. Mounted units retain unused movement. To place a Mine or Light Rune, choose Use in Items, tap an adjacent highlighted tile, then Confirm. Mines stop movement and deal 10 damage; Light Runes block a tile for three turns. Canceling placement preserves the item. Undo can restore a Mine encounter."
	modal[1].add_child(text)
	_button(modal[1], "Back to Info", func(): _set_panel_visible(help_overlay, false);_open_info())

func _open_help() -> void:
	_set_panel_visible(info_overlay, false)
	_set_panel_visible(help_overlay, true)
	move_child(help_overlay, get_child_count() - 1)

func _recruitment_text() -> String:
	var candidates: Dictionary = {}
	var names: Dictionary = {}
	for character in support_manifest.get("characters", []):
		names[str(character.id)] = str(character.get("name", character.id))
	for unit in Army.all_units(battle): names[str(unit.id)] = str(unit.get("name", unit.id))
	for unit in chapter.get("units", []): names[str(unit.id)] = str(unit.get("name", unit.id))
	for event in chapter.get("events", []):
		for unit in NativeEvents.spawn_templates(event): names[str(unit.id)] = str(unit.get("name", unit.id))
	for talk in chapter.get("talks", []):
		for id in NativeEvents.recruitment_ids(talk):
			var actor:= str(talk.get("from", ""))
			if actor == id: actor = str(talk.get("to", ""))
			if not candidates.has(id): candidates[id] = []
			var label:= str(names.get(actor, actor)) if not actor.is_empty() else "Any"
			if not candidates[id].has(label): candidates[id].append(label)
	for event in chapter.get("events", []):
		if event.get("trigger", "") not in ["visit", "interact"]: continue
		var visitors: Dictionary = NativeEvents.recruitment_visitors(event)
		for id in visitors:
			if not candidates.has(id): candidates[id] = []
			for visitor in visitors[id]:
				var actor := str(event.get("unit_id",visitor))
				var label := str(names.get(actor,actor))+" (visit)" if not actor.is_empty() else "Any (visit)"
				if not candidates[id].has(label): candidates[id].append(label)
	var lines: Array[String] = []
	for id in candidates:
		var current: Dictionary = battle.get_unit(id)
		var status:= " · recruited" if current.get("faction", "") == "player" else (" · fallen" if not current.is_empty() and int(current.get("hp", 0)) <= 0 else "")
		lines.append("%s — %s%s" % [names.get(id, id), ", ".join(candidates[id]), status])
	return "RECRUITMENT\n" + "\n".join(lines) if not lines.is_empty() else ""

func _update_terrain(cell: Vector2i) -> void:
	if not battle or not terrain_panel or dialogue_overlay.visible or browsing or busy or terrain_overlay.visible: return
	if cell.x < 0 or cell.y < 0 or cell.x >= battle.width or cell.y >= battle.height: return
	terrain_cell = cell
	terrain_panel.present(battle.terrain_at(cell), cell)
	_position_terrain()
	_set_panel_visible(terrain_panel, true, Vector2.LEFT if terrain_panel.position.x < size.x * 0.5 else Vector2.RIGHT)

func _position_terrain() -> void:
	_position_info_button()
	if not terrain_panel or not board or terrain_cell.x < 0: return
	terrain_panel.size = terrain_panel.get_combined_minimum_size()
	var at: Vector2 = board.cell_screen_position(terrain_cell)
	var on_right:= at.x < size.x * 0.5
	var destination:= Vector2(size.x - terrain_panel.size.x if on_right else 0.0, size.y - terrain_panel.size.y)
	if forecast_panel.visible and Rect2(destination, terrain_panel.size).intersects(forecast_panel.get_rect()):
		destination.x = 0.0 if on_right else size.x - terrain_panel.size.x
	panel_motion.relocate(terrain_panel, destination)
	_position_info_button()

func _position_info_button() -> void:
	if not info_button: return
	var destination := size - Vector2(64, 64)
	if terrain_panel and terrain_panel.visible:
		var card := terrain_panel.get_rect()
		destination.x = card.position.x - info_button.size.x - 12 if card.get_center().x > size.x * 0.5 else card.end.x + 12
		# Very narrow windows keep the button above the card instead of overlapping.
		if destination.x < 0 or destination.x + info_button.size.x > size.x:
			destination.x = clampf(destination.x, 0, maxf(0, size.x - info_button.size.x))
			destination.y = maxf(0, card.position.y - info_button.size.y - 12)
	info_button.position = destination

func _build_terrain_costs() -> void:
	var modal:= _modal(560, 580)
	terrain_overlay = modal[0]
	terrain_heading = _label("TERRAIN", 25, GOLD)
	modal[1].add_child(terrain_heading)
	terrain_costs = _rich(280)
	terrain_costs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal[1].add_child(terrain_costs)
	_button(modal[1], "Close", func(): _set_panel_visible(terrain_overlay, false))

func _open_terrain_costs(cell: Vector2i) -> void:
	if busy or browsing or not battle or dialogue_overlay.visible: return
	var terrain: Dictionary = battle.terrain_at(cell)
	terrain_heading.text = str(terrain.get("name", "Terrain")).to_upper()
	var lines: Array[String] = ["[b]Movement points per tile[/b]"]
	var party: Array = battle.units.filter( func(unit): return unit.get("faction", "") == "player" and int(unit.get("hp", 0)) > 0)
	party.sort_custom( func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	for unit in party:
		var cost: int = battle.movement_cost(unit, cell)
		var value:= "%d" % cost if cost > 0 else "Cannot cross"
		var unit_name:= str(unit.get("name", "Unit"))
		if str(unit.id) == selected_id: unit_name = "[color=#f4d68d]" + unit_name + "[/color]"
		lines.append("%s · %s: [b]%s[/b]" % [unit_name, unit.get("class_name", "Unit"), value])
	terrain_costs.text = "\n\n".join(lines)
	_set_panel_visible(terrain_overlay, true)
	move_child(terrain_overlay, get_child_count() - 1)

func _weapon_pointer_input(event: InputEvent) -> bool:


	var active:= weapon_pointer_id != -1
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1:
		if active or Time.get_ticks_msec() - weapon_touch_msec < 500:
			get_viewport().set_input_as_handled()
			return true
		return false
	var blocked:= busy or dialogue_overlay.visible or (cutscene and cutscene.visible) or (scene_transition and scene_transition.visible)
	for modal in [terrain_overlay, info_overlay, settings_overlay, help_overlay, record_overlay, end_turn_overlay, backdrop_overlay, supports_overlay, supply_overlay, title_screen, items_overlay, trade_menu, details_overlay, shop_overlay, undo_overlay, library_overlay, choice_overlay]:
		if modal and modal.visible: blocked = true
	if blocked and active: weapon_pointer_canceled = true
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		if not active: return false
		if event is InputEventScreenDrag and event.index != weapon_pointer_id: return false
		if event is InputEventScreenDrag:
			var scroll_bar:= actions_scroll.get_v_scroll_bar()
			var scroll_rect:= actions_scroll.get_global_rect()
			var near_edge: bool = event.position.y < scroll_rect.position.y + 18 or event.position.y > scroll_rect.end.y - 18
			if scroll_bar.max_value > scroll_bar.page and near_edge and absf(event.position.y - weapon_pointer_origin.y) > 14:
				weapon_pointer_scrolling = true
			if weapon_pointer_scrolling:
				weapon_pointer_canceled = true
				actions_scroll.scroll_vertical = weapon_pointer_scroll + roundi(weapon_pointer_origin.y - event.position.y)
		if not weapon_buttons.get_global_rect().intersection(actions_scroll.get_global_rect()).has_point(event.position): weapon_pointer_canceled = true
		var hovered:= _weapon_choice_at(event.position)
		if hovered and not weapon_pointer_canceled:
			if is_instance_valid(weapon_pointer_button): weapon_pointer_button.set_pressed_no_signal(false)
			weapon_pointer_button = hovered
			hovered.set_pressed_no_signal(true)
			_preview_weapon(str(hovered.get_meta("weapon_key", "")))
		get_viewport().set_input_as_handled()
		return true
	var pointer:= -1
	if event is InputEventScreenTouch:
		pointer = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = -2
	else: return false
	if event.pressed:
		if active:
			weapon_pointer_canceled = true
			get_viewport().set_input_as_handled()
			return true
		if blocked or not actions_panel.visible: return false
		for button in weapon_buttons.get_children():
			var visible_rect: Rect2 = button.get_global_rect().intersection(actions_scroll.get_global_rect())
			if not button.is_visible_in_tree() or button.disabled or not visible_rect.has_point(event.position): continue
			weapon_pointer_button = button
			weapon_pointer_id = pointer
			weapon_pointer_origin = event.position
			weapon_pointer_scroll = actions_scroll.scroll_vertical
			weapon_pointer_scrolling = false
			weapon_pointer_rect = visible_rect
			weapon_pointer_bounds.clear()
			for choice in weapon_buttons.get_children():
				weapon_pointer_bounds[str(choice.get_meta("weapon_key", ""))] = choice.get_global_rect().intersection(actions_scroll.get_global_rect())
			weapon_pointer_key = str(button.get_meta("weapon_key", ""))
			weapon_pointer_battle = battle
			weapon_pointer_actor = selected_id
			weapon_pointer_target = pending_target
			weapon_pointer_canceled = false
			if pointer >= 0: weapon_touch_msec = Time.get_ticks_msec()
			button.set_pressed_no_signal(true)
			_preview_weapon(weapon_pointer_key)
			get_viewport().set_input_as_handled()
			return true
	elif active and weapon_pointer_id == pointer:
		var commit:= not blocked and not weapon_pointer_canceled
		commit = commit and weapon_pointer_battle == battle and weapon_pointer_actor == selected_id and weapon_pointer_target == pending_target and actions_panel.visible
		var released_choice:= _weapon_choice_at(event.position)
		var key:= str(released_choice.get_meta("weapon_key", "")) if released_choice else ""
		if released_choice and weapon_pointer_bounds.has(key):
			var current_rect: Rect2 = released_choice.get_global_rect().intersection(actions_scroll.get_global_rect())
			commit = commit and current_rect.is_equal_approx(weapon_pointer_bounds[key])
		else: commit = false
		if event is InputEventScreenTouch:
			weapon_touch_msec = Time.get_ticks_msec()
			if event.canceled: commit = false
		if is_instance_valid(weapon_pointer_button): weapon_pointer_button.set_pressed_no_signal(false)
		weapon_pointer_button = null
		weapon_pointer_id = -1
		weapon_pointer_battle = null
		weapon_pointer_bounds.clear()
		get_viewport().set_input_as_handled()
		if commit: _confirm_attack(key)
		return true
	return false

func _weapon_choice_at(point: Vector2) -> Button:
	if not actions_panel.visible: return null
	for button in weapon_buttons.get_children():
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().intersection(actions_scroll.get_global_rect()).has_point(point): return button
	return null

var staff_detail_target: String = ""

func _open_trap_destination() -> void:
	var item: Dictionary = _selected().inventory[selected_staff]
	choice_mode = "trap_destination"
	staff_detail_target = selected_id
	choice_ids.clear()
	_clear_staff_choices()
	items_overlay.hide()
	actions_panel.hide()
	board.staff_cells = battle.Traps.destinations(battle, _selected(), item)
	choice_heading.text = "%s · choose a tile" % item.name
	choice_list.add_child(_label("Select a highlighted adjacent tile." if not board.staff_cells.is_empty() else "No adjacent tile is available.", 18))
	board.set_ally_choices([], true)
	board.queue_redraw()
	_set_panel_visible(choice_overlay, true)
	move_child(choice_overlay, get_child_count() - 1)
	_position_choice_panel()

func _clear_staff_choices() -> void:
	for child in choice_list.get_children():
		choice_list.remove_child(child)
		child.queue_free()

func _open_staff_detail(target_id: String) -> void:
	var item: Dictionary = _selected().inventory[selected_staff]
	if item.get("staff_effect", "") not in ["torch", "unlock"] and not battle.helpful_targets(selected_id, selected_staff).has(target_id):
		items_overlay.hide()
		_open_choice("staff")
		return
	staff_detail_target = target_id
	choice_ids.clear()
	_clear_staff_choices()
	items_overlay.hide()
	actions_panel.hide()
	var target: Dictionary = battle.get_unit(target_id)
	if item.get("staff_effect", "") == "repair":
		choice_mode = "staff_repair"
		choice_heading.text = "Hammerne · choose an item"
		for entry in battle.Staff.repair_slots(battle, target):
			var slot:= int(entry.slot)
			_button(choice_list, "%s · %d/%d" % [entry.item.name, entry.item.uses, entry.item.max_uses], func(): _confirm_staff_repair(slot))
	else:
		choice_mode = "staff_destination"
		board.staff_cells = battle.Staff.destinations(battle, _selected(), item, target)
		choice_heading.text = "%s · choose a tile" % item.name
		choice_list.add_child(_label("Select a highlighted tile on the map.", 18))
	board.set_ally_choices([], true)
	board.queue_redraw()
	_set_panel_visible(choice_overlay, true)
	move_child(choice_overlay, get_child_count() - 1)
	_position_choice_panel()

func _choose_staff_destination(cell: Vector2i) -> void:
	if not board.staff_cells.has(cell): return
	_clear_staff_choices()
	choice_heading.text = "Confirm destination (%d, %d)" % [cell.x + 1, cell.y + 1]
	_button(choice_list, "Confirm", func():
		var id:= staff_detail_target
		_cancel_choice()
		await _use_inventory_item(selected_staff, id, cell))

func _confirm_staff_repair(slot: int) -> void:
	var id:= staff_detail_target
	_cancel_choice()
	await _use_inventory_item(selected_staff, id, Vector2i(-1, -1), slot)

func _play_phase_assist(action: Dictionary) -> void:
	if skip_enemy_animations: return
	if not _assist_has_other_target(str(action.unit_id), str(action.result.get("target_id", "")), action.get("item", {"type":"staff"})): return
	if not _show_battle_cutscenes(str(action.get("phase", battle.get_unit(str(action.unit_id)).get("faction", "")))): return
	await cutscene.play_assist(battle, str(action.unit_id), str(action.result.target_id), action.get("item", {"type": "staff", "name": action.result.get("item_name", "Staff")}), action.result)

func _assist_has_other_target(actor: String, target: String, item: Dictionary) -> bool:
	return not target.is_empty() and target != actor and not battle.get_unit(target).is_empty() and item.get("staff_effect", "") not in ["unlock", "torch"] and (item.get("type", "") == "staff" or item.has("ring_bonuses"))

func _show_character_art() -> void:
	var unit: Dictionary = battle.get_unit(details_unit_id)
	var overlay:= ColorRect.new()
	overlay.color = Color("080d18")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var portrait:= preload("res://ui/unit_portrait.gd").new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(portrait)
	portrait.present(unit)
	var full_art:= preload("res://runtime/custom_portraits.gd")
	var context:= unit.duplicate(true)
	context.portrait_id = str(unit.get("portrait", "")).get_file().get_basename().to_int()
	var entry: Dictionary = full_art.find_portrait(str(unit.get("name", "")), context)
	if not entry.is_empty():
		portrait.custom_texture = full_art.texture(entry)
		portrait.custom = {"scale_percent": 100, "x_percent": 0, "y_percent": 0}
		portrait.texture = null
		portrait.queue_redraw()
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var image_rect: Rect2 = portrait.custom_rect()
			if portrait.custom_texture == null and portrait.texture:
				var dimensions: Vector2 = portrait.texture.get_size()
				var fitted:= dimensions * minf(portrait.size.x / dimensions.x, portrait.size.y / dimensions.y)
				image_rect = Rect2((portrait.size - fitted) / 2, fitted)
			if not image_rect.has_point(event.position): overlay.queue_free())
	var close:= Button.new()
	close.text = "Close"
	close.position = Vector2(20, 20)
	close.custom_minimum_size = Vector2(110, 48)
	close.pressed.connect(overlay.queue_free)
	overlay.add_child(close)

func _open_music_library() -> void:
	if not audio_manager: return
	if not music_library_active:
		library_previous_music = audio_manager.current_music
		music_library_active = true
	music_library.clear()
	var entries: Array = []
	var seen:= {}
	for key in audio_manager.manifest.get("music", {}):
		var entry: Dictionary = audio_manager.manifest.music[key]
		var id:= int(entry.get("song_id", -1))
		if seen.has(id) or entry.get("silent", false) or id == 0: continue
		seen[id] = true
		entries.append({"key": key, "id": id, "title": str(entry.get("title", key))})
	entries.sort_custom( func(a, b): return a.id < b.id)
	for entry in entries:
		music_library.add_item("%03X · %s" % [entry.id, entry.title])
		music_library.set_item_metadata(music_library.item_count - 1, entry.key)

func _restore_library_music() -> void:
	if not music_library_active: return
	music_library_active = false
	if audio_manager:
		if library_previous_music.is_empty(): audio_manager.stop_music()
		else: audio_manager.play_music(library_previous_music)

func _open_custom() -> void:
	if not custom_overlay:
		var modal := _modal(620, 350)
		custom_overlay = modal[0]
		custom_overlay.visibility_changed.connect(_sync_settings_scroll)
		modal[1].add_child(_label("CUSTOM",25,GOLD))
		_button(modal[1], "Custom art", _import_portraits)
		_button(modal[1], "Custom voices", _open_voice_options)
		_button(modal[1], "Custom translations", _open_translations)
		_button(modal[1], "Back to Settings", func(): custom_overlay.hide())
	custom_overlay.show()
	move_child(custom_overlay,get_child_count()-1)

func _open_translations() -> void:
	if not translations_overlay:
		var modal := _modal(740, 730)
		translations_overlay = modal[0]
		translations_overlay.visibility_changed.connect(_sync_settings_scroll)
		modal[1].add_child(_label("CUSTOM TRANSLATIONS",25,GOLD))
		var scroll := preload("res://ui/swipe_scroll.gd").new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		modal[1].add_child(scroll)
		translations_panel = preload("res://ui/translations_panel.gd").new()
		translations_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(translations_panel)
		_button(modal[1], "Back to Custom", func(): translations_overlay.hide())
	translations_panel.reload()
	translations_overlay.show()
	move_child(translations_overlay,get_child_count()-1)

func _open_voice_options() -> void:
	if not voice_overlay:
		var modal:= _modal(620, 470)
		voice_overlay = modal[0]
		voice_overlay.visibility_changed.connect(_sync_settings_scroll)
		modal[1].add_child(_label("CUSTOM VOICES", 25, GOLD))
		var enabled:= CheckButton.new()
		enabled.text = "Play character voices"
		enabled.button_pressed = voice_player.store.enabled
		enabled.toggled.connect(func(value): voice_player.store.enabled = value;voice_player.store.save_preferences();voice_player.update_volume())
		modal[1].add_child(enabled)
		modal[1].add_child(_label("Voice volume", 18))
		var volume:= HSlider.new()
		volume.min_value = 0;volume.max_value = 100;volume.step = 1
		volume.value = voice_player.store.volume * 100
		volume.custom_minimum_size.y = 40
		volume.value_changed.connect(func(value): voice_player.store.volume = value / 100.0;voice_player.store.save_preferences();voice_player.update_volume())
		modal[1].add_child(volume)
		voice_import_button = _button(modal[1], "Import voice ZIP", _choose_voice_zip)
		voice_delete_prompt = ConfirmationDialog.new()
		voice_delete_prompt.title = "Delete all imported voices?"
		voice_delete_prompt.dialog_text = "Delete all imported voices for both games, including inactive packs? Your source ZIP files will be kept."
		voice_delete_prompt.ok_button_text = "Delete all voices"
		voice_delete_prompt.confirmed.connect(_delete_imported_voices)
		voice_overlay.add_child(voice_delete_prompt)
		voice_clear_button = _button(modal[1], "Delete all imported voices", func(): voice_delete_prompt.popup_centered())
		voice_status = _label("Import a ZIP of .ogg, .wav, or .mp3 clips with voices.json. Listen in Library → Character voices.", 17)
		voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		voice_status.max_lines_visible = 5
		voice_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		modal[1].add_child(voice_status)
		_button(modal[1], "Back to Custom", func(): voice_overlay.hide())
	_update_voice_storage_label()
	voice_overlay.show()
	move_child(voice_overlay, get_child_count() - 1)

func _update_voice_storage_label() -> void:
	if not voice_clear_button or (voice_import_worker and voice_import_worker.is_started()): return
	var bytes := 0
	for game in ["fe6", "fe7"]:
		var store = preload("res://runtime/voice_store.gd").new(game)
		bytes += preload("res://runtime/import_storage.gd").pack_bytes(store.root)
	voice_clear_button.text = "Delete all imported voices (%s)…" % preload("res://runtime/import_storage.gd").label(bytes)
	voice_clear_button.disabled = bytes == 0

func _delete_imported_voices() -> void:
	if voice_import_worker and voice_import_worker.is_started(): return
	var enabled: bool = voice_player.store.enabled
	var volume: float = voice_player.store.volume
	voice_player.stop()
	voice_player.store.cache.clear()
	var failed := false
	for game in ["fe6", "fe7"]:
		var store = preload("res://runtime/voice_store.gd").new(game)
		if store.delete_all() != OK: failed = true
	voice_player.store.reload()
	voice_player.store.enabled = enabled
	voice_player.store.volume = volume
	voice_player.store.save_preferences()
	if voice_library: voice_library.configure(voice_player)
	_update_voice_storage_label()
	voice_status.text = "Some voice files could not be deleted. Please try again." if failed else "All imported voices deleted for both games. Source ZIP files were kept."

func _choose_voice_zip() -> void:
	if voice_import_worker and voice_import_worker.is_started(): return
	var picker:= FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.zip ; Custom voice pack"])
	picker.use_native_dialog = true
	add_child(picker)
	picker.file_selected.connect(func(path): picker.queue_free();_import_voice_file(path))
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.8)

func _import_voice_file(path: String) -> void:
	if voice_import_worker and voice_import_worker.is_started(): return
	voice_import_button.disabled = true
	voice_clear_button.disabled = true
	voice_status.text = "Importing voices…"
	voice_player.stop()
	voice_import_worker = Thread.new()

	var importer = preload("res://runtime/voice_store.gd").new(voice_player.store.game_id)
	if voice_import_worker.start( func(): return importer.import_pack(path)) != OK:
		voice_status.text = "Cannot start voice import."
		voice_import_button.disabled = false
		voice_clear_button.disabled = false
		return
	while voice_import_worker.is_alive(): await get_tree().process_frame
	var failure: String = voice_import_worker.wait_to_finish()
	voice_import_button.disabled = false
	voice_clear_button.disabled = false
	if failure.is_empty():
		voice_player.store.reload()
		voice_status.text = importer.report.summary("voice clips in %d sets" % voice_player.store.entries.size())
	else: voice_status.text = failure
	voice_status.tooltip_text = voice_status.text
	_update_voice_storage_label()
	get_node("/root/Diagnostics").record("voice_import", {"ok":failure.is_empty(),"error":failure,"skipped":importer.report.warnings})
