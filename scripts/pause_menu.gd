# In-match pause: Esc or Start toggles it (Start defers to the warm-up
# lobby, where it begins the match instead). Fully pad-navigable —
# d-pad moves focus, A activates, B or Start backs out. Solo play
# freezes the tree; versus keeps running underneath.
extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)
const TITLE_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

var _panel: PanelContainer
var _resume_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.045, 0.07, 0.97)
	ps.border_color = Color(1.0, 0.62, 0.1, 0.35)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(20)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 30
	ps.content_margin_left = 52.0
	ps.content_margin_right = 52.0
	ps.content_margin_top = 34.0
	ps.content_margin_bottom = 30.0
	_panel.add_theme_stylebox_override("panel", ps)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	var tf := FontVariation.new()
	tf.base_font = TITLE_FONT
	tf.set_spacing(TextServer.SPACING_GLYPH, 10)
	title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_spacer(10))
	box.add_child(_volume_row("MUSIC", Net.music_volume, func(v): Net.set_music_volume(v)))
	box.add_child(_volume_row("SFX", Net.sfx_volume, func(v): Net.set_sfx_volume(v)))

	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = Net.fullscreen
	fullscreen.add_theme_font_size_override("font_size", 17)
	fullscreen.add_theme_color_override("font_color", TEXT_BRIGHT)
	fullscreen.add_theme_color_override("font_hover_color", ACCENT)
	fullscreen.add_theme_color_override("font_focus_color", ACCENT)
	fullscreen.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	fullscreen.toggled.connect(func(on): Net.set_fullscreen(on))
	box.add_child(fullscreen)

	box.add_child(_spacer(12))

	_resume_btn = _menu_item(box, "Resume", _close)
	_menu_item(box, "Main Menu", func(): Net.leave())

	box.add_child(_spacer(8))
	var hint := Label.new()
	hint.text = "B / Esc  ·  resume"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


# Toggle handling lives in _input so it works regardless of where GUI
# focus sits while the menu is up.
func _input(event: InputEvent) -> void:
	var toggle := false
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		toggle = true
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			# In a versus warm-up, Start belongs to "begin the match".
			toggle = visible or not _lobby_waiting()
		elif event.button_index == JOY_BUTTON_B and visible:
			toggle = true
	if toggle:
		_close() if visible else _open()
		get_viewport().set_input_as_handled()


func _lobby_waiting() -> bool:
	var main := Arena.of(self)
	var rm: Node = main.round_manager if main != null and "round_manager" in main else null
	return rm != null and int(rm.phase) == RoundManager.Phase.LOBBY


func _open() -> void:
	visible = true
	Net.ui_open = true
	if Net.mode == Net.Mode.SOLO:
		get_tree().paused = true
	_resume_btn.grab_focus()
	# Quick pop so opening feels deliberate, not like a glitch.
	_panel.pivot_offset = _panel.size / 2.0
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16) \
			.from(Vector2.ONE * 0.92).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	visible = false
	Net.ui_open = false
	get_tree().paused = false


func _volume_row(label_text: String, initial: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(250, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var pct := Label.new()
	pct.text = "%d%%" % roundi(initial * 100.0)
	pct.custom_minimum_size = Vector2(52, 0)
	pct.add_theme_font_size_override("font_size", 15)
	pct.add_theme_color_override("font_color", TEXT_DIM)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)

	slider.value_changed.connect(func(v: float):
		pct.text = "%d%%" % roundi(v * 100.0)
		on_change.call(v)
	)
	return row


# Rail-style text item: clean text with a ▸ marker on hover/focus,
# matching the main menu.
func _menu_item(parent: Container, label_text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_override("font", TITLE_FONT)
	btn.add_theme_font_size_override("font_size", 21)
	btn.add_theme_color_override("font_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	btn.add_theme_color_override("font_focus_color", ACCENT)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.75, 0.35))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 30.0
	empty.content_margin_top = 6.0
	empty.content_margin_bottom = 6.0
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.pressed.connect(on_pressed)
	parent.add_child(btn)

	var marker := Label.new()
	marker.text = "▸"
	marker.add_theme_font_size_override("font_size", 20)
	marker.add_theme_color_override("font_color", ACCENT)
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	marker.offset_left = 2.0
	marker.offset_right = 24.0
	marker.modulate.a = 0.0
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(marker)
	var show_marker := func(on: bool): marker.modulate.a = 1.0 if on else 0.0
	btn.mouse_entered.connect(func(): show_marker.call(true))
	btn.mouse_exited.connect(func(): show_marker.call(btn.has_focus()))
	btn.focus_entered.connect(func(): show_marker.call(true))
	btn.focus_exited.connect(func(): show_marker.call(false))
	return btn


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
