# A kill-laser running from this node's origin along +x for `length`.
# Blinks on a warn -> lethal -> off cycle unless always_on. Every peer
# animates its own clock from the moment the fight goes live (identical
# geometry and timings everywhere), while damage runs only on the
# server so visual drift can't cause phantom kills. Players are checked
# with a per-frame path sweep so no speed tunnels through the beam.
class_name LaserStrip
extends Node2D

enum Beam { OFF, WARN, ON }

@export var length := 800.0
@export var always_on := false
@export var warn_time := 0.6
@export var on_time := 1.4
@export var off_time := 1.5
@export var phase_offset := 0.0

const PLAYER_DAMAGE := 30.0
const ROCK_DAMAGE := 10.0
const TICK := 0.25
const WIDTH := 10.0
const TOUCH := 24.0  # half-width counted as a hit: beam glow + ship hull
const REHIT := 0.35  # per-player cooldown so a burn isn't applied every frame
const MAX_FRAME_HOP := 320.0  # farther than any flown frame: a warp, not a path

var _t := 0.0
var _tick := 0.0
var _prev := {}   # player instance id -> last beam-local position
var _burnt := {}  # player instance id -> damage cooldown remaining


func _physics_process(delta: float) -> void:
	queue_redraw()
	var live := _running()
	if live:
		_t += delta
	else:
		_t = 0.0
	if not multiplayer.is_server():
		return
	# Players get a swept check every frame: comparing each ship's path
	# against the beam catches crossings between frames, so top speed
	# can't tunnel through the way the old 0.25s tick allowed.
	_sweep_players(delta, live and state() == Beam.ON)
	if live and state() == Beam.ON:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			_zap()


# Track every player's beam-local position each frame and burn the ones
# whose path touched or crossed the lethal line since the last frame.
func _sweep_players(delta: float, lethal: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var id: int = p.get_instance_id()
		var cur: Vector2 = to_local(p.global_position)
		var prev: Vector2 = _prev.get(id, cur)
		_prev[id] = cur
		# Portal hops, respawns, and network warps move a ship much
		# farther in one frame than flying ever could. No path was flown
		# across the arena, so nothing crossed the beam — only genuine
		# contact at the new spot counts.
		if prev.distance_to(cur) > MAX_FRAME_HOP:
			prev = cur
		var cd: float = maxf(float(_burnt.get(id, 0.0)) - delta, 0.0)
		_burnt[id] = cd
		if not lethal or not p.visible or cd > 0.0:
			continue
		if not _path_hits(prev, cur):
			continue
		_burnt[id] = REHIT
		var side := signf(cur.y)
		if side == 0.0:
			side = signf(cur.y - prev.y)
		if side == 0.0:
			side = 1.0
		var dir := (global_transform.y * side).normalized()
		p.take_damage(PLAYER_DAMAGE, dir, p.global_position, 0)


# Beam-local space: the laser is the segment y = 0, x in [0, length].
func _path_hits(prev: Vector2, cur: Vector2) -> bool:
	# Sitting on (or skimming) the beam right now.
	if absf(cur.y) <= TOUCH and cur.x >= -TOUCH and cur.x <= length + TOUCH:
		return true
	# Jumped clean across between frames: find where the path met y = 0.
	if (prev.y > 0.0) == (cur.y > 0.0) or absf(prev.y - cur.y) < 0.001:
		return false
	var t := prev.y / (prev.y - cur.y)
	var x := lerpf(prev.x, cur.x, t)
	return x >= -TOUCH and x <= length + TOUCH


# Lasers idle outside the fight (warm-up, countdown, round end) so
# nobody dies between rounds. With no round manager (solo, tests) they
# just run.
func _running() -> bool:
	var main := get_tree().current_scene
	if main == null or not ("round_manager" in main) or main.round_manager == null:
		return true
	return main.round_manager.fight_active()


func state() -> int:
	if always_on:
		return Beam.ON
	if _t <= 0.0:
		return Beam.OFF
	var cycle := warn_time + on_time + off_time
	var t := fposmod(_t + phase_offset, cycle)
	if t < warn_time:
		return Beam.WARN
	if t < warn_time + on_time:
		return Beam.ON
	return Beam.OFF


# Coarse tick for rocks and enemy ships; players are handled by the
# per-frame swept check above.
func _zap() -> void:
	var seg := SegmentShape2D.new()
	seg.a = Vector2.ZERO
	seg.b = Vector2(length, 0.0)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = seg
	q.transform = global_transform
	q.collision_mask = 3  # world bodies + ships
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c: Object = hit["collider"]
		if c is StaticBody2D or not (c is Node2D) or not c.has_method("take_damage"):
			continue
		if (c as Node).is_in_group("player"):
			continue
		# Shove perpendicular to the beam, away from whichever side the
		# body is on, so the burn also pushes you off the line.
		var side := signf(to_local((c as Node2D).global_position).y)
		if side == 0.0:
			side = 1.0
		var dir := (global_transform.y * side).normalized()
		c.take_damage(ROCK_DAMAGE, dir, (c as Node2D).global_position, 0)


func _draw() -> void:
	var to := Vector2(length, 0.0)
	match state():
		Beam.WARN:
			var a := 0.25 + 0.2 * sin(_t * 40.0)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.3, 0.32, a), 2.0)
		Beam.ON:
			draw_line(Vector2.ZERO, to, Color(1.0, 0.25, 0.3, 0.25), WIDTH * 3.2)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.45, 0.45, 0.95), WIDTH)
			draw_line(Vector2.ZERO, to, Color(1.0, 0.9, 0.9, 0.9), WIDTH * 0.35)
		_:
			pass
	# Emitter studs at both ends, visible even while the beam rests.
	for p in [Vector2.ZERO, to]:
		draw_circle(p, 7.0, Color(0.55, 0.1, 0.14))
		draw_circle(p, 4.0, Color(1.0, 0.35, 0.35))
