# Owns the swappable arena geometry: walls, obstacles, and hazards live
# in a level scene instanced under this node. Every peer loads the same
# scene locally (the id rides the round manager's phase RPC), so static
# geometry needs no network sync at all.
class_name LevelHost
extends Node2D

signal level_loaded

var level_id := -1
var bounds := Rect2(-1600, -900, 3200, 1800)
var spawns: Array = [Vector2(-600, 0), Vector2(600, 0), Vector2(0, -450), Vector2(0, 450)]
var asteroid_density := 1.0

var _level: Node2D = null
var _shapes: Array = []  # CollisionShape2D nodes of the active level


func load_level(id: int) -> void:
	if not LevelDB.LEVELS.has(id):
		push_warning("unknown level id %d; falling back to Classic" % id)
		id = 0
	if id == level_id and _level != null:
		return
	var info: Dictionary = LevelDB.LEVELS[id]
	var scene := load(info["scene_path"]) as PackedScene
	if scene == null:
		push_error("level scene missing: %s" % info["scene_path"])
		if id != 0:
			load_level(0)
		return
	if _level != null:
		_level.queue_free()
	_level = scene.instantiate()
	add_child(_level)
	level_id = id
	bounds = info["bounds"]
	spawns = info["spawns"]
	asteroid_density = float(info["asteroid_density"])
	_collect_shapes()
	level_loaded.emit()


func _collect_shapes() -> void:
	_shapes.clear()
	for body in _level.get_children():
		if body is StaticBody2D:
			for cs in body.get_children():
				if cs is CollisionShape2D and cs.shape != null:
					_shapes.append(cs)


# True when a circle at `point` overlaps any wall or obstacle of the
# active level. Geometric, not physics-based, so it works mid-frame
# during world spawns (the physics space only syncs between frames).
func blocked(point: Vector2, radius: float) -> bool:
	for cs in _shapes:
		if not is_instance_valid(cs):
			continue
		var shape: Shape2D = cs.shape
		var local: Vector2 = cs.global_transform.affine_inverse() * point
		if shape is CircleShape2D:
			if local.length() < (shape as CircleShape2D).radius + radius:
				return true
		elif shape is RectangleShape2D:
			var half: Vector2 = (shape as RectangleShape2D).size / 2.0
			if local.clamp(-half, half).distance_to(local) < radius:
				return true
	return false
