# Cargo crate adrift in a chamber: a shootable supply box. Breaks under
# fire and spills shell packs or repair orbs, occasionally a whole gun.
# Drawn flat, no sprite needed.
class_name DungeonCrate
extends RigidBody2D

const SIZE := 36.0
const HEALTH := 30.0
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")

var health := HEALTH

var _flash := 0.0
var _dead := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 7
	gravity_scale = 0.0
	can_sleep = false
	mass = 4.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * SIZE
	shape.shape = rect
	add_child(shape)
	linear_velocity = Vector2.from_angle(randf() * TAU) * randf_range(10.0, 40.0)
	angular_velocity = randf_range(-0.6, 0.6)
	rotation = randf() * TAU


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - 4.0 * delta, 0.0)
		queue_redraw()


func take_damage(amount: float, dir: Vector2, at: Vector2, _attacker_id := 0) -> void:
	if _dead:
		return
	health -= amount
	_flash = 1.0
	apply_impulse(dir * amount * 3.0, at - global_position)
	queue_redraw()
	if health <= 0.0:
		_dead = true
		_break_open()


func _break_open() -> void:
	var main := Arena.of(self)
	var fx := BREAK_EFFECT.instantiate()
	fx.scale = Vector2.ONE * 0.6
	fx.position = global_position
	main.add_child(fx)
	fx.reset_physics_interpolation()
	if randf() < 0.12 and main.has_method("spawn_weapon_pickup"):
		var kind := WeaponDB.roll_weapon(1)
		main.spawn_weapon_pickup(kind, int(WeaponDB.DATA[kind]["max_ammo"]),
				global_position, Vector2.from_angle(randf() * TAU) * 40.0,
				randf_range(-1.2, 1.2))
	else:
		var holder := main.get_node_or_null("Drops")
		if holder != null:
			for i in 1 + randi() % 2:
				var drop := DungeonDrop.new()
				drop.kind = DungeonDrop.Kind.SHELLS if randf() < 0.6 else DungeonDrop.Kind.REPAIR
				drop.position = global_position + Vector2.from_angle(randf() * TAU) * 14.0
				holder.add_child(drop)
	queue_free()


func _draw() -> void:
	var h := SIZE / 2.0
	var fill := Color(0.16, 0.17, 0.22).lerp(Color(0.6, 0.4, 0.3), _flash)
	var edge := Color(0.42, 0.44, 0.52)
	draw_rect(Rect2(-h, -h, SIZE, SIZE), fill)
	draw_rect(Rect2(-h, -h, SIZE, SIZE), edge, false, 2.0)
	# Cross straps so it reads as cargo, not a rock.
	draw_line(Vector2(-h, -h), Vector2(h, h), edge, 2.0)
	draw_line(Vector2(-h, h), Vector2(h, -h), edge, 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.62, 0.1))
