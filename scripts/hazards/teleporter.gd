# One mouth of a paired portal: a ship that drifts into the ring pops
# out of the twin with its speed intact, redirected along the twin's +x
# facing (rotate the exit node to aim arrivals). Applied by whichever
# machine simulates the body, like the vortex pull and pad fling, so
# portals need no network traffic. Players only — rocks and pickups
# ignore them so the arena stays readable.
class_name Teleporter
extends Node2D

@export var twin_path: NodePath
@export var radius := 70.0

const COOLDOWN := 0.8
const MIN_EXIT_SPEED := 300.0  # a crawl still clears the twin's mouth

var _cooldowns := {}  # node instance id -> seconds left
var _spin := 0.0


func _physics_process(delta: float) -> void:
	_spin += delta * 1.6
	queue_redraw()
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	var twin := get_node_or_null(twin_path) as Teleporter
	if twin == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_locally_controlled() and p.visible:
			_try_send(p, twin)


# The per-body cooldown refreshes while it stays inside the ring, so an
# arrival re-arms only after it has fully left the twin's mouth.
func _try_send(p: Node2D, twin: Teleporter) -> void:
	if p.global_position.distance_to(global_position) > radius:
		return
	var key := p.get_instance_id()
	var fresh := not _cooldowns.has(key)
	_cooldowns[key] = COOLDOWN
	if not fresh:
		return
	var speed: float = maxf(p.velocity.length(), MIN_EXIT_SPEED)
	p.global_position = twin.global_position
	p.velocity = twin.global_transform.x.normalized() * speed
	twin._cooldowns[key] = COOLDOWN
	if p.has_method("_add_shake"):
		p._add_shake(5.0)


func _draw() -> void:
	# Dark throat with a cyan event-horizon ring.
	draw_circle(Vector2.ZERO, radius * 0.55, Color(0.02, 0.09, 0.12))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.2, 0.9, 1.0, 0.85), 3.0)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 48, Color(0.2, 0.9, 1.0, 0.25), 6.0)
	# Two counter-winding particle spirals falling into the throat.
	for i in 2:
		var t := _spin + i * PI
		for j in 10:
			var f := j / 10.0
			var r := lerpf(radius * 0.92, radius * 0.2, f)
			var a := t + f * 3.4
			draw_circle(Vector2(cos(a), sin(a)) * r, 2.0 + (1.0 - f) * 2.0,
					Color(0.4, 0.95, 1.0, 0.7 - 0.5 * f))
	# Exit chevron: arrivals at the twin launch along its +x.
	var s := radius * 0.28
	draw_colored_polygon(PackedVector2Array([
		Vector2(radius * 0.62, -s), Vector2(radius * 0.62 + s * 1.4, 0.0),
		Vector2(radius * 0.62, s),
	]), Color(0.2, 0.9, 1.0, 0.5))
