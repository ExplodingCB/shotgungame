# Room border and interior hull blocks for dungeon chambers: same
# hull-edge look as the arena backdrop, sized to whatever the generator
# just built. dungeon_main sets rect/blocks/tint each room and calls
# queue_redraw(). tint is a subtle per-theme cast over the hull colors,
# kept close to white so rooms shift mood without turning gaudy.
extends Node2D

const WALL := 24.0

var rect := Rect2(-1300, -750, 2600, 1500)
var blocks: Array = []
var tint := Color(1, 1, 1)


func _draw() -> void:
	var frame := rect.grow(WALL)
	draw_rect(frame, Color(0, 0, 0, 0.3))

	_frame_band(frame, rect, _c(Color(0.1, 0.11, 0.17)))
	_frame_band(rect.grow(WALL * 0.62), rect, _c(Color(0.18, 0.21, 0.3)))
	_frame_band(rect.grow(WALL * 0.3), rect, _c(Color(0.26, 0.3, 0.43)))
	_frame_band(rect.grow(3.0), rect, _c(Color(0.55, 0.65, 0.95)))

	_frame_band(rect, rect.grow(-16.0), _c(Color(0.45, 0.55, 1.0, 0.1)))
	_frame_band(rect.grow(-16.0), rect.grow(-40.0), _c(Color(0.45, 0.55, 1.0, 0.05)))
	_frame_band(rect.grow(-40.0), rect.grow(-72.0), _c(Color(0.45, 0.55, 1.0, 0.025)))

	# Interior hull slabs: solid, flat, edged like the outer wall.
	for b in blocks:
		var block := b as Rect2
		draw_rect(block.grow(WALL * 0.3), _c(Color(0.1, 0.11, 0.17)))
		draw_rect(block, _c(Color(0.18, 0.21, 0.3)))
		draw_rect(block, _c(Color(0.55, 0.65, 0.95)), false, 2.0)


func _c(base: Color) -> Color:
	return Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)


# Fills the area between an outer and inner rect with four rects.
func _frame_band(outer: Rect2, inner: Rect2, color: Color) -> void:
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), color)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), color)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), color)
