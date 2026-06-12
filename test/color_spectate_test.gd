# Headless checks for the multiplayer polish set: spawn colors never
# collide, the menu color handshake grants free paints and refuses
# taken ones, the HUD event feed posts death/leave lines, and the
# death spectator camera finds and cycles survivors. Run with:
#   godot --headless --path . -s res://test/color_spectate_test.gd
extends SceneTree

var _frames := 0
var _failed := false


func _initialize() -> void:
	var net: Node = root.get_node("Net")
	net.mode = net.Mode.LOCAL
	net.local_roster = [-1, 0]
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(_delta: float) -> bool:
	_frames += 1
	var main: Node = root.get_node_or_null("Main")
	match _frames:
		5:
			_stage_colors(main)
		8:
			_stage_feed(main)
			main.set_spectating(true, Vector2.ZERO)
		12:
			_stage_spectator(main)
			_finish()
	return false


func _stage_colors(main: Node) -> void:
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	_check(int(a.color_idx) == 0 and int(b.color_idx) == 1,
			"slot colors expected at spawn (%s, %s)" % [a.color_idx, b.color_idx])
	# Both slot paints are worn, so the next spawn gets the first free.
	_check(main._free_color(0) == 2, "free color should skip worn paints")
	# The handshake refuses a color someone else wears…
	a._net_request_color(1)
	_check(int(a.color_idx) == 0, "request for a taken color must be refused")
	# …and grants a free one.
	b._net_request_color(5)
	_check(int(b.color_idx) == 5, "request for a free color must be granted")
	_check(main._free_color(1) == 1, "vacated paint should be free again")


func _stage_feed(main: Node) -> void:
	var hud: Control = main.get_node("HUD/Hud")
	var feed: Node = hud._feed_box
	var before: int = feed.get_child_count()
	hud.notify("P9 left the game")
	_check(feed.get_child_count() == before + 1, "notify posted no feed line")
	var players: Array = main.get_node("Players").get_children()
	main._net_death_msg(1, 5, players[0].fighter_key())
	_check(feed.get_child_count() == before + 2, "death message posted no feed line")
	var last: Label = feed.get_child(feed.get_child_count() - 1)
	_check(last.text == "P1 destroyed P2", "unexpected kill line: %s" % last.text)


func _stage_spectator(main: Node) -> void:
	var cam: Node = main.spectator
	_check(cam != null and cam.enabled, "spectator camera missing after set_spectating")
	var first: Node2D = main.spectate_target()
	_check(first != null, "spectator found nobody to watch")
	var second: Node2D = cam._next_target(first)
	_check(second != null and second != first, "spectate cycle did not advance")
	_check(cam._next_target(second) == first, "spectate cycle did not wrap")
	main.set_spectating(false, Vector2.ZERO)
	_check(main.spectate_target() == null, "spectator still active after revive")


func _finish() -> void:
	if _failed:
		print("COLOR SPECTATE TEST FAILED")
		quit(1)
	else:
		print("COLOR SPECTATE TEST OK")
		quit(0)
