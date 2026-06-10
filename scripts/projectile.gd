extends Node2D

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
	if deals_damage and direct_hit != null and direct_hit.has_method("take_damage"):
		direct_hit.take_damage(damage, velocity.normalized(), global_position, shooter_id)
	Explosions.blast(self, global_position, explode_radius, explode_damage,
			shooter_id, deals_damage, direct_hit)
	queue_free()
