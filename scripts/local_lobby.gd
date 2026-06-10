# Couch lobby: each pad joins with A, keyboard+mouse joins with click
# or Enter. Join order is slot order (P1 orange, P2 cyan, ...). Start
# fires with two or more players in.
extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)
const COLORS: Array = preload("res://scripts/player.gd").COLORS

var roster: Array = []  # PlayerInput device ids in join order

var _cards: Array[Label] = []
var _start_label: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title := Label.new()
	title.text = "LOCAL VERSUS"
	var tf := FontVariation.new()
	tf.base_font = ThemeDB.fallback_font
	tf.set_spacing(TextServer.SPACING_GLYPH, 12)
	tf.variation_embolden = 0.9
	title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "pads press Ⓐ to join — keyboard joins with click or Enter"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 24)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards)
	for i in 4:
		cards.add_child(_build_card(i))

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer2)

	_start_label = Label.new()
	_start_label.add_theme_font_size_override("font_size", 22)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_start_label)

	var hints := Label.new()
	hints.text = "Start / Enter — fight    ·    Ⓑ / Esc — leave"
	hints.add_theme_font_size_override("font_size", 15)
	hints.add_theme_color_override("font_color", TEXT_DIM)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hints)

	_refresh()


func _build_card(i: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.07, 0.09, 0.92)
	style.border_color = Color(0.23, 0.22, 0.27)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 30.0
	style.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(220, 150)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	var pnum := Label.new()
	pnum.text = "P%d" % (i + 1)
	pnum.add_theme_font_size_override("font_size", 30)
	pnum.add_theme_color_override("font_color", COLORS[i])
	pnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pnum)

	var who := Label.new()
	who.add_theme_font_size_override("font_size", 16)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(who)
	_cards.append(who)
	return panel


func _refresh() -> void:
	for i in 4:
		if i < roster.size():
			_cards[i].text = "KEYBOARD + MOUSE" if roster[i] == -1 else "GAMEPAD %d" % (roster[i] + 1)
			_cards[i].add_theme_color_override("font_color", TEXT_BRIGHT)
		else:
			_cards[i].text = "press Ⓐ to join"
			_cards[i].add_theme_color_override("font_color", TEXT_DIM)
	if roster.size() >= 2:
		_start_label.text = "%d players in — press Start / Enter" % roster.size()
		_start_label.add_theme_color_override("font_color", ACCENT)
	else:
		_start_label.text = "waiting for at least 2 players…"
		_start_label.add_theme_color_override("font_color", TEXT_DIM)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				_join(event.device)
			JOY_BUTTON_B:
				_drop(event.device)
			JOY_BUTTON_START:
				_try_start()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_join(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if roster.has(-1):
					_try_start()
				else:
					_join(-1)
			KEY_ESCAPE:
				if roster.has(-1):
					_drop(-1)
				else:
					get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _join(device: int) -> void:
	if roster.has(device) or roster.size() >= 4:
		return
	roster.append(device)
	_refresh()


func _drop(device: int) -> void:
	if roster.has(device):
		roster.erase(device)
		_refresh()


func _try_start() -> void:
	if roster.size() >= 2:
		Net.start_local(roster)
