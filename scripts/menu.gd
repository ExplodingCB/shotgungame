# Main menu: Portal 2-style left rail over the actual game. A couch
# brawl runs in a SubViewport behind the rail — four DemoBrain ships
# playing real rounds — while the rail swaps its page in place
# (main list / Play Online / Options).
extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const TEXT_BRIGHT := Color(0.94, 0.93, 0.97)
const TEXT_DIM := Color(0.62, 0.6, 0.68)

const TITLE_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const LOGO := preload("res://assets/mainmenu/logo.png")
const MUSIC := preload("res://audio/music/main_menu_music.mp3")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const PlayerScript := preload("res://scripts/player.gd")

var _ip_edit: LineEdit
var _swatches: Array[Button] = []

var _pages := {}  # name -> Control, swapped in place on the rail
var _page := "main"
var _first_focus := {}  # name -> Control to focus when the page shows


func _ready() -> void:
	_build_demo()
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


# --- Background demo: the real game, played by brains ------------------

# The demo's gunfire rides the SFX bus; hold it muted while the menu
# owns the screen (volume changes elsewhere re-apply bus state, so
# this re-asserts every frame).
func _process(_delta: float) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)


func _exit_tree() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"),
			Net.sfx_volume <= 0.001)


func _build_demo() -> void:
	Net.mode = Net.Mode.LOCAL
	Net.local_roster = [100, 101, 102, 103]
	Net.local_colors = [0, 1, 2, 3]

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)

	# The demo plays mute and chromeless: no HUD, no pause handler, no
	# second music track; brains replace the pad-polling controls.
	var demo: Node = MAIN_SCENE.instantiate()
	vp.add_child(demo)
	demo.get_node("HUD").visible = false
	demo.get_node("HUD/PauseMenu").queue_free()
	for c in demo.get_children():
		if c is AudioStreamPlayer:
			c.queue_free()
	for p in demo.get_node("Players").get_children():
		p.controls = DemoBrain.new(p)

	# Dim + vignette so the rail reads over the firefight.
	var tint := ColorRect.new()
	tint.color = Color(0, 0, 0, 0.32)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

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
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


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

	rail.add_child(_build_logo())

	rail.add_child(_vspace(56))

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


# The wordmark image, sized for the rail (the PNG carries its own
# transparent padding).
func _build_logo() -> Control:
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var ratio := LOGO.get_height() / float(LOGO.get_width())
	logo.custom_minimum_size = Vector2(500, 500 * ratio)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return logo


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
	btn.add_theme_font_override("font", TITLE_FONT)
	btn.add_theme_font_size_override("font_size", 20)
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
	font.base_font = TITLE_FONT
	font.set_spacing(TextServer.SPACING_GLYPH, 5)
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 25)
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
