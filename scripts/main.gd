extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const PICKUP_SCENE := preload("res://scenes/pickup.tscn")
const MEDKIT_SCENE := preload("res://scenes/medkit.tscn")

# Weapon pickups are rolled by rarity weight and spawn with a full
# magazine. The server tops the map back up to this count over time as
# guns get carried off (thrown guns just drift, so they still count).
const WEAPON_PICKUPS := 12
const RESTOCK_INTERVAL := 10.0

# The Nano-Medkit rides the pickup spawner with this sentinel kind.
# Legendary-rare: at most one in the world, small odds per restock tick,
# versus modes only.
const MEDKIT_KIND := -1
const MEDKIT_CHANCE := 0.12

# Single grenades ride the same spawner. Versus only, kept topped up
# to a few in the world so frags stay scarce but findable.
const GRENADE_KIND := -2
const GRENADE_PACKS := 3
const GRENADE_CHANCE := 0.45
const GRENADE_PACK_SCENE := preload("res://scenes/grenade_pack.tscn")

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

const WALL_MARGIN := 80.0
const SPAWN_CLEAR_RADIUS := 380.0
const SPACING_PAD := 40.0
const COUNTS := [12, 8, 5, 2]  # per variant: small, medium, large, huge
const ASTEROID_RADII := [11.0, 22.0, 45.0, 100.0]
const PICKUP_RADIUS := 20.0

@onready var level_host: LevelHost = $LevelHost
@onready var asteroids: Node2D = $Asteroids
@onready var players: Node2D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var asteroid_spawner: MultiplayerSpawner = $AsteroidSpawner
@onready var pickup_spawner: MultiplayerSpawner = $PickupSpawner
@onready var stars_far: Sprite2D = $StarsFar/Sprite
@onready var stars_near: Sprite2D = $StarsNear/Sprite
@onready var hud: Control = $HUD/Hud

var _player_count := 0
var wave := 0
var enemies_alive := 0
var _wave_pending := false

# fighter key -> kills (peer id online, slot+1 in couch mode). The
# server owns this and broadcasts every change; clients only ever read
# it (the HUD scoreboard).
var scores := {}

var round_manager: Node = null

# Online death view (see set_spectating).
var spectator: SpectatorCamera = null

# Joins replicate as player spawns, so a "joined" feed line only makes
# sense once the initial batch (our own ship, everyone already here)
# has landed; this flips on shortly after the scene starts.
var _join_notices := false


func _ready() -> void:
	# Everyone starts on Classic: it's the solo arena and the warm-up
	# lobby. Versus rounds swap levels through the round manager.
	level_host.load_level(0)
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

	if Net.mode == Net.Mode.HOST or Net.mode == Net.Mode.JOIN:
		var join_gate := Timer.new()
		join_gate.one_shot = true
		join_gate.wait_time = 2.0
		join_gate.timeout.connect(func(): _join_notices = true)
		add_child(join_gate)
		join_gate.start()

	# Solo counts as the server; clients receive everything replicated.
	if multiplayer.is_server():
		# Versus modes get their world from the round manager's first
		# phase broadcast (lobby/countdown both rebuild it).
		if Net.mode == Net.Mode.SOLO:
			_spawn_world()
		if Net.mode == Net.Mode.LOCAL:
			var cam := SharedCamera.new()
			cam.name = "SharedCamera"
			add_child(cam)
			_add_local_players()
		else:
			_add_player(1)
		var restock := Timer.new()
		restock.wait_time = RESTOCK_INTERVAL
		restock.timeout.connect(_restock_pickups)
		add_child(restock)
		restock.start()
	if Net.mode == Net.Mode.SOLO:
		_schedule_wave(FIRST_WAVE_DELAY)
	else:
		# Every versus mode runs the same match flow: warm-up lobby,
		# then rounds. Each peer holds its own manager (same node path
		# everywhere) so the server's phase broadcasts reach them all.
		round_manager = RoundManager.new()
		round_manager.name = "RoundManager"
		add_child(round_manager)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_add_player(id)
		_sync_scores.rpc(scores)


func _on_peer_disconnected(id: int) -> void:
	# Every machine hears the disconnect, so each posts its own notice.
	if players.has_node(str(id)):
		var gone: Node = players.get_node(str(id))
		var colors: Array = preload("res://scripts/player.gd").COLORS
		hud.notify("P%d left the game" % (int(gone.slot) + 1),
				colors[int(gone.color_idx) % colors.size()])
	if multiplayer.is_server():
		if players.has_node(str(id)):
			players.get_node(str(id)).queue_free()
		scores.erase(id)
		_sync_scores.rpc(scores)
		# Leaving mid-fight counts as dying, so the round can resolve.
		if round_manager != null:
			round_manager.call_deferred("recheck_alive")


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


# Eliminated online players ride the spectator camera until the next
# revive hands their own camera back (see player._apply_dead_state).
func set_spectating(on: bool, from: Vector2) -> void:
	if not on:
		if spectator != null:
			spectator.enabled = false
		return
	if spectator == null:
		spectator = SpectatorCamera.new()
		spectator.name = "SpectatorCamera"
		add_child(spectator)
	spectator.target = null
	spectator.global_position = from
	spectator.reset_physics_interpolation()
	spectator.enabled = true
	spectator.make_current()


# Who the death view is watching right now; the HUD names them.
func spectate_target() -> Node2D:
	if spectator != null and spectator.enabled:
		return spectator.target
	return null


# Every peer hears about every death: a feed line for the room, plus a
# YOU DIED flash on the machine whose ship went down. Round
# eliminations skip the flash — the persistent spectate label takes over.
@rpc("any_peer", "call_local", "reliable")
func _net_death_msg(victim_slot: int, victim_color: int, attacker_key: int) -> void:
	var colors: Array = preload("res://scripts/player.gd").COLORS
	var victim_name := "P%d" % (victim_slot + 1)
	var attacker: Node = _player_by_key(attacker_key)
	if attacker != null and int(attacker.slot) != victim_slot:
		hud.notify("P%d destroyed %s" % [int(attacker.slot) + 1, victim_name],
				colors[int(attacker.color_idx) % colors.size()])
	else:
		hud.notify("%s died" % victim_name, colors[victim_color % colors.size()])
	if Net.mode == Net.Mode.LOCAL:
		return  # shared screen: the explosion already tells everyone
	for p in players.get_children():
		if int(p.slot) == victim_slot and p.is_locally_controlled() \
				and not round_fight_active():
			hud.flash_death("YOU DIED")


func _player_by_key(key: int) -> Node:
	for p in players.get_children():
		if p.fighter_key() == key:
			return p
	return null


@rpc("authority", "call_local", "reliable")
func _sync_scores(s: Dictionary) -> void:
	scores = s


func _leave() -> void:
	Net.leave()


func _add_player(id: int) -> void:
	player_spawner.spawn([id, _player_count, _free_color(_player_count)])
	_player_count += 1


# Couch mode: every joined device gets a player under peer 1's
# authority. Non-numeric names keep authority at 1 (see player.gd).
func _add_local_players() -> void:
	for i in Net.local_roster.size():
		var color: int = Net.local_colors[i] if i < Net.local_colors.size() else i
		player_spawner.spawn(["local_%d" % i, i, color, Net.local_roster[i]])
	_player_count = Net.local_roster.size()


# Spawn paint: the slot's classic color when nobody wears it, else the
# first free one (earlier joiners may have picked custom colors).
func _free_color(slot: int) -> int:
	var n: int = preload("res://scripts/player.gd").COLORS.size()
	var used := {}
	for p in players.get_children():
		used[int(p.color_idx)] = true
	if not used.has(slot % n):
		return slot % n
	for i in n:
		if not used.has(i):
			return i
	return slot % n


# data: [name, slot, color, device?] — device only rides couch spawns.
func _spawn_player(data: Variant) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(data[0])
	p.slot = data[1]
	p.color_idx = data[2] if data.size() > 2 else data[1]
	if data.size() > 3:
		p.device = data[3]
	var spawns: Array = level_host.spawns
	p.position = spawns[data[1] % spawns.size()]
	if _join_notices:
		var colors: Array = preload("res://scripts/player.gd").COLORS
		hud.notify("P%d joined the game" % (int(data[1]) + 1),
				colors[int(p.color_idx) % colors.size()])
	return p


func _spawn_asteroid(data: Variant) -> Node:
	var rock := ASTEROID_SCENE.instantiate()
	rock.variant = data[0]
	rock.position = data[1]
	if data.size() > 2:
		rock.volatile = data[2]
	if data.size() > 3:
		rock.init_velocity = data[3]
	return rock


# Spawns everything with size-aware spacing so nothing starts
# overlapping (overlap makes the physics solver fling bodies apart).
func _spawn_world() -> void:
	var placed: Array = []
	# Keep every player spawn point clear, not just the arena center.
	for s in level_host.spawns:
		placed.append({"pos": s, "r": 150.0})
	# Largest rocks first: they're hardest to fit, smalls fill the gaps.
	# A handful of the small/medium rocks roll volatile (they explode).
	# Each level dials its own debris density (0 = clean arena).
	var density: float = level_host.asteroid_density
	for variant in [3, 2, 1, 0]:
		for i in maxi(roundi(COUNTS[variant] * density), 0):
			asteroid_spawner.spawn([
				variant,
				_find_spot(ASTEROID_RADII[variant], placed),
				variant <= 1 and randf() < 0.18,
			])
	for i in WEAPON_PICKUPS:
		_spawn_rolled_pickup(placed)


# Round transitions: tear the floating world down and grow the next
# level's spread. Server-only — the despawns and spawns replicate.
func rebuild_world() -> void:
	if not multiplayer.is_server():
		return
	for holder in [asteroids, $Pickups]:
		for c in holder.get_children():
			c.free()
	_spawn_world()


func _spawn_rolled_pickup(placed: Array) -> void:
	var kind := WeaponDB.roll_weapon()
	pickup_spawner.spawn([
		kind,
		_find_spot(PICKUP_RADIUS, placed),
		Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0),
		randf_range(-1.2, 1.2),
		int(WeaponDB.DATA[kind]["max_ammo"]),
	])


# Touch items (medkits, grenade packs) drift in like rolled guns do.
func _spawn_item_pickup(kind: int) -> void:
	pickup_spawner.spawn([
		kind,
		_find_spot(PICKUP_RADIUS, _live_placed()),
		Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0),
		randf_range(-1.2, 1.2),
	])


# Players call this through the server to drop what they're holding —
# either a deliberate throw or the swap when grabbing a new gun. A fast
# throw arrives armed: it bonks whoever it hits, credited to `thrower`.
func spawn_weapon_pickup(kind: int, ammo_amount: int, pos: Vector2, vel: Vector2,
		spin: float, thrower := 0) -> void:
	if not multiplayer.is_server():
		return
	pickup_spawner.spawn([kind, pos, vel, spin, ammo_amount, thrower])


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
	if int(data[0]) == MEDKIT_KIND or int(data[0]) == GRENADE_KIND:
		var item: RigidBody2D = (MEDKIT_SCENE if int(data[0]) == MEDKIT_KIND
				else GRENADE_PACK_SCENE).instantiate()
		item.position = data[1]
		item.init_velocity = data[2]
		item.init_spin = data[3]
		return item
	var p := PICKUP_SCENE.instantiate()
	p.kind = data[0]
	p.position = data[1]
	p.init_velocity = data[2]
	p.init_spin = data[3]
	p.ammo = data[4]
	if data.size() > 5:
		p.thrower = data[5]
	return p


# Tops the arena back up to WEAPON_PICKUPS, one fresh roll per tick, as
# guns get picked up and carried around. Versus modes also get a rare
# Nano-Medkit roll while none is in the world.
func _restock_pickups() -> void:
	if Net.mode != Net.Mode.SOLO:
		if get_tree().get_nodes_in_group("medkits").is_empty() \
				and randf() < MEDKIT_CHANCE:
			_spawn_item_pickup(MEDKIT_KIND)
		if get_tree().get_nodes_in_group("grenade_packs").size() < GRENADE_PACKS \
				and randf() < GRENADE_CHANCE:
			_spawn_item_pickup(GRENADE_KIND)
	var guns := 0
	for c in $Pickups.get_children():
		if c.is_in_group("pickups"):
			guns += 1
	if guns >= WEAPON_PICKUPS:
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
	var arena: Rect2 = level_host.bounds
	for attempt in 40:
		var inset := 140.0
		var p: Vector2
		match randi() % 4:
			0:
				p = Vector2(randf_range(arena.position.x + inset, arena.end.x - inset), arena.position.y + inset)
			1:
				p = Vector2(randf_range(arena.position.x + inset, arena.end.x - inset), arena.end.y - inset)
			2:
				p = Vector2(arena.position.x + inset, randf_range(arena.position.y + inset, arena.end.y - inset))
			_:
				p = Vector2(arena.end.x - inset, randf_range(arena.position.y + inset, arena.end.y - inset))
		if level_host.blocked(p, 60.0):
			continue
		var clear := true
		for pl in players.get_children():
			if p.distance_to(pl.position) < 500.0:
				clear = false
				break
		if clear:
			return p
	return Vector2(arena.end.x - 140.0, 0.0)


# The dying player's peer broadcasts the blow-up so every screen sees
# (and feels) it.
@rpc("any_peer", "call_local", "reliable")
func _net_player_death_fx(pos: Vector2, color_idx: int) -> void:
	var fx := PlayerExplosion.new()
	var colors: Array = preload("res://scripts/player.gd").COLORS
	fx.color = colors[color_idx % colors.size()]
	fx.position = pos
	add_child(fx)
	fx.reset_physics_interpolation()
	add_shake(14.0)


# Kicks whichever camera this machine is looking through.
func add_shake(amount: float) -> void:
	var cam := get_node_or_null("SharedCamera")
	if cam != null:
		cam.add_shake(amount)
		return
	for p in players.get_children():
		if p.camera.enabled:
			p._shake = maxf(p._shake, amount)


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
		# The server's blast already shoved everything it simulates;
		# clients ride the fx broadcast to push their own ships.
		if not multiplayer.is_server():
			Explosions.shockwave(self, pos,
					fx_scale * 70.0 * Explosions.WAVE_RADIUS_MULT,
					30.0 * Explosions.WAVE_PUSH)


func _find_spot(radius: float, placed: Array) -> Vector2:
	var arena: Rect2 = level_host.bounds
	var margin := WALL_MARGIN + radius
	for attempt in 120:
		var p := Vector2(
			randf_range(arena.position.x + margin, arena.end.x - margin),
			randf_range(arena.position.y + margin, arena.end.y - margin)
		)
		if p.length() < SPAWN_CLEAR_RADIUS + radius:
			continue
		if level_host.blocked(p, radius + SPACING_PAD):
			continue
		var crowded := false
		for q in placed:
			if p.distance_to(q["pos"]) < radius + q["r"] + SPACING_PAD:
				crowded = true
				break
		if not crowded:
			placed.append({"pos": p, "r": radius})
			return p
	# No spot clear of everything; settle for at least missing the
	# level geometry so nothing materializes inside a block.
	for attempt in 40:
		var fallback := Vector2(
			randf_range(arena.position.x + margin, arena.end.x - margin),
			randf_range(arena.position.y + margin, arena.end.y - margin)
		)
		if not level_host.blocked(fallback, radius):
			placed.append({"pos": fallback, "r": radius})
			return fallback
	push_warning("no clear spawn spot on level %d" % level_host.level_id)
	var last: Vector2 = level_host.spawns[0]
	placed.append({"pos": last, "r": radius})
	return last
