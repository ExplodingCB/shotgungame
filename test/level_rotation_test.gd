# Headless versus-flow test: each round loads a fresh level (never the
# same twice in a row), rebuilds the floating world to that level's rock
# density, and revives players at the level's own spawn points. Run:
#   godot --headless --path . -s res://test/level_rotation_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _first_level := -1


func _initialize() -> void:
	var net: Node = root.get_node("Net")
	net.mode = net.Mode.LOCAL
	net.local_roster = [-1, 0, 1]
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_stage_first_round()
	elif _frames == 10:
		_stage_kill()
	elif _frames == 15:
		_stage_second_round()
		_finish()
	return false


func _stage_first_round() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "match should open with a countdown")
	_first_level = int(rm.current_level)
	_check(_first_level != 0, "round 1 should rotate off the warm-up level")
	_check(int(main.level_host.level_id) == _first_level, "level scene not loaded")
	# The world regrew to the level's own density.
	var info: Dictionary = LevelDB.LEVELS[_first_level]
	var expected := 0
	for variant in 4:
		expected += maxi(roundi(main.COUNTS[variant] * float(info["asteroid_density"])), 0)
	_check(main.get_node("Asteroids").get_child_count() == expected,
			"rock count %d != density's %d" % [main.get_node("Asteroids").get_child_count(), expected])
	_check(main.get_node("Pickups").get_child_count() == main.WEAPON_PICKUPS,
			"pickups not restocked (%d)" % main.get_node("Pickups").get_child_count())
	rm._t = 0.0  # skip the countdown


func _stage_kill() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(int(rm.phase) == rm.Phase.FIGHT, "countdown did not hand over to the fight")
	var players: Array = main.get_node("Players").get_children()
	var winner: Node = players[0]
	for i in [1, 2]:
		players[i].health = 5.0
		players[i]._apply_damage(10.0, Vector2.RIGHT, winner.fighter_key())
	_check(int(rm.phase) == rm.Phase.ROUND_END, "round did not end with one player left")
	rm._t = 0.0  # skip the result flash


func _stage_second_round() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "no countdown after the round ended")
	_check(int(rm.current_level) != _first_level, "level repeated back-to-back")
	_check(int(main.level_host.level_id) == int(rm.current_level),
			"level host out of sync with the round manager")
	var spawns: Array = main.level_host.spawns
	for p in main.get_node("Players").get_children():
		_check(p.visible and not bool(p._dead), "%s was not revived" % p.name)
		var want: Vector2 = spawns[int(p.slot) % spawns.size()]
		_check(p.global_position.distance_to(want) < 60.0,
				"%s not at the new level's spawn (%s vs %s)" % [p.name, p.global_position, want])


func _finish() -> void:
	if _failed:
		print("LEVEL ROTATION TEST FAILED")
		quit(1)
	else:
		print("LEVEL ROTATION TEST OK")
		quit(0)
