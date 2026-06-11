# Headless Nano-Medkit behaviors: touch collection, the overheal spike,
# and its slow decay back to the cap. Run with:
#   godot --headless --path . -s res://test/medkit_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _peak := 0.0


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
		_stage_collected()
	elif _frames == 80:
		_stage_decay()
		_finish()
	return false


func _setup() -> void:
	var main: Node = root.get_node("Main")
	main.round_manager._t = 600.0  # hold the countdown open
	var a: Node = main.get_node("Players").get_child(0)
	a.global_position = Vector2(400, 0)
	a.velocity = Vector2.ZERO
	a.health = 40.0
	# Drop a medkit right on top of the hurt player.
	main.pickup_spawner.spawn([main.MEDKIT_KIND, a.global_position, Vector2.ZERO, 0.0])


func _stage_collected() -> void:
	var main: Node = root.get_node("Main")
	var a: Node = main.get_node("Players").get_child(0)
	_check(get_nodes_in_group("medkits").is_empty(), "medkit was not collected on touch")
	_check(a.health > a.max_health, "touch did not overheal (%s)" % a.health)
	_check(a.health <= a.OVERHEAL_MAX + 0.01, "overheal exceeded the cap (%s)" % a.health)
	_peak = a.health


func _stage_decay() -> void:
	var main: Node = root.get_node("Main")
	var a: Node = main.get_node("Players").get_child(0)
	_check(a.health < _peak, "overheal did not decay (%s -> %s)" % [_peak, a.health])
	_check(a.health >= a.max_health, "decay dropped below full health (%s)" % a.health)


func _finish() -> void:
	if _failed:
		print("MEDKIT TEST FAILED")
		quit(1)
	else:
		print("MEDKIT TEST OK")
		quit(0)
