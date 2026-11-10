extends RefCounted
const INK := Color("dae4e5")
const GOLD := Color("e5c78e")
static func create() -> Theme:
	var ui_theme:= Theme.new()
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("default_color", "RichTextLabel", INK)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style:= StyleBoxFlat.new()
		style.bg_color = Color("343d92")
		style.border_color = Color("cbbd87")
		if state == "hover" or state == "focus":
			style.bg_color = Color("4b5ab3")
			style.border_color = GOLD
		elif state == "pressed":
			style.bg_color = Color("232e72")
		elif state == "disabled":
			style.bg_color = Color("162932")
			style.border_color = Color("263c44")
		style.set_border_width_all(2)
		style.set_corner_radius_all(2)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		ui_theme.set_stylebox(state, "Button", style)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_disabled_color", "Button", Color("607681"))
	ui_theme.set_constant("separation", "VBoxContainer", 10)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	ui_theme.set_constant("scrollbar_h_separation", "ScrollContainer", 18)
	ui_theme.set_constant("scrollbar_h_separation", "ItemList", 18)
	var scroll_style:= StyleBoxFlat.new()
	scroll_style.bg_color = Color("172747")
	scroll_style.content_margin_left = 10
	scroll_style.content_margin_right = 10
	ui_theme.set_stylebox("scroll", "VScrollBar", scroll_style)
	return ui_theme

