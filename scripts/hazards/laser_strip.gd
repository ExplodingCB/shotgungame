# A kill-laser running from this node's origin along +x for `length`.
# Blinks on a warn -> lethal -> off cycle unless always_on. Every peer
# animates its own clock from the moment the fight goes live (identical
# geometry and timings everywhere), while damage ticks only on the
# server so visual drift can't cause phantom kills.
class_name LaserStrip
extends Node2D

enum Beam { OFF, WARN, ON }

@export var length := 800.0
@export var always_on := false
@export var warn_time := 0.6
@export var on_time := 1.4
@export var off_time := 1.5
@export var phase_offset := 0.0

const PLAYER_DAMAGE := 30.0
const ROCK_DAMAGE := 10.0
const TICK := 0.25
const WIDTH := 10.0

var _t := 0.0
var _tick := 0.0


func _physics_process(delta: float) -> void:
	queue_redraw()
	if not _running():
		_t = 0.0
		return
	_t += delta
	if multiplayer.is_server() and state() == Beam.ON:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			_zap()


# Lasers idle outside the fight (warm-up, countdown, round end) so
# nobody dies between rounds. With no round manager (solo, tests) they
# just run.
func _running() -> bool:
	var main := get_tree().current_scene
	if main == null or not ("round_manager" in main) or main.round_manager == null:
		return true
	return main.round_manager.fight_active()


func state() -> int:
	if always_on:
		return Beam.ON
	if _t <= 0.0:
		return Beam.OFF
	var cycle := warn_time + on_time + off_time
	var t := fposmod(_t + phase_offset, cycle)
	if t < warn_time:
		return Beam.WARN
	if t < warn_time + on_time:
		return Beam.ON
	return Beam.OFF


func _zap() -> void:
	var seg := SegmentShape2D.new()
	seg.a = Vector2.ZERO
	seg.b = Vector2(length, 0.0)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = seg
	q.transform = global_transform
	q.collision_mask = 3  # world bodies + ships
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit["collider"]
		if c is StaticBody2D or not (c is Node2D) or not c.has_method("take_damage"):
			continue
		# Shove perpendicular to the beam, away from whichever side the
		# body is on, so the burn also pushes you off the line.
		var side := signf(to_local((c as Node2D).global_position).y)
		if side == 0.0:
			side = 1.0
		var dir := (global_transform.y * side).normalized()
		var amount := PLAYER_DAMAGE if (c as Node).is_in_group("player") else ROCK_DAMAGE
		c.take_damage(amount, dir, (c as Node2D).global_position, 0)


func _draw() -> void:
	var to := Vector2(length, 0.0)
	match state():
		Beam.WARN:
			var a := 0.25 + 0.2 * sin(_t * 40.0)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.3, 0.32, a), 2.0)
		Beam.ON:
			draw_line(Vector2.ZERO, to, Color(1.0, 0.25, 0.3, 0.25), WIDTH * 3.2)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.45, 0.45, 0.95), WIDTH)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.9, 0.9, 0.9), WIDTH * 0.35)
		_:
			pass
	# Emitter studs at both ends, visible even while the beam rests.
	for p in [Vector2.ZERO, to]:
		draw_circle(p, 7.0, Color(0.55, 0.1, 0.14))
		draw_circle(p, 4.0, Color(1.0, 0.35, 0.35))
