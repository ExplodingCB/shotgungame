# Headless hazard behaviors: vortex pull and core burn, bounce-pad
# flings, and the laser's cycle + damage. Run with:
#   godot --headless --path . -s res://test/hazard_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _vortex: Vortex
var _pad: BouncePad


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
	if _frames == 5:
		_setup()
	elif _frames == 12:
		_stage_vortex_then_pad()
	elif _frames == 18:
		_stage_pad_and_laser()
		_finish()
	return false


# A flat, empty classic arena with two parked players: hazards under
# test get added by hand so nothing else perturbs velocities.
func _setup() -> void:
	var main: Node = root.get_node("Main")
	main.round_manager._t = 600.0  # hold the countdown open
	main.level_host.load_level(0)
	for holder in ["Asteroids", "Pickups"]:
		for c in main.get_node(holder).get_children():
			c.free()
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	a.global_position = Vector2(-1200, -600)
	a.velocity = Vector2.ZERO
	b.global_position = Vector2(1200, 600)
	b.velocity = Vector2.ZERO
	_vortex = Vortex.new()
	_vortex.position = a.global_position + Vector2(300, 0)
	main.add_child(_vortex)


func _stage_vortex_then_pad() -> void:
	var main: Node = root.get_node("Main")
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	# Direction is what matters; magnitude fights the drift friction.
	_check(a.velocity.x > 1.0, "vortex did not pull the player inward (%s)" % a.velocity)
	# Core burn: standing on the well's heart hurts on the sweep.
	var hp: float = b.health
	_vortex.position = b.global_position
	_vortex._prev[b.get_instance_id()] = b.global_position
	_vortex._sweep_core(0.016)
	_check(b.health < hp, "vortex core did not burn (%s -> %s)" % [hp, b.health])
	# Cooldown: the very next frame must not burn again.
	hp = b.health
	_vortex._sweep_core(0.016)
	_check(b.health == hp, "vortex core re-burned inside the cooldown window")
	# Tunneling: a ship that dove clean across the core between frames
	# still burns — the swept path passes through the heart.
	_vortex.position = a.global_position + Vector2(0, 300)
	var a_hp: float = a.health
	_vortex._prev[a.get_instance_id()] = a.global_position
	a.global_position = a.global_position + Vector2(0, 600)
	_vortex._sweep_core(0.016)
	_check(a.health < a_hp, "vortex core missed a ship that crossed between frames")
	a.global_position = a.global_position + Vector2(0, -600)
	a.velocity = Vector2.ZERO
	_vortex.free()
	# Park a pad under player A, pointing +x.
	a.velocity = Vector2.ZERO
	_pad = BouncePad.new()
	_pad.position = a.global_position
	main.add_child(_pad)


func _stage_pad_and_laser() -> void:
	var main: Node = root.get_node("Main")
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	_check(a.velocity.x > 600.0, "pad did not fling (%s)" % a.velocity)
	_pad.free()
	var laser := LaserStrip.new()
	laser.length = 400.0
	main.add_child(laser)
	# Cycle: warn first, lethal after warn_time, dark after on_time.
	laser._t = 0.3
	_check(laser.state() == LaserStrip.Beam.WARN, "0.3s into the cycle should warn")
	laser._t = 1.0
	_check(laser.state() == LaserStrip.Beam.ON, "1.0s into the cycle should burn")
	laser._t = 2.5
	_check(laser.state() == LaserStrip.Beam.OFF, "2.5s into the cycle should rest")
	# Damage: a ship sitting on the beam burns on the sweep.
	laser.position = b.global_position - Vector2(200, 0)
	var hp: float = b.health
	laser._prev[b.get_instance_id()] = laser.to_local(b.global_position)
	laser._sweep_players(0.016, true)
	_check(b.health < hp, "laser did not damage a ship on the beam (%s)" % hp)
	# Cooldown: the very next frame must not burn again.
	hp = b.health
	laser._sweep_players(0.016, true)
	_check(b.health == hp, "laser re-burned inside the cooldown window")
	# Tunneling: a ship crossing the whole beam between two frames —
	# faster than any tick could catch — still gets clipped.
	var c_hp: float = a.health
	laser._prev[a.get_instance_id()] = laser.to_local(b.global_position + Vector2(0, -400))
	a.global_position = b.global_position + Vector2(0, 400)
	laser._sweep_players(0.016, true)
	_check(a.health < c_hp, "laser missed a ship that crossed between frames (%s)" % c_hp)
	laser.free()
	_stage_teleporter(main, a)


func _stage_teleporter(main: Node, a: Node) -> void:
	var portal_in := Teleporter.new()
	var portal_out := Teleporter.new()
	portal_in.position = Vector2(-900, -300)
	portal_out.position = Vector2(900, 300)
	portal_out.rotation = PI / 2.0  # arrivals launch along +x = down
	main.add_child(portal_in)
	main.add_child(portal_out)
	portal_in.twin_path = portal_in.get_path_to(portal_out)
	portal_out.twin_path = portal_out.get_path_to(portal_in)
	# Ride in: the ship pops out of the twin, redirected along its +x.
	a.global_position = portal_in.global_position
	a.velocity = Vector2(500, 0)
	portal_in._try_send(a, portal_out)
	_check(a.global_position == portal_out.global_position,
			"teleporter did not move the ship (%s)" % a.global_position)
	_check(a.velocity.length() > 400.0 and absf(a.velocity.angle_to(Vector2.DOWN)) < 0.01,
			"exit velocity not redirected along the twin's facing (%s)" % a.velocity)
	# The arrival is on cooldown at the twin: it must not ping-pong back.
	portal_out._try_send(a, portal_in)
	_check(a.global_position == portal_out.global_position,
			"teleporter ping-ponged the ship straight back")
	portal_in.free()
	portal_out.free()


func _finish() -> void:
	if _failed:
		print("HAZARD TEST FAILED")
		quit(1)
	else:
		print("HAZARD TEST OK")
		quit(0)
