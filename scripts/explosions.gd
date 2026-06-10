# Shared blast logic for anything that goes bang: rocket and grenade
# rounds, volatile asteroids. Visuals are optional so callers that
# already broadcast their own fx don't double up.
class_name Explosions

const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const SND_EXPLOSION := preload("res://audio/gunsounds/20 Gauge/MP3/20 Gauge Single Isolated.mp3")


static func blast(from: Node2D, pos: Vector2, radius: float, dmg: float,
		attacker_id := 0, lethal := true, except: Object = null, visual := true) -> void:
	var scene := from.get_tree().current_scene
	if visual:
		var fx := BREAK_EFFECT.instantiate()
		fx.scale = Vector2.ONE * (radius / 70.0)
		fx.position = pos
		scene.add_child(fx)
		fx.reset_physics_interpolation()
		boom(from, pos)
	if not lethal:
		return
	var shape := CircleShape2D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = 3
	var damaged := {}
	for h in from.get_world_2d().direct_space_state.intersect_shape(q, 24):
		var c: Object = h["collider"]
		if c == except or damaged.has(c.get_instance_id()) \
				or not c.has_method("take_damage") or not c is Node2D:
			continue
		damaged[c.get_instance_id()] = true
		var dir := pos.direction_to((c as Node2D).global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		c.take_damage(dmg, dir, (c as Node2D).global_position, attacker_id)


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
