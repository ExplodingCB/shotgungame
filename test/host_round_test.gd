# Headless test of the online match flow: hosting opens in a warm-up
# lobby, the match can't start alone, Enter/Start kicks off the
# countdown once players are in, rounds resolve and award wins, and
# the match ends back in the warm-up for a rematch.
# Run with:
#   godot --headless --path . -s res://test/host_round_test.gd
extends SceneTree

var _frames := 0
var _failed := false


func _initialize() -> void:
	var net: Node = root.get_node("Net")
	net.mode = net.Mode.HOST
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _main() -> Node:
	return root.get_node("Main")


func _rm() -> Node:
	return _main().round_manager


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			_stage_lobby()
		10:
			_stage_countdown()
		15:
			_stage_fight_and_round()
		20:
			_stage_next_round_then_force_match_point()
		30:
			_stage_match_end()
		40:
			_stage_match_end_banner()
		45:
			_stage_rematch_lobby()
		50:
			if _failed:
				print("HOST ROUND TEST FAILED")
				quit(1)
			else:
				print("HOST ROUND TEST OK")
				quit(0)
	return false


func _stage_lobby() -> void:
	var rm := _rm()
	_check(rm != null, "no round manager when hosting")
	_check(int(rm.phase) == rm.Phase.LOBBY, "hosting should open in the warm-up lobby")
	var host_player: Node = _main().get_node("Players").get_child(0)
	_check(not bool(host_player.input_locked), "warm-up should leave input free")
	rm._try_start()
	_check(int(rm.phase) == rm.Phase.LOBBY, "match started with only one player")
	# A second peer's player arrives (its owner is a fake peer id; the
	# node is a remote copy on this machine, which is all rounds need).
	_main()._add_player(2)
	_check(_main().get_node("Players").get_child_count() == 2, "second player missing")


func _stage_countdown() -> void:
	var rm := _rm()
	rm._try_start()
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "start did not begin the countdown")
	_check(str(rm.banner_text).begins_with("ROUND 1"), "countdown banner missing (%s)" % rm.banner_text)
	var host_player: Node = _main().get_node("Players").get_child(0)
	_check(bool(host_player.input_locked), "host player not locked during countdown")
	rm._t = 0.0


func _stage_fight_and_round() -> void:
	var rm := _rm()
	_check(int(rm.phase) == rm.Phase.FIGHT, "countdown did not hand over to the fight")
	var host_player: Node = _main().get_node("Players").get_child(0)
	_check(not bool(host_player.input_locked), "host player still locked in the fight")
	_check(bool(_main().get_node("ShrinkZone").active), "zone not running during the fight")
	# The remote player dies (its peer would report this over the wire).
	_main().report_death(2, 1)
	_check(int(rm.phase) == rm.Phase.ROUND_END, "round did not end with one survivor")
	_check(int(rm.round_wins.get(1, 0)) == 1, "host not awarded the round (%s)" % rm.round_wins)
	_check(int(_main().scores.get(1, 0)) == 1, "kill not scored (%s)" % _main().scores)
	rm._t = 0.0


func _stage_next_round_then_force_match_point() -> void:
	var rm := _rm()
	_check(int(rm.phase) == rm.Phase.COUNTDOWN, "no countdown after the round")
	_check(int(rm.round_num) == 2, "round counter did not advance")
	rm._t = 0.0  # into round 2's fight
	rm.round_wins[1] = rm.ROUNDS_TO_WIN - 1


func _stage_match_end() -> void:
	var rm := _rm()
	_check(int(rm.phase) == rm.Phase.FIGHT, "round 2 fight did not start")
	_main().report_death(2, 1)  # match point
	_check(int(rm.phase) == rm.Phase.ROUND_END, "match-point round did not end")
	rm._t = 0.0


func _stage_match_end_banner() -> void:
	var rm := _rm()
	_check(int(rm.phase) == rm.Phase.MATCH_END,
			"reaching %d wins did not end the match (phase %s)" % [rm.ROUNDS_TO_WIN, rm.phase])
	_check("WINS THE MATCH" in str(rm.banner_text), "no match-winner banner (%s)" % rm.banner_text)
	rm._t = 0.0


func _stage_rematch_lobby() -> void:
	var rm := _rm()
	_check(int(rm.phase) == rm.Phase.LOBBY, "match end did not return to the warm-up")
	var host_player: Node = _main().get_node("Players").get_child(0)
	_check(host_player.visible and not bool(host_player._dead), "host not revived for warm-up")
	_check(not bool(host_player.input_locked), "warm-up rematch left input locked")
