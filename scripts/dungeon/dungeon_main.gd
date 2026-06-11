# DUNGEON DIVE: the singleplayer roguelite run. An endless chain of
# procedurally generated chambers — each rolls a layout pattern, a
# difficulty budget of enemies, and weapon pickups (deeper = luckier
# rarity rolls). Clear the room, pick an exit gate by its reward, dive
# deeper. Every BOSS_EVERY-th chamber holds the Warden. Death ends the
# run; depth is the score.
#
# Runs offline on the default peer, so all the multiplayer-aware
# gameplay scripts (player, pickups, asteroids, projectiles) work
# unchanged — this scene just has to offer the same API surface that
# main.gd does (spawn_weapon_pickup, report_death, the fx RPCs, …).
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const ENEMY_SCENE := preload("res://scenes/dungeon_enemy.tscn")
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")
const MUSIC := preload("res://audio/music/game_music.mp3")

const STARFIELDS: Array[Texture2D] = [
	preload("res://assets/space-backgrounds/Starfields/Starfield_01-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_02-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_03-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_04-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_05-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_06-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_07-1024x1024.png"),
	preload("res://assets/space-backgrounds/Starfields/Starfield_08-1024x1024.png"),
]

const Kind := DungeonEnemy.Kind
const Reward := DungeonDoor.Reward

enum Pattern { OPEN, FIELD, PILLARS, VOLATILE, CLUSTER }

# Pattern: room size, asteroid counts per variant (small..huge), and
# how often a small/medium rock rolls volatile.
const PATTERNS := {
	Pattern.OPEN: {"size": Vector2(2400, 1400), "counts": [2, 2, 1, 0], "volatile": 0.1},
	Pattern.FIELD: {"size": Vector2(2700, 1550), "counts": [7, 5, 3, 1], "volatile": 0.15},
	Pattern.PILLARS: {"size": Vector2(2600, 1450), "counts": [4, 0, 0, 5], "volatile": 0.0},
	Pattern.VOLATILE: {"size": Vector2(2250, 1300), "counts": [5, 5, 1, 0], "volatile": 0.7},
	Pattern.CLUSTER: {"size": Vector2(2450, 1500), "counts": [4, 6, 0, 1], "volatile": 0.2},
}
const BOSS_ROOM_SIZE := Vector2(2900, 1700)
const ASTEROID_RADII := [11.0, 22.0, 45.0, 100.0]
const WALL_MARGIN := 80.0
const SPACING_PAD := 40.0
const PICKUP_RADIUS := 20.0

# Difficulty: each room spends a budget on the unlocked roster.
# Swarmlings are bought as packs of three.
const ENEMY_COSTS := {
	Kind.DRIFTER: 1.5, Kind.GUNNER: 2.0, Kind.SWARMLING: 2.4,
	Kind.CHARGER: 2.6, Kind.TURRET: 2.6, Kind.SPLITTER: 3.6,
}
const ENEMY_UNLOCK_DEPTH := {
	Kind.DRIFTER: 1, Kind.GUNNER: 1, Kind.SWARMLING: 2,
	Kind.CHARGER: 3, Kind.TURRET: 4, Kind.SPLITTER: 6,
}
const BOSS_EVERY := 5
const TELEGRAPH_TIME := 0.85
const DROP_CHANCE := 0.22
const SAVE_PATH := "user://dungeon.cfg"

var depth := 0
var kills := 0
var best_depth := 0
var new_best := false
var run_over := false
var room_clear := false
var enemies_alive := 0
var perks: Array = []  # perk ids in pickup order (the HUD lists them)

# Run-side perk effects (player-side ones live on player.gd).
var lifesteal := 0.0
var scavenger_mult := 1.0

var banner_text := ""
var banner_color := Color.WHITE
var banner_until := 0

var _room_rect := Rect2(-1200, -700, 2400, 1400)
var _boss_room := false
var _entry_reward := -1
var _pulses: Array = []     # arrays of enemy kinds still queued
var _pending := 0           # telegraphs currently counting down
var _spawn_delay := 0.0     # breathing room after entering a room
var _transitioning := true
var _wall_shapes: Array = []
var _fade: ColorRect

@onready var asteroids: Node2D = $Asteroids
@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var pickups: Node2D = $Pickups
@onready var drops: Node2D = $Drops
@onready var doors: Node2D = $Doors
@onready var walls: StaticBody2D = $Walls
@onready var backdrop: Node2D = $Backdrop
@onready var dungeon_hud: Control = $HUD/DungeonHud


func _ready() -> void:
	var stream: AudioStreamMP3 = MUSIC
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -14.0
	music.bus = "Music"
	add_child(music)
	music.play()

	var picks := STARFIELDS.duplicate()
	picks.shuffle()
	$StarsFar/Sprite.texture = picks[0]
	$StarsNear/Sprite.texture = picks[1]

	for i in 4:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		walls.add_child(shape)
		_wall_shapes.append(shape)

	# Full-screen fade for room transitions, above all HUD.
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_fade)

	dungeon_hud.perk_chosen.connect(_on_perk_chosen)
	_load_best()

	var p := PLAYER_SCENE.instantiate()
	p.name = "1"
	p.color_idx = 0
	p.slot = 0
	players.add_child(p)

	_build_room(1, -1)
	_intro()


func _intro() -> void:
	var p := _player()
	if p != null:
		p.input_locked = true
	await _fade_to(0.0, 0.6)
	if p != null:
		p.input_locked = false
	_transitioning = false


func _process(delta: float) -> void:
	if run_over:
		return
	_spawn_delay = maxf(_spawn_delay - delta, 0.0)
	# Next enemy pulse arrives when the current one is almost wiped.
	if not room_clear and _spawn_delay == 0.0 and not _pulses.is_empty() \
			and enemies_alive + _pending <= 1:
		_spawn_pulse(_pulses.pop_front())
	_check_clear()


func _unhandled_input(event: InputEvent) -> void:
	if run_over and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_tree().reload_current_scene()


func _player() -> Node:
	return players.get_child(0) if players.get_child_count() > 0 else null


# --- Room generation --------------------------------------------------

func _build_room(d: int, reward: int) -> void:
	depth = d
	room_clear = false
	_boss_room = d % BOSS_EVERY == 0
	_entry_reward = reward
	_pulses.clear()
	_pending = 0
	enemies_alive = 0
	_spawn_delay = 1.2
	if depth > best_depth:
		best_depth = depth
		new_best = depth > 1
		_save_best()
	_clear_field()

	# Geometry: boss rooms are big and open; everything else rolls a
	# pattern from the unlocked set, with a little size jitter.
	var pattern: int = Pattern.OPEN
	var size := BOSS_ROOM_SIZE
	var pdata := {"counts": [2, 2, 0, 0], "volatile": 0.0}
	if not _boss_room:
		var pool: Array = [Pattern.OPEN, Pattern.FIELD]
		if d >= 2:
			pool.append_array([Pattern.PILLARS, Pattern.CLUSTER])
		if d >= 3:
			pool.append(Pattern.VOLATILE)
		pattern = pool[randi() % pool.size()]
		pdata = PATTERNS[pattern]
		size = (pdata["size"] as Vector2) * randf_range(0.95, 1.1)
		size.x = maxf(size.x, 2050.0)
		size.y = maxf(size.y, 1200.0)
	_room_rect = Rect2(-size / 2.0, size)
	_apply_geometry()

	var entry := Vector2(_room_rect.position.x + 170.0, 0.0)
	var p := _player()
	if p != null:
		p.global_position = entry
		p.velocity = Vector2.ZERO
		p.reset_physics_interpolation()

	# Keep the entry and the exit-gate strip clear of rocks.
	var placed: Array = [
		{"pos": entry, "r": 320.0},
		{"pos": Vector2(_room_rect.end.x - 100.0, 0.0), "r": 380.0},
	]
	_spawn_rocks(pattern, pdata, placed)

	# Entry rewards from the gate you came through.
	if reward == Reward.REPAIR and p != null:
		p.health = minf(p.health + 0.4 * p.max_health, p.max_health)
	if reward == Reward.ARMORY:
		for i in 3:
			var kind := WeaponDB.roll_weapon(3 + mini(depth / 5, 3))
			_drop_pickup(kind, int(WeaponDB.DATA[kind]["max_ammo"]),
					_find_spot(PICKUP_RADIUS, placed, entry, 700.0))
	# Baseline loot: one rolled gun somewhere in the room.
	if not _boss_room:
		var kind := WeaponDB.roll_weapon(mini(depth / 4, 3))
		_drop_pickup(kind, int(WeaponDB.DATA[kind]["max_ammo"]),
				_find_spot(PICKUP_RADIUS, placed))

	_queue_enemies()
	_make_doors()

	if _boss_room:
		_set_banner("THE WARDEN", Color(1.0, 0.38, 0.28), 3.0)
	else:
		_set_banner("DEPTH %d" % depth, Color(0.96, 0.96, 1.0), 2.0)


func _apply_geometry() -> void:
	var r := _room_rect
	var t := 48.0
	# Top, bottom, left, right — inner faces flush with the room rect.
	_set_wall(_wall_shapes[0], Vector2(r.size.x + 200.0, t), Vector2(r.get_center().x, r.position.y - t / 2.0))
	_set_wall(_wall_shapes[1], Vector2(r.size.x + 200.0, t), Vector2(r.get_center().x, r.end.y + t / 2.0))
	_set_wall(_wall_shapes[2], Vector2(t, r.size.y + 200.0), Vector2(r.position.x - t / 2.0, r.get_center().y))
	_set_wall(_wall_shapes[3], Vector2(t, r.size.y + 200.0), Vector2(r.end.x + t / 2.0, r.get_center().y))
	backdrop.rect = r
	backdrop.queue_redraw()
	var p := _player()
	if p != null:
		p.camera.limit_left = int(r.position.x) - 24
		p.camera.limit_top = int(r.position.y) - 24
		p.camera.limit_right = int(r.end.x) + 24
		p.camera.limit_bottom = int(r.end.y) + 24


func _set_wall(shape: CollisionShape2D, size: Vector2, pos: Vector2) -> void:
	(shape.shape as RectangleShape2D).size = size
	shape.position = pos


func _clear_field() -> void:
	for holder in [asteroids, enemies, pickups, drops, doors]:
		for c in holder.get_children():
			c.queue_free()
	for c in get_children():
		# Stray bullets and grenades from the last room; smoke, beams,
		# and break fx clean themselves up fast enough to leave alone.
		if c.get_script() == PROJECTILE_SCRIPT:
			c.queue_free()
	for m in get_tree().get_nodes_in_group("spawn_markers"):
		m.queue_free()


func _spawn_rocks(pattern: int, pdata: Dictionary, placed: Array) -> void:
	if pattern == Pattern.CLUSTER:
		# A huge anchor in the middle, mediums ringed around it.
		_spawn_rock(3, _room_rect.get_center(), false, placed)
		for i in 6:
			var pos := _room_rect.get_center() + Vector2.from_angle(i * TAU / 6.0) \
					* randf_range(230.0, 330.0)
			_spawn_rock(1, pos, randf() < float(pdata["volatile"]), placed)
		for i in int(pdata["counts"][0]):
			_spawn_rock(0, _find_spot(ASTEROID_RADII[0], placed),
					randf() < float(pdata["volatile"]), placed)
		return
	var counts: Array = pdata["counts"]
	for variant in [3, 2, 1, 0]:
		for i in int(counts[variant]):
			var volatile: bool = variant <= 1 and randf() < float(pdata["volatile"])
			_spawn_rock(variant, _find_spot(ASTEROID_RADII[variant], placed), volatile, placed)


func _spawn_rock(variant: int, pos: Vector2, volatile: bool, _placed: Array) -> void:
	var rock := ASTEROID_SCENE.instantiate()
	rock.variant = variant
	rock.position = pos
	rock.volatile = volatile
	asteroids.add_child(rock)
	rock.reset_physics_interpolation()


func _find_spot(radius: float, placed: Array, near := Vector2.INF, within := 0.0) -> Vector2:
	var margin := WALL_MARGIN + radius
	var area := _room_rect.grow(-margin)
	for attempt in 120:
		var pos := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		if near != Vector2.INF and pos.distance_to(near) > within:
			continue
		var crowded := false
		for q in placed:
			if pos.distance_to(q["pos"]) < radius + float(q["r"]) + SPACING_PAD:
				crowded = true
				break
		if not crowded:
			placed.append({"pos": pos, "r": radius})
			return pos
	var fallback := Vector2(
		randf_range(area.position.x, area.end.x),
		randf_range(area.position.y, area.end.y))
	placed.append({"pos": fallback, "r": radius})
	return fallback


# --- Enemy waves -------------------------------------------------------

func _queue_enemies() -> void:
	if _boss_room:
		_pulses = [[Kind.WARDEN]]
		return
	var roster := _roll_enemies(minf(3.2 + depth * 1.5, 26.0))
	# Deeper rooms arrive in pulses so the fight breathes.
	var pulse_count := 1 if depth <= 2 else (2 if depth <= 6 else 3)
	pulse_count = mini(pulse_count, roster.size())
	_pulses = []
	var per := ceili(float(roster.size()) / pulse_count)
	for i in range(0, roster.size(), per):
		_pulses.append(roster.slice(i, i + per))


func _roll_enemies(budget: float) -> Array:
	var unlocked: Array = []
	for kind in ENEMY_UNLOCK_DEPTH:
		if depth >= int(ENEMY_UNLOCK_DEPTH[kind]):
			unlocked.append(kind)
	var roster: Array = []
	var guard := 0
	while budget > 0.0 and guard < 60:
		guard += 1
		var kind: int = unlocked[randi() % unlocked.size()]
		var cost := float(ENEMY_COSTS[kind])
		if cost > budget and roster.size() >= 2:
			break
		budget -= cost
		if kind == Kind.SWARMLING:
			roster.append_array([Kind.SWARMLING, Kind.SWARMLING, Kind.SWARMLING])
		else:
			roster.append(kind)
	roster.shuffle()
	return roster


func _spawn_pulse(pulse: Array) -> void:
	var p := _player()
	var avoid: Vector2 = p.global_position if p != null else Vector2.ZERO
	for kind in pulse:
		spawn_enemy(kind, _enemy_spot(avoid))


func _enemy_spot(avoid: Vector2) -> Vector2:
	var area := _room_rect.grow(-150.0)
	for attempt in 40:
		var pos := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y))
		if pos.distance_to(avoid) < 430.0:
			continue
		var blocked := false
		for rock in asteroids.get_children():
			if pos.distance_to(rock.position) < rock._radius + 60.0:
				blocked = true
				break
		if not blocked:
			return pos
	return Vector2(area.end.x - 100.0, randf_range(area.position.y, area.end.y))


# Also called by splitters bursting and the Warden summoning; instant
# spawns skip the telegraph.
func spawn_enemy(kind: int, pos: Vector2, telegraph := true) -> void:
	if run_over:
		return
	if not telegraph:
		_spawn_enemy_now(kind, pos)
		return
	_pending += 1
	var marker := SpawnMarker.new()
	marker.big = kind == Kind.WARDEN
	marker.dur = TELEGRAPH_TIME * (1.6 if marker.big else 1.0)
	marker.position = pos
	add_child(marker)
	marker.done.connect(func():
		_pending -= 1
		_spawn_enemy_now(kind, pos)
	)


func _spawn_enemy_now(kind: int, pos: Vector2) -> void:
	if run_over:
		return
	var e := ENEMY_SCENE.instantiate()
	e.kind = kind
	if kind == Kind.WARDEN:
		e.hp_mult = 1.0 + depth * 0.25
		Juice.slowmo(0.5, 0.7)
	else:
		e.hp_mult = 1.0 + 0.07 * (depth - 1)
	e.position = pos
	e.died.connect(_on_enemy_died)
	enemies.add_child(e)
	e.reset_physics_interpolation()
	enemies_alive += 1


func _on_enemy_died(kind: int, at: Vector2, killer_id: int) -> void:
	kills += 1
	var p := _player()
	if killer_id == 1 and lifesteal > 0.0 and p != null:
		p.health = minf(p.health + lifesteal, p.max_health)
	if kind == Kind.SPLITTER:
		for i in 3:
			var off := Vector2.from_angle(i * TAU / 3.0 + randf()) * randf_range(40.0, 70.0)
			spawn_enemy(Kind.SWARMLING, at + off, false)
	if kind == Kind.WARDEN:
		_warden_down(at)
	elif randf() < DROP_CHANCE * scavenger_mult and drops.get_child_count() < 7:
		var drop := DungeonDrop.new()
		drop.kind = DungeonDrop.Kind.SHELLS if randf() < 0.55 else DungeonDrop.Kind.REPAIR
		drop.position = at
		drops.add_child(drop)
	enemies_alive -= 1
	_check_clear()


func _warden_down(at: Vector2) -> void:
	Juice.slowmo(0.3, 1.2)
	spawn_break_fx(at, 3.0, true)
	_set_banner("WARDEN DOWN", Color(0.96, 0.96, 1.0), 2.5)
	# Spoils: a top-shelf gun plus a pair of repair orbs.
	_drop_pickup(_roll_high_tier(), -2, at)
	for i in 2:
		var drop := DungeonDrop.new()
		drop.kind = DungeonDrop.Kind.REPAIR
		drop.position = at + Vector2.from_angle(randf() * TAU) * 90.0
		drops.add_child(drop)


func _roll_high_tier() -> int:
	var pool: Array = []
	for id in WeaponDB.DATA:
		if int(WeaponDB.DATA[id]["rarity"]) >= WeaponDB.Rarity.EPIC \
				and not WeaponDB.DATA[id].get("no_drop", false):
			pool.append(id)
	return pool[randi() % pool.size()]


func _check_clear() -> void:
	if run_over or room_clear or _transitioning:
		return
	if enemies_alive <= 0 and _pending == 0 and _pulses.is_empty() and _spawn_delay == 0.0:
		_room_cleared()


func _room_cleared() -> void:
	room_clear = true
	# Tech caches (and every boss) pay out a perk; gates open after the
	# choice is made so you can't drift through mid-decision.
	if _entry_reward == Reward.TECH or _entry_reward == Reward.BOSS:
		dungeon_hud.open_perk_choice(DungeonPerks.roll(3))
	else:
		_unlock_doors()


func _on_perk_chosen(id: int) -> void:
	var p := _player()
	if p != null:
		DungeonPerks.apply(p, self, id)
		perks.append(id)
	_unlock_doors()


func _unlock_doors() -> void:
	for door in doors.get_children():
		door.unlock()
	_set_banner("ROOM CLEAR — PICK A GATE", Color(1.0, 0.62, 0.1), 2.2)


# --- Gates -------------------------------------------------------------

func _make_doors() -> void:
	var next := depth + 1
	var rewards: Array = []
	if next % BOSS_EVERY == 0:
		rewards = [Reward.BOSS]
	else:
		rewards = [Reward.ARMORY, Reward.REPAIR, Reward.TECH]
		rewards.shuffle()
		rewards = rewards.slice(0, 2 if depth < 4 else 3)
	for i in rewards.size():
		var door := DungeonDoor.new()
		door.reward = rewards[i]
		door.position = Vector2(_room_rect.end.x - 26.0,
				(i - (rewards.size() - 1) / 2.0) * 280.0)
		doors.add_child(door)


func enter_door(reward: int) -> void:
	if _transitioning or not room_clear or run_over:
		return
	_transitioning = true
	var p := _player()
	if p != null:
		p.input_locked = true
	await _fade_to(1.0, 0.3)
	_build_room(depth + 1, reward)
	await _fade_to(0.0, 0.4)
	if p != null:
		p.input_locked = false
	_transitioning = false


func _fade_to(alpha: float, dur: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, dur)
	await tween.finished


# --- Run over ----------------------------------------------------------

# Same entry points main.gd offers, so player.gd's death path lands
# here unchanged. Any player death ends the run.
@rpc("any_peer", "call_local", "reliable")
func _net_report_kill(attacker_id: int) -> void:
	report_death(1, attacker_id)


func report_death(_victim_key: int, _attacker_key: int) -> void:
	if run_over:
		return
	run_over = true
	_save_best()
	Juice.slowmo(0.35, 1.5)
	_set_banner("", Color.WHITE, 0.0)


# Deaths always eliminate in the dungeon — there are no respawns, the
# game-over overlay takes it from here.
func round_fight_active() -> bool:
	return true


# --- Shared-API shims (same shapes as main.gd) -------------------------

func spawn_weapon_pickup(kind: int, ammo_amount: int, pos: Vector2, vel: Vector2,
		spin: float, thrower := 0) -> void:
	var pickup := PICKUP_SCENE.instantiate()
	pickup.kind = kind
	pickup.position = pos
	pickup.init_velocity = vel
	pickup.init_spin = spin
	pickup.ammo = ammo_amount
	pickup.thrower = thrower
	pickups.add_child(pickup)
	pickup.reset_physics_interpolation()


# Weapon loot drifting gently in place. ammo -2 means "full magazine".
func _drop_pickup(kind: int, ammo_amount: int, pos: Vector2) -> void:
	if ammo_amount == -2:
		ammo_amount = int(WeaponDB.DATA[kind]["max_ammo"])
	spawn_weapon_pickup(kind, ammo_amount, pos,
			Vector2.from_angle(randf() * TAU) * randf_range(15.0, 50.0),
			randf_range(-1.2, 1.2))


@rpc("any_peer", "call_local", "reliable")
func _net_player_death_fx(pos: Vector2, color_idx: int) -> void:
	var fx := PlayerExplosion.new()
	var colors: Array = preload("res://scripts/player.gd").COLORS
	fx.color = colors[color_idx % colors.size()]
	fx.position = pos
	add_child(fx)
	fx.reset_physics_interpolation()
	add_shake(14.0)


@rpc("authority", "call_local", "reliable")
func spawn_break_fx(pos: Vector2, fx_scale: float, with_boom := false) -> void:
	var fx := BREAK_EFFECT.instantiate()
	fx.scale = Vector2.ONE * fx_scale
	fx.position = pos
	add_child(fx)
	fx.reset_physics_interpolation()
	if with_boom:
		Explosions.boom(self, pos)
		add_shake(8.0)


func add_shake(amount: float) -> void:
	for p in players.get_children():
		if p.camera.enabled:
			p._shake = maxf(p._shake, amount)


# --- Bits and bobs -----------------------------------------------------

func _set_banner(text: String, color: Color, dur: float) -> void:
	banner_text = text
	banner_color = color
	banner_until = Time.get_ticks_msec() + int(dur * 1000.0)


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_depth = int(cfg.get_value("dungeon", "best_depth", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep unrelated keys if the file grows later
	cfg.set_value("dungeon", "best_depth", best_depth)
	cfg.save(SAVE_PATH)


# Pulsing warning ring where an enemy is about to arrive, so spawns
# never feel like ambushes.
class SpawnMarker extends Node2D:
	signal done

	var dur := 0.85
	var big := false
	var _t := 0.0

	func _ready() -> void:
		add_to_group("spawn_markers")
		z_index = 5

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t >= dur:
			done.emit()
			queue_free()

	func _draw() -> void:
		var k := _t / dur
		var base := 90.0 if big else 46.0
		var floor_r := 30.0 if big else 16.0
		var r := lerpf(base, floor_r, k)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.4, 0.35, 0.7), 2.0)
