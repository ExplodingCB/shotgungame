extends Node2D

var velocity := Vector2.ZERO
var damage := 10.0
var lifetime := 0.5
var damping := 0.0
var exclude: Array[RID] = []
var deals_damage := true  # false on remote-replicated copies (visual only)

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
		if deals_damage and collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage, velocity.normalized(), hit["position"])
		queue_free()
		return

	global_position = to
	_age += delta
	modulate.a = maxf(1.0 - _age / lifetime, 0.0)
	if _age >= lifetime or velocity.length() < 40.0:
		queue_free()
