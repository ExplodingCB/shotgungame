# Headless test of couch lobby color picking: joins, cycling (skipping
# taken colors), drops keeping picks aligned, and the picked colors
# riding Net.start_local through to spawned players.
# Run with:
#   godot --headless --path . -s res://test/lobby_color_test.gd
extends SceneTree

var _frames := 0
var _failed := false


func _initialize() -> void:
	var lobby: Node = (load("res://scenes/local_lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_exercise_lobby()
	if _frames == 8:
		_exercise_spawn()
	if _frames >= 40:
		if _failed:
			print("LOBBY COLOR TEST FAILED")
			quit(1)
		else:
			print("LOBBY COLOR TEST OK")
			quit(0)
	return false


func _exercise_lobby() -> void:
	var lobby: Node = current_scene

	# Joins default to slot colors.
	lobby._join(-1)
	lobby._join(0)
	lobby._join(1)
	_check(lobby.picks == [0, 1, 2], "default picks wrong: %s" % str(lobby.picks))

	# Cycling skips colors other players wear: P1 right from 0 lands on
	# 3 (1 and 2 are taken... no wait, 3 is free immediately).
	lobby._cycle_color(-1, 1)
	_check(lobby.picks[0] == 3, "cycle right from 0 should land on 3, got %d" % lobby.picks[0])
	lobby._cycle_color(-1, -1)
	_check(lobby.picks[0] == 0, "cycle back should return to 0, got %d" % lobby.picks[0])

	# Cycling never lands on a taken color even when adjacent.
	lobby._cycle_color(0, 1)  # P2: 1 -> 3 (2 is taken)
	_check(lobby.picks[1] == 3, "P2 cycle should skip taken 2, got %d" % lobby.picks[1])

	# Dropping the middle player keeps picks aligned with the roster.
	lobby._drop(0)
	_check(lobby.roster == [-1, 1], "drop misaligned roster: %s" % str(lobby.roster))
	_check(lobby.picks == [0, 2], "drop misaligned picks: %s" % str(lobby.picks))

	# A re-joiner whose slot color is taken gets the first free one.
	lobby._cycle_color(-1, 1)  # P1: 0 -> 1
	lobby._cycle_color(-1, 1)  # P1: 1 -> 3 (2 is taken)
	lobby._join(0)  # slot 2's default (2) is worn by P2 -> first free, 0
	lobby._cycle_color(0, -1)  # 0 wraps left to 7
	lobby._join(2)  # slot 3 wants 3, taken by P1 -> first free is 0
	_check(lobby.picks == [3, 2, 7, 0], "rejoin picks wrong: %s" % str(lobby.picks))

	# Start hands roster + picks to Net (scene changes next frame).
	lobby._try_start()
	var net: Node = root.get_node("Net")
	_check(net.local_roster == [-1, 1, 0, 2], "roster not handed to Net: %s" % str(net.local_roster))
	_check(net.local_colors == [3, 2, 7, 0], "picks not handed to Net: %s" % str(net.local_colors))


func _exercise_spawn() -> void:
	# start_local changed the scene to main; players wear the picks.
	var main: Node = root.get_node_or_null("Main")
	_check(main != null, "main scene did not load after start")
	if main == null:
		return
	var players: Array[Node] = main.get_node("Players").get_children()
	_check(players.size() == 4, "expected 4 couch players, got %d" % players.size())
	var expected := {0: 3, 1: 2, 2: 7, 3: 0}  # slot -> picked color
	for p in players:
		_check(int(p.color_idx) == expected[int(p.slot)],
				"slot %d wears color %d, wanted %d" % [int(p.slot), int(p.color_idx), expected[int(p.slot)]])
