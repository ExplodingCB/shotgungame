extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const ALERT := Color(1.0, 0.38, 0.28)
const TEXT_BRIGHT := Color(0.96, 0.96, 1.0)
const TEXT_DIM := Color(0.66, 0.68, 0.76)

var player: Node = null

var _rows: Array[Dictionary] = []
var _key1_label: Label
var _wave_label: Label
var _host_info_label: Label
var _score_box: VBoxContainer
var _score_key := ""

# Couch mode: one compact panel per local player along the bottom.
var _local_box: HBoxContainer
var _local_rows := {}  # player node name -> row widgets
var _round_banner: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Net.mode == Net.Mode.LOCAL:
		_build_local_box()
		_build_round_banner()
	else:
		_build_weapon_panel()
	_build_hints()
	_build_wave_label()
	_build_host_info()
	_build_scoreboard()


# Big center label for round flow: countdown, FIGHT!, winner flashes.
func _build_round_banner() -> void:
	_round_banner = Label.new()
	_round_banner.visible = false
	_round_banner.anchor_left = 0.5
	_round_banner.anchor_right = 0.5
	_round_banner.anchor_top = 0.0
	_round_banner.offset_left = -500.0
	_round_banner.offset_right = 500.0
	_round_banner.offset_top = 90.0
	_round_banner.offset_bottom = 230.0
	_round_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bf := FontVariation.new()
	bf.base_font = ThemeDB.fallback_font
	bf.set_spacing(TextServer.SPACING_GLYPH, 8)
	bf.variation_embolden = 0.8
	_round_banner.add_theme_font_override("font", bf)
	_round_banner.add_theme_font_size_override("font_size", 46)
	_round_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_round_banner.add_theme_constant_override("outline_size", 8)
	add_child(_round_banner)


func _update_round_banner() -> void:
	var main := get_tree().current_scene
	var rm: Node = main.round_manager if main != null and "round_manager" in main else null
	if rm == null or str(rm.banner_text) == "":
		_round_banner.visible = false
		return
	_round_banner.visible = true
	_round_banner.text = rm.banner_text
	_round_banner.add_theme_color_override("font_color", rm.banner_color)


# Top-left line the host shares with friends: UPnP progress, then the
# public IP to join with (or port-forward instructions if UPnP failed).
# Bound method, not a lambda: Net outlives this HUD across scene
# changes, and a lambda connection would keep firing on a freed label.
func _build_host_info() -> void:
	_host_info_label = Label.new()
	_host_info_label.position = Vector2(28, 18)
	_host_info_label.add_theme_font_size_override("font_size", 17)
	_host_info_label.add_theme_color_override("font_color", TEXT_BRIGHT)
	_host_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_host_info_label.add_theme_constant_override("outline_size", 5)
	add_child(_host_info_label)
	Net.host_info_changed.connect(_update_host_info)
	_update_host_info()


func _update_host_info() -> void:
	_host_info_label.text = Net.host_info
	_host_info_label.visible = Net.mode == Net.Mode.HOST and Net.host_info != ""


func _exit_tree() -> void:
	if Net.host_info_changed.is_connected(_update_host_info):
		Net.host_info_changed.disconnect(_update_host_info)


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
	_update_scoreboard()
	if Net.mode == Net.Mode.LOCAL:
		# One shared camera shows everyone, so no off-screen arrows.
		_update_local_panels()
		_update_round_banner()
		return
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


# --- Couch-mode weapon strips, one per local player ------------------

func _build_local_box() -> void:
	_local_box = HBoxContainer.new()
	_local_box.anchor_left = 0.0
	_local_box.anchor_right = 1.0
	_local_box.anchor_top = 1.0
	_local_box.anchor_bottom = 1.0
	_local_box.offset_top = -78.0
	_local_box.offset_bottom = -24.0
	_local_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_local_box.add_theme_constant_override("separation", 52)
	_local_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_local_box)


func _update_local_panels() -> void:
	var locals: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.is_locally_controlled():
			locals.append(p)
	locals.sort_custom(func(a, b): return a.slot < b.slot)
	for p in locals:
		var key := str(p.name)
		if not _local_rows.has(key):
			_local_rows[key] = _build_local_row(p)
		var row: Dictionary = _local_rows[key]
		var w: int = int(p.weapon)
		var data: Dictionary = WeaponDB.DATA[w]
		var icon: TextureRect = row["icon"]
		icon.texture = data["texture"]
		var num: Label = row["num"]
		var a: int = int(p.ammo[w])
		num.text = "∞" if a < 0 else str(a)
		num.add_theme_color_override("font_color", ALERT if a == 0 else TEXT_BRIGHT)
		var box: HBoxContainer = row["box"]
		box.modulate = Color(1, 1, 1, 1.0 if p.visible else 0.3)


func _build_local_row(p: Node) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_local_box.add_child(box)

	var color: Color = p.COLORS[p.color_idx % p.COLORS.size()]
	var pnum := Label.new()
	pnum.text = "P%d" % (int(p.slot) + 1)
	pnum.add_theme_font_size_override("font_size", 22)
	pnum.add_theme_color_override("font_color", color)
	pnum.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	pnum.add_theme_constant_override("outline_size", 4)
	pnum.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(pnum)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(80, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)

	var num := Label.new()
	num.add_theme_font_size_override("font_size", 24)
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	num.add_theme_constant_override("outline_size", 4)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(num)

	return {"box": box, "icon": icon, "num": num}


# --- Kill scoreboard (multiplayer only), top-right ------------------

func _build_scoreboard() -> void:
	_score_box = VBoxContainer.new()
	_score_box.anchor_left = 1.0
	_score_box.anchor_right = 1.0
	_score_box.offset_left = -240.0
	_score_box.offset_right = -28.0
	_score_box.offset_top = 16.0
	_score_box.add_theme_constant_override("separation", 4)
	_score_box.visible = false
	add_child(_score_box)


func _update_scoreboard() -> void:
	var main := get_tree().current_scene
	var players_node: Node = main.get_node_or_null("Players") if main != null else null
	if Net.mode == Net.Mode.SOLO or players_node == null or not "scores" in main:
		_score_box.visible = false
		return
	var rm: Node = main.round_manager if "round_manager" in main else null
	var entries: Array = []
	for p in players_node.get_children():
		entries.append({
			"kills": int(main.scores.get(p.fighter_key(), 0)),
			"wins": int(rm.round_wins.get(p.fighter_key(), 0)) if rm != null else -1,
			"color": p.COLORS[p.color_idx % p.COLORS.size()],
			"num": int(p.color_idx) + 1,
		})
	entries.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		return a["kills"] > b["kills"])
	# Rows rebuild only when something actually changed.
	var key := str(entries)
	if key == _score_key and _score_box.visible:
		return
	_score_key = key
	_score_box.visible = true
	for c in _score_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "KILLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_DIM)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 4)
	_score_box.add_child(title)
	for e in entries:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = e["color"]
		swatch.custom_minimum_size = Vector2(15, 15)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_lbl := Label.new()
		name_lbl.text = "P%d" % e["num"]
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", e["color"])
		name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		name_lbl.add_theme_constant_override("outline_size", 4)
		row.add_child(name_lbl)
		if int(e["wins"]) >= 0:
			var wins_lbl := Label.new()
			wins_lbl.text = "★%d" % e["wins"]
			wins_lbl.add_theme_font_size_override("font_size", 18)
			wins_lbl.add_theme_color_override("font_color", ACCENT)
			wins_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			wins_lbl.add_theme_constant_override("outline_size", 4)
			row.add_child(wins_lbl)
		var kills_lbl := Label.new()
		kills_lbl.text = str(e["kills"])
		kills_lbl.custom_minimum_size = Vector2(34, 0)
		kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kills_lbl.add_theme_font_size_override("font_size", 18)
		kills_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
		kills_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		kills_lbl.add_theme_constant_override("outline_size", 4)
		row.add_child(kills_lbl)
		_score_box.add_child(row)


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

	return {"box": box, "arrow": arrow, "icon": icon, "name": name_lbl, "num": num}


func _update_row(row: Dictionary, w: int, active: bool) -> void:
	var arrow: Label = row["arrow"]
	var icon: TextureRect = row["icon"]
	var name_lbl: Label = row["name"]
	var num: Label = row["num"]
	var box: HBoxContainer = row["box"]

	if w < 0:
		arrow.self_modulate.a = 0.0
		icon.texture = null
		name_lbl.text = "empty"
		num.text = ""
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
		num.add_theme_font_size_override("font_size", 30)
	elif a == 0:
		num.text = "OUT OF AMMO"
		num.add_theme_font_size_override("font_size", 16)
	else:
		num.text = str(a)
		num.add_theme_font_size_override("font_size", 30)
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
	hints.offset_left = -960.0
	hints.offset_top = -62.0
	hints.offset_right = -28.0
	hints.offset_bottom = -28.0
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(hints)

	if Net.mode == Net.Mode.LOCAL:
		_add_hint(hints, ["LS"], "Aim")
		_add_hint(hints, ["RT"], "Fire")
		_add_hint(hints, ["X"], "Grab")
		_add_hint(hints, ["Y"], "Throw")
		_add_hint(hints, ["B"], "Swap")
		return
	_key1_label = _add_hint(hints, ["1"], "Shotgun")
	_add_hint(hints, ["2"], "Pistol")
	_add_hint(hints, ["E"], "Grab")
	_add_hint(hints, ["Q"], "Throw")
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
