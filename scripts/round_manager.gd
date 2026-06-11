# Match flow for versus play: a warm-up lobby while players gather,
# then last-one-standing rounds — countdown, fight until one survives,
# flash the result, repeat; first to ROUNDS_TO_WIN takes the match,
# then everyone drops back to warm-up for a rematch.
#
# The server runs the state machine and broadcasts every transition;
# each peer applies the side effects (lock input, revive, reset
# loadouts) to the players it controls. Couch mode is the offline
# server, so the same broadcasts just execute as direct local calls.
class_name RoundManager
extends Node

enum Phase { LOBBY, COUNTDOWN, FIGHT, ROUND_END, MATCH_END }

const COUNTDOWN_TIME := 3.0
const FIGHT_BANNER_TIME := 0.9
const ROUND_END_TIME := 2.5
const MATCH_END_TIME := 6.0
const ROUNDS_TO_WIN := 5
const MIN_PLAYERS := 2

var phase: int = Phase.LOBBY
var round_num := 0
var current_level := 0  # active LevelDB id; rides the phase broadcast
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
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_joined)
		if Net.mode == Net.Mode.LOCAL:
			# Couch players already gathered in the join screen.
			_try_start()
		else:
			_enter_lobby()


# RPCs aren't replayed for late joiners, so catch the newcomer up on
# the current phase (their zone picks up mid-shrink from fight_t).
func _on_peer_joined(id: int) -> void:
	_net_phase.rpc_id(id, phase, _phase_data())
	_net_banner.rpc_id(id, banner_text, banner_color)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_t -= delta
	match phase:
		Phase.LOBBY:
			_set_banner(_lobby_text(), Color(0.96, 0.96, 1.0))
		Phase.COUNTDOWN:
			_set_banner("ROUND %d\n%d" % [round_num, ceili(maxf(_t, 0.01))],
					Color(0.96, 0.96, 1.0))
			if _t <= 0.0:
				_begin_fight()
		Phase.FIGHT:
			_fight_t += delta
			if _fight_t > _banner_until and banner_text != "":
				_set_banner("", banner_color)
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
				_enter_lobby()


func fight_active() -> bool:
	return phase == Phase.FIGHT


# Called by main.report_death for every player death, including zone
# burn (attacker 0). Survivor count decides the round.
func on_player_died(victim_key: int) -> void:
	if phase != Phase.FIGHT:
		return
	_dead_keys[victim_key] = true
	recheck_alive()


# Also called after a peer disconnects mid-fight (their node is gone,
# which thins the survivors just like a death would).
func recheck_alive() -> void:
	if phase != Phase.FIGHT:
		return
	var alive: Array = []
	for p in _players():
		if not p.is_queued_for_deletion() and not _dead_keys.has(p.fighter_key()):
			alive.append(p)
	if alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else null)


# The host (or any couch device) starts the match from the warm-up.
func _unhandled_input(event: InputEvent) -> void:
	if not multiplayer.is_server() or phase != Phase.LOBBY:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)) \
			or (event is InputEventJoypadButton and event.pressed
				and event.button_index == JOY_BUTTON_START)
	if pressed:
		_try_start()


func _try_start() -> void:
	if _players().size() < MIN_PLAYERS:
		return
	# Warm-up kills don't count: the match starts from zero.
	round_num = 0
	round_wins.clear()
	main.scores.clear()
	main._sync_scores.rpc(main.scores)
	_begin_countdown()


# --- Server-side transitions (broadcast to every peer) ----------------

func _enter_lobby() -> void:
	# Warm-up always happens on Classic.
	current_level = 0
	_net_phase.rpc(Phase.LOBBY, _phase_data())


func _begin_countdown() -> void:
	round_num += 1
	current_level = LevelDB.pick_next(current_level)
	_dead_keys.clear()
	_t = COUNTDOWN_TIME
	_net_phase.rpc(Phase.COUNTDOWN, _phase_data())
	_set_banner("ROUND %d\n%d" % [round_num, ceili(COUNTDOWN_TIME)],
			Color(0.96, 0.96, 1.0))


func _begin_fight() -> void:
	_fight_t = 0.0
	_banner_until = FIGHT_BANNER_TIME
	_event_at = randf_range(12.0, 25.0)
	_net_phase.rpc(Phase.FIGHT, _phase_data())
	_set_banner("FIGHT!", Color(1.0, 0.62, 0.1))


func _end_round(winner: Node) -> void:
	_t = ROUND_END_TIME
	var data := _phase_data()
	if winner != null:
		var key: int = winner.fighter_key()
		round_wins[key] = int(round_wins.get(key, 0)) + 1
		data["wins"] = round_wins
		data["winner"] = int(winner.slot)
	_net_phase.rpc(Phase.ROUND_END, data)
	if winner != null:
		_set_banner("P%d TAKES THE ROUND" % (int(winner.slot) + 1),
				winner.COLORS[winner.color_idx % winner.COLORS.size()])
	else:
		_set_banner("NOBODY SURVIVES", Color(0.66, 0.68, 0.76))


func _begin_match_end() -> void:
	_t = MATCH_END_TIME
	_net_phase.rpc(Phase.MATCH_END, _phase_data())
	for p in _players():
		if int(round_wins.get(p.fighter_key(), 0)) >= ROUNDS_TO_WIN:
			_set_banner("P%d WINS THE MATCH" % (int(p.slot) + 1),
					p.COLORS[p.color_idx % p.COLORS.size()])
			break


func _set_banner(text: String, color: Color) -> void:
	if text == banner_text and color == banner_color:
		return
	_net_banner.rpc(text, color)


func _lobby_text() -> String:
	var n := _players().size()
	if n < MIN_PLAYERS:
		return "WARM-UP\n%d / %d players" % [n, MIN_PLAYERS]
	return "WARM-UP\nEnter / Start to fight"


# --- Replicated state (runs on every peer, including the server) ------

@rpc("authority", "call_local", "reliable")
func _net_phase(new_phase: int, data: Dictionary) -> void:
	phase = new_phase
	round_wins = data.get("wins", round_wins)
	round_num = int(data.get("round", round_num))
	# Swap the arena before anyone revives, so spawn points belong to
	# the level being played (late joiners build it here too). The
	# server then regrows rocks and guns to the level's own density.
	current_level = int(data.get("level", current_level))
	main.level_host.load_level(current_level)
	if multiplayer.is_server() \
			and (phase == Phase.LOBBY or phase == Phase.COUNTDOWN):
		main.rebuild_world()
	match phase:
		Phase.LOBBY:
			_zone.reset()
			for p in _local_players():
				p.revive(_spawn_for(p))
				p.reset_loadout()
				p.input_locked = false
		Phase.COUNTDOWN:
			_zone.reset()
			for p in _local_players():
				p.revive(_spawn_for(p))
				p.reset_loadout()
				p.input_locked = true
		Phase.FIGHT:
			_zone.start()
			_zone._t = float(data.get("fight_t", 0.0))
			for p in _local_players():
				p.input_locked = false
		Phase.ROUND_END:
			if int(data.get("winner", -1)) >= 0:
				Juice.slowmo(0.3, 1.0)
		Phase.MATCH_END:
			Juice.slowmo(0.4, 1.5)


@rpc("authority", "call_local", "reliable")
func _net_banner(text: String, color: Color) -> void:
	banner_text = text
	banner_color = color


func _phase_data() -> Dictionary:
	return {"wins": round_wins, "round": round_num, "fight_t": _fight_t,
			"level": current_level}


# --- Chaos events ------------------------------------------------------

# One chaos event per round, somewhere in the middle of the fight.
func _fire_event(which: int) -> void:
	match which:
		0:
			_set_banner("ASTEROID SHOWER", Color(1.0, 0.45, 0.15))
			for i in 10:
				var pos: Vector2 = main._edge_spawn()
				var vel := pos.direction_to(Vector2.ZERO).rotated(randf_range(-0.5, 0.5)) \
						* randf_range(220.0, 350.0)
				main.asteroid_spawner.spawn([randi() % 2, pos, randf() < 0.3, vel])
		1:
			_set_banner("ARMS RACE", Color(1.0, 0.45, 0.15))
			for p in _players():
				if not p._dead:
					var kind := _roll_high_tier()
					p._net_receive_weapon.rpc_id(p.get_multiplayer_authority(),
							kind, int(WeaponDB.DATA[kind]["max_ammo"]))
		2:
			_set_banner("SUPPLY DROP", Color(1.0, 0.45, 0.15))
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


func _best_wins() -> int:
	var best := 0
	for w in round_wins.values():
		best = maxi(best, int(w))
	return best


func _players() -> Array:
	return main.get_node("Players").get_children()


func _local_players() -> Array:
	var out: Array = []
	for p in _players():
		if p.is_locally_controlled():
			out.append(p)
	return out


func _spawn_for(p: Node) -> Vector2:
	var spawns: Array = main.level_host.spawns
	return spawns[int(p.slot) % spawns.size()]
