extends CharacterBody2D

enum Kind { BEHOLDER, EMISSARY }

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")

const DATA := {
	Kind.BEHOLDER: {
		"texture": preload("res://assets/spaceships/Beholder/Beholder.png"),
		"health": 40.0,
		"speed": 250.0,
		"accel": 320.0,
		"sprite_rot": 0.0,
		"scale": 1.4,
	},
	Kind.EMISSARY: {
		"texture": preload("res://assets/spaceships/Emissary/Emissary.png"),
		"health": 30.0,
		"speed": 180.0,
		"accel": 240.0,
		"sprite_rot": PI / 2.0,  # art faces up; rotate to face +x
		"scale": 1.4,
	},
}

const RAM_DAMAGE := 14.0
const RAM_COOLDOWN := 0.9
const FIRE_RANGE := 750.0
const FIRE_INTERVAL := 1.7
const ORBIT_DIST := 420.0
const HIT_KNOCKBACK := 3.0

signal died

@export_range(0, 1) var kind := 0

var health := 40.0
var max_health := 40.0
var _speed := 250.0
var _accel := 320.0
var _ram_cd := 0.0
var _fire_cd := randf_range(1.2, 2.2)

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	var d: Dictionary = DATA[kind]
	sprite.texture = d["texture"]
	sprite.rotation = d["sprite_rot"]
	sprite.scale = Vector2.ONE * float(d["scale"])
	health = d["health"]
	max_health = d["health"]
	_speed = d["speed"]
	_accel = d["accel"]
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	_ram_cd = maxf(_ram_cd - delta, 0.0)
	var target := _nearest_player()
	var desired := Vector2.ZERO
	if target != null:
		var to_target: Vector2 = target.global_position - global_position
		if kind == Kind.BEHOLDER:
			# Rammer: fly straight at the player.
			desired = to_target.normalized() * _speed
		else:
			# Gunner: hold orbit distance and strafe while shooting.
			var dir := to_target.normalized()
			var dist_err: float = clampf((to_target.length() - ORBIT_DIST) / 200.0, -1.0, 1.0)
			desired = dir * dist_err * _speed * 0.9 + dir.orthogonal() * _speed * 0.55
			_fire_cd -= delta
			if _fire_cd <= 0.0 and to_target.length() < FIRE_RANGE:
				_fire_cd = FIRE_INTERVAL
				_shoot(dir)
		rotation = lerp_angle(rotation, to_target.angle(), 6.0 * delta)

	velocity = velocity.move_toward(desired, _accel * delta)
	var collision := move_and_collide(velocity * delta)
	if collision:
		var col := collision.get_collider()
		if _ram_cd == 0.0 and col is Node2D and (col as Node2D).is_in_group("player") \
				and col.has_method("take_damage"):
			_ram_cd = RAM_COOLDOWN
			col.take_damage(RAM_DAMAGE, -collision.get_normal(), collision.get_position())
		velocity = velocity.bounce(collision.get_normal()) * 0.6


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("player"):
		var d: float = global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _shoot(dir: Vector2) -> void:
	var p := PROJECTILE_SCENE.instantiate()
	var excl: Array[RID] = [get_rid()]
	p.velocity = dir.rotated(randf_range(-0.06, 0.06)) * 430.0
	p.damage = 7.0
	p.lifetime = 2.2
	p.modulate = Color(0.45, 1.0, 0.9)
	p.exclude = excl
	p.position = global_position + dir * 32.0
	get_tree().current_scene.add_child(p)
	p.reset_physics_interpolation()


func take_damage(amount: float, dir: Vector2, _at: Vector2) -> void:
	health -= amount
	velocity += dir * amount * HIT_KNOCKBACK
	sprite.modulate = Color(1.0, 0.45, 0.4)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if health <= 0.0:
		var fx := BREAK_EFFECT.instantiate()
		fx.scale = Vector2.ONE * 0.7
		fx.position = global_position
		get_tree().current_scene.add_child(fx)
		fx.reset_physics_interpolation()
		died.emit()
		queue_free()
