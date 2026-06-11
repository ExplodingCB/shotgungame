# Couch lobby: a full-screen board that slams up over whatever is on
# screen, Smash-select style. Each pad joins with A, keyboard+mouse
# joins with click or Enter; your ship rides up into your column,
# huge, and repaints live as you cycle colors with d-pad left/right
# (arrow keys for KB+M). Colors stay unique across joined players.
# Start fires with two or more players in.
extends Control

# Fired when the player backs out; the menu restores its rail. With no
# listener (the scene ran standalone) closing falls back to a scene
# change.
signal closed

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)
const COLORS: Array = preload("res://scripts/player.gd").COLORS
const TITLE_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

var roster: Array = []  # PlayerInput device ids in join order
var picks: Array = []  # color index per roster entry

var _cols: Array[Dictionary] = []  # per slot: {panel, pnum, dev, area, ship, join_hint, color_hint}
var _board: Control
var _dim: ColorRect
var _start_label: Label
var _start_icon: TextureRect
var _start_sep: Label
var _start_key: Label
var _pulse: Tween
var _closing := false


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_board)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 42)
	_board.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := Label.new()
	title.text = "SHOWDOWN"
	var tf := FontVariation.new()
	tf.base_font = TITLE_FONT
	tf.set_spacing(TextServer.SPACING_GLYPH, 12)
	title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.15, 0.0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := HBoxContainer.new()
	subtitle.alignment = BoxContainer.ALIGNMENT_CENTER
	subtitle.add_theme_constant_override("separation", 8)
	subtitle.add_child(ButtonIcons.icon("a", 30.0))
	subtitle.add_child(_dim_label("pad joins      ·      "))
	subtitle.add_child(ButtonIcons.keycap("Click"))
	subtitle.add_child(_dim_label("/"))
	subtitle.add_child(ButtonIcons.keycap("Enter"))
	subtitle.add_child(_dim_label("keyboard joins"))
	box.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	for i in 4:
		columns.add_child(_build_column(i))

	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	start_row.add_theme_constant_override("separation", 10)
	_start_label = Label.new()
	_start_label.add_theme_font_override("font", TITLE_FONT)
	_start_label.add_theme_font_size_override("font_size", 26)
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_row.add_child(_start_label)
	_start_icon = ButtonIcons.icon("start", 36.0)
	start_row.add_child(_start_icon)
	_start_sep = _dim_label("/")
	start_row.add_child(_start_sep)
	_start_key = ButtonIcons.keycap("Enter")
	start_row.add_child(_start_key)
	box.add_child(start_row)

	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 8)
	hints.add_child(_dim_label("◂ ▸"))
	hints.add_child(_dim_label("color      ·      "))
	hints.add_child(ButtonIcons.icon("b", 28.0))
	hints.add_child(ButtonIcons.keycap("Esc"))
	hints.add_child(_dim_label("leave"))
	box.add_child(hints)

	_refresh()

	# The board slams up from below the screen, dimming what it covers.
	var vs := get_viewport_rect().size
	_board.position.y = vs.y
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.5, 0.3)
	tw.parallel().tween_property(_board, "position:y", 0.0, 0.5) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _build_column(i: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var pnum := Label.new()
	pnum.text = "P%d" % (i + 1)
	pnum.add_theme_font_override("font", TITLE_FONT)
	pnum.add_theme_font_size_override("font_size", 46)
	pnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pnum)

	var dev := Label.new()
	dev.add_theme_font_size_override("font_size", 15)
	dev.add_theme_color_override("font_color", TEXT_DIM)
	dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev.custom_minimum_size = Vector2(0, 22)
	v.add_child(dev)

	# The ship rides in this area; clipped so it can slide in from
	# below the column without painting over the bottom bar.
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	v.add_child(area)

	var ship := ShipPortrait.new()
	ship.visible = false
	area.add_child(ship)

	# "press A to join", centered in the empty column.
	var join_hint := VBoxContainer.new()
	join_hint.set_anchors_preset(Control.PRESET_CENTER)
	join_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	join_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	join_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	join_hint.add_theme_constant_override("separation", 10)
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(ButtonIcons.icon("a", 38.0))
	join_hint.add_child(icon_wrap)
	var join_lbl := Label.new()
	join_lbl.text = "to join"
	join_lbl.add_theme_font_size_override("font_size", 16)
	join_lbl.add_theme_color_override("font_color", TEXT_DIM)
	join_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_hint.add_child(join_lbl)
	area.add_child(join_hint)

	var color_hint := Label.new()
	color_hint.text = "◂          ▸"
	color_hint.add_theme_font_size_override("font_size", 22)
	color_hint.add_theme_color_override("font_color", TEXT_DIM)
	color_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(color_hint)

	area.resized.connect(func(): _rest_ship(i))

	_cols.append({"panel": panel, "pnum": pnum, "dev": dev, "area": area,
			"ship": ship, "join_hint": join_hint, "color_hint": color_hint})
	return panel


func _rest_ship(i: int) -> void:
	var area: Control = _cols[i]["area"]
	var ship: Node2D = _cols[i]["ship"]
	ship.position = area.size / 2.0


func _col_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.07, 0.09, 0.6)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 22.0
	sb.content_margin_bottom = 18.0
	return sb


func _refresh() -> void:
	for i in 4:
		var c := _cols[i]
		var joined: bool = i < roster.size()
		var pnum: Label = c["pnum"]
		var dev: Label = c["dev"]
		var ship: ShipPortrait = c["ship"]
		(c["join_hint"] as Control).visible = not joined
		(c["color_hint"] as Control).visible = joined
		if joined:
			var color: Color = COLORS[picks[i]]
			(c["panel"] as PanelContainer).add_theme_stylebox_override(
					"panel", _col_style(Color(color.r, color.g, color.b, 0.85)))
			pnum.add_theme_color_override("font_color", color)
			dev.text = "KEYBOARD + MOUSE" if roster[i] == -1 else "GAMEPAD %d" % (roster[i] + 1)
			ship.visible = true
			ship.color = color
		else:
			(c["panel"] as PanelContainer).add_theme_stylebox_override(
					"panel", _col_style(Color(0.23, 0.22, 0.27)))
			pnum.add_theme_color_override("font_color", Color(0.35, 0.34, 0.4))
			dev.text = ""
			ship.visible = false
	var can_start := roster.size() >= 2
	_start_icon.visible = can_start
	_start_sep.visible = can_start
	_start_key.visible = can_start
	if can_start:
		_start_label.text = "%d PLAYERS IN — PRESS" % roster.size()
		_start_label.add_theme_color_override("font_color", ACCENT)
		if _pulse == null:
			_pulse = create_tween().set_loops()
			_pulse.tween_property(_start_label, "modulate:a", 0.45, 0.55) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_pulse.tween_property(_start_label, "modulate:a", 1.0, 0.55) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_start_label.text = "waiting for at least 2 players…"
		_start_label.add_theme_color_override("font_color", TEXT_DIM)
		if _pulse != null:
			_pulse.kill()
			_pulse = null
			_start_label.modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				_join(event.device)
			JOY_BUTTON_B:
				if roster.has(event.device):
					_drop(event.device)
				else:
					_close()
			JOY_BUTTON_START:
				_try_start()
			JOY_BUTTON_DPAD_LEFT:
				_cycle_color(event.device, -1)
			JOY_BUTTON_DPAD_RIGHT:
				_cycle_color(event.device, 1)
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
			KEY_LEFT:
				_cycle_color(-1, -1)
			KEY_RIGHT:
				_cycle_color(-1, 1)
			KEY_ESCAPE:
				if roster.has(-1):
					_drop(-1)
				else:
					_close()


func _join(device: int) -> void:
	if roster.has(device) or roster.size() >= 4:
		return
	roster.append(device)
	picks.append(_free_color(roster.size() - 1))
	_refresh()
	_animate_join(roster.size() - 1)


# Your ship rides up into the column from below, with a landing thud.
func _animate_join(i: int) -> void:
	var area: Control = _cols[i]["area"]
	var ship: Node2D = _cols[i]["ship"]
	var rest := area.size / 2.0
	ship.position = rest + Vector2(0, area.size.y)
	ship.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(ship, "position", rest, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ship, "rotation", 0.0, 0.45).from(-0.35)
	var shake := create_tween()
	shake.tween_interval(0.3)
	for off in [Vector2(0, 7), Vector2(0, -4), Vector2(0, 2), Vector2.ZERO]:
		shake.tween_property(_board, "position", off, 0.05)


func _drop(device: int) -> void:
	var idx := roster.find(device)
	if idx != -1:
		roster.remove_at(idx)
		picks.remove_at(idx)
		_refresh()
		for i in roster.size():
			_rest_ship(i)


# Your slot's classic color when nobody wears it, else the first free.
func _free_color(slot: int) -> int:
	if not picks.has(slot % COLORS.size()):
		return slot % COLORS.size()
	for i in COLORS.size():
		if not picks.has(i):
			return i
	return slot % COLORS.size()


func _cycle_color(device: int, dir: int) -> void:
	var idx := roster.find(device)
	if idx == -1:
		return
	var c: int = picks[idx]
	for _step in COLORS.size():
		c = wrapi(c + dir, 0, COLORS.size())
		if not picks.has(c):
			break
	picks[idx] = c
	_refresh()
	# Repaint punch: the ship pops as the new color lands.
	var ship: Node2D = _cols[idx]["ship"]
	var tw := create_tween()
	tw.tween_property(ship, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 1.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _try_start() -> void:
	if roster.size() >= 2:
		Net.start_local(roster, picks)


# Slide the board back out, then hand control to whoever opened us.
func _close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(_board, "position:y", get_viewport_rect().size.y, 0.35) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_dim, "color:a", 0.0, 0.35)
	tw.tween_callback(func():
		if closed.get_connections().is_empty():
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		else:
			closed.emit())


# A blown-up replica of the in-game ship: the player scene's radial-
# gradient body and hull spots, redrawn at portrait size, with the
# pistol on the hip (short enough to stay inside the column).
class ShipPortrait extends Node2D:
	const GUN := preload("res://assets/guns-assetpack/Handguns/M1911.png")
	const R := 105.0  # body radius; in-game it's 22

	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _init() -> void:
		var gun := Sprite2D.new()
		gun.texture = GUN
		gun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gun.scale = Vector2.ONE * (R / 22.0) * 1.1  # the pistol's in-game sprite_scale
		gun.position = Vector2(16, 0) * (R / 22.0)
		add_child(gun)

	func _draw() -> void:
		# Soft halo, then the body gradient from the player scene
		# (white core falling to grey rim), tinted like body_sprite.
		draw_circle(Vector2.ZERO, R * 1.16, Color(color.r, color.g, color.b, 0.14))
		for step in [[1.0, 0.52], [0.92, 0.66], [0.8, 0.78], [0.55, 0.92], [0.3, 1.0]]:
			draw_circle(Vector2.ZERO, R * step[0],
					Color(color.r * step[1], color.g * step[1], color.b * step[1]))
		# Hull spots, matching the Body's two darker dots.
		draw_circle(Vector2(R * 0.46, -R * 0.25), R * 0.17, Color(0, 0, 0, 0.3))
		draw_circle(Vector2(-R * 0.21, R * 0.5), R * 0.12, Color(0, 0, 0, 0.3))
