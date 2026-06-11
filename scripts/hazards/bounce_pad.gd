# A directional fling strip: anything touching it gets shot out along
# the pad's +x axis at launch_speed — a hard set, not a nudge, so
# trajectories stay predictable. Applied by whichever machine simulates
# the body (like the vortex pull), so pads need no network traffic.
class_name BouncePad
extends Node2D

@export var size := Vector2(60, 480)  # depth along the fling, width across
@export var launch_speed := 1100.0

const COOLDOWN := 0.3
const BODY_PAD := 16.0

var _cooldowns := {}  # node instance id -> seconds left


func _physics_process(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	var dir := global_transform.x.normalized()
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_locally_controlled() and p.visible and _touching(p.global_position):
			_fling(p, dir, false)
	if not multiplayer.is_server():
		return
	var main := get_tree().current_scene
	if main == null:
		return
	for holder_name in ["Asteroids", "Pickups"]:
		var holder := main.get_node_or_null(holder_name)
		if holder == null:
			continue
		for body in holder.get_children():
			if body is RigidBody2D and not body.freeze and _touching(body.global_position):
				_fling(body, dir, true)


func _touching(point: Vector2) -> bool:
	var local := to_local(point)
	var half := size / 2.0 + Vector2.ONE * BODY_PAD
	return absf(local.x) <= half.x and absf(local.y) <= half.y


# The per-body cooldown refreshes while it stays on the pad, so a body
# resting against one fires once and re-arms only after it leaves.
func _fling(body: Node2D, dir: Vector2, rigid: bool) -> void:
	var key := body.get_instance_id()
	var fresh := not _cooldowns.has(key)
	_cooldowns[key] = COOLDOWN
	if not fresh:
		return
	if rigid:
		body.linear_velocity = dir * launch_speed
	else:
		body.velocity = dir * launch_speed
		if body.has_method("_add_shake"):
			body._add_shake(6.0)


func _draw() -> void:
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.16, 0.5, 0.3, 0.55))
	draw_rect(Rect2(-half, size), Color(0.25, 0.95, 0.55, 0.9), false, 2.5)
	# Chevrons pointing the way out.
	var s := minf(half.y * 0.5, 26.0)
	for i in 3:
		var x := lerpf(-half.x * 0.4, half.x * 0.9, i / 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, -s), Vector2(x + s, 0.0), Vector2(x, s)
		]), Color(0.25, 0.95, 0.55, 0.85))
