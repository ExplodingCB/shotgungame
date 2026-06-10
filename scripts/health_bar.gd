extends Node2D

const WIDTH := 44.0
const HEIGHT := 5.0
const Y_OFFSET := -40.0

@onready var player: Node = get_parent()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var pct: float = clampf(player.health / player.max_health, 0.0, 1.0)
	if pct >= 1.0:
		return  # hidden while at full health
	draw_rect(Rect2(-WIDTH / 2.0 - 1, Y_OFFSET - 1, WIDTH + 2, HEIGHT + 2), Color(0, 0, 0, 0.65))
	var fill := Color(1.0, 0.3, 0.2).lerp(Color(0.35, 1.0, 0.4), pct)
	draw_rect(Rect2(-WIDTH / 2.0, Y_OFFSET, WIDTH * pct, HEIGHT), fill)
