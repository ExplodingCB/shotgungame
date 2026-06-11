# Headless validation of every registered level: the scene loads, the
# metadata is complete, and all spawn points sit inside the bounds and
# clear of the level's own geometry. Run with:
#   godot --headless --path . -s res://test/level_db_test.gd
extends SceneTree

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _initialize() -> void:
	var host := LevelHost.new()
	root.add_child(host)
	_check(LevelDB.LEVELS.has(0), "Classic (id 0) must exist")
	for id in LevelDB.LEVELS:
		var info: Dictionary = LevelDB.LEVELS[id]
		for key in ["scene_path", "name", "bounds", "spawns", "asteroid_density"]:
			_check(info.has(key), "level %d missing %s" % [id, key])
		host.load_level(id)
		_check(host.level_id == id,
				"level %d scene did not load (%s)" % [id, info["scene_path"]])
		var b: Rect2 = info["bounds"]
		var spawns: Array = info["spawns"]
		_check(spawns.size() >= 4, "level %d needs 4+ spawns" % id)
		for s in spawns:
			_check(b.grow(-40.0).has_point(s), "level %d spawn %s outside bounds" % [id, s])
			_check(not host.blocked(s, 60.0), "level %d spawn %s inside geometry" % [id, s])
	# Rotation never hands back the level just played.
	for i in 60:
		var cur := i % LevelDB.LEVELS.size()
		var n := LevelDB.pick_next(cur)
		_check(n != cur, "pick_next repeated level %d" % cur)
		_check(LevelDB.LEVELS.has(n), "pick_next returned unknown id %d" % n)
	if _failed:
		print("LEVEL DB TEST FAILED")
		quit(1)
	else:
		print("LEVEL DB TEST OK")
		quit(0)
