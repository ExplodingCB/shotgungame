# Dungeon-run overlay, kept deliberately sparse: one status line up
# top, the center banner (same pattern as the versus round banner), a
# small list of owned perks, the pick-one perk choice, and the
# game-over card. The shared hud.gd under the same CanvasLayer keeps
# handling weapons/ammo/hints; state arrives by polling the dungeon
# controller every frame, same as the rest of the codebase.
extends Control

signal perk_chosen(id: int)

const ACCENT := Color(1.0, 0.62, 0.1)
const ALERT := Color(1.0, 0.38, 0.28)
const TEXT_BRIGHT := Color(0.96, 0.96, 1.0)
const TEXT_DIM := Color(0.66, 0.68, 0.76)

var _status: Label
var _banner: Label
var _perk_box: VBoxContainer
var _perk_key := ""
var _choice_layer: Control
var _choice_options: Array = []
var _gameover: Control

# Resolved by position, not current_scene — that isn't assigned yet
# while the scene tree is still readying.
@onready var main: Node = get_node("../..")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_status = _label(18, TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.offset_left = -300.0
	_status.offset_right = 300.0
	_status.offset_top = 18.0
	add_child(_status)

	# Big center flash for room transitions, mirroring hud.gd's round
	# banner so both modes speak the same language.
	_banner = _label(46, TEXT_BRIGHT)
	_banner.visible = false
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -500.0
	_banner.offset_right = 500.0
	_banner.offset_top = 90.0
	_banner.offset_bottom = 230.0
	var bf := FontVariation.new()
	bf.base_font = ThemeDB.fallback_font
	bf.set_spacing(TextServer.SPACING_GLYPH, 8)
	bf.variation_embolden = 0.8
	_banner.add_theme_font_override("font", bf)
	_banner.add_theme_constant_override("outline_size", 8)
	add_child(_banner)

	_perk_box = VBoxContainer.new()
	_perk_box.anchor_left = 1.0
	_perk_box.anchor_right = 1.0
	_perk_box.offset_left = -300.0
	_perk_box.offset_right = -28.0
	_perk_box.offset_top = 16.0
	_perk_box.add_theme_constant_override("separation", 2)
	add_child(_perk_box)


func _process(_delta: float) -> void:
	_status.text = "DEPTH %d   ·   %d KILLS" % [int(main.depth), int(main.kills)]
	_update_banner()
	_update_perk_box()
	if main.run_over and _gameover == null:
		_build_gameover()


func _update_banner() -> void:
	var remaining := float(int(main.banner_until) - Time.get_ticks_msec()) / 1000.0
	if str(main.banner_text) == "" or remaining <= 0.0:
		_banner.visible = false
		return
	_banner.visible = true
	_banner.text = main.banner_text
	_banner.add_theme_color_override("font_color", main.banner_color)
	_banner.modulate.a = clampf(remaining / 0.4, 0.0, 1.0)


# Owned perks, top right; stacks collapse to "×n".
func _update_perk_box() -> void:
	var owned: Array = main.perks
	var key := str(owned)
	if key == _perk_key:
		return
	_perk_key = key
	for c in _perk_box.get_children():
		c.queue_free()
	var counts := {}
	for id in owned:
		counts[id] = int(counts.get(id, 0)) + 1
	for id in counts:
		var data: Dictionary = DungeonPerks.DATA[id]
		var lbl := _label(13, TEXT_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.text = data["name"] + ("  ×%d" % counts[id] if int(counts[id]) > 1 else "")
		_perk_box.add_child(lbl)


# --- Perk choice -------------------------------------------------------

func open_perk_choice(options: Array) -> void:
	_choice_options = options
	Net.ui_open = true

	_choice_layer = Control.new()
	_choice_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_choice_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_layer.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := _label(22, TEXT_BRIGHT)
	title.text = "CHOOSE ONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	for i in options.size():
		row.add_child(_perk_card(i, options[i]))


func _perk_card(index: int, id: int) -> Control:
	var data: Dictionary = DungeonPerks.DATA[id]

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(260, 170)
	btn.add_theme_stylebox_override("normal", _card_style(Color(0.075, 0.07, 0.09, 0.95), Color(0.25, 0.24, 0.3)))
	btn.add_theme_stylebox_override("hover", _card_style(Color(0.1, 0.09, 0.12, 0.95), Color(1, 0.62, 0.1, 0.55)))
	btn.add_theme_stylebox_override("pressed", _card_style(Color(0.05, 0.05, 0.07, 0.95), Color(1, 0.62, 0.1, 0.8)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func(): _choose(index))

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 10)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var keycap := _label(14, TEXT_DIM)
	keycap.text = str(index + 1)
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(keycap)

	var name_lbl := _label(19, TEXT_BRIGHT)
	name_lbl.text = data["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	var desc := _label(14, TEXT_DIM)
	desc.text = data["desc"]
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(desc)

	return btn


func _choose(index: int) -> void:
	if _choice_layer == null:
		return
	var id: int = _choice_options[index]
	_choice_layer.queue_free()
	_choice_layer = null
	Net.ui_open = false
	perk_chosen.emit(id)


func _input(event: InputEvent) -> void:
	if _choice_layer == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var idx := -1
	match event.keycode:
		KEY_1, KEY_KP_1: idx = 0
		KEY_2, KEY_KP_2: idx = 1
		KEY_3, KEY_KP_3: idx = 2
	if idx >= 0 and idx < _choice_options.size():
		get_viewport().set_input_as_handled()
		_choose(idx)


# --- Game over ---------------------------------------------------------

func _build_gameover() -> void:
	_gameover = Control.new()
	_gameover.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_gameover)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := _label(44, ALERT)
	title.text = "RUN OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tf := FontVariation.new()
	tf.base_font = ThemeDB.fallback_font
	tf.set_spacing(TextServer.SPACING_GLYPH, 10)
	tf.variation_embolden = 0.8
	title.add_theme_font_override("font", tf)
	box.add_child(title)

	var stats := _label(20, TEXT_BRIGHT)
	stats.text = "DEPTH %d   ·   %d kills   ·   best %d" \
			% [int(main.depth), int(main.kills), int(main.best_depth)]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats)

	if main.new_best:
		var best := _label(16, Color(0.45, 0.95, 0.5))
		best.text = "new best"
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(best)

	var hint := _label(15, TEXT_DIM)
	hint.text = "ENTER — dive again      ESC — menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


# --- Helpers -----------------------------------------------------------

func _label(size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 5)
	return lbl


func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	return sb
