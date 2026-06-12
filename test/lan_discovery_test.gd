# Headless test for LAN room discovery: a responder and probers talk
# over loopback inside one process. Run with:
#   godot --headless --path . -s res://test/lan_discovery_test.gd
extends SceneTree

const CODE := "KQ7M-2PXD"
const GAME_PORT := 7781

var _responder: LanDiscovery.Responder
var _second: LanDiscovery.Responder
var _good: LanDiscovery.Prober
var _bad: LanDiscovery.Prober
var _frames := 0
var _found := {}


func _initialize() -> void:
	_responder = LanDiscovery.Responder.new()
	if not _responder.start():
		push_error("responder could not bind any discovery port")
		quit(1)
		return
	_responder.code = CODE
	_responder.game_port = GAME_PORT

	# A second responder must coexist by taking the next port.
	_second = LanDiscovery.Responder.new()
	if not _second.start():
		push_error("second responder could not bind alongside the first")
		quit(1)
		return
	_second.code = "AAAA-AAAA"
	_second.game_port = 7782

	_good = LanDiscovery.Prober.new()
	_bad = LanDiscovery.Prober.new()
	# Lowercase, no dash: the responder must normalize before matching.
	if not _good.start("kq7m2pxd") or not _bad.start("ZZZZ-ZZZZ"):
		push_error("prober could not start")
		quit(1)


func _process(_delta: float) -> bool:
	_frames += 1
	_responder.poll()
	_second.poll()
	if _found.is_empty():
		_found = _good.poll()
	var wrong := _bad.poll()
	if not wrong.is_empty():
		push_error("responder answered a wrong-code probe: %s" % wrong)
		quit(1)
		return true
	# Give the wrong-code prober time to (not) hear back after the good
	# one succeeded.
	if not _found.is_empty() and _frames >= 60:
		if int(_found["port"]) != GAME_PORT:
			push_error("reply carried port %s, want %d" % [_found["port"], GAME_PORT])
			quit(1)
			return true
		print("LAN DISCOVERY TEST OK (host %s:%s)" % [_found["ip"], _found["port"]])
		quit(0)
		return true
	if _frames > 600:
		push_error("no discovery reply after %d frames" % _frames)
		quit(1)
		return true
	return false
