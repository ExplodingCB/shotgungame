extends Node2D

const ARENA := Rect2(-1600, -900, 3200, 1800)
const WALL := 24.0


func _draw() -> void:
	var frame := ARENA.grow(WALL)
	# Slight dark tint over the nebula so the action stays readable.
	draw_rect(frame, Color(0, 0, 0, 0.3))

	# Wall band, layered from dark base to a bright inner lip so it
	# reads as a solid hull edge instead of a flat outline.
	_frame_band(frame, ARENA, Color(0.1, 0.11, 0.17))
	_frame_band(ARENA.grow(WALL * 0.62), ARENA, Color(0.18, 0.21, 0.3))
	_frame_band(ARENA.grow(WALL * 0.3), ARENA, Color(0.26, 0.3, 0.43))
	_frame_band(ARENA.grow(3.0), ARENA, Color(0.55, 0.65, 0.95))

	# Soft glow bleeding from the walls into the arena, fading inward,
	# so the border blends into the space behind it.
	_frame_band(ARENA, ARENA.grow(-16.0), Color(0.45, 0.55, 1.0, 0.1))
	_frame_band(ARENA.grow(-16.0), ARENA.grow(-40.0), Color(0.45, 0.55, 1.0, 0.05))
	_frame_band(ARENA.grow(-40.0), ARENA.grow(-72.0), Color(0.45, 0.55, 1.0, 0.025))


# Fills the area between an outer and inner rect with four rects.
func _frame_band(outer: Rect2, inner: Rect2, color: Color) -> void:
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), color)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), color)
