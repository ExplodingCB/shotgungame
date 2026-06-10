# Headless test of the throw/grab weapon economy:
#  - world pickups all spawn as weapons with a full magazine
#  - throwing drops a pickup carrying the gun's exact remaining ammo
#  - E-grab within radius equips the pickup (swap drops your old gun)
#  - empty weapons stay equipped and dry-fire instead of breaking
# Run with:
#   godot --headless --path . -s res://test/pickup_throw_test.gd
extends SceneTree

const AK := WeaponDB.Weapon.AK47
const THROWN_AMMO := 17

var _frames := 0
var _failed := false
var _world_count := 0


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _pickups() -> Array:
	return root.get_node("Main/Pickups").get_children()


func _player() -> Node:
	return get_first_node_in_group("player")


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			# World spawned weapons only, each with a full magazine.
			_world_count = _pickups().size()
			_check(_world_count == root.get_node("Main").WEAPON_PICKUPS,
					"expected %s world pickups, got %d" % [root.get_node("Main").WEAPON_PICKUPS, _world_count])
			for p in _pickups():
				_check(int(p.kind) >= 0, "shell pack found; pickups should all be weapons")
				_check(int(p.ammo) == int(WeaponDB.DATA[p.kind]["max_ammo"]),
						"%s spawned with %s ammo, expected full %s"
						% [WeaponDB.DATA[p.kind]["name"], p.ammo, WeaponDB.DATA[p.kind]["max_ammo"]])
			# Throw a partly-used AK.
			var pl := _player()
			pl.give_weapon(AK, THROWN_AMMO)
			pl.throw_weapon(Vector2.RIGHT)
			_check(int(pl.primary) == -1, "throw should empty the primary slot")
			_check(int(pl.weapon) == WeaponDB.Weapon.PISTOL, "throw should switch to pistol")
		7:
			# The thrown AK exists as a pickup with its ammo intact.
			var thrown: Node = null
			for p in _pickups():
				if int(p.kind) == AK and int(p.ammo) == THROWN_AMMO:
					thrown = p
			_check(thrown != null, "thrown AK with %d ammo not found in world" % THROWN_AMMO)
			_check(_pickups().size() == _world_count + 1,
					"expected %d pickups after throw, got %d" % [_world_count + 1, _pickups().size()])
			if thrown != null:
				# Fly over and grab it back.
				var pl := _player()
				pl.global_position = thrown.global_position + Vector2(10, 0)
				pl._try_pickup()
		9:
			var pl := _player()
			_check(int(pl.primary) == AK, "grab should equip the AK (primary=%s)" % pl.primary)
			_check(int(pl.ammo[AK]) == THROWN_AMMO,
					"grabbed AK should keep %d ammo (got %s)" % [THROWN_AMMO, pl.ammo[AK]])
			_check(_pickups().size() == _world_count,
					"grabbed pickup should leave the world (have %d)" % _pickups().size())
			# Drain to zero: weapon stays, dry-fires, and can be thrown empty.
			pl.ammo[AK] = 1
			pl._switch_weapon(AK)
			pl._cooldown = 0.0
			pl._fire(Vector2.RIGHT)
			pl._cooldown = 0.0
			pl._fire(Vector2.RIGHT)  # dry click
			_check(int(pl.primary) == AK, "empty weapon must stay equipped")
			_check(int(pl.ammo[AK]) == 0, "empty weapon ammo should sit at 0")
			pl.throw_weapon(Vector2.DOWN)
		11:
			var found_empty := false
			for p in _pickups():
				if int(p.kind) == AK and int(p.ammo) == 0:
					found_empty = true
			_check(found_empty, "thrown empty AK should exist as a 0-ammo pickup")
			if _failed:
				print("PICKUP TEST FAILED")
				quit(1)
			else:
				print("PICKUP TEST OK")
				quit(0)
	return false
