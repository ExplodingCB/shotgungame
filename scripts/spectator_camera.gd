# Death view for online rounds: when your ship is eliminated, this
# camera takes over and rides whoever is still fighting; clicking (or
# any pad button) hops to the next survivor. main.set_spectating turns
# it on at elimination and off again when revive() hands the player
# camera back.
class_name SpectatorCamera
extends Camera2D

var target: Node2D = null


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0
	_apply_limits()
	var lh := get_node_or_null("../LevelHost")
	if lh != null:
		lh.level_loaded.connect(_apply_limits)


# Pin the view inside the active level, like the player cameras do.
func _apply_limits() -> void:
	var b := Rect2(-1600, -900, 3200, 1800)
	var lh := get_node_or_null("../LevelHost")
	if lh != null:
		b = lh.bounds
	limit_left = int(b.position.x) - 24
	limit_top = int(b.position.y) - 24
	limit_right = int(b.end.x) + 24
	limit_bottom = int(b.end.y) + 24


func _process(_delta: float) -> void:
	if not enabled:
		return
	if target == null or not is_instance_valid(target) or not target.visible:
		target = _next_target(null)
	if target != null:
		global_position = target.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		target = _next_target(target)


# Survivors in slot order; `after` picks the one following it so clicks
# cycle through everyone left.
func _next_target(after: Node2D) -> Node2D:
	var pool: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.visible:
			pool.append(p)
	if pool.is_empty():
		return null
	pool.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	if after == null:
		return pool[0]
	var idx := pool.find(after)
	return pool[(idx + 1) % pool.size()]
