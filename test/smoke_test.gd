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
	if _frames >= 90:
		print("SMOKE TEST OK")
		quit(0)
	return false


func _exercise() -> void:
	var player: Node = get_first_node_in_group("player")
	if player == null:
		push_error("no player spawned")
		quit(1)
		return
	# Pistol, then each primary via the pickup path.
	player._switch_weapon(1)
	player._fire(Vector2.RIGHT)
	for w in [0, 2, 3]:
		player.give_weapon(w)
		player._cooldown = 0.0
		player._fire(Vector2.RIGHT)
	# Drain a pickup weapon to zero: it must break and hand back the shotgun.
	player.give_weapon(3)
	player.ammo[3] = 1
	player._cooldown = 0.0
	player._fire(Vector2.RIGHT)
	if int(player.primary) != 0 or int(player.weapon) != 0:
		push_error("spent pickup weapon did not return the shotgun (primary=%s weapon=%s)"
				% [player.primary, player.weapon])
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
