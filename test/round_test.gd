# Headless test of round play: countdown locks input, last player
# standing takes the round, everyone revives for the next countdown,
# and the shrink zone burns players caught outside it.
# Run with:
#   godot --headless --path . -s res://test/round_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _stage := 0


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
		_stage_countdown()
	elif _frames == 10:
		_stage_fight()
	elif _frames == 15:
		_stage_round_end_then_revive()
	if _stage == 3 and _frames >= 20:
		_stage_zone()
		_finish()
	return false


func _stage_countdown() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(rm != null, "no round manager in couch mode")
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "round should open with a countdown")
	for p in main.get_node("Players").get_children():
		_check(bool(p.input_locked), "%s can act during the countdown" % p.name)
	_check(main.get_node_or_null("ShrinkZone") != null, "no shrink zone spawned")
	# Skip the countdown so the fight starts on the next frame batch.
	rm._t = 0.0
	_stage = 1


func _stage_fight() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(int(rm.phase) == rm.Phase.FIGHT, "countdown did not hand over to the fight")
	var players: Array[Node] = main.get_node("Players").get_children()
	for p in players:
		_check(not bool(p.input_locked), "%s still locked during the fight" % p.name)
	# Two die; the survivor takes the round and the dead are eliminated.
	var winner: Node = players[0]
	for i in [1, 2]:
		players[i].health = 5.0
		players[i]._apply_damage(10.0, Vector2.RIGHT, winner.fighter_key())
	_check(int(rm.phase) == rm.Phase.ROUND_END, "round did not end with one player left")
	_check(int(rm.round_wins.get(winner.fighter_key(), 0)) == 1,
			"survivor was not awarded the round (%s)" % rm.round_wins)
	_check(not players[1].visible and bool(players[1]._dead), "loser was not eliminated")
	_check(int(main.scores.get(winner.fighter_key(), 0)) == 2,
			"kills not credited during the round (%s)" % main.scores)
	_stage = 2


func _stage_round_end_then_revive() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	rm._t = 0.0  # skip the result flash; next frame begins round 2
	_stage = 3


func _stage_zone() -> void:
	var main: Node = root.get_node("Main")
	var rm: Node = main.round_manager
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "no countdown after the round ended")
	_check(int(rm.round_num) == 2, "round counter did not advance (%s)" % rm.round_num)
	var players: Array[Node] = main.get_node("Players").get_children()
	for p in players:
		_check(p.visible and not bool(p._dead), "%s was not revived" % p.name)
		_check(float(p.health) == float(p.MAX_HEALTH), "%s not healed on revive" % p.name)
		_check(int(p.primary) == WeaponDB.Weapon.SHOTGUN, "%s loadout not reset" % p.name)

	# Shrink zone: a player outside the safe rect burns on the tick.
	var zone: Node = main.get_node("ShrinkZone")
	zone.start()
	zone.rect = Rect2(-100, -100, 200, 200)
	var outsider: Node = players[0]
	outsider.global_position = Vector2(1400, 800)
	var before: float = outsider.health
	zone._damage_outside()
	_check(float(outsider.health) < before, "zone did not damage a player outside it")


func _finish() -> void:
	if _failed:
		print("ROUND TEST FAILED")
		quit(1)
	else:
		print("ROUND TEST OK")
		quit(0)
