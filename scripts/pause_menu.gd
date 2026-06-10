extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.065, 0.09, 0.97)
	ps.border_color = Color(0.25, 0.24, 0.3)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(14)
	ps.content_margin_left = 36.0
	ps.content_margin_right = 36.0
	ps.content_margin_top = 28.0
	ps.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	var tf := FontVariation.new()
	tf.base_font = ThemeDB.fallback_font
	tf.set_spacing(TextServer.SPACING_GLYPH, 10)
	tf.variation_embolden = 0.7
	title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_spacer(8))
	box.add_child(_volume_row("Music", Net.music_volume, func(v): Net.set_music_volume(v)))
	box.add_child(_volume_row("SFX", Net.sfx_volume, func(v): Net.set_sfx_volume(v)))
	box.add_child(_spacer(12))

	box.add_child(_button("Resume", _close))
	box.add_child(_button("Main Menu", func(): Net.leave()))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	Net.ui_open = true
	if Net.mode == Net.Mode.SOLO:
		get_tree().paused = true


func _close() -> void:
	visible = false
	Net.ui_open = false
	get_tree().paused = false


func _volume_row(label_text: String, initial: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(240, 24)
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


func _button(label_text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _btn_style(Color(0.1, 0.095, 0.125, 0.95), Color(0.25, 0.24, 0.3)))
	btn.add_theme_stylebox_override("hover", _btn_style(Color(0.13, 0.12, 0.16, 0.95), Color(1, 0.62, 0.1, 0.55)))
	btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.07, 0.065, 0.09, 0.95), Color(1, 0.62, 0.1, 0.8)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(on_pressed)
	return btn


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
