# Shared blast logic for anything that goes bang: rocket and grenade
# rounds, volatile asteroids. Visuals are optional so callers that
# already broadcast their own fx don't double up.
class_name Explosions

const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const SND_EXPLOSION := preload("res://audio/gunsounds/20 Gauge/MP3/20 Gauge Single Isolated.mp3")

# Concussion wave: every blast also shoves whatever floats near it,
# reaching past the damage radius so near misses still toss you around.
const WAVE_RADIUS_MULT := 1.6
const WAVE_PUSH := 9.0  # px/s of shove per point of blast damage, at the heart


# `except` skips damage (not the shove) for one object or an array of
# them — the body that already took the direct hit, or a hammer wielder
# standing inside their own blast.
static func blast(from: Node2D, pos: Vector2, radius: float, dmg: float,
		attacker_id := 0, lethal := true, except = null, visual := true) -> void:
	var scene := from.get_tree().current_scene
	if visual:
		var fx := BREAK_EFFECT.instantiate()
		fx.scale = Vector2.ONE * (radius / 70.0)
		fx.position = pos
		scene.add_child(fx)
		fx.reset_physics_interpolation()
		boom(from, pos)
	shockwave(from, pos, radius * WAVE_RADIUS_MULT, maxf(dmg, 25.0) * WAVE_PUSH)
	if not lethal:
		return
	var skip: Array = except if except is Array else [except]
	var shape := CircleShape2D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = 3
	var damaged := {}
	for h in from.get_world_2d().direct_space_state.intersect_shape(q, 24):
		var c: Object = h["collider"]
		if c in skip or damaged.has(c.get_instance_id()) \
				or not c.has_method("take_damage") or not c is Node2D:
			continue
		damaged[c.get_instance_id()] = true
		var dir := pos.direction_to((c as Node2D).global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		c.take_damage(dmg, dir, (c as Node2D).global_position, attacker_id)


# The pressure front: shoves players (each machine pushes the bodies it
# simulates, like the vortex pull), plus rocks, drifting guns, and enemy
# ships on the server. Runs on every copy of a blast — lethal or visual
# — so each peer's own ship feels the push without any network traffic.
static func shockwave(from: Node2D, pos: Vector2, radius: float, strength: float) -> void:
	for p in from.get_tree().get_nodes_in_group("player"):
		if p.is_locally_controlled() and p.visible:
			_shove(pos, radius, strength, p)
	if not from.multiplayer.is_server():
		return
	var scene := from.get_tree().current_scene
	if scene == null:
		return
	for holder_name in ["Asteroids", "Pickups"]:
		var holder: Node = scene.get_node_or_null(holder_name)
		if holder == null:
			continue
		for body in holder.get_children():
			if body is RigidBody2D and not body.freeze:
				_shove(pos, radius, strength, body)
	for e in from.get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and "velocity" in e:
			_shove(pos, radius, strength, e)


# Linear falloff: full strength at the heart, nothing at the rim.
static func _shove(pos: Vector2, radius: float, strength: float, body: Node2D) -> void:
	var d := pos.distance_to(body.global_position)
	if d >= radius:
		return
	var dir := pos.direction_to(body.global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var kick := dir * strength * (1.0 - d / radius)
	if body is RigidBody2D:
		(body as RigidBody2D).linear_velocity += kick
	elif "velocity" in body:
		body.velocity += kick
	if body.has_method("_add_shake"):
		body._add_shake(6.0 * (1.0 - d / radius))


static func boom(from: Node2D, pos: Vector2) -> void:
	var snd := AudioStreamPlayer2D.new()
	snd.stream = SND_EXPLOSION
	snd.pitch_scale = 0.45 * randf_range(0.92, 1.08)
	snd.volume_db = 2.0
	snd.max_distance = 4000.0
	snd.bus = "SFX"
	snd.position = pos
	from.get_tree().current_scene.add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)
