# Last-one-standing rounds for versus play: countdown, fight until one
# player survives, flash the result, repeat — first to ROUNDS_TO_WIN
# takes the match. Runs where the server runs (couch mode is the
# offline server, so everything here is direct calls).
class_name RoundManager
extends Node

enum Phase { COUNTDOWN, FIGHT, ROUND_END, MATCH_END }

const COUNTDOWN_TIME := 3.0
const FIGHT_BANNER_TIME := 0.9
const ROUND_END_TIME := 2.5
const MATCH_END_TIME := 6.0
const ROUNDS_TO_WIN := 5

var phase: int = Phase.COUNTDOWN
var round_num := 0
var round_wins := {}  # fighter key -> rounds won
var banner_text := ""
var banner_color := Color(0.96, 0.96, 1.0)

var _t := 0.0
var _fight_t := 0.0
var _banner_until := 0.0
var _event_at := -1.0  # fight time when this round's chaos event fires
var _dead_keys := {}
var _zone: ShrinkZone

@onready var main: Node = get_parent()


func _ready() -> void:
	_zone = ShrinkZone.new()
	_zone.name = "ShrinkZone"
	main.add_child.call_deferred(_zone)
	_begin_countdown()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_t -= delta
	match phase:
		Phase.COUNTDOWN:
			banner_text = "ROUND %d\n%d" % [round_num, ceili(maxf(_t, 0.01))]
			if _t <= 0.0:
				_begin_fight()
		Phase.FIGHT:
			_fight_t += delta
			if _fight_t > _banner_until and banner_text != "":
				banner_text = ""
			if _event_at > 0.0 and _fight_t >= _event_at:
				_event_at = -1.0
				_fire_event(randi() % 3)
		Phase.ROUND_END:
			if _t <= 0.0:
				if _best_wins() >= ROUNDS_TO_WIN:
					_begin_match_end()
				else:
					_begin_countdown()
		Phase.MATCH_END:
			if _t <= 0.0:
				Net.leave()


func fight_active() -> bool:
	return phase == Phase.FIGHT


# Called by main.report_death for every player death, including zone
# burn (attacker 0). Survivor count decides the round.
func on_player_died(victim_key: int) -> void:
	if phase != Phase.FIGHT:
		return
	_dead_keys[victim_key] = true
	var alive: Array = []
	for p in _players():
		if not _dead_keys.has(p.fighter_key()):
			alive.append(p)
	if alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else null)


func _begin_countdown() -> void:
	round_num += 1
	phase = Phase.COUNTDOWN
	_t = COUNTDOWN_TIME
	_dead_keys.clear()
	_zone.reset()
	banner_color = Color(0.96, 0.96, 1.0)
	var spawns: Array = main.PLAYER_SPAWNS
	for p in _players():
		p.revive(spawns[p.slot % spawns.size()])
		p.reset_loadout()
		p.input_locked = true


func _begin_fight() -> void:
	phase = Phase.FIGHT
	_fight_t = 0.0
	banner_text = "FIGHT!"
	banner_color = Color(1.0, 0.62, 0.1)
	_banner_until = FIGHT_BANNER_TIME
	_event_at = randf_range(12.0, 25.0)
	_zone.start()
	for p in _players():
		p.input_locked = false


# One chaos event per round, somewhere in the middle of the fight.
func _fire_event(which: int) -> void:
	banner_color = Color(1.0, 0.45, 0.15)
	match which:
		0:
			banner_text = "ASTEROID SHOWER"
			for i in 10:
				var pos: Vector2 = main._edge_spawn()
				var vel := pos.direction_to(Vector2.ZERO).rotated(randf_range(-0.5, 0.5)) \
						* randf_range(220.0, 350.0)
				main.asteroid_spawner.spawn([randi() % 2, pos, randf() < 0.3, vel])
		1:
			banner_text = "ARMS RACE"
			for p in _players():
				if not p.visible:
					continue
				var kind := _roll_high_tier()
				p._net_receive_weapon.rpc_id(p.get_multiplayer_authority(),
						kind, int(WeaponDB.DATA[kind]["max_ammo"]))
		2:
			banner_text = "SUPPLY DROP"
			for i in 6:
				var dir := Vector2.from_angle(i * TAU / 6.0 + randf() * 0.5)
				var kind := WeaponDB.roll_weapon()
				main.spawn_weapon_pickup(kind, int(WeaponDB.DATA[kind]["max_ammo"]),
						dir * 60.0, dir * randf_range(120.0, 200.0), randf_range(-2.0, 2.0))
	_banner_until = _fight_t + 2.2


func _roll_high_tier() -> int:
	var pool: Array = []
	for id in WeaponDB.DATA:
		if int(WeaponDB.DATA[id]["rarity"]) >= WeaponDB.Rarity.EPIC:
			pool.append(id)
	return pool[randi() % pool.size()]


func _end_round(winner: Node) -> void:
	phase = Phase.ROUND_END
	_t = ROUND_END_TIME
	if winner != null:
		var key: int = winner.fighter_key()
		round_wins[key] = int(round_wins.get(key, 0)) + 1
		banner_text = "P%d TAKES THE ROUND" % (int(winner.slot) + 1)
		banner_color = winner.COLORS[winner.color_idx % winner.COLORS.size()]
		Juice.slowmo(0.3, 1.0)
	else:
		banner_text = "NOBODY SURVIVES"
		banner_color = Color(0.66, 0.68, 0.76)


func _begin_match_end() -> void:
	phase = Phase.MATCH_END
	_t = MATCH_END_TIME
	for p in _players():
		if int(round_wins.get(p.fighter_key(), 0)) >= ROUNDS_TO_WIN:
			banner_text = "P%d WINS THE MATCH" % (int(p.slot) + 1)
			banner_color = p.COLORS[p.color_idx % p.COLORS.size()]
			break


func _best_wins() -> int:
	var best := 0
	for w in round_wins.values():
		best = maxi(best, int(w))
	return best


func _players() -> Array:
	return main.get_node("Players").get_children()
