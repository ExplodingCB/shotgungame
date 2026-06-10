extends Node2D

const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const SND_EXPLOSION := preload("res://audio/gunsounds/20 Gauge/MP3/20 Gauge Single Isolated.mp3")

var velocity := Vector2.ZERO
var damage := 10.0
var lifetime := 0.5
var damping := 0.0
var exclude: Array[RID] = []
var deals_damage := true  # false on remote-replicated copies (visual only)
var shooter_id := 0  # peer id credited for kills; 0 = nobody (enemies)

# Explosives: detonate on impact (or fuse end) and damage everything in
# the radius — including the shooter, so rockets double as engines.
# bounces > 0 ricochets off rocks/walls first; ships always trigger it.
var explode_radius := 0.0
var explode_damage := 0.0
var bounces := 0

var _age := 0.0


func _physics_process(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, damping * delta)
	var from := global_position
	var to := from + velocity * delta

	# Raycast the path each tick so fast shots can't tunnel through
	# small asteroids between frames.
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 3  # world + players; shots pass through pickups
	query.exclude = exclude
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		var collider: Object = hit["collider"]
		var is_ship: bool = collider is Node2D and ((collider as Node2D).is_in_group("player")
				or (collider as Node2D).is_in_group("enemies"))
		if bounces > 0 and not is_ship:
			bounces -= 1
			global_position = (hit["position"] as Vector2) + (hit["normal"] as Vector2) * 2.0
			velocity = velocity.bounce(hit["normal"]) * 0.8
			return
		global_position = hit["position"]
		if explode_radius > 0.0:
			_explode(collider)
			return
		if deals_damage and collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage, velocity.normalized(), hit["position"], shooter_id)
		queue_free()
		return

	global_position = to
	_age += delta
	modulate.a = maxf(1.0 - _age / lifetime, 0.0)
	if _age >= lifetime or velocity.length() < 40.0:
		if explode_radius > 0.0:
			_explode(null)
		else:
			queue_free()


func _explode(direct_hit: Object) -> void:
	# Blast visuals and boom play on every peer; damage comes only from
	# the shooter's lethal copy so hits land exactly once.
	var fx := BREAK_EFFECT.instantiate()
	fx.scale = Vector2.ONE * (explode_radius / 70.0)
	fx.position = global_position
	get_tree().current_scene.add_child(fx)
	fx.reset_physics_interpolation()
	_boom()
	if deals_damage:
		if direct_hit != null and direct_hit.has_method("take_damage"):
			direct_hit.take_damage(damage, velocity.normalized(), global_position, shooter_id)
		var shape := CircleShape2D.new()
		shape.radius = explode_radius
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, global_position)
		q.collision_mask = 3
		var damaged := {}
		for h in get_world_2d().direct_space_state.intersect_shape(q, 24):
			var c: Object = h["collider"]
			if c == direct_hit or damaged.has(c.get_instance_id()) \
					or not c.has_method("take_damage") or not c is Node2D:
				continue
			damaged[c.get_instance_id()] = true
			var dir := global_position.direction_to((c as Node2D).global_position)
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			c.take_damage(explode_damage, dir, (c as Node2D).global_position, shooter_id)
	queue_free()


func _boom() -> void:
	var snd := AudioStreamPlayer2D.new()
	snd.stream = SND_EXPLOSION
	snd.pitch_scale = 0.45 * randf_range(0.92, 1.08)
	snd.volume_db = 2.0
	snd.max_distance = 4000.0
	snd.bus = "SFX"
	snd.position = global_position
	get_tree().current_scene.add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)
