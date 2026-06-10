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
			if _fight_t > FIGHT_BANNER_TIME and banner_text != "":
				banner_text = ""
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
	_zone.start()
	for p in _players():
		p.input_locked = false


func _end_round(winner: Node) -> void:
	phase = Phase.ROUND_END
	_t = ROUND_END_TIME
	if winner != null:
		var key: int = winner.fighter_key()
		round_wins[key] = int(round_wins.get(key, 0)) + 1
		banner_text = "P%d TAKES THE ROUND" % (int(winner.slot) + 1)
		banner_color = winner.COLORS[winner.color_idx % winner.COLORS.size()]
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
