# A gravity well: constant pull toward the center that ramps up close
# in, with a lethal core. Each machine pulls the bodies it simulates —
# its own players, plus rocks and pickups on the server — so identical
# geometry needs no sync; core damage is server-authoritative like the
# shrink zone, checked against each ship's swept path every frame so no
# speed dives through the heart unburned. Projectiles are deliberately
# unaffected so aim stays readable.
class_name Vortex
extends Node2D

@export var radius := 450.0
@export var core_radius := 40.0
@export var pull := 1100.0  # acceleration at the dead center, px/s^2

const CORE_DAMAGE := 60.0
const REHIT := 0.5  # per-player burn cooldown, matches the old tick pace

var _spin := 0.0
var _prev := {}   # player instance id -> last global position
var _burnt := {}  # player instance id -> burn cooldown remaining


func _physics_process(delta: float) -> void:
	_spin += delta * 0.9
	queue_redraw()
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_locally_controlled() and p.visible:
			p.velocity += _accel(p.global_position) * delta
	if not multiplayer.is_server():
		return
	var main := Arena.of(self)
	if main == null:
		return
	for holder_name in ["Asteroids", "Pickups"]:
		var holder := main.get_node_or_null(holder_name)
		if holder == null:
			continue
		for body in holder.get_children():
			if body is RigidBody2D and not body.freeze:
				body.linear_velocity += _accel(body.global_position) * delta
	_sweep_core(delta)


# Linear falloff: noticeable at the rim, `pull` at the heart.
func _accel(at: Vector2) -> Vector2:
	var off := global_position - at
	var d := off.length()
	if d >= radius or d < 1.0:
		return Vector2.ZERO
	var k := 1.0 - d / radius
	return off / d * pull * k


# Burn any ship whose path since last frame passed through the core —
# a point-in-circle tick would let a fast dive skip clean across it.
func _sweep_core(delta: float) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var id: int = p.get_instance_id()
		var cur: Vector2 = p.global_position
		var prev: Vector2 = _prev.get(id, cur)
		_prev[id] = cur
		var cd: float = maxf(float(_burnt.get(id, 0.0)) - delta, 0.0)
		_burnt[id] = cd
		if not p.visible or cd > 0.0:
			continue
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(
				global_position, prev, cur)
		if near.distance_to(global_position) >= core_radius + 14.0:
			continue
		_burnt[id] = REHIT
		# Knock outward so a grazing pass has a chance to escape.
		var dir: Vector2 = (cur - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		p.take_damage(CORE_DAMAGE, dir, cur, 0)


func _draw() -> void:
	draw_circle(Vector2.ZERO, core_radius, Color(0.08, 0.02, 0.14))
	draw_arc(Vector2.ZERO, core_radius, 0.0, TAU, 32, Color(0.69, 0.42, 1.0, 0.9), 3.0)
	# Three particle spirals winding into the core.
	for i in 3:
		var t := _spin + i * TAU / 3.0
		for j in 14:
			var f := j / 14.0
			var r := lerpf(core_radius + 6.0, radius, f)
			var a := t + f * 2.6
			draw_circle(Vector2(cos(a), sin(a)) * r, 2.5 + (1.0 - f) * 2.0,
					Color(0.69, 0.42, 1.0, 0.55 * (1.0 - f) + 0.08))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.69, 0.42, 1.0, 0.10), 2.0)
