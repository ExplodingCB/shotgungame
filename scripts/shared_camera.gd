# Couch-mode camera: one view framing every living player, panning and
# zooming as the fight spreads out or tightens up. Replaces the
# per-player follow cameras that LOCAL mode disables.
class_name SharedCamera
extends Camera2D

const MARGIN := 250.0
const MIN_ZOOM := 0.5   # never wider than the whole arena
const MAX_ZOOM := 1.0   # never tighter than a 1:1 view
const ZOOM_SPEED := 4.0
const PAN_SPEED := 6.0
const SHAKE_DECAY := 30.0

var shake := 0.0


func _ready() -> void:
	_apply_limits()
	var lh := get_node_or_null("../LevelHost")
	if lh != null:
		lh.level_loaded.connect(_apply_limits)
	make_current()


# Pin the view to the active level (24px of wall band slack).
func _apply_limits() -> void:
	var b := Rect2(-1600, -900, 3200, 1800)
	var lh := get_node_or_null("../LevelHost")
	if lh != null:
		b = lh.bounds
	limit_left = int(b.position.x) - 24
	limit_top = int(b.position.y) - 24
	limit_right = int(b.end.x) + 24
	limit_bottom = int(b.end.y) + 24


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func _process(delta: float) -> void:
	var box := _players_box()
	if box.size != Vector2.ZERO or box.position != Vector2.ZERO:
		box = box.grow(MARGIN)
		var vp := get_viewport_rect().size
		var z := clampf(minf(vp.x / box.size.x, vp.y / box.size.y), MIN_ZOOM, MAX_ZOOM)
		zoom = zoom.lerp(Vector2.ONE * z, minf(ZOOM_SPEED * delta, 1.0))
		position = position.lerp(box.get_center(), minf(PAN_SPEED * delta, 1.0))

	shake = maxf(shake - SHAKE_DECAY * delta, 0.0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake


# Bounding box of everyone still in the fight (eliminated players are
# hidden, so they stop steering the camera).
func _players_box() -> Rect2:
	var box := Rect2()
	var first := true
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not p.visible:
			continue
		if first:
			box = Rect2(p.global_position, Vector2.ZERO)
			first = false
		else:
			box = box.expand(p.global_position)
	return box
