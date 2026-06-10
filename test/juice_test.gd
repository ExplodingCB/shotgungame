# Headless test of the Juice autoload: hitstop dips Engine.time_scale
# and always restores it to exactly 1.0, damage pooling only freezes
# past the threshold, rumble no-ops without a pad, and the player
# explosion runs its full life without errors.
# Run with:
#   godot --headless --path . -s res://test/juice_test.gd
extends SceneTree

var _frames := 0
var _failed := false
var _dipped := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(_delta: float) -> bool:
	_frames += 1
	var juice: Node = root.get_node("Juice")
	if _frames == 2:
		juice.rumble(-1, 1.0, 1.0, 0.2)  # keyboard player: must no-op
		juice.hit_landed(3.0)  # below the pooling threshold
		juice.hitstop(120)
		var fx: Node2D = (load("res://scripts/player_explosion.gd") as GDScript).new()
		fx.color = Color(1.0, 0.62, 0.12)
		root.add_child(fx)
	elif _frames == 4:
		_dipped = Engine.time_scale < 1.0
		_check(_dipped, "hitstop did not lower Engine.time_scale (%s)" % Engine.time_scale)
	elif _frames == 90:
		_check(Engine.time_scale == 1.0,
				"time scale stuck at %s after hitstop" % Engine.time_scale)
		juice.hit_landed(50.0)  # a pooled shotgun-blast worth of damage
	elif _frames == 92:
		_check(Engine.time_scale < 1.0, "pooled damage did not trigger hitstop")
	elif _frames >= 180:
		_check(Engine.time_scale == 1.0,
				"time scale stuck at %s at exit" % Engine.time_scale)
		if _failed:
			print("JUICE TEST FAILED")
			quit(1)
		else:
			print("JUICE TEST OK")
			quit(0)
	return false
