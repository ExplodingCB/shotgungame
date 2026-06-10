# Game-feel autoload: hitstop, slow motion, and controller rumble.
# Time effects work through Engine.time_scale, restored by polling real
# (unscaled) clock time every frame, so the game can never get stuck
# slow — whatever fires or overlaps, _process converges back to 1.0.
extends Node

const STOP_SCALE := 0.05
const POOL_THRESHOLD := 8.0  # min damage in a frame to freeze for

var _pending_hit := 0.0
var _stop_until := 0
var _stop_scale := STOP_SCALE
var _slow_until := 0
var _slow_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# Pool damage landed this frame: a 12-pellet shotgun blast should slam
# once, not twelve times, and single SMG ticks shouldn't freeze at all.
func hit_landed(amount: float) -> void:
	_pending_hit += amount


func hitstop(ms: int, scale := STOP_SCALE) -> void:
	# Online peers run their own simulations; long freezes drift them
	# apart, so halve the effect and let the synchronizer absorb it.
	if Net.mode == Net.Mode.HOST or Net.mode == Net.Mode.JOIN:
		ms = int(ms * 0.5)
	if ms <= 0:
		return
	_stop_until = maxi(_stop_until, Time.get_ticks_msec() + ms)
	_stop_scale = scale
	_apply()


func slowmo(scale := 0.3, dur := 1.0) -> void:
	if Net.mode == Net.Mode.HOST or Net.mode == Net.Mode.JOIN:
		return
	_slow_until = maxi(_slow_until, Time.get_ticks_msec() + int(dur * 1000.0))
	_slow_scale = scale
	_apply()


func rumble(device: int, weak: float, strong: float, dur: float) -> void:
	if device >= 0:
		Input.start_joy_vibration(device, weak, strong, dur)


func _process(_delta: float) -> void:
	if _pending_hit >= POOL_THRESHOLD:
		hitstop(clampi(int(_pending_hit * 2.5), 20, 70))
	_pending_hit = 0.0
	_apply()


func _apply() -> void:
	var now := Time.get_ticks_msec()
	var t := 1.0
	if now < _stop_until:
		t = minf(t, _stop_scale)
	if now < _slow_until:
		t = minf(t, _slow_scale)
	if Engine.time_scale != t:
		Engine.time_scale = t
