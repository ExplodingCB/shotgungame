# Headless test of the chaos layer: armed thrown guns bonk ships,
# volatile asteroids explode and chain, fast body contact deals ram
# damage, and each mid-round event runs clean.
# Run with:
#   godot --headless --path . -s res://test/chaos_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _rock_count_before := 0


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


func _main() -> Node:
	return root.get_node("Main")


func _players() -> Array[Node]:
	return _main().get_node("Players").get_children()


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			# Park the round flow in its countdown so nothing interferes.
			_main().round_manager._t = 9999.0
			_stage_bonk_and_light_fuse()
		90:
			# Generous window: two 0.12s fuses have long since resolved.
			_stage_check_chain_then_ram()
		120:
			_stage_check_ram_then_events()
		140:
			if _failed:
				print("CHAOS TEST FAILED")
				quit(1)
			else:
				print("CHAOS TEST OK")
				quit(0)
	return false


func _stage_bonk_and_light_fuse() -> void:
	var main := _main()
	var players := _players()
	var p1: Node = players[0]
	var p2: Node = players[1]

	# Armed thrown gun overlapping a ship bonks it once. p2 sits at its
	# spawn point — its physics body is already committed there, so the
	# bonk's shape query can see it.
	main.spawn_weapon_pickup(WeaponDB.Weapon.AK47, 30,
			p2.global_position, Vector2(400, 0), 0.0, p1.fighter_key())
	var pickups: Array[Node] = main.get_node("Pickups").get_children()
	var gun: Node = pickups[pickups.size() - 1]
	_check(bool(gun._armed), "fast-thrown gun did not arrive armed")
	gun._arm_grace = 0.0
	gun._check_bonk()
	_check(float(p2.health) < 100.0, "armed gun did not bonk the ship")
	_check(not bool(gun._armed), "gun stayed armed after the bonk")
	var after_bonk: float = p2.health
	gun._check_bonk()
	_check(float(p2.health) == after_bonk, "disarmed gun kept dealing damage")

	# Two volatile rocks in a cluster; light the first one. p2 moves
	# into blast range now — the fuse gives physics time to commit it.
	main.asteroid_spawner.spawn([0, Vector2(800, 600), true])
	main.asteroid_spawner.spawn([0, Vector2(860, 640), true])
	_rock_count_before = main.get_node("Asteroids").get_child_count()
	p2.health = 100.0
	p2.global_position = Vector2(870, 600)
	p2.velocity = Vector2.ZERO
	var rocks: Array[Node] = main.get_node("Asteroids").get_children()
	rocks[rocks.size() - 2].take_damage(10000.0, Vector2.RIGHT, Vector2(800, 600),
			p1.fighter_key())


func _stage_check_chain_then_ram() -> void:
	var main := _main()
	var players := _players()
	var p2: Node = players[1]
	_check(main.get_node("Asteroids").get_child_count() <= _rock_count_before - 2,
			"volatile chain did not destroy both rocks")
	_check(float(p2.health) < 100.0, "volatile blast did not damage the nearby ship")

	# Ram: p1 slams into p2 well above the ram speed threshold.
	var p1: Node = players[0]
	p2.health = 100.0
	p2.global_position = Vector2(-1000, -600)
	p2.velocity = Vector2.ZERO
	p1.global_position = Vector2(-1100, -600)
	p1.velocity = Vector2(900, 0)
	p1._ram_cd = 0.0


func _stage_check_ram_then_events() -> void:
	var main := _main()
	var players := _players()
	_check(float(players[1].health) < 100.0, "ramming dealt no damage")

	var rm: Node = main.round_manager
	var rocks_before: int = main.get_node("Asteroids").get_child_count()
	rm._fire_event(0)
	_check(main.get_node("Asteroids").get_child_count() == rocks_before + 10,
			"asteroid shower spawned no rocks")

	rm._fire_event(1)
	for p in players:
		_check(int(WeaponDB.DATA[p.primary]["rarity"]) >= WeaponDB.Rarity.EPIC,
				"arms race left %s with a %s" % [p.name, WeaponDB.DATA[p.primary]["name"]])

	var pickups_before: int = main.get_node("Pickups").get_child_count()
	rm._fire_event(2)
	_check(main.get_node("Pickups").get_child_count() == pickups_before + 6,
			"supply drop spawned no pickups")
