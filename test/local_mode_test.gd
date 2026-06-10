# Headless test of couch (LOCAL) mode: three players on one machine,
# all under the offline peer's authority, sharing one camera. Exercises
# firing, the pickup/throw RPC loopback, and slot-keyed kill scoring.
# Run with:
#   godot --headless --path . -s res://test/local_mode_test.gd
extends SceneTree

var _frames := 0
var _failed := false


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
		_exercise()
	if _frames >= 40:
		if _failed:
			print("LOCAL MODE TEST FAILED")
			quit(1)
		else:
			print("LOCAL MODE TEST OK")
			quit(0)
	return false


func _exercise() -> void:
	var main: Node = root.get_node("Main")
	var players: Array[Node] = main.get_node("Players").get_children()
	_check(players.size() == 3, "expected 3 couch players, got %d" % players.size())

	var slots := {}
	for p in players:
		_check(p.is_multiplayer_authority(), "%s lost offline authority" % p.name)
		_check(p.is_locally_controlled(), "%s is not locally controlled" % p.name)
		_check(not p.camera.enabled, "%s still has its own camera" % p.name)
		slots[p.slot] = true
	_check(slots.size() == 3, "couch slots not distinct: %s" % slots)

	_check(main.get_node_or_null("SharedCamera") != null, "no shared camera in couch mode")

	# Every couch player can fire their own lethal shots.
	for p in players:
		p._cooldown = 0.0
		p._fire(Vector2.RIGHT)
	var projectiles := 0
	for c in main.get_children():
		if "shooter_id" in c:
			projectiles += 1
	_check(projectiles >= 3, "expected a projectile per player, got %d" % projectiles)

	# Throw + grab run through the same server RPCs as networked play;
	# offline they loop back as direct calls.
	var thrower: Node = players[0]
	var before: int = main.get_node("Pickups").get_child_count()
	thrower.throw_weapon(Vector2.RIGHT)
	_check(main.get_node("Pickups").get_child_count() == before + 1,
			"thrown weapon did not spawn a pickup")
	_check(int(thrower.primary) == -1, "thrower still holds a primary")

	# Kills are credited by slot key, so peer 1 sharing is no problem.
	var victim: Node = players[1]
	var attacker: Node = players[2]
	victim.health = 5.0
	victim._apply_damage(10.0, Vector2.RIGHT, attacker.fighter_key())
	_check(int(main.scores.get(attacker.fighter_key(), 0)) == 1,
			"couch kill not credited by slot key (%s)" % main.scores)
	_check(float(victim.health) == float(victim.MAX_HEALTH), "victim did not respawn")
