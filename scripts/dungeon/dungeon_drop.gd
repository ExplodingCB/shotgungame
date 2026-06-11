# Supply drop left behind by a dead enemy: a shell pack (ammo) or a
# repair orb (hull). Drifts gently, then homes toward any nearby player
# and is collected on contact. Drawn flat — a diamond for shells, a
# cross for repairs.
class_name DungeonDrop
extends Area2D

enum Kind { SHELLS, REPAIR }

const MAGNET_RANGE := 300.0
const MAGNET_SPEED := 380.0
const LIFETIME := 25.0

const SND_PICKUP := preload("res://audio/gunsounds/Pistol/MP3/9mm Pistol Slide Release.mp3")

var kind: int = Kind.SHELLS
var velocity := Vector2.ZERO

var _age := 0.0
var _collected := false


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	shape.shape = circle
	add_child(shape)
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body)
	velocity = Vector2.from_angle(randf() * TAU) * randf_range(20.0, 60.0)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	# Blink out the last few seconds.
	modulate.a = 1.0 if _age < LIFETIME - 4.0 else (0.4 + 0.6 * float(int(_age * 6.0) % 2))

	var target := _nearest_player()
	if target != null:
		var d := global_position.distance_to(target.global_position)
		if d < MAGNET_RANGE:
			var pull := 1.0 - d / MAGNET_RANGE
			velocity = velocity.move_toward(
					global_position.direction_to(target.global_position) * MAGNET_SPEED,
					MAGNET_SPEED * 3.0 * pull * delta)
	velocity = velocity.move_toward(Vector2.ZERO, 15.0 * delta)
	global_position += velocity * delta


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not p.visible:
			continue
		var d: float = global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _on_body(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	match kind:
		Kind.SHELLS:
			# Shotgun shells always; the held primary gets a quarter mag.
			var shotgun: int = WeaponDB.Weapon.SHOTGUN
			body.ammo[shotgun] = mini(int(body.ammo[shotgun]) + 6,
					int(WeaponDB.DATA[shotgun]["max_ammo"]))
			var prim: int = body.primary
			if prim >= 0 and prim != shotgun:
				var cap := int(WeaponDB.DATA[prim]["max_ammo"])
				body.ammo[prim] = mini(int(body.ammo[prim]) + maxi(cap / 4, 1), cap)
		Kind.REPAIR:
			body.health = minf(body.health + 0.18 * body.max_health, body.max_health)
	var snd := AudioStreamPlayer2D.new()
	snd.stream = SND_PICKUP
	snd.bus = "SFX"
	snd.pitch_scale = 1.3 if kind == Kind.REPAIR else 1.0
	snd.max_distance = 2500.0
	snd.position = global_position
	Arena.of(self).add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)
	queue_free()


func _draw() -> void:
	if kind == Kind.SHELLS:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, -13), Vector2(10, 0), Vector2(0, 13), Vector2(-10, 0),
		]), Color(1.0, 0.55, 0.15))
	else:
		var c := Color(0.35, 1.0, 0.45)
		draw_rect(Rect2(-4.0, -13.0, 8.0, 26.0), c)
		draw_rect(Rect2(-13.0, -4.0, 26.0, 8.0), c)
