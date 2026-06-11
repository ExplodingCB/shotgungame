# Headless grenade behaviors: pack touch-collection with the carry cap,
# the lobbed projectile, fuse blast damage, and the empty-handed case.
# Run with:
#   godot --headless --path . -s res://test/grenade_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _b_hp := 0.0


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
		_stage_pack_collected()
	elif _frames == 14:
		_stage_throw()
	elif _frames > 20 and (_no_projectiles_left() or _frames >= 900):
		# Idle frames outpace physics ticks headless, so wait for the
		# frag itself (it despawns on detonation) instead of a clock.
		_stage_blast()
		_finish()
	return false


func _no_projectiles_left() -> bool:
	var main: Node = root.get_node("Main")
	for c in main.get_children():
		var s: Script = c.get_script()
		if s != null and str(s.resource_path).ends_with("projectile.gd"):
			return false
	return true


func _setup() -> void:
	var main: Node = root.get_node("Main")
	main.round_manager._t = 600.0  # hold the countdown open
	# Clear the firing lane so a drifting rock can't eat the frag.
	for holder in ["Asteroids", "Pickups"]:
		for c in main.get_node(holder).get_children():
			c.free()
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	a.global_position = Vector2(-400, 0)
	a.velocity = Vector2.ZERO
	b.global_position = Vector2(200, 0)
	b.velocity = Vector2.ZERO
	# Cap check: collecting a frag while already full stays at the cap.
	a.grenades = a.GRENADE_CAP
	main.pickup_spawner.spawn([main.GRENADE_KIND, a.global_position, Vector2.ZERO, 0.0])


func _stage_pack_collected() -> void:
	var main: Node = root.get_node("Main")
	var a: Node = main.get_node("Players").get_child(0)
	_check(get_nodes_in_group("grenade_packs").is_empty(), "pack was not collected on touch")
	_check(a.grenades == a.GRENADE_CAP,
			"pack did not clamp to the carry cap (%s)" % a.grenades)


func _stage_throw() -> void:
	var main: Node = root.get_node("Main")
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	_b_hp = b.health
	a.throw_grenade(Vector2.RIGHT)
	_check(a.grenades == a.GRENADE_CAP - 1, "throw did not spend a grenade (%s)" % a.grenades)
	# The cooldown blocks an instant second throw.
	a.throw_grenade(Vector2.RIGHT)
	_check(a.grenades == a.GRENADE_CAP - 1, "cooldown did not block the double throw")
	# Empty hands just dry-click.
	var kept: int = a.grenades
	a.grenades = 0
	a._grenade_cd = 0.0
	a.throw_grenade(Vector2.RIGHT)
	_check(a.grenades == 0, "empty throw went negative (%s)" % a.grenades)
	a.grenades = kept


func _stage_blast() -> void:
	# The frag flew toward player B (800px away, fuse pops near them):
	# the blast must have hurt them by now.
	var main: Node = root.get_node("Main")
	var b: Node = main.get_node("Players").get_child(1)
	_check(b.health < _b_hp, "grenade blast never hurt the target (%s -> %s)" % [_b_hp, b.health])


func _finish() -> void:
	if _failed:
		print("GRENADE TEST FAILED")
		quit(1)
	else:
		print("GRENADE TEST OK")
		quit(0)
