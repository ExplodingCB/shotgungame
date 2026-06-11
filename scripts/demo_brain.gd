# AI stand-in for a couch player's PlayerInput, driving the main
# menu's background demo. It plays by the real rules: recoil from
# firing is the only engine, so it aims at rivals to brawl, aims away
# from dropped guns to surf onto them, and grabs what lands in reach.
class_name DemoBrain
extends PlayerInput

const PICKUP_INTEREST := 700.0
const TURN_STEP := 0.09  # rad per physics frame; ~5 rad/s of gun swing

var _ship: CharacterBody2D
var _aim_dir := Vector2.RIGHT
var _smooth_aim := Vector2.RIGHT
var _next_think := 0.0
var _burst_until := 0.0


func _init(ship: CharacterBody2D) -> void:
	super(ship.device)
	_ship = ship


# aim() is polled every physics frame, so thinking piggybacks on it.
# The gun sweeps toward the intended direction instead of snapping.
func aim(_player: Node2D) -> Vector2:
	_think()
	var diff := _smooth_aim.angle_to(_aim_dir)
	_smooth_aim = _smooth_aim.rotated(clampf(diff, -TURN_STEP, TURN_STEP)).normalized()
	return _smooth_aim


# Hold fire until the sweep is roughly on target, so recoil pushes
# where the brain meant to go instead of wherever the gun happened
# to point mid-swing.
func fire_held() -> bool:
	return _now() < _burst_until \
			and absf(_smooth_aim.angle_to(_aim_dir)) < 0.5


func spin_axis() -> float:
	return 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _think() -> void:
	var now := _now()
	if now < _next_think or not is_instance_valid(_ship):
		return
	_next_think = now + randf_range(0.35, 0.85)

	# Brains never dry-fire: recoil is the engine, and a ship with an
	# empty gun just sits there killing the demo.
	_ship.ammo[int(_ship.weapon)] = 99

	# Bursts get the gun-sweep time on top, so a big course change
	# still ends in actual shots once the barrel arrives.
	var sweep := absf(_smooth_aim.angle_to(_aim_dir)) / (TURN_STEP * 60.0)

	# Drifted out of the arena: recoil pushes opposite the muzzle, so
	# face away from center and blast yourself home.
	var lh: Node = _ship.get_node_or_null("../../LevelHost")
	if lh != null:
		var bounds: Rect2 = lh.bounds
		if not bounds.grow(-80.0).has_point(_ship.global_position):
			_aim_dir = (_ship.global_position - bounds.get_center()).normalized()
			_burst_until = now + sweep + 0.5
			return

	# A dropped gun nearby: grab it if it's in reach, else recoil-surf
	# toward it.
	var pickup := _nearest_pickup()
	if pickup != null:
		if _ship.global_position.distance_to(pickup.global_position) <= _ship.GRAB_RADIUS:
			_ship._try_pickup()
		elif randf() < 0.5:
			_aim_dir = (_ship.global_position - pickup.global_position).normalized()
			_burst_until = now + sweep + 0.4
			return

	# Brawl: pepper a rival, with enough jitter to stay scrappy.
	var rival := _pick_rival()
	if rival != null:
		_aim_dir = _ship.global_position.direction_to(rival.global_position) \
				.rotated(randf_range(-0.22, 0.22))
		if _ship.grenades > 0 and randf() < 0.1:
			_ship.throw_grenade(_aim_dir)
		_burst_until = now + sweep + randf_range(0.25, 0.7)
	else:
		_aim_dir = _aim_dir.rotated(randf_range(-1.0, 1.0))
		_burst_until = now + sweep + 0.3


# Usually the nearest living rival, sometimes a random one so the
# fight wanders.
func _pick_rival() -> Node2D:
	var alive := []
	for p in _ship.get_parent().get_children():
		if p != _ship and not p._dead:
			alive.append(p)
	if alive.is_empty():
		return null
	if randf() < 0.3:
		return alive.pick_random()
	var best: Node2D = null
	var best_d := INF
	for p in alive:
		var d: float = _ship.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _nearest_pickup() -> Node2D:
	var best: Node2D = null
	var best_d := PICKUP_INTEREST
	for p in _ship.get_tree().get_nodes_in_group("pickups"):
		var d: float = _ship.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
