# The closing ring for round play: after a grace period the safe area
# contracts toward the arena center, and anyone caught outside takes
# steady damage (with a nudge back in). Damage-only — the walls and
# rocks stay put — so it just forces fights, never blocks movement.
class_name ShrinkZone
extends Node2D

const ARENA := Rect2(-1600, -900, 3200, 1800)
const GRACE := 15.0        # seconds before the ring starts moving
const SHRINK_TIME := 60.0  # seconds from full arena to MIN_SCALE
const MIN_SCALE := 0.3
const DPS := 6.0
const TICK := 0.5

var active := false
var rect := ARENA

var _t := 0.0
var _tick := 0.0


func _ready() -> void:
	z_index = 10
	reset()


func reset() -> void:
	active = false
	_t = 0.0
	rect = ARENA
	queue_redraw()


func start() -> void:
	active = true
	_t = 0.0
	_tick = TICK


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	var k := clampf((_t - GRACE) / SHRINK_TIME, 0.0, 1.0)
	var s := lerpf(1.0, MIN_SCALE, k)
	rect = Rect2(ARENA.get_center() - ARENA.size * s / 2.0, ARENA.size * s)
	queue_redraw()
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_damage_outside()


func _damage_outside() -> void:
	if not multiplayer.is_server():
		return
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not p.visible:
			continue
		if rect.has_point(p.global_position):
			continue
		var dir: Vector2 = p.global_position.direction_to(rect.get_center())
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		p.take_damage(DPS * TICK, dir, p.global_position, 0)


func _draw() -> void:
	if not active or rect.size >= ARENA.size:
		return
	var outer := ARENA.grow(240.0)
	var fill := Color(1.0, 0.2, 0.12, 0.12)
	# Four rects tile everything outside the safe area.
	draw_rect(Rect2(outer.position,
			Vector2(outer.size.x, rect.position.y - outer.position.y)), fill)
	draw_rect(Rect2(Vector2(outer.position.x, rect.end.y),
			Vector2(outer.size.x, outer.end.y - rect.end.y)), fill)
	draw_rect(Rect2(Vector2(outer.position.x, rect.position.y),
			Vector2(rect.position.x - outer.position.x, rect.size.y)), fill)
	draw_rect(Rect2(Vector2(rect.end.x, rect.position.y),
			Vector2(outer.end.x - rect.end.x, rect.size.y)), fill)
	draw_rect(rect, Color(1.0, 0.35, 0.2, 0.7), false, 3.0)
