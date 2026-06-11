# A two-frag supply pack drifting in space. Touch-collected like the
# Nano-Medkit — no grab key, no weapon swap — topping the toucher up to
# the carry cap. Server-simulated like every pickup.
extends RigidBody2D

const SPEED_CAP := 180.0
const TOUCH_RADIUS := 60.0
const COUNT := 2
const TEX := preload("res://assets/grenades/white-grenade.png")

var init_velocity := Vector2.ZERO
var init_spin := 0.0
var _collected := false
var _t := randf() * TAU


func _ready() -> void:
	add_to_group("grenade_packs")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
			p.give_grenades(COUNT)
			queue_free()
			return


# Two frags drifting side by side, bare like every other pickup.
func _draw() -> void:
	for x in [-13.0, 13.0]:
		draw_texture_rect(TEX, Rect2(x - 11, -16, 22, 32), false)
