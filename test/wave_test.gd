# Headless regression test for wave bookkeeping: overkilling one enemy
# (several shotgun pellets landing the same frame) must count as ONE
# death, and the next wave must start exactly once, only after every
# enemy is dead. Run with:
#   godot --headless --path . -s res://test/wave_test.gd
extends SceneTree

var _frames := 0
var _t := 0.0
var _failed := false
var _stage := 0
var _mark := 0
var _wave1_count := 0


func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _overkill(e: Node) -> void:
	# Same-frame pellet burst: every call lands before queue_free runs.
	for i in 6:
		e.take_damage(10000.0, Vector2.RIGHT, e.global_position)


func _pending_timers(main: Node) -> int:
	var n := 0
	for c in main.get_children():
		if c is Timer:
			n += 1
	return n


func _done(main: Node) -> void:
	if _failed:
		print("WAVE TEST FAILED")
		quit(1)
	else:
		print("WAVE TEST OK (final wave=%s, enemies=%d)" % [main.wave, main.get_node("Enemies").get_child_count()])
		quit(0)


func _process(delta: float) -> bool:
	_frames += 1
	_t += delta
	var main: Node = root.get_node("Main")

	# Stage 0: wait for the natural first wave (FIRST_WAVE_DELAY = 5s).
	if _stage == 0:
		if int(main.wave) == 1:
			_stage = 1
			_mark = _frames
			_wave1_count = main.get_node("Enemies").get_child_count()
			_check(_wave1_count == int(main.enemies_alive), "wave 1 spawn count mismatch")
			_overkill(main.get_node("Enemies").get_child(0))
		elif _t > 8.0:
			_check(false, "first wave never spawned")
			_done(main)

	# Two frames later the overkilled enemy is gone; exactly one death
	# may have been counted and no wave-break may be pending yet.
	elif _stage == 1 and _frames == _mark + 2:
		_stage = 2
		_check(int(main.enemies_alive) == _wave1_count - 1,
				"overkill counted %d deaths, expected 1 (enemies_alive=%s)"
				% [_wave1_count - int(main.enemies_alive), main.enemies_alive])
		_check(_pending_timers(main) == 0, "wave break scheduled while enemies remain")
		# Now overkill everything that's left.
		for e in main.get_node("Enemies").get_children():
			_overkill(e)

	elif _stage == 2 and _frames == _mark + 5:
		_stage = 3
		_t = 0.0
		_check(int(main.enemies_alive) == 0, "enemies_alive=%s after wiping wave" % main.enemies_alive)
		_check(_pending_timers(main) == 1,
				"%d wave timers pending, expected exactly 1" % _pending_timers(main))

	# WAVE_BREAK is 5s of game time; after 6s wave 2 must have started
	# exactly once: wave == 2 with one fresh batch of 1+wave enemies.
	elif _stage == 3 and _t > 6.0:
		_check(int(main.wave) == 2, "expected wave 2, got %s (stacked wave timers)" % main.wave)
		var expect := 1 + int(main.wave)
		var alive: int = main.get_node("Enemies").get_child_count()
		_check(alive == expect, "wave 2 spawned %d enemies, expected %d" % [alive, expect])
		_check(int(main.enemies_alive) == expect,
				"enemies_alive=%s, expected %d" % [main.enemies_alive, expect])
		_done(main)
	return false
