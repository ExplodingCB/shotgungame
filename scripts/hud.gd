extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const ALERT := Color(1.0, 0.38, 0.28)
const TEXT_BRIGHT := Color(0.96, 0.96, 1.0)
const TEXT_DIM := Color(0.66, 0.68, 0.76)
const TEXT_FAINT := Color(0.46, 0.48, 0.56)

var player: Node = null

var _rows: Array[Dictionary] = []
var _key1_label: Label
var _wave_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_weapon_panel()
	_build_hints()
	_build_wave_label()
	_build_host_info()


# Top-left line the host shares with friends: UPnP progress, then the
# public IP to join with (or port-forward instructions if UPnP failed).
func _build_host_info() -> void:
	var lbl := Label.new()
	lbl.position = Vector2(28, 18)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 5)
	add_child(lbl)
	var update := func():
		lbl.text = Net.host_info
		lbl.visible = Net.mode == Net.Mode.HOST and Net.host_info != ""
	Net.host_info_changed.connect(update)
	update.call()


func _build_wave_label() -> void:
	_wave_label = Label.new()
	_wave_label.visible = false
	_wave_label.anchor_left = 0.5
	_wave_label.anchor_right = 0.5
	_wave_label.offset_left = -300.0
	_wave_label.offset_right = 300.0
	_wave_label.offset_top = 18.0
	_wave_label.offset_bottom = 56.0
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 24)
	_wave_label.add_theme_color_override("font_color", ACCENT)
	_wave_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_wave_label.add_theme_constant_override("outline_size", 5)
	add_child(_wave_label)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = _find_local_player()
		if player == null:
			return
	var prim: int = player.primary
	var active: int = int(player.weapon)
	_update_row(_rows[0], prim, prim >= 0 and active == prim)
	_update_row(_rows[1], 1, active == 1)
	if prim >= 0:
		_key1_label.text = WeaponDB.DATA[prim]["name"]
	_update_wave_label()
	queue_redraw()


func _update_wave_label() -> void:
	var main := get_tree().current_scene
	if main == null or not "wave" in main or int(main.wave) == 0:
		_wave_label.visible = false
		return
	_wave_label.visible = true
	if int(main.enemies_alive) > 0:
		_wave_label.text = "WAVE %d  —  %d left" % [main.wave, main.enemies_alive]
	else:
		_wave_label.text = "WAVE %d cleared — next wave incoming…" % main.wave


func _find_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null


# Edge arrows pointing at off-screen players, tinted their color.
func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var vp := get_viewport_rect().size
	var margin := 36.0
	for other in get_tree().get_nodes_in_group("player"):
		if other == player or not is_instance_valid(other):
			continue
		var sp: Vector2 = get_viewport().canvas_transform * other.global_position
		if sp.x >= 0.0 and sp.x <= vp.x and sp.y >= 0.0 and sp.y <= vp.y:
			continue
		var clamped := Vector2(clampf(sp.x, margin, vp.x - margin), clampf(sp.y, margin, vp.y - margin))
		var dir := (sp - clamped).normalized()
		if dir == Vector2.ZERO:
			continue
		var color: Color = other.COLORS[other.color_idx % other.COLORS.size()]
		draw_set_transform_matrix(Transform2D(dir.angle(), clamped))
		draw_colored_polygon(
			PackedVector2Array([Vector2(18, 0), Vector2(-9, 11), Vector2(-4, 0), Vector2(-9, -11)]),
			color
		)
		draw_set_transform_matrix(Transform2D())


func _build_weapon_panel() -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 28.0
	panel.offset_top = -160.0
	panel.offset_right = 480.0
	panel.offset_bottom = -28.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.alignment = BoxContainer.ALIGNMENT_END
	add_child(panel)
	_rows.append(_build_row(panel))
	_rows.append(_build_row(panel))


func _build_row(parent: Control) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)

	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_color_override("font_color", ACCENT)
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.custom_minimum_size = Vector2(18, 0)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(arrow)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(96, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.uppercase = true
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(name_lbl)

	var num := Label.new()
	num.add_theme_font_size_override("font_size", 30)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(num)

	var max_lbl := Label.new()
	max_lbl.add_theme_font_size_override("font_size", 16)
	max_lbl.add_theme_color_override("font_color", TEXT_FAINT)
	max_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(max_lbl)

	return {"box": box, "arrow": arrow, "icon": icon, "name": name_lbl, "num": num, "max": max_lbl}


func _update_row(row: Dictionary, w: int, active: bool) -> void:
	var arrow: Label = row["arrow"]
	var icon: TextureRect = row["icon"]
	var name_lbl: Label = row["name"]
	var num: Label = row["num"]
	var max_lbl: Label = row["max"]
	var box: HBoxContainer = row["box"]

	if w < 0:
		arrow.self_modulate.a = 0.0
		icon.texture = null
		name_lbl.text = "empty"
		num.text = ""
		max_lbl.text = ""
		box.modulate = Color(1, 1, 1, 0.4)
		return

	var data: Dictionary = player.WEAPON_DATA[w]
	arrow.self_modulate.a = 1.0 if active else 0.0
	icon.texture = data["texture"]
	name_lbl.text = data["name"]
	# Rarity is the name's color; inactive rows just run darker.
	var rarity_col := WeaponDB.rarity_color(w)
	name_lbl.add_theme_color_override("font_color", rarity_col if active else rarity_col.darkened(0.35))
	var a: int = int(player.ammo[w])
	if a < 0:
		num.text = "∞"
		max_lbl.text = ""
	else:
		num.text = str(a)
		max_lbl.text = "/ %d" % int(data["max_ammo"])
	var num_color := TEXT_BRIGHT if active else TEXT_DIM
	if a == 0:
		num_color = ALERT
	num.add_theme_color_override("font_color", num_color)
	box.modulate = Color(1, 1, 1, 1.0 if active else 0.62)


func _build_hints() -> void:
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 10)
	hints.anchor_left = 1.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = -720.0
	hints.offset_top = -62.0
	hints.offset_right = -28.0
	hints.offset_bottom = -28.0
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(hints)

	_key1_label = _add_hint(hints, ["1"], "Shotgun")
	_add_hint(hints, ["2"], "Pistol")
	_add_hint(hints, ["A", "D"], "Spin", "/")


func _add_hint(parent: Control, keys: Array, label: String, sep := "") -> Label:
	var first := true
	for k in keys:
		if not first and sep != "":
			var s := Label.new()
			s.text = sep
			s.add_theme_color_override("font_color", TEXT_DIM)
			s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			parent.add_child(s)
		parent.add_child(_keycap(k))
		first = false
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	parent.add_child(spacer)
	return lbl


func _keycap(key_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = key_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.9)
	style.border_color = Color(0.5, 0.52, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	lbl.add_theme_stylebox_override("normal", style)
	return lbl
