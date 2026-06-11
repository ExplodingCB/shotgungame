# Couch lobby: a big board that slides up over whatever is on screen
# (the menu keeps its demo brawl running behind it). Each pad joins
# with A, keyboard+mouse joins with click or Enter. Join order is slot
# order. Once in, d-pad left/right (or arrow keys for KB+M) picks your
# ship color — colors stay unique across joined players. Start fires
# with two or more players in.
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

var _cards: Array[Dictionary] = []  # per slot: {panel, icon, label, pnum, swatch, cycle}
var _start_label: Label
var _start_icon: TextureRect
var _start_sep: Label
var _start_key: Label
var _dim: ColorRect
var _panel: PanelContainer
var _home_y := 0.0
var _closing := false


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.07, 0.97)
	style.border_color = ACCENT
	style.set_border_width_all(3)
	style.set_corner_radius_all(26)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 42
	style.content_margin_left = 64.0
	style.content_margin_right = 64.0
	style.content_margin_top = 42.0
	style.content_margin_bottom = 38.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "LOCAL VERSUS"
	var tf := FontVariation.new()
	tf.base_font = TITLE_FONT
	tf.set_spacing(TextServer.SPACING_GLYPH, 10)
	title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 62)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.15, 0.0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 4)
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

	var start_row := HBoxContainer.new()
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	start_row.add_theme_constant_override("separation", 10)
	_start_label = Label.new()
	_start_label.add_theme_font_size_override("font_size", 22)
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_row.add_child(_start_label)
	_start_icon = ButtonIcons.icon("start", 34.0)
	start_row.add_child(_start_icon)
	_start_sep = _dim_label("/")
	start_row.add_child(_start_sep)
	_start_key = ButtonIcons.keycap("Enter")
	start_row.add_child(_start_key)
	box.add_child(start_row)

	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 8)
	hints.add_child(ButtonIcons.icon("start", 28.0))
	hints.add_child(ButtonIcons.keycap("Enter"))
	hints.add_child(_dim_label("fight      ·      "))
	hints.add_child(_dim_label("◂ ▸"))
	hints.add_child(_dim_label("color      ·      "))
	hints.add_child(ButtonIcons.icon("b", 28.0))
	hints.add_child(ButtonIcons.keycap("Esc"))
	hints.add_child(_dim_label("leave"))
	box.add_child(hints)

	_refresh()

	# Let the panel size itself, then make the entrance: board slides
	# up from below the screen, player cards pop in left to right.
	await get_tree().process_frame
	var vs := get_viewport_rect().size
	_panel.position = (vs - _panel.size) / 2.0
	_home_y = _panel.position.y
	_panel.position.y = vs.y + 80.0
	var tw := create_tween()
	tw.tween_property(_dim, "color:a", 0.55, 0.3)
	tw.parallel().tween_property(_panel, "position:y", _home_y, 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _cards.size():
		var card: Control = _cards[i]["panel"]
		card.pivot_offset = card.size / 2.0
		card.scale = Vector2.ZERO
		var ct := create_tween()
		ct.tween_interval(0.42 + i * 0.1)
		ct.tween_property(card, "scale", Vector2.ONE, 0.32) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


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

	# "press A to join" with the real button sprite; swaps to the
	# device name once someone claims the slot.
	var who := HBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 7)
	var icon := ButtonIcons.icon("a", 26.0)
	who.add_child(icon)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	who.add_child(lbl)
	v.add_child(who)

	# Ship color: ◂ swatch ▸, shown once the slot is claimed.
	var cycle := HBoxContainer.new()
	cycle.alignment = BoxContainer.ALIGNMENT_CENTER
	cycle.add_theme_constant_override("separation", 10)
	cycle.add_child(_dim_label("◂"))
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	cycle.add_child(swatch)
	cycle.add_child(_dim_label("▸"))
	cycle.visible = false
	v.add_child(cycle)

	_cards.append({"panel": panel, "icon": icon, "label": lbl, "pnum": pnum,
			"swatch": swatch, "cycle": cycle})
	return panel


func _refresh() -> void:
	for i in 4:
		var icon: TextureRect = _cards[i]["icon"]
		var lbl: Label = _cards[i]["label"]
		var pnum: Label = _cards[i]["pnum"]
		var cycle: Control = _cards[i]["cycle"]
		if i < roster.size():
			icon.visible = false
			lbl.text = "KEYBOARD + MOUSE" if roster[i] == -1 else "GAMEPAD %d" % (roster[i] + 1)
			lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
			cycle.visible = true
			pnum.add_theme_color_override("font_color", COLORS[picks[i]])
			var swatch: Panel = _cards[i]["swatch"]
			var sb := StyleBoxFlat.new()
			sb.bg_color = COLORS[picks[i]]
			sb.set_corner_radius_all(8)
			sb.set_border_width_all(2)
			sb.border_color = Color(0, 0, 0, 0.55)
			swatch.add_theme_stylebox_override("panel", sb)
		else:
			icon.visible = true
			lbl.text = "to join"
			lbl.add_theme_color_override("font_color", TEXT_DIM)
			cycle.visible = false
			pnum.add_theme_color_override("font_color", COLORS[i])
	var can_start := roster.size() >= 2
	_start_icon.visible = can_start
	_start_sep.visible = can_start
	_start_key.visible = can_start
	if can_start:
		_start_label.text = "%d players in — press" % roster.size()
		_start_label.add_theme_color_override("font_color", ACCENT)
	else:
		_start_label.text = "waiting for at least 2 players…"
		_start_label.add_theme_color_override("font_color", TEXT_DIM)


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


# Slide the board back out, then hand control to whoever opened us.
func _close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", get_viewport_rect().size.y + 80.0, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_dim, "color:a", 0.0, 0.4)
	tw.tween_callback(func():
		if closed.get_connections().is_empty():
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		else:
			closed.emit())


func _join(device: int) -> void:
	if roster.has(device) or roster.size() >= 4:
		return
	roster.append(device)
	picks.append(_free_color(roster.size() - 1))
	_refresh()


func _drop(device: int) -> void:
	var idx := roster.find(device)
	if idx != -1:
		roster.remove_at(idx)
		picks.remove_at(idx)
		_refresh()


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


func _try_start() -> void:
	if roster.size() >= 2:
		Net.start_local(roster, picks)
