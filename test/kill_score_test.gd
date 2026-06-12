# Headless test of kill scoring:
#  - projectiles carry the shooter's peer id
#  - the server credits the attacker, ignoring suicides and enemy
#    ships (attacker 0), with the victim identified by the RPC sender
#  - a lethal _apply_damage reports the killer and respawns
#  - the HUD scoreboard builds color rows in multiplayer mode
# Run with:
#   godot --headless --path . -s res://test/kill_score_test.gd
extends SceneTree

var _frames := 0
var _failed := false


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames != 5:
		return false
	var main: Node = root.get_node("Main")
	var pl: Node = get_first_node_in_group("player")

	# Fired projectiles are stamped with the shooter's peer id.
	pl._switch_weapon(WeaponDB.Weapon.PISTOL)
	pl._cooldown = 0.0
	pl._fire(Vector2.RIGHT)
	var stamped := false
	for c in main.get_children():
		if "shooter_id" in c and int(c.shooter_id) == 1:
			stamped = true
	_check(stamped, "no projectile carried the shooter's peer id")

	# Server scoring rules: credit attacker, never suicides or enemies.
	main._net_report_kill.rpc_id(1, 7)
	_check(main.scores.get(7, 0) == 1, "kill by peer 7 not scored (%s)" % main.scores)
	main._net_report_kill.rpc_id(1, 1)  # victim is sender (peer 1): suicide
	main._net_report_kill.rpc_id(1, 0)  # enemy-ship kill
	_check(main.scores.get(1, 0) == 0 and main.scores.get(0, 0) == 0,
			"suicide or enemy kill was scored (%s)" % main.scores)

	# Lethal damage reports the killing peer and respawns the victim.
	pl.health = 5.0
	pl._apply_damage(10.0, Vector2.RIGHT, 7)
	_check(main.scores.get(7, 0) == 2, "death did not credit the killer (%s)" % main.scores)
	_check(float(pl.health) == float(pl.MAX_HEALTH), "victim did not respawn")

	# Scoreboard UI: visible with one color row per player. The minimal HUD
	# redesign dropped the "KILLS" title, so it's a row each and nothing more.
	var net: Node = root.get_node("Net")
	net.mode = net.Mode.HOST  # display-mode only; no peer was created
	var hud: Node = main.get_node("HUD/Hud")
	hud._update_scoreboard()
	_check(hud._score_box.visible, "scoreboard hidden in multiplayer mode")
	_check(hud._score_box.get_child_count() == 1,
			"expected one row per player (no title), got %d children" % hud._score_box.get_child_count())
	net.mode = net.Mode.SOLO
	hud._update_scoreboard()
	_check(not hud._score_box.visible, "scoreboard should hide in solo")

	if _failed:
		print("KILL SCORE TEST FAILED")
		quit(1)
	else:
		print("KILL SCORE TEST OK")
		quit(0)
	return false
