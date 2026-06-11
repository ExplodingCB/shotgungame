# Headless run-through of Dungeon Dive: boots the dungeon scene, clears
# rooms 1-4 by force, checks the gate flow (including the boss gate at
# depth 4 and the perk choice after the Warden), then dies and checks
# the game-over state. Run with:
#   godot --headless --path . -s res://test/dungeon_test.gd
extends SceneTree

var _frames := 0
var _t := 0.0
var _stage := 0
var _failed := false
var _expected_depth := 1
var _perk_done := false


func _initialize() -> void:
	var main: Node = (load("res://scenes/dungeon.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _fail_now(main: Node, msg: String) -> void:
	_check(false, msg)
	_done(main)


func _done(main: Node) -> void:
	if _failed:
		print("DUNGEON TEST FAILED")
		quit(1)
	else:
		print("DUNGEON TEST OK (depth=%s kills=%s perks=%s)"
				% [main.depth, main.kills, (main.perks as Array).size()])
		quit(0)


func _wipe(main: Node) -> void:
	for e in main.get_node("Enemies").get_children():
		if not e.is_queued_for_deletion():
			e.take_damage(100000.0, Vector2.RIGHT, e.global_position, 1)


func _process(delta: float) -> bool:
	_frames += 1
	_t += delta
	var main: Node = root.get_node("Dungeon")
	var hud: Node = main.get_node("HUD/DungeonHud")

	match _stage:
		0:  # boot: player spawned, depth 1, gates already standing (locked)
			if main.get_node("Players").get_child_count() == 1 and int(main.depth) == 1:
				_check(main.get_node("Doors").get_child_count() >= 2, "depth 1 should offer 2+ gates")
				for d in main.get_node("Doors").get_children():
					_check(d.locked, "gates must start locked")
				_stage = 1
				_t = 0.0
			elif _t > 5.0:
				_fail_now(main, "dungeon never booted")

		1:  # enemies arrive after the spawn delay + telegraph
			if int(main.enemies_alive) > 0:
				_stage = 2
				_t = 0.0
			elif _t > 8.0:
				_fail_now(main, "no enemies spawned at depth %s" % main.depth)

		2:  # wipe pulses until the room reports clear
			if _frames % 10 == 0:
				_wipe(main)
			if main.room_clear:
				_stage = 3
				_t = 0.0
			elif _t > 25.0:
				_fail_now(main, "room at depth %s never cleared" % main.depth)

		3:  # resolve a perk choice if one is up, then take a gate
			if hud._choice_layer != null:
				if not _perk_done:
					_perk_done = true
					var before: float = main._player().fire_rate_mult
					hud._choose(0)
					_check((main.perks as Array).size() >= 1, "perk was not recorded")
					_check(not root.get_node("Net").ui_open, "ui_open stuck after perk choice")
					# At least prove the apply path ran without breaking mods.
					_check(main._player().fire_rate_mult >= before, "perk apply mangled mods")
				return false
			var doors: Array = main.get_node("Doors").get_children()
			_check(doors.size() > 0, "no gates after clearing depth %s" % main.depth)
			for d in doors:
				_check(not d.locked, "gates still locked after clear")
			if int(main.depth) == 4:
				_check(doors.size() == 1 and int(doors[0].reward) == DungeonDoor.Reward.BOSS,
						"depth 4 should offer exactly the Warden's gate")
			if int(main.depth) >= 5:
				# Boss down: spoils should be floating around.
				_check(main.get_node("Pickups").get_child_count() >= 1, "no boss spoils")
				_stage = 5
				return false
			_expected_depth = int(main.depth) + 1
			_perk_done = false
			main.enter_door(int(doors[0].reward))
			_stage = 4
			_t = 0.0

		4:  # ride the fade into the next room
			if int(main.depth) == _expected_depth:
				_check(not main.room_clear, "fresh room flagged clear")
				_stage = 1
				_t = 0.0
			elif _t > 6.0:
				_fail_now(main, "gate never carried us to depth %d" % _expected_depth)

		5:  # exercise every perk, then die and check the run-over state
			var p: Node = main._player()
			for id in DungeonPerks.DATA:
				DungeonPerks.apply(p, main, id)
			_check(p.fire_rate_mult > 1.0, "fire rate perk had no effect")
			_check(p.max_health > 100.0, "hull perk had no effect")
			_check(main.lifesteal > 0.0, "leech perk had no effect")
			for i in 30:
				var w := WeaponDB.roll_weapon(i % 9)
				_check(WeaponDB.DATA.has(w), "roll_weapon(luck) returned junk: %s" % w)
			p.take_damage(100000.0, Vector2.RIGHT, p.global_position, 0)
			_stage = 6
			_t = 0.0

		6:
			if main.run_over:
				_check(not main._player().visible, "dead player still visible")
				_done(main)
			elif _t > 4.0:
				_fail_now(main, "death did not end the run")

	if _t > 60.0:
		_fail_now(main, "stage %d timed out" % _stage)
	return false
