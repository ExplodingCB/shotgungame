extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const PICKUP_SCENE := preload("res://scenes/pickup.tscn")

# Weapon pickups are rolled by rarity weight and spawn with a full
# magazine. The server tops the map back up to this count over time as
# guns get carried off (thrown guns just drift, so they still count).
const WEAPON_PICKUPS := 12
const RESTOCK_INTERVAL := 10.0

const ENEMY_SCENE := preload("res://scenes/enemy_ship.tscn")
const FIRST_WAVE_DELAY := 5.0
const WAVE_BREAK := 5.0

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

const ARENA := Rect2(-1600, -900, 3200, 1800)
const WALL_MARGIN := 80.0
const SPAWN_CLEAR_RADIUS := 380.0
const SPACING_PAD := 40.0
const COUNTS := [12, 8, 5, 2]  # per variant: small, medium, large, huge
const ASTEROID_RADII := [11.0, 22.0, 45.0, 100.0]
const PICKUP_RADIUS := 20.0
const PLAYER_SPAWNS := [Vector2(-600, 0), Vector2(600, 0), Vector2(0, -450), Vector2(0, 450)]

@onready var asteroids: Node2D = $Asteroids
@onready var players: Node2D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var asteroid_spawner: MultiplayerSpawner = $AsteroidSpawner
@onready var pickup_spawner: MultiplayerSpawner = $PickupSpawner
@onready var stars_far: Sprite2D = $StarsFar/Sprite
@onready var stars_near: Sprite2D = $StarsNear/Sprite

var _player_count := 0
var wave := 0
var enemies_alive := 0
var _wave_pending := false

# fighter key -> kills (peer id online, slot+1 in couch mode). The
# server owns this and broadcasts every change; clients only ever read
# it (the HUD scoreboard).
var scores := {}

var round_manager: Node = null


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	asteroid_spawner.spawn_function = _spawn_asteroid
	pickup_spawner.spawn_function = _spawn_pickup_node

	var stream: AudioStreamMP3 = MUSIC
	stream.loop = true
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -14.0
	music.bus = "Music"
	add_child(music)
	music.play()

	# A different pair of starfields every run: dim distant layer,
	# brighter additive layer up front.
	var picks := STARFIELDS.duplicate()
	picks.shuffle()
	stars_far.texture = picks[0]
	stars_near.texture = picks[1]

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_leave)
	multiplayer.server_disconnected.connect(_leave)
	Net.setup_peer()

	# Solo counts as the server; clients receive everything replicated.
	if multiplayer.is_server():
		_spawn_world()
		if Net.mode == Net.Mode.LOCAL:
			var cam := SharedCamera.new()
			cam.name = "SharedCamera"
			add_child(cam)
			_add_local_players()
			round_manager = RoundManager.new()
			round_manager.name = "RoundManager"
			add_child(round_manager)
		else:
			_add_player(1)
		var restock := Timer.new()
		restock.wait_time = RESTOCK_INTERVAL
		restock.timeout.connect(_restock_pickups)
		add_child(restock)
		restock.start()
	if Net.mode == Net.Mode.SOLO:
		_schedule_wave(FIRST_WAVE_DELAY)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_add_player(id)
		_sync_scores.rpc(scores)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		if players.has_node(str(id)):
			players.get_node(str(id)).queue_free()
		scores.erase(id)
		_sync_scores.rpc(scores)


# The dying peer reports who killed it; sender identifies the victim,
# so a peer can never inflate its own count.
@rpc("any_peer", "call_local", "reliable")
func _net_report_kill(attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	report_death(multiplayer.get_remote_sender_id(), attacker_id)


# Server-side bookkeeping for any player death. Keys are fighter keys:
# peer ids online, slot+1 in couch mode (couch deaths arrive as direct
# calls — every couch player shares peer 1, so the sender id is mute).
func report_death(victim_key: int, attacker_key: int) -> void:
	if not multiplayer.is_server():
		return
	if attacker_key > 0 and attacker_key != victim_key:
		scores[attacker_key] = int(scores.get(attacker_key, 0)) + 1
		_sync_scores.rpc(scores)
	if round_manager != null:
		round_manager.on_player_died(victim_key)


# During an active round, deaths eliminate instead of respawning.
func round_fight_active() -> bool:
	return round_manager != null and round_manager.fight_active()


@rpc("authority", "call_local", "reliable")
func _sync_scores(s: Dictionary) -> void:
	scores = s


func _leave() -> void:
	Net.leave()


func _add_player(id: int) -> void:
	player_spawner.spawn([id, _player_count])
	_player_count += 1


# Couch mode: every joined device gets a player under peer 1's
# authority. Non-numeric names keep authority at 1 (see player.gd).
func _add_local_players() -> void:
	for i in Net.local_roster.size():
		player_spawner.spawn(["local_%d" % i, i, Net.local_roster[i]])
	_player_count = Net.local_roster.size()


func _spawn_player(data: Variant) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data[0])
	p.color_idx = data[1]
	p.slot = data[1]
	if data.size() > 2:
		p.device = data[2]
	p.position = PLAYER_SPAWNS[data[1] % PLAYER_SPAWNS.size()]
	return p


func _spawn_asteroid(data: Variant) -> Node:
	var rock := ASTEROID_SCENE.instantiate()
	rock.variant = data[0]
	rock.position = data[1]
	return rock


# Spawns everything with size-aware spacing so nothing starts
# overlapping (overlap makes the physics solver fling bodies apart).
func _spawn_world() -> void:
	var placed: Array = []
	# Keep every player spawn point clear, not just the arena center.
	for s in PLAYER_SPAWNS:
		placed.append({"pos": s, "r": 150.0})
	# Largest rocks first: they're hardest to fit, smalls fill the gaps.
	for variant in [3, 2, 1, 0]:
		for i in COUNTS[variant]:
			asteroid_spawner.spawn([variant, _find_spot(ASTEROID_RADII[variant], placed)])
	for i in WEAPON_PICKUPS:
		_spawn_rolled_pickup(placed)


func _spawn_rolled_pickup(placed: Array) -> void:
	var kind := WeaponDB.roll_weapon()
	pickup_spawner.spawn([
		kind,
		_find_spot(PICKUP_RADIUS, placed),
		Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0),
		randf_range(-1.2, 1.2),
		int(WeaponDB.DATA[kind]["max_ammo"]),
	])


# Players call this through the server to drop what they're holding —
# either a deliberate throw or the swap when grabbing a new gun.
func spawn_weapon_pickup(kind: int, ammo_amount: int, pos: Vector2, vel: Vector2, spin: float) -> void:
	if not multiplayer.is_server():
		return
	pickup_spawner.spawn([kind, pos, vel, spin, ammo_amount])


# Positions and sizes of everything currently floating around, so
# respawns don't materialize inside a drifting rock.
func _live_placed() -> Array:
	var out: Array = []
	for a in asteroids.get_children():
		out.append({"pos": a.position, "r": a._radius})
	for p in $Pickups.get_children():
		out.append({"pos": p.position, "r": PICKUP_RADIUS})
	for pl in players.get_children():
		out.append({"pos": pl.position, "r": 80.0})
	return out


func _spawn_pickup_node(data: Variant) -> Node:
	var p := PICKUP_SCENE.instantiate()
	p.kind = data[0]
	p.position = data[1]
	p.init_velocity = data[2]
	p.init_spin = data[3]
	p.ammo = data[4]
	return p


# Tops the arena back up to WEAPON_PICKUPS, one fresh roll per tick, as
# guns get picked up and carried around.
func _restock_pickups() -> void:
	if $Pickups.get_child_count() >= WEAPON_PICKUPS:
		return
	_spawn_rolled_pickup(_live_placed())


# --- Solo wave mode -------------------------------------------------

func _schedule_wave(delay: float) -> void:
	if _wave_pending:
		return
	_wave_pending = true
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	add_child(t)
	t.timeout.connect(func():
		_wave_pending = false
		_start_wave()
		t.queue_free()
	)
	t.start()


func _start_wave() -> void:
	wave += 1
	var count := 1 + wave
	# Early waves are mostly rammers; gunners creep in over time.
	var gunner_chance := minf(0.2 + wave * 0.06, 0.55)
	for i in count:
		var e := ENEMY_SCENE.instantiate()
		e.kind = 1 if randf() < gunner_chance else 0
		e.position = _edge_spawn()
		e.died.connect(_on_enemy_died)
		$Enemies.add_child(e)
		e.reset_physics_interpolation()
	enemies_alive = count


func _on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		_schedule_wave(WAVE_BREAK)


# A spot just inside a random wall, away from every player.
func _edge_spawn() -> Vector2:
	for attempt in 40:
		var inset := 140.0
		var p: Vector2
		match randi() % 4:
			0:
				p = Vector2(randf_range(ARENA.position.x + inset, ARENA.end.x - inset), ARENA.position.y + inset)
			1:
				p = Vector2(randf_range(ARENA.position.x + inset, ARENA.end.x - inset), ARENA.end.y - inset)
			2:
				p = Vector2(ARENA.position.x + inset, randf_range(ARENA.position.y + inset, ARENA.end.y - inset))
			_:
				p = Vector2(ARENA.end.x - inset, randf_range(ARENA.position.y + inset, ARENA.end.y - inset))
		var clear := true
		for pl in players.get_children():
			if p.distance_to(pl.position) < 500.0:
				clear = false
				break
		if clear:
			return p
	return Vector2(ARENA.end.x - 140.0, 0.0)


@rpc("authority", "call_local", "reliable")
func spawn_break_fx(pos: Vector2, fx_scale: float) -> void:
	var fx := BREAK_EFFECT.instantiate()
	fx.scale = Vector2.ONE * fx_scale
	fx.position = pos
	add_child(fx)
	fx.reset_physics_interpolation()


func _find_spot(radius: float, placed: Array) -> Vector2:
	var margin := WALL_MARGIN + radius
	for attempt in 120:
		var p := Vector2(
			randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
			randf_range(ARENA.position.y + margin, ARENA.end.y - margin)
		)
		if p.length() < SPAWN_CLEAR_RADIUS + radius:
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q["pos"]) < radius + q["r"] + SPACING_PAD:
				crowded = true
				break
		if not crowded:
			placed.append({"pos": p, "r": radius})
			return p
	# No clean spot found; take anything inside the walls.
	var fallback := Vector2(
		randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
		randf_range(ARENA.position.y + margin, ARENA.end.y - margin)
	)
	placed.append({"pos": fallback, "r": radius})
	return fallback
