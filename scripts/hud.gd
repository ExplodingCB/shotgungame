extends Control

const ACCENT := Color(1.0, 0.62, 0.1)
const ALERT := Color(1.0, 0.38, 0.28)
const TEXT_BRIGHT := Color(0.96, 0.96, 1.0)
const TEXT_DIM := Color(0.66, 0.68, 0.76)
const HUD_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

# Control hints melt away once you've had a moment to read them.
const HINT_FADE_AFTER := 9.0

var player: Node = null

var _rows: Array[Dictionary] = []
var _key1_label: Label
var _grenade_label: Label
var _wave_label: Label
var _host_info_label: Label
var _score_box: VBoxContainer
var _score_key := ""

# Couch mode: one compact panel per local player along the bottom.
var _local_box: HBoxContainer
var _local_rows := {}  # player node name -> row widgets
var _round_banner: Label

# Event feed (joins, leaves, kills) under the host info line, plus the
# big center death text: a YOU DIED flash on warm-up deaths, or the
# persistent ELIMINATED/spectate label while sitting out a round.
var _feed_box: VBoxContainer
var _death_label: Label
var _death_flash := 0.0  # seconds left on a transient flash
var _spotlight: TextureRect


# House style: display font, soft shadow, thin outline — readable over
# gameplay without boxing anything in.
func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", HUD_FONT)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Net.mode == Net.Mode.LOCAL:
		_build_local_box()
	else:
		_build_weapon_panel()
	if Net.mode != Net.Mode.SOLO:
		_build_round_banner()
	_build_hints()
	_build_wave_label()
	_build_host_info()
	_build_scoreboard()
	_build_feed()
	if Net.mode != Net.Mode.LOCAL:
		_build_death_label()


# Big center text for round flow: countdown, FIGHT!, winner flashes.
# A soft radial spotlight glows behind it — light, not a box.
func _build_round_banner() -> void:
	_spotlight = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.30))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 256
	gtex.height = 128
	_spotlight.texture = gtex
	_spotlight.stretch_mode = TextureRect.STRETCH_SCALE
	_spotlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spotlight.anchor_left = 0.5
	_spotlight.anchor_right = 0.5
	_spotlight.offset_left = -640.0
	_spotlight.offset_right = 640.0
	_spotlight.offset_top = 10.0
	_spotlight.offset_bottom = 330.0
	_spotlight.visible = false
	add_child(_spotlight)

	_round_banner = _label("", 54, TEXT_BRIGHT)
	_round_banner.visible = false
	_round_banner.anchor_left = 0.5
	_round_banner.anchor_right = 0.5
	_round_banner.anchor_top = 0.0
	_round_banner.offset_left = -500.0
	_round_banner.offset_right = 500.0
	_round_banner.offset_top = 84.0
	_round_banner.offset_bottom = 240.0
	_round_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bf := FontVariation.new()
	bf.base_font = HUD_FONT
	bf.set_spacing(TextServer.SPACING_GLYPH, 6)
	_round_banner.add_theme_font_override("font", bf)
	add_child(_round_banner)


func _update_round_banner() -> void:
	var main := Arena.of(self)
	var rm: Node = main.round_manager if main != null and "round_manager" in main else null
	if rm == null or str(rm.banner_text) == "":
		_round_banner.visible = false
		_spotlight.visible = false
		return
	_round_banner.visible = true
	_round_banner.text = rm.banner_text
	_round_banner.add_theme_color_override("font_color", rm.banner_color)
	_spotlight.visible = true
	_spotlight.modulate = rm.banner_color


# Top-left line the host shares with friends: UPnP progress, then the
# room code to join with (plus whether it reaches the internet or LAN).
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
	var text := Net.host_info
	if Net.room_code != "":
		text = "ROOM  %s" % Net.room_code
		if Net.host_info != "":
			text += "\n" + Net.host_info
	_host_info_label.text = text
	_host_info_label.visible = Net.mode == Net.Mode.HOST and text != ""


func _exit_tree() -> void:
	if Net.host_info_changed.is_connected(_update_host_info):
		Net.host_info_changed.disconnect(_update_host_info)


# --- Event feed and death text ---------------------------------------

func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.position = Vector2(28, 54)
	_feed_box.add_theme_constant_override("separation", 2)
	add_child(_feed_box)


# Posts a fading line to the event feed: joins, leaves, kills.
func notify(text: String, color: Color = TEXT_BRIGHT) -> void:
	while _feed_box.get_child_count() >= 6:
		_feed_box.get_child(0).free()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 4)
	_feed_box.add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_interval(3.4)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.9)
	tween.tween_callback(lbl.queue_free)


func _build_death_label() -> void:
	_death_label = _label("", 34, ALERT)
	_death_label.visible = false
	_death_label.anchor_left = 0.5
	_death_label.anchor_right = 0.5
	_death_label.offset_left = -500.0
	_death_label.offset_right = 500.0
	_death_label.offset_top = 252.0
	_death_label.offset_bottom = 360.0
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bf := FontVariation.new()
	bf.base_font = HUD_FONT
	bf.set_spacing(TextServer.SPACING_GLYPH, 5)
	_death_label.add_theme_font_override("font", bf)
	add_child(_death_label)


# Short center-screen flash for deaths that respawn (warm-up, solo).
func flash_death(text: String) -> void:
	if _death_label == null:
		return
	_death_label.text = text
	_death_flash = 2.2


# While the local ship sits out a round, the label stays up and names
# whoever the spectator camera is riding; otherwise it runs the flash
# timer down and hides.
func _update_death_label(delta: float) -> void:
	if player != null and is_instance_valid(player) and player._dead:
		_death_flash = 0.0
		_death_label.visible = true
		_death_label.modulate.a = 1.0
		var text := "ELIMINATED"
		var main := Arena.of(self)
		if main != null and main.has_method("spectate_target"):
			var t: Node2D = main.spectate_target()
			if t != null:
				text += "\nwatching P%d  —  click to switch" % (int(t.slot) + 1)
		_death_label.text = text
		return
	if _death_flash > 0.0:
		_death_flash -= delta
		_death_label.visible = true
		_death_label.modulate.a = clampf(_death_flash / 0.7, 0.0, 1.0)
	else:
		_death_label.visible = false


func _build_wave_label() -> void:
	_wave_label = _label("", 22, ACCENT)
	_wave_label.visible = false
	_wave_label.anchor_left = 0.5
	_wave_label.anchor_right = 0.5
	_wave_label.offset_left = -300.0
	_wave_label.offset_right = 300.0
	_wave_label.offset_top = 18.0
	_wave_label.offset_bottom = 56.0
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_wave_label)


func _process(delta: float) -> void:
	_update_scoreboard()
	if _death_label != null:
		_update_death_label(delta)
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
	# Third slot only exists once the dungeon AUX RACK upgrade is fitted.
	var prim_b: int = int(player.primary_b)
	var has_rack: bool = bool(player.second_slot) or prim_b >= 0
	(_rows[2]["box"] as Control).visible = has_rack
	if has_rack:
		_update_row(_rows[2], prim_b, prim_b >= 0 and active == prim_b)
	if prim >= 0:
		_key1_label.text = WeaponDB.DATA[prim]["name"]
	_grenade_label.visible = int(player.grenades) > 0
	_grenade_label.text = "✚ %d   ·   G" % int(player.grenades)
	_update_wave_label()
	if _round_banner != null:
		_update_round_banner()
	queue_redraw()


# --- Couch-mode weapon strips, one per local player ------------------

func _build_local_box() -> void:
	_local_box = HBoxContainer.new()
	_local_box.anchor_left = 0.0
	_local_box.anchor_right = 1.0
	_local_box.anchor_top = 1.0
	_local_box.anchor_bottom = 1.0
	_local_box.offset_top = -76.0
	_local_box.offset_bottom = -26.0
	_local_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_local_box.add_theme_constant_override("separation", 72)
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
		var nades: Label = row["nades"]
		nades.visible = int(p.grenades) > 0
		nades.text = "✚%d" % int(p.grenades)
		var box: HBoxContainer = row["box"]
		box.modulate = Color(1, 1, 1, 1.0 if p.visible else 0.3)


func _build_local_row(p: Node) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_local_box.add_child(box)

	var color: Color = p.COLORS[p.color_idx % p.COLORS.size()]
	box.add_child(_label("P%d" % (int(p.slot) + 1), 24, color))

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(76, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)

	var num := _label("", 26, TEXT_BRIGHT)
	box.add_child(num)

	var nades := _label("", 18, Color(0.5, 1.0, 0.45))
	nades.visible = false
	box.add_child(nades)

	return {"box": box, "icon": icon, "num": num, "nades": nades}


# --- Kill scoreboard (multiplayer only), top-right ------------------

func _build_scoreboard() -> void:
	_score_box = VBoxContainer.new()
	_score_box.anchor_left = 1.0
	_score_box.anchor_right = 1.0
	_score_box.offset_left = -320.0
	_score_box.offset_right = -36.0
	_score_box.offset_top = 22.0
	_score_box.add_theme_constant_override("separation", 8)
	_score_box.visible = false
	add_child(_score_box)


func _update_scoreboard() -> void:
	var main := Arena.of(self)
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
			"num": int(p.slot) + 1,
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
	for e in entries:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 14)
		var swatch := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = e["color"]
		sb.set_corner_radius_all(5)
		swatch.add_theme_stylebox_override("panel", sb)
		swatch.custom_minimum_size = Vector2(19, 19)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		row.add_child(_label("P%d" % e["num"], 24, e["color"]))
		if int(e["wins"]) >= 0:
			row.add_child(_label("★%d" % e["wins"], 22, ACCENT))
		var kills_lbl := _label(str(e["kills"]), 26, TEXT_BRIGHT)
		kills_lbl.custom_minimum_size = Vector2(44, 0)
		kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(kills_lbl)
		_score_box.add_child(row)


func _update_wave_label() -> void:
	var main := Arena.of(self)
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
	# Hidden until the dungeon AUX RACK upgrade adds a second slot.
	_rows.append(_build_row(panel))
	(_rows[2]["box"] as Control).visible = false
	# Frag count under the gun rows; hidden until you're carrying any.
	_grenade_label = _label("", 18, Color(0.5, 1.0, 0.45))
	_grenade_label.visible = false
	panel.add_child(_grenade_label)


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

	var num := _label("", 28, TEXT_BRIGHT)
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
		num.add_theme_font_size_override("font_size", 28)
	elif a == 0:
		num.text = "OUT"
		num.add_theme_font_size_override("font_size", 18)
	else:
		num.text = str(a)
		num.add_theme_font_size_override("font_size", 28)
	var num_color := TEXT_BRIGHT if active else TEXT_DIM
	if a == 0:
		num_color = ALERT
	num.add_theme_color_override("font_color", num_color)
	box.modulate = Color(1, 1, 1, 1.0 if active else 0.62)


# Control instructions along the bottom: pad players read sprite
# prompts from the Xbox button library, keyboard players read keycaps.
# Couch mode shows the pad strip (plus a keyboard strip if a KB+M
# player joined); solo/online play is keyboard+mouse. The whole block
# fades out after a few seconds so the arena stays clean.
func _build_hints() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.anchor_left = 1.0
	rows.anchor_right = 1.0
	rows.anchor_top = 1.0
	rows.anchor_bottom = 1.0
	rows.offset_left = -1100.0
	rows.offset_top = -110.0
	rows.offset_right = -28.0
	rows.offset_bottom = -28.0
	rows.alignment = BoxContainer.ALIGNMENT_END
	rows.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rows.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(rows)

	var fade := rows.create_tween()
	fade.tween_interval(HINT_FADE_AFTER)
	fade.tween_property(rows, "modulate:a", 0.0, 1.2)
	fade.tween_callback(rows.hide)

	if Net.mode == Net.Mode.LOCAL:
		var pads := _hint_row(rows)
		_add_pad_hint(pads, ["ls"], "Aim")
		_add_pad_hint(pads, ["rt"], "Fire")
		_add_pad_hint(pads, ["x"], "Grab")
		_add_pad_hint(pads, ["y"], "Throw")
		_add_pad_hint(pads, ["a"], "Nade")
		_add_pad_hint(pads, ["b"], "Swap")
		_add_pad_hint(pads, ["lb", "rb"], "Spin")
		if Net.local_roster.has(-1):
			var kb := _hint_row(rows)
			_add_hint(kb, ["Mouse"], "Aim")
			_add_hint(kb, ["LMB"], "Fire")
			_add_hint(kb, ["E"], "Grab")
			_add_hint(kb, ["Q"], "Throw")
			_add_hint(kb, ["G"], "Nade")
			_add_hint(kb, ["Wheel"], "Swap")
			_add_hint(kb, ["A", "D"], "Spin", "/")
		return
	var hints := _hint_row(rows)
	_key1_label = _add_hint(hints, ["1"], "Shotgun")
	_add_hint(hints, ["2"], "Pistol")
	_add_hint(hints, ["LMB"], "Fire")
	_add_hint(hints, ["E"], "Grab")
	_add_hint(hints, ["Q"], "Throw")
	_add_hint(hints, ["G"], "Nade")
	_add_hint(hints, ["A", "D"], "Spin", "/")


func _hint_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(row)
	return row


func _add_hint(parent: Control, keys: Array, label: String, sep := "") -> Label:
	var first := true
	for k in keys:
		if not first and sep != "":
			var s := Label.new()
			s.text = sep
			s.add_theme_color_override("font_color", TEXT_DIM)
			s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			parent.add_child(s)
		parent.add_child(ButtonIcons.keycap(k))
		first = false
	return _hint_label(parent, label)


# Pad hints use the sprite library instead of keycaps.
func _add_pad_hint(parent: Control, icons: Array, label: String) -> Label:
	for name in icons:
		parent.add_child(ButtonIcons.icon(name, 32.0))
	return _hint_label(parent, label)


func _hint_label(parent: Control, label: String) -> Label:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	parent.add_child(spacer)
	return lbl
