# The Nano-Medkit: a legendary field heal drifting in space. Fly over
# it and it slams you back to full and beyond — an overheal that decays
# back down (see player.gd). Server-simulated like weapon pickups, and
# collected by touch rather than the grab key so a desperate dash
# through the crossfire just works.
extends RigidBody2D

const SPEED_CAP := 180.0
const TOUCH_RADIUS := 60.0
const GOLD := Color(1.0, 0.65, 0.15)

var init_velocity := Vector2.ZERO
var init_spin := 0.0
var _collected := false
var _t := randf() * TAU


func _ready() -> void:
	add_to_group("medkits")
	if multiplayer.is_server():
		linear_velocity = init_velocity
		angular_velocity = init_spin
	else:
		# Clients display the server's simulation via the synchronizer.
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true


func _process(delta: float) -> void:
	_t += delta * 3.0
	modulate.a = 0.85 + 0.15 * sin(_t)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if freeze or not multiplayer.is_server():
		return
	var speed := linear_velocity.length()
	if speed > SPEED_CAP:
		linear_velocity *= maxf(SPEED_CAP / speed, 1.0 - 3.0 * delta)
	_check_touch()


func _check_touch() -> void:
	if _collected:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if not p.visible:
			continue
		if p.global_position.distance_to(global_position) < TOUCH_RADIUS:
			_collected = true
			p.give_overheal()
			Explosions.boom(self, global_position)
			queue_free()
			return


# Legendary-gold glow ring around a white kit with a gold cross.
func _draw() -> void:
	draw_circle(Vector2.ZERO, 34.0, Color(GOLD, 0.16))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 48, Color(GOLD, 0.55), 2.5)
	draw_rect(Rect2(-14, -11, 28, 22), Color(0.92, 0.94, 0.97))
	draw_rect(Rect2(-14, -11, 28, 22), Color(GOLD, 0.9), false, 2.0)
	draw_rect(Rect2(-3.5, -8, 7, 16), GOLD)
	draw_rect(Rect2(-8, -3.5, 16, 7), GOLD)
