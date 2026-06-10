# Headless smoke test: boots the real game, fires every weapon, and
# breaks an asteroid, so input-triggered runtime errors show up in CI
# instead of in play. Run with:
#   godot --headless --path . -s res://test/smoke_test.gd
extends SceneTree

var _frames := 0
var _ran := false


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5 and not _ran:
		_ran = true
		_exercise()
	# Long enough for grenade/rocket fuses (2.5s) to detonate.
	if _frames >= 240:
		print("SMOKE TEST OK")
		quit(0)
	return false


func _exercise() -> void:
	var player: Node = get_first_node_in_group("player")
	if player == null:
		push_error("no player spawned")
		quit(1)
		return
	# Pistol, then every primary in the database via the pickup path
	# (covers pellets, beams, and explosive/bouncing rounds).
	player._switch_weapon(WeaponDB.Weapon.PISTOL)
	player._fire(Vector2.RIGHT)
	for w in WeaponDB.DATA:
		if w == WeaponDB.Weapon.PISTOL:
			continue
		player.give_weapon(w, int(WeaponDB.DATA[w]["max_ammo"]))
		player._cooldown = 0.0
		player._fire(Vector2.RIGHT)
	# Drain a weapon to zero: it stays equipped and just dry-fires.
	player.give_weapon(WeaponDB.Weapon.SNIPER, 1)
	player._cooldown = 0.0
	player._fire(Vector2.RIGHT)
	player._cooldown = 0.0
	player._fire(Vector2.RIGHT)  # dry click on empty
	if int(player.primary) != WeaponDB.Weapon.SNIPER or int(player.ammo[WeaponDB.Weapon.SNIPER]) != 0:
		push_error("spent weapon should stay equipped at 0 ammo (primary=%s ammo=%s)"
				% [player.primary, player.ammo[WeaponDB.Weapon.SNIPER]])
	var rocks: Array[Node] = root.get_node("Main/Asteroids").get_children()
	if not rocks.is_empty():
		rocks[0].take_damage(10000.0, Vector2.RIGHT, rocks[0].global_position)
	# Force a wave and kill one enemy to exercise the solo wave path.
	var main: Node = root.get_node("Main")
	main._start_wave()
	var enemies: Array[Node] = main.get_node("Enemies").get_children()
	if enemies.is_empty():
		push_error("wave spawned no enemies")
	else:
		enemies[0].take_damage(10000.0, Vector2.RIGHT, enemies[0].global_position)
	print("exercised all weapons + disappear path + asteroid break + wave")
