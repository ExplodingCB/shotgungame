extends Node2D

const WALL := 24.0

var _bounds := Rect2(-1600, -900, 3200, 1800)


func _ready() -> void:
	# The hull band hugs whatever level is loaded.
	var lh := get_node_or_null("../LevelHost")
	if lh != null:
		lh.level_loaded.connect(func() -> void:
			_bounds = lh.bounds
			queue_redraw())


func _draw() -> void:
	var arena := _bounds
	var frame := arena.grow(WALL)
	# Slight dark tint over the nebula so the action stays readable.
	draw_rect(frame, Color(0, 0, 0, 0.3))

	# Wall band, layered from dark base to a bright inner lip so it
	# reads as a solid hull edge instead of a flat outline.
	_frame_band(frame, arena, Color(0.1, 0.11, 0.17))
	_frame_band(arena.grow(WALL * 0.62), arena, Color(0.18, 0.21, 0.3))
	_frame_band(arena.grow(WALL * 0.3), arena, Color(0.26, 0.3, 0.43))
	_frame_band(arena.grow(3.0), arena, Color(0.55, 0.65, 0.95))

	# Soft glow bleeding from the walls into the arena, fading inward,
	# so the border blends into the space behind it.
	_frame_band(arena, arena.grow(-16.0), Color(0.45, 0.55, 1.0, 0.1))
	_frame_band(arena.grow(-16.0), arena.grow(-40.0), Color(0.45, 0.55, 1.0, 0.05))
	_frame_band(arena.grow(-40.0), arena.grow(-72.0), Color(0.45, 0.55, 1.0, 0.025))


# Fills the area between an outer and inner rect with four rects.
func _frame_band(outer: Rect2, inner: Rect2, color: Color) -> void:
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), color)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), color)
