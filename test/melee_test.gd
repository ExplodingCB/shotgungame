# Headless checks for the brawl pass: throwing a gun shoves the
# thrower backwards, every blast carries a concussion shockwave that
# pushes nearby ships, and the legendary Warhammer one-shots whatever
# the swing meets (detonating on impact, smashing rocks). Run with:
#   godot --headless --path . -s res://test/melee_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _rock: Node2D


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
			main.round_manager._t = 600.0  # hold the countdown open
			_stage_throw_and_wave(main)
		8:
			_stage_hammer_setup(main)
		11:
			# A frame later, so the physics space has the staged positions.
			_stage_hammer_swing(main)
		13:
			_check(_rock == null or _rock.is_queued_for_deletion()
					or not is_instance_valid(_rock),
					"hammer swing did not smash the rock")
			_finish()
	return false


func _stage_throw_and_wave(main: Node) -> void:
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	# Equal and opposite: hurling the starting shotgun moves you back.
	a.global_position = Vector2(-1200, -600)
	a.velocity = Vector2.ZERO
	a.throw_weapon(Vector2.RIGHT)
	_check(a.velocity.x < -300.0, "throw recoil missing (%s)" % a.velocity)
	_check(int(a.primary) < 0, "thrown gun still equipped")
	# Concussion: a non-lethal blast copy still shoves local ships.
	b.global_position = Vector2(1200, 600)
	b.velocity = Vector2.ZERO
	var hp: float = b.health
	Explosions.blast(main, b.global_position + Vector2(120, 0),
			150.0, 50.0, 0, false, null, false)
	_check(b.velocity.x < -100.0, "shockwave did not push the ship (%s)" % b.velocity)
	_check(b.health == hp, "non-lethal blast dealt damage")


func _stage_hammer_setup(main: Node) -> void:
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	var b: Node = players[1]
	a.global_position = Vector2(-1200, 600)
	a.velocity = Vector2.ZERO
	b.global_position = a.global_position + Vector2(80, 30)
	b.velocity = Vector2.ZERO
	b.health = b.MAX_HEALTH
	main.asteroid_spawner.spawn([0, a.global_position + Vector2(80, -30), false])
	_rock = main.get_node("Asteroids").get_children().back()
	a.give_weapon(WeaponDB.Weapon.HAMMER, -1)
	_check(int(a.weapon) == WeaponDB.Weapon.HAMMER, "hammer not equipped")
	_check(WeaponDB.rarity_of(WeaponDB.Weapon.HAMMER) == WeaponDB.Rarity.LEGENDARY,
			"the hammer must be legendary")


func _stage_hammer_swing(main: Node) -> void:
	var players: Array = main.get_node("Players").get_children()
	var a: Node = players[0]
	a.velocity = Vector2.ZERO  # the staging frame may have drifted bodies
	var kills: int = int(main.scores.get(a.fighter_key(), 0))
	a._fire_fx(Vector2.RIGHT, WeaponDB.Weapon.HAMMER)
	_check(int(main.scores.get(a.fighter_key(), 0)) == kills + 1,
			"hammer swing did not one-shot the ship beside it")


func _finish() -> void:
	if _failed:
		print("MELEE TEST FAILED")
		quit(1)
	else:
		print("MELEE TEST OK")
		quit(0)
