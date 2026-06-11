# Attached to every level scene root: draws the obstacle blocks from
# their collision shapes, so visuals can never drift out of sync with
# physics. Boundary walls are skipped — the backdrop draws the hull
# band around the arena bounds.
extends Node2D

const FILL := Color(0.13, 0.15, 0.22)
const EDGE := Color(0.55, 0.65, 0.95)


func _draw() -> void:
	var obstacles := get_node_or_null("Obstacles")
	if obstacles == null:
		return
	for cs in obstacles.get_children():
		if not (cs is CollisionShape2D) or cs.shape == null:
			continue
		draw_set_transform(cs.position, cs.rotation, cs.scale)
		var shape: Shape2D = cs.shape
		if shape is RectangleShape2D:
			var size: Vector2 = (shape as RectangleShape2D).size
			draw_rect(Rect2(-size / 2.0, size), FILL)
			draw_rect(Rect2(-size / 2.0, size), EDGE, false, 3.0)
		elif shape is CircleShape2D:
			var r: float = (shape as CircleShape2D).radius
			draw_circle(Vector2.ZERO, r, FILL)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, EDGE, 3.0)
	draw_set_transform(Vector2.ZERO)
