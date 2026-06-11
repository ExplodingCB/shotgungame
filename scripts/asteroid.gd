extends RigidBody2D

const VARIANTS := [
	{"texture": preload("res://assets/asteroids/Asteroids_01_small.png"), "radius": 11.0, "mass": 3.0, "health": 25.0},
	{"texture": preload("res://assets/asteroids/Asteroids_01_medium.png"), "radius": 22.0, "mass": 8.0, "health": 60.0},
	{"texture": preload("res://assets/asteroids/Asteroids_01_large.png"), "radius": 45.0, "mass": 20.0, "health": 140.0},
	{"texture": preload("res://assets/asteroids/Asteroids_01_huge.png"), "radius": 100.0, "mass": 60.0, "health": 350.0},
]

const MAX_DRIFT_SPEED := 110.0
const MAX_SPIN := 1.8
const HIT_PUSH := 4.0
const SPEED_CAP := 240.0
const SPIN_CAP := 3.0

@export_range(-1, 3) var variant := -1  # -1 = random

# Volatile rocks glow orange and detonate when destroyed, damaging and
# launching everything nearby — including other volatiles, so a tight
# cluster chains. Rolled at spawn and replicated through spawn data.
var volatile := false
var init_velocity := Vector2.ZERO  # zero = random drift

var health := 25.0
var _radius := 11.0
var _detonating := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var v: Dictionary = VARIANTS[variant] if variant >= 0 else VARIANTS[randi() % VARIANTS.size()]
	sprite.texture = v["texture"]
	var circle := CircleShape2D.new()
	circle.radius = v["radius"]
	shape.shape = circle
	mass = v["mass"]
	health = v["health"]
	_radius = v["radius"]
	rotation = randf() * TAU
	if volatile:
		var glow := VolatileGlow.new()
		glow.radius = _radius + 9.0
		glow.z_index = -1
		add_child(glow)
	if multiplayer.is_server():
		if init_velocity != Vector2.ZERO:
			linear_velocity = init_velocity
		else:
			linear_velocity = Vector2.from_angle(randf() * TAU) * randf_range(30.0, MAX_DRIFT_SPEED)
		angular_velocity = randf_range(-MAX_SPIN, MAX_SPIN)
	else:
		# Clients display the server's simulation via the synchronizer.
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if freeze or not multiplayer.is_server():
		return
	# Soft speed cap: rocks never stop, but runaway energy from shoves
	# and blasts bleeds off over a few frames instead of accumulating.
	var speed := linear_velocity.length()
	if speed > SPEED_CAP:
		linear_velocity *= maxf(SPEED_CAP / speed, 1.0 - 3.0 * delta)
	angular_velocity = clampf(angular_velocity, -SPIN_CAP, SPIN_CAP)


func take_damage(amount: float, dir: Vector2, at: Vector2, attacker_id := 0) -> void:
	_flash()
	if multiplayer.is_server():
		_server_damage(amount, dir, at, attacker_id)
	else:
		_server_damage.rpc_id(1, amount, dir, at, attacker_id)


@rpc("any_peer", "call_remote", "reliable")
func _server_damage(amount: float, dir: Vector2, at: Vector2, attacker_id := 0) -> void:
	if not multiplayer.is_server():
		return
	if _detonating:
		return  # the fuse is already lit
	health -= amount
	apply_impulse(dir * amount * HIT_PUSH, at - global_position)
	if health <= 0.0:
		if volatile:
			# Short fuse so chain reactions ripple instead of popping
			# all at once. Freeze in place so the killing blow's
			# knockback can't carry the blast away from its cluster.
			# Kills credit whoever lit the first rock.
			_detonating = true
			freeze = true
			sprite.modulate = Color(1.0, 0.75, 0.3)
			get_tree().create_timer(0.12).timeout.connect(_detonate.bind(attacker_id))
			return
		var main: Node = Arena.of(self)
		main.spawn_break_fx.rpc(global_position, clampf(_radius / 30.0, 0.5, 3.0), false)
		queue_free()


func _detonate(attacker_id: int) -> void:
	if not is_inside_tree():
		return
	var radius := _radius * 4.0 + 60.0
	var main: Node = Arena.of(self)
	main.spawn_break_fx.rpc(global_position, clampf(radius / 70.0, 1.0, 3.5), true)
	Explosions.blast(self, global_position, radius, 30.0, attacker_id, true, self, false)
	queue_free()


func _flash() -> void:
	if _detonating:
		return
	sprite.modulate = Color(1.0, 0.5, 0.4)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


# Pulsing warning ring so volatile rocks read from across the arena.
class VolatileGlow extends Node2D:
	var radius := 20.0
	var _t := randf() * TAU

	func _process(delta: float) -> void:
		_t += delta * 5.0
		queue_redraw()

	func _draw() -> void:
		var a := 0.4 + 0.25 * sin(_t)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.45, 0.05, a * 0.25))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1.0, 0.55, 0.1, a), 3.0)
