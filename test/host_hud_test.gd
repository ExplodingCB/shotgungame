# Regression test: the HUD must disconnect from Net.host_info_changed
# when the game scene dies. A stale connection used to crash the next
# host with "Invalid assignment of property 'text' ... on Nil".
# Run with:
#   godot --headless --path . -s res://test/host_hud_test.gd
extends SceneTree

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main


func _process(_delta: float) -> bool:
	_frames += 1
	var net: Node = root.get_node("Net")
	if _frames == 3:
		var n: int = net.host_info_changed.get_connections().size()
		if n != 1:
			push_error("FAIL: expected the HUD connected once, got %d" % n)
			print("HOST HUD TEST FAILED")
			quit(1)
			return false
		_main.queue_free()
	elif _frames == 6:
		var n: int = net.host_info_changed.get_connections().size()
		if n != 0:
			push_error("FAIL: %d stale connection(s) survived the scene change" % n)
			print("HOST HUD TEST FAILED")
			quit(1)
			return false
		# Emitting now must not touch any freed label.
		net.host_info = "host again after a round"
		net.host_info_changed.emit()
		print("HOST HUD TEST OK")
		quit(0)
	return false
