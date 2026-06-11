# A dead ship drifting in the dark: tough, inert, and worth cracking
# open. Breaks under sustained fire and always gives up a weapon plus
# some shells. The gray hull tint keeps it clearly distinct from the
# live (colored) enemies built from the same sprites.
class_name DungeonWreck
extends RigidBody2D

const HEALTH := 130.0
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const HULL := preload("res://assets/spaceships/Emissary/Emissary.png")

var health := HEALTH

var _dead := false
var _sprite: Sprite2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 7
	gravity_scale = 0.0
	can_sleep = false
	mass = 18.0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 38.0
	shape.shape = circle
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = HULL
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * 2.6
	_sprite.modulate = Color(0.42, 0.44, 0.5)
	add_child(_sprite)
	rotation = randf() * TAU
	linear_velocity = Vector2.from_angle(randf() * TAU) * randf_range(5.0, 25.0)
	angular_velocity = randf_range(-0.3, 0.3)


func take_damage(amount: float, dir: Vector2, at: Vector2, _attacker_id := 0) -> void:
	if _dead:
		return
	health -= amount
	apply_impulse(dir * amount * 1.5, at - global_position)
	_sprite.modulate = Color(0.65, 0.5, 0.45)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color(0.42, 0.44, 0.5), 0.15)
	if health <= 0.0:
		_dead = true
		_break_open()


func _break_open() -> void:
	var main := get_tree().current_scene
	var fx := BREAK_EFFECT.instantiate()
	fx.scale = Vector2.ONE * 1.1
	fx.position = global_position
	main.add_child(fx)
	fx.reset_physics_interpolation()
	if main.has_method("spawn_weapon_pickup"):
		var luck := mini(int(main.depth) / 4, 3) if "depth" in main else 0
		var kind := WeaponDB.roll_weapon(luck)
		main.spawn_weapon_pickup(kind, int(WeaponDB.DATA[kind]["max_ammo"]),
				global_position, Vector2.from_angle(randf() * TAU) * 30.0,
				randf_range(-1.2, 1.2))
	var holder := main.get_node_or_null("Drops")
	if holder != null:
		var drop := DungeonDrop.new()
		drop.kind = DungeonDrop.Kind.SHELLS
		drop.position = global_position + Vector2.from_angle(randf() * TAU) * 30.0
		holder.add_child(drop)
	queue_free()
