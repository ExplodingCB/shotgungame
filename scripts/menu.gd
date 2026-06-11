extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)

const MUSIC := preload("res://audio/music/main_menu_music.mp3")
const NEBULA := preload("res://assets/space-backgrounds/Purple Nebula/Purple_Nebula_05-1024x1024.png")
const ROCK_HUGE := preload("res://assets/asteroids/Asteroids_01_huge.png")
const ROCK_LARGE := preload("res://assets/asteroids/Asteroids_01_large.png")
const ROCK_MEDIUM := preload("res://assets/asteroids/Asteroids_01_medium.png")
const SHIP := preload("res://assets/spaceships/Beholder/Beholder.png")
const MenuIcon := preload("res://scripts/menu_icon.gd")
const PlayerScript := preload("res://scripts/player.gd")

var _ip_edit: LineEdit
var _swatches: Array[Button] = []
var _rocks: Array[TextureRect] = []
var _ship: TextureRect
var _t := 0.0


func _ready() -> void:
	_build_background()
	_build_center()

	var stream: AudioStreamMP3 = MUSIC
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -10.0
	music.bus = "Music"
	add_child(music)
	music.play()


func _process(delta: float) -> void:
	_t += delta
	for i in _rocks.size():
		var dir := 1.0 if i % 2 == 0 else -1.0
		_rocks[i].rotation += delta * (0.04 + 0.025 * i) * dir
	if _ship != null:
		_ship.position.x += delta * 14.0
		_ship.position.y += sin(_t * 0.7) * 0.15
		if _ship.position.x > size.x + 120.0:
			_ship.position.x = -120.0


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.texture = NEBULA
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.modulate = Color(0.62, 0.58, 0.68)
	add_child(bg)

	var tint := ColorRect.new()
	tint.color = Color(0, 0, 0, 0.42)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tint)

	_add_rock(ROCK_HUGE, Vector2(70, 600), 170.0, 0.5)
	_add_rock(ROCK_LARGE, Vector2(1640, 740), 120.0, 0.55)
	_add_rock(ROCK_MEDIUM, Vector2(330, 940), 64.0, 0.45)
	_add_rock(ROCK_MEDIUM, Vector2(1800, 150), 56.0, 0.4)

	_ship = TextureRect.new()
	_ship.texture = SHIP
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ship.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ship.size = Vector2(110, 84)
	_ship.position = Vector2(1380, 420)
	_ship.pivot_offset = _ship.size / 2.0
	_ship.rotation_degrees = -10.0
	_ship.modulate = Color(1, 1, 1, 0.9)
	add_child(_ship)


func _add_rock(tex: Texture2D, pos: Vector2, rock_size: float, alpha: float) -> void:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2.ONE * rock_size
	r.position = pos
	r.pivot_offset = r.size / 2.0
	r.rotation = randf() * TAU
	r.modulate = Color(0.75, 0.7, 0.78, alpha)
	add_child(r)
	_rocks.append(r)


func _build_center() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "SHOTGUN DRIFT"
	var title_font := FontVariation.new()
	title_font.base_font = ThemeDB.fallback_font
	title_font.set_spacing(TextServer.SPACING_GLYPH, 14)
	title_font.variation_embolden = 0.9
	title.add_theme_font_override("font", title_font)
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", Color(1.0, 0.64, 0.18))
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.15, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_vspace(8))
	box.add_child(_ornament(56, false))
	box.add_child(_vspace(10))

	var subtitle := Label.new()
	subtitle.text = "recoil is your engine"
	var sub_font := FontVariation.new()
	sub_font.base_font = ThemeDB.fallback_font
	sub_font.set_spacing(TextServer.SPACING_GLYPH, 8)
	subtitle.add_theme_font_override("font", sub_font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_vspace(44))

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	box.add_child(btns)

	btns.add_child(_menu_button("Dungeon Dive  (solo runs)", "solo", func():
		Net.mode = Net.Mode.SOLO
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")))
	btns.add_child(_menu_button("Arena Waves  (solo)", "solo", func(): Net.start_solo()))
	btns.add_child(_menu_button("Local Versus  (couch)", "solo",
			func(): get_tree().change_scene_to_file("res://scenes/local_lobby.tscn")))
	btns.add_child(_menu_button("Host  (port %d)" % Net.PORT, "host", func(): Net.start_host()))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 16)
	btns.add_child(join_row)

	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(324, 56)
	_ip_edit.add_theme_font_size_override("font_size", 18)
	_ip_edit.add_theme_color_override("font_color", TEXT_BRIGHT)
	_ip_edit.add_theme_color_override("caret_color", ACCENT)
	var ip_style := _panel_style(Color(0.075, 0.07, 0.09, 0.92), Color(0.23, 0.22, 0.27))
	ip_style.content_margin_left = 52.0
	_ip_edit.add_theme_stylebox_override("normal", ip_style)
	var ip_focus := _panel_style(Color(0.085, 0.08, 0.1, 0.95), Color(1, 0.62, 0.1, 0.45))
	ip_focus.content_margin_left = 52.0
	_ip_edit.add_theme_stylebox_override("focus", ip_focus)
	_ip_edit.text_submitted.connect(func(_t2): Net.start_join(_ip_edit.text))
	_attach_icon(_ip_edit, "globe", 16)
	join_row.add_child(_ip_edit)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(140, 56)
	join_btn.add_theme_font_size_override("font_size", 19)
	join_btn.add_theme_color_override("font_color", ACCENT)
	join_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.35))
	join_btn.add_theme_color_override("font_pressed_color", ACCENT)
	var jb := _panel_style(Color(0.1, 0.06, 0.02, 0.7), ACCENT, 2)
	jb.shadow_color = Color(1, 0.55, 0.1, 0.22)
	jb.shadow_size = 10
	join_btn.add_theme_stylebox_override("normal", jb)
	var jbh := _panel_style(Color(0.18, 0.1, 0.03, 0.8), Color(1.0, 0.75, 0.35), 2)
	jbh.shadow_color = Color(1, 0.55, 0.1, 0.35)
	jbh.shadow_size = 12
	join_btn.add_theme_stylebox_override("hover", jbh)
	join_btn.add_theme_stylebox_override("pressed", jb)
	join_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	join_btn.pressed.connect(func(): Net.start_join(_ip_edit.text))
	join_row.add_child(join_btn)

	btns.add_child(_build_color_row())

	btns.add_child(_menu_button("Quit", "power", func(): get_tree().quit()))

	box.add_child(_vspace(40))
	box.add_child(_ornament(140, true))


# Ship color picker: one swatch per paint job. The pick is saved and
# claimed from the server on spawn (first come keeps a contested
# color). Clicking the active swatch goes back to your slot's default.
func _build_color_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	var lbl := Label.new()
	lbl.text = "SHIP COLOR"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	row.add_child(gap)
	for i in PlayerScript.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(32, 32)
		b.tooltip_text = "Fly this color (click again for auto)"
		b.pressed.connect(func():
			Net.set_preferred_color(-1 if Net.preferred_color == i else i)
			_refresh_swatches())
		row.add_child(b)
		_swatches.append(b)
	_refresh_swatches()
	return row


func _refresh_swatches() -> void:
	for i in _swatches.size():
		var sel: bool = Net.preferred_color == i
		var color: Color = PlayerScript.COLORS[i]
		var normal := _swatch_style(color, Color(0, 0, 0, 0.6), sel)
		_swatches[i].add_theme_stylebox_override("normal", normal)
		_swatches[i].add_theme_stylebox_override("pressed", normal)
		_swatches[i].add_theme_stylebox_override("hover",
				_swatch_style(color.lightened(0.15), Color(1, 1, 1, 0.65), sel))
		_swatches[i].add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _swatch_style(bg: Color, idle_border: Color, sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if sel else 1)
	sb.border_color = Color.WHITE if sel else idle_border
	return sb


func _menu_button(label: String, icon_kind: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(480, 56)
	btn.add_theme_font_size_override("font_size", 19)
	btn.add_theme_color_override("font_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_stylebox_override("normal", _panel_style(Color(0.075, 0.07, 0.09, 0.92), Color(0.23, 0.22, 0.27)))
	btn.add_theme_stylebox_override("hover", _panel_style(Color(0.1, 0.09, 0.12, 0.95), Color(1, 0.62, 0.1, 0.55)))
	btn.add_theme_stylebox_override("pressed", _panel_style(Color(0.05, 0.05, 0.07, 0.95), Color(1, 0.62, 0.1, 0.8)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(on_pressed)
	_attach_icon(btn, icon_kind, 20)
	return btn


func _attach_icon(parent: Control, kind: String, left: float) -> void:
	var ic: Control = MenuIcon.new()
	ic.kind = kind
	ic.anchor_top = 0.5
	ic.anchor_bottom = 0.5
	ic.offset_top = -12.0
	ic.offset_bottom = 12.0
	ic.offset_left = left
	ic.offset_right = left + 24.0
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ic)


func _panel_style(bg: Color, border: Color, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _ornament(line_w: float, diamond: bool) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	h.add_child(_orn_line(line_w))
	if diamond:
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(16, 16)
		var d := ColorRect.new()
		d.color = ACCENT
		d.size = Vector2(9, 9)
		d.position = Vector2(3.5, 3.5)
		d.pivot_offset = Vector2(4.5, 4.5)
		d.rotation_degrees = 45.0
		wrap.add_child(d)
		h.add_child(wrap)
	else:
		var bar := ColorRect.new()
		bar.color = ACCENT
		bar.custom_minimum_size = Vector2(18, 3)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
	h.add_child(_orn_line(line_w))
	return h


func _orn_line(w: float) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.75, 0.55, 0.35, 0.35)
	line.custom_minimum_size = Vector2(w, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line


func _vspace(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
