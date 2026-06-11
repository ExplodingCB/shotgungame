# Main menu: Portal 2-style left rail over a live arena diorama.
# The rail swaps its page in place (main list / Play Online / Options);
# behind it a handful of scripted ships drift and trade tracer fire.
extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)

const MUSIC := preload("res://audio/music/main_menu_music.mp3")
const NEBULA := preload("res://assets/space-backgrounds/Purple Nebula/Purple_Nebula_05-1024x1024.png")
const ROCK_HUGE := preload("res://assets/asteroids/Asteroids_01_huge.png")
const ROCK_LARGE := preload("res://assets/asteroids/Asteroids_01_large.png")
const ROCK_MEDIUM := preload("res://assets/asteroids/Asteroids_01_medium.png")
const PlayerScript := preload("res://scripts/player.gd")

var _ip_edit: LineEdit
var _swatches: Array[Button] = []

var _pages := {}  # name -> Control, swapped in place on the rail
var _page := "main"
var _first_focus := {}  # name -> Control to focus when the page shows

var _ships: Array = []  # Diorama.Ship
var _rocks: Array[TextureRect] = []
var _fx_layer: Node2D
var _t := 0.0
var _next_shot := 2.0


func _ready() -> void:
	_build_diorama()
	_build_rail()
	_show_page("main")

	var stream: AudioStreamMP3 = MUSIC
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -10.0
	music.bus = "Music"
	add_child(music)
	music.play()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page != "main":
		_show_page("main")
		accept_event()


# --- Diorama: drifting rocks + ships flying lazy loops ----------------

func _process(delta: float) -> void:
	_t += delta
	for i in _rocks.size():
		var r := _rocks[i]
		var dir := 1.0 if i % 2 == 0 else -1.0
		r.rotation += delta * (0.03 + 0.02 * i) * dir
		r.position += Vector2(8.0 + 3.0 * i, -4.0 + 2.5 * i) * delta * dir
		if r.position.x > size.x + 200.0:
			r.position.x = -200.0
		elif r.position.x < -200.0:
			r.position.x = size.x + 200.0
	for s in _ships:
		s.fly(_t, delta)
	_next_shot -= delta
	if _next_shot <= 0.0 and _ships.size() >= 2:
		_next_shot = randf_range(1.6, 4.0)
		var a: Node2D = _ships.pick_random()
		var b: Node2D = _ships[(_ships.find(a) + 1 + randi() % (_ships.size() - 1)) % _ships.size()]
		var tracer := Diorama.Tracer.new()
		tracer.from = a.position
		tracer.to = b.position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		tracer.color = a.color
		_fx_layer.add_child(tracer)


func _build_diorama() -> void:
	var bg := TextureRect.new()
	bg.texture = NEBULA
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.modulate = Color(0.58, 0.54, 0.64)
	add_child(bg)

	var tint := ColorRect.new()
	tint.color = Color(0, 0, 0, 0.38)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tint)

	_add_rock(ROCK_HUGE, Vector2(1380, 720), 190.0, 0.55)
	_add_rock(ROCK_LARGE, Vector2(900, 220), 110.0, 0.5)
	_add_rock(ROCK_MEDIUM, Vector2(1700, 380), 62.0, 0.45)
	_add_rock(ROCK_MEDIUM, Vector2(1150, 880), 50.0, 0.4)

	_fx_layer = Node2D.new()
	add_child(_fx_layer)

	# Three ships dogfight on the right two-thirds, clear of the rail.
	var arena := Rect2(Vector2(820, 140), Vector2(940, 800))
	for i in 3:
		var ship := Diorama.Ship.new()
		ship.color = PlayerScript.COLORS[i]
		ship.center = arena.position + arena.size * Vector2(randf_range(0.2, 0.8), randf_range(0.25, 0.75))
		ship.radii = Vector2(randf_range(130, 260), randf_range(90, 190))
		ship.speed = randf_range(0.25, 0.45) * (1.0 if i % 2 == 0 else -1.0)
		ship.phase = randf() * TAU
		_fx_layer.add_child(ship)
		_ships.append(ship)

	# Soft vignette so the rail text pops and edges fall away.
	var vignette := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 1.1)
	vignette.texture = gtex
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(vignette)


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


# --- Left rail ---------------------------------------------------------

func _build_rail() -> void:
	# Dark gradient that owns the left ~40% and fades into the scene.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.016, 0.012, 0.028, 0.97))
	grad.set_color(1, Color(0.016, 0.012, 0.028, 0.0))
	grad.set_offset(0, 0.45)
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)
	shade.texture = gtex
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.42
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.anchor_right = 0.38
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", 84)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 0)
	margin.add_child(rail)

	var title := Label.new()
	title.text = "SHOTGUN\nDRIFT"
	var title_font := FontVariation.new()
	title_font.base_font = ThemeDB.fallback_font
	title_font.set_spacing(TextServer.SPACING_GLYPH, 10)
	title_font.variation_embolden = 0.9
	title.add_theme_font_override("font", title_font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_constant_override("line_spacing", -14)
	title.add_theme_color_override("font_color", Color(1.0, 0.64, 0.18))
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.15, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 4)
	rail.add_child(title)

	rail.add_child(_vspace(10))

	var subtitle := Label.new()
	subtitle.text = "recoil is your engine"
	var sub_font := FontVariation.new()
	sub_font.base_font = ThemeDB.fallback_font
	sub_font.set_spacing(TextServer.SPACING_GLYPH, 6)
	subtitle.add_theme_font_override("font", sub_font)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	rail.add_child(subtitle)

	rail.add_child(_vspace(52))

	# Pages swap inside this host; the rail never moves.
	var host := Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(host)
	_pages["main"] = _build_main_page(host)
	_pages["online"] = _build_online_page(host)
	_pages["options"] = _build_options_page(host)

	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(0.45, 0.43, 0.5))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 16)
	add_child(version)


func _build_main_page(host: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	host.add_child(page)

	var first := _rail_item(page, "Dungeon Dive", func():
		Net.mode = Net.Mode.SOLO
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn"))
	_rail_item(page, "Arena Waves", func(): Net.start_solo())
	_rail_item(page, "Local Versus",
			func(): get_tree().change_scene_to_file("res://scenes/local_lobby.tscn"))
	_rail_item(page, "Play Online", func(): _show_page("online"))
	page.add_child(_vspace(18))
	_rail_item(page, "Options", func(): _show_page("options"))
	_rail_item(page, "Quit", func(): get_tree().quit())

	_first_focus["main"] = first
	return page


func _build_online_page(host: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	host.add_child(page)

	page.add_child(_heading("PLAY ONLINE"))
	page.add_child(_vspace(14))

	var first := _rail_item(page, "Host  (port %d)" % Net.PORT, func(): Net.start_host())

	page.add_child(_vspace(10))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	page.add_child(join_row)

	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(230, 46)
	_ip_edit.add_theme_font_size_override("font_size", 17)
	_ip_edit.add_theme_color_override("font_color", TEXT_BRIGHT)
	_ip_edit.add_theme_color_override("caret_color", ACCENT)
	_ip_edit.add_theme_stylebox_override("normal",
			_underline_style(Color(0.35, 0.33, 0.4)))
	_ip_edit.add_theme_stylebox_override("focus", _underline_style(ACCENT))
	_ip_edit.text_submitted.connect(func(_t2): Net.start_join(_ip_edit.text))
	join_row.add_child(_ip_edit)

	var join := _item_button("Join")
	join.pressed.connect(func(): Net.start_join(_ip_edit.text))
	join_row.add_child(join)

	page.add_child(_vspace(22))

	var color_lbl := Label.new()
	color_lbl.text = "SHIP COLOR"
	color_lbl.add_theme_font_size_override("font_size", 13)
	color_lbl.add_theme_color_override("font_color", TEXT_DIM)
	page.add_child(color_lbl)
	page.add_child(_vspace(8))
	page.add_child(_build_color_row())

	page.add_child(_vspace(26))
	_rail_item(page, "Back", func(): _show_page("main"))

	_first_focus["online"] = first
	return page


func _build_options_page(host: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	host.add_child(page)

	page.add_child(_heading("OPTIONS"))
	page.add_child(_vspace(14))

	var music := _slider_row(page, "MUSIC", Net.music_volume)
	music.value_changed.connect(func(v): Net.set_music_volume(v))
	var sfx := _slider_row(page, "SFX", Net.sfx_volume)
	sfx.value_changed.connect(func(v): Net.set_sfx_volume(v))

	page.add_child(_vspace(14))

	var fullscreen := _check_row(page, "Fullscreen", Net.fullscreen)
	fullscreen.toggled.connect(func(on): Net.set_fullscreen(on))
	var vsync := _check_row(page, "VSync", Net.vsync)
	vsync.toggled.connect(func(on): Net.set_vsync(on))

	page.add_child(_vspace(26))
	_rail_item(page, "Back", func(): _show_page("main"))

	_first_focus["options"] = music
	return page


func _show_page(name_: String) -> void:
	_page = name_
	for key in _pages:
		_pages[key].visible = key == name_
	var focus: Control = _first_focus.get(name_)
	if focus != null:
		focus.grab_focus()


# --- Rail widgets -------------------------------------------------------

# A clean text menu item: dim at rest, accent + ▸ marker on hover/focus.
func _rail_item(page: Container, label: String, on_pressed: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	page.add_child(row)

	var marker := Label.new()
	marker.text = "▸ "
	marker.custom_minimum_size = Vector2(26, 0)
	marker.add_theme_font_size_override("font_size", 21)
	marker.add_theme_color_override("font_color", ACCENT)
	marker.modulate.a = 0.0
	row.add_child(marker)

	var btn := _item_button(label)
	btn.pressed.connect(on_pressed)
	var show_marker := func(on: bool): marker.modulate.a = 1.0 if on else 0.0
	btn.mouse_entered.connect(func(): show_marker.call(true))
	btn.mouse_exited.connect(func(): show_marker.call(btn.has_focus()))
	btn.focus_entered.connect(func(): show_marker.call(true))
	btn.focus_exited.connect(func(): show_marker.call(false))
	row.add_child(btn)
	return btn


func _item_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 21)
	btn.add_theme_color_override("font_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	btn.add_theme_color_override("font_focus_color", ACCENT)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.75, 0.35))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 6.0
	empty.content_margin_bottom = 6.0
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, empty)
	return btn


func _heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.set_spacing(TextServer.SPACING_GLYPH, 6)
	font.variation_embolden = 0.6
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", ACCENT)
	return lbl


func _slider_row(page: Container, label: String, value: float) -> HSlider:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	page.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(300, 24)
	page.add_child(slider)
	return slider


func _check_row(page: Container, label: String, on: bool) -> CheckButton:
	var check := CheckButton.new()
	check.text = label
	check.button_pressed = on
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", TEXT_BRIGHT)
	check.add_theme_color_override("font_hover_color", ACCENT)
	check.add_theme_color_override("font_focus_color", ACCENT)
	check.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	page.add_child(check)
	return check


# Ship color picker: one swatch per paint job. The pick is saved and
# claimed from the server on spawn (first come keeps a contested
# color). Clicking the active swatch goes back to your slot's default.
func _build_color_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
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


func _underline_style(line: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = line
	sb.border_width_bottom = 2
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _vspace(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


# --- Diorama actors -----------------------------------------------------

class Diorama:
	# A ship blob (matching the in-game gradient-circle look) that flies
	# a lazy lissajous loop and banks into its heading.
	class Ship extends Node2D:
		var color := Color.WHITE
		var center := Vector2.ZERO
		var radii := Vector2(200, 140)
		var speed := 0.3
		var phase := 0.0

		func fly(t: float, _delta: float) -> void:
			var a := t * speed + phase
			var pos := center + Vector2(cos(a) * radii.x, sin(a * 1.4) * radii.y)
			var vel := Vector2(-sin(a) * radii.x, cos(a * 1.4) * radii.y * 1.4) * speed
			position = pos
			rotation = vel.angle()
			queue_redraw()

		func _draw() -> void:
			# Fading thruster trail behind the body.
			for i in 4:
				var k := 1.0 - i / 4.0
				draw_circle(Vector2(-10.0 - i * 7.0, 0), 3.5 * k,
						Color(color.r, color.g, color.b, 0.16 * k))
			draw_circle(Vector2.ZERO, 9.0, color)
			draw_circle(Vector2(3.5, 0), 2.4, Color(0, 0, 0, 0.5))

	# One shot: a tracer line that fades fast with a flash at the muzzle
	# and a pop at the far end. Frees itself when spent.
	class Tracer extends Node2D:
		var from := Vector2.ZERO
		var to := Vector2.ZERO
		var color := Color.WHITE
		var _life := 0.35

		func _process(delta: float) -> void:
			_life -= delta
			if _life <= 0.0:
				queue_free()
			queue_redraw()

		func _draw() -> void:
			var k := clampf(_life / 0.35, 0.0, 1.0)
			var col := Color(color.r, color.g, color.b, 0.55 * k)
			draw_line(from, to, col, 2.0, true)
			draw_circle(from, 4.0 * k, Color(1, 1, 1, 0.5 * k))
			draw_circle(to, 7.0 * (1.0 - k) + 2.0, Color(1, 0.9, 0.7, 0.45 * k))
