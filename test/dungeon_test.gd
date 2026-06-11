# Headless run-through of Dungeon Dive: boots the dungeon scene, clears
# rooms 1-4 by force, checks the gate flow (including the boss gate at
# depth 4 and the perk choice after the Warden), exercises the full
# enemy roster, props, room shapes, minor upgrades and the AUX RACK
# second slot, then dies and checks the game-over state. Run with:
#   godot --headless --path . -s res://test/dungeon_test.gd
extends SceneTree

var _frames := 0
var _t := 0.0
var _stage := 0
var _failed := false
var _expected_depth := 1
var _perk_done := false
var _mark := 0


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
	# Kamikaze blasts and sniper beams chip the player between wipes.
	var p: Node = main._player()
	if p != null:
		p.health = p.max_health


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

		3:  # resolve any perk/upgrade choice, then take a gate
			if hud._choice_layer != null:
				if not _perk_done:
					_perk_done = true
					hud._choose(0)
					_check((main.perks as Array).size() >= 1, "perk was not recorded")
					_check(not root.get_node("Net").ui_open, "ui_open stuck after perk choice")
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

		5:  # shape invariants: blocks stay in bounds, entry/gate strips clear
			var rect: Rect2 = main._room_rect
			var entry := Vector2(rect.position.x + 170.0, 0.0)
			var gate_strip := Rect2(rect.end.x - 340.0, -460.0, 340.0, 920.0)
			for shape in 6:
				for b in main._blocks_for(shape):
					var block := b as Rect2
					_check(rect.grow(8.0).encloses(block),
							"shape %d block leaves the room: %s" % [shape, block])
					_check(not block.grow(40.0).has_point(entry),
							"shape %d block covers the entry" % shape)
					_check(not block.intersects(gate_strip),
							"shape %d block covers the gate strip" % shape)
			_stage = 6

		6:  # roster + props coverage: one of everything, then break it all
			var p: Node = main._player()
			var center: Vector2 = main._room_rect.get_center()
			for kind in 11:
				main.spawn_enemy(kind, center + Vector2.from_angle(kind * TAU / 11.0) * 380.0, false)
			_check(int(main.enemies_alive) >= 11, "roster spawn came up short")
			var props_node: Node = main.get_node("Props")
			var mine := DungeonMine.new()
			mine.position = center + Vector2(0, 560)
			props_node.add_child(mine)
			var crate := DungeonCrate.new()
			crate.position = center + Vector2(120, 560)
			props_node.add_child(crate)
			var wreck := DungeonWreck.new()
			wreck.position = center + Vector2(-160, 560)
			props_node.add_child(wreck)
			_mark = _frames
			_stage = 7

		7:  # let the brains tick (snipers aim, bombers lob, layers seed)
			if _frames == _mark + 50:
				var props_node: Node = main.get_node("Props")
				var pickups_before: int = main.get_node("Pickups").get_child_count()
				for c in props_node.get_children():
					if not c.is_queued_for_deletion() and c.has_method("take_damage"):
						c.take_damage(100000.0, Vector2.RIGHT, c.global_position, 1)
				_check(main.get_node("Pickups").get_child_count() > pickups_before,
						"broken wreck dropped no weapon")
				_mark = _frames
				_stage = 8

		8:  # wipe the menagerie (kamikaze blasts + splitter spawn echoes)
			if _frames % 10 == 0:
				_wipe(main)
			if int(main.enemies_alive) <= 0 and main.get_node("Enemies").get_child_count() == 0:
				_stage = 9
			elif _t > 50.0:
				_fail_now(main, "roster coverage never wiped clean")

		9:  # AUX RACK second slot + perk pools, then die
			var p: Node = main._player()
			p.health = p.max_health
			DungeonPerks.apply(p, main, DungeonPerks.Perk.AUX_RACK)
			_check(bool(p.second_slot), "AUX RACK did not grant the slot")
			p.give_weapon(WeaponDB.Weapon.AK47, 30)
			_check(int(p.primary_b) == WeaponDB.Weapon.AK47,
					"free second slot should take the new gun (primary_b=%s)" % p.primary_b)
			_check(int(p.primary) == WeaponDB.Weapon.SHOTGUN, "primary should keep the shotgun")
			p._switch_weapon(int(p.primary))
			p.give_weapon(WeaponDB.Weapon.M4, 40)
			_check(int(p.primary) == WeaponDB.Weapon.M4, "wielded primary should be replaced")
			_check(int(p.primary_b) == WeaponDB.Weapon.AK47, "second slot should be untouched")
			p._toggle_weapon()
			_check(int(p.weapon) == WeaponDB.Weapon.PISTOL, "cycle: primary to pistol")
			p._toggle_weapon()
			_check(int(p.weapon) == WeaponDB.Weapon.AK47, "cycle: pistol to second slot")
			p._toggle_weapon()
			_check(int(p.weapon) == WeaponDB.Weapon.M4, "cycle: second slot to primary")
			p.throw_weapon(Vector2.RIGHT)
			_check(int(p.primary) < 0 and int(p.primary_b) == WeaponDB.Weapon.AK47,
					"throw should empty the wielded slot only")
			for id in DungeonPerks.MINORS:
				DungeonPerks.apply(p, main, id)
			_check(p.fire_rate_mult > 1.0 and p.max_health > 100.0, "minor upgrades had no effect")
			for i in 20:
				var picks: Array = DungeonPerks.roll_minor(2, p)
				_check(picks.size() == 2 and DungeonPerks.DATA.has(picks[0]),
						"roll_minor returned junk: %s" % str(picks))
			for i in 30:
				var w := WeaponDB.roll_weapon(i % 9)
				_check(WeaponDB.DATA.has(w), "roll_weapon(luck) returned junk: %s" % w)
			p.take_damage(100000.0, Vector2.RIGHT, p.global_position, 0)
			_stage = 10
			_t = 0.0

		10:
			if main.run_over:
				_check(not main._player().visible, "dead player still visible")
				_done(main)
			elif _t > 4.0:
				_fail_now(main, "death did not end the run")

	if _t > 70.0:
		_fail_now(main, "stage %d timed out" % _stage)
	return false
