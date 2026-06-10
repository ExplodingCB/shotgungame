extends Control

const ORANGE := Color(1.0, 0.62, 0.1)

var kind := "solo"


func _draw() -> void:
	var c := size / 2.0
	var w := 1.6
	match kind:
		"solo":  # crosshair
			draw_arc(c, 7.0, 0, TAU, 28, ORANGE, w, true)
			for a in 4:
				var dir := Vector2.RIGHT.rotated(a * PI / 2.0)
				draw_line(c + dir * 4.5, c + dir * 10.0, ORANGE, w, true)
			draw_circle(c, 1.6, ORANGE)
		"host":  # two players
			_person(c + Vector2(-4.5, 0.0))
			_person(c + Vector2(5.0, 1.5))
		"globe":
			draw_arc(c, 8.0, 0, TAU, 32, ORANGE, w, true)
			draw_line(c - Vector2(8, 0), c + Vector2(8, 0), ORANGE, w * 0.8, true)
			draw_set_transform(c, 0.0, Vector2(0.45, 1.0))
			draw_arc(Vector2.ZERO, 8.0, 0, TAU, 32, ORANGE, w * 0.8, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"power":
			draw_arc(c, 7.0, deg_to_rad(-60), deg_to_rad(240), 28, ORANGE, w, true)
			draw_line(c + Vector2(0, -9), c + Vector2(0, -1), ORANGE, w, true)


func _person(p: Vector2) -> void:
	draw_circle(p + Vector2(0, -3.5), 2.6, ORANGE)
	draw_arc(p + Vector2(0, 4.5), 4.6, PI, TAU, 16, ORANGE, 1.6, true)
