# Temporary headless check: runs the real host UPnP path against the
# local router, prints each host_info update, then tears down. Run with:
#   godot --headless --path . -s res://test/upnp_smoke_test.gd
extends SceneTree

var _t := 0.0
var _done := false
var _started := false


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		var net: Node = root.get_node("Net")
		net.host_info_changed.connect(func(): print("HOST INFO: ", net.host_info))
		net.mode = net.Mode.HOST
		net.setup_peer()
	_t += delta
	if _t > 12.0 and not _done:
		_done = true
		var net: Node = root.get_node("Net")
		print("external_ip=", net.external_ip)
		net._stop_upnp()
		print("UPNP TEST DONE")
		quit(0)
	return false
