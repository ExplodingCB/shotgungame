extends CharacterBody2D

# Weapon stats, rarities, and ids all live in WeaponDB.
const Weapon := WeaponDB.Weapon
const WEAPON_DATA := WeaponDB.DATA

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const SMOKE_PUFF_SCENE := preload("res://scenes/smoke_puff.tscn")

const SND_DRY := preload("res://audio/gunsounds/Pistol/MP3/9mm Pistol Dry Fire.mp3")
const SND_SWITCH := preload("res://audio/gunsounds/Pistol/MP3/9mm Pistol Slide Release.mp3")
const SND_RACK := preload("res://audio/gunsounds/Reloads, Cycling & More/MP3/AK Rack MP3.mp3")

const COLORS := [
	Color(1.0, 0.62, 0.12),  # P1 orange
	Color(0.35, 0.8, 1.0),   # P2 cyan
	Color(0.55, 1.0, 0.5),   # P3 green
	Color(1.0, 0.5, 0.85),   # P4 pink
]

const MAX_HEALTH := 100.0
const HIT_KNOCKBACK := 3.0

const MAX_SPEED := 900.0
const DRIFT_FRICTION := 30.0
const SHAKE_DECAY := 30.0
const WALL_BOUNCE := 0.55
const GUN_RETURN_SPEED := 60.0
const PUSH_FACTOR := 1.2
const SPIN_ACCEL := 8.0
const SPIN_DAMP := 1.5
const MAX_BODY_SPIN := 8.0
const ROCK_SPIN_TRANSFER := 0.004
const MAX_ROCK_SPIN := 5.0
const BEAM_RANGE := 5000.0
const BEAM_DAMAGE := 200.0

const START_SHELLS := 8

# Weapons are grabbed with E inside this radius and thrown with Q;
# thrown guns keep whatever ammo they had.
const GRAB_RADIUS := 220.0
const THROW_SPEED := 420.0

# Body contact above this speed hurts the ship you hit — sawed-off and
# rocket recoil double as a battering ram.
const RAM_SPEED := 550.0
const RAM_COOLDOWN := 0.5

var weapon: int = Weapon.SHOTGUN
var primary: int = Weapon.SHOTGUN  # the one big-gun slot; -1 = empty
var ammo := {}
var color_idx := 0
var health := MAX_HEALTH
var max_health := MAX_HEALTH

# Which physical device steers this body (see PlayerInput). Couch mode
# spawns several locally-controlled players, each bound to one device.
var device := -2
var slot := 0  # stable couch identity; mirrors color_idx
var controls: PlayerInput = PlayerInput.new(-2)

# Round play: eliminated players sit out until the next countdown, and
# everyone's trigger is locked while the countdown runs. _dead rides
# the synchronizer so every peer (and late joiners) hides the corpse.
var _dead := false
var _shown_dead := false
var input_locked := false

@onready var body_sprite: Sprite2D = $Body
@onready var gun_pivot: Node2D = $GunPivot
@onready var gun_sprite: Sprite2D = $GunPivot/GunSprite
@onready var muzzle: Marker2D = $GunPivot/Muzzle
@onready var camera: Camera2D = $Camera2D
@onready var shot_audio: AudioStreamPlayer2D = $ShotAudio
@onready var fx_audio: AudioStreamPlayer2D = $FxAudio

var _cooldown := 0.0
var _shake := 0.0
var _last_health := MAX_HEALTH
var _ram_cd := 0.0
var _gun_rest_x := 0.0
var _spin := 0.0
var _shown_weapon := -1
var _suppress_switch_snd := false
var _muzzle_y := -5.0


func _init() -> void:
	for id in WEAPON_DATA:
		ammo[id] = 0
	ammo[Weapon.SHOTGUN] = START_SHELLS
	ammo[Weapon.PISTOL] = -1  # infinite


func _enter_tree() -> void:
	# Node is named after its owning peer id by the spawner.
	if str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	body_sprite.modulate = COLORS[color_idx % COLORS.size()]
	if device == -2 and is_multiplayer_authority() and Net.mode != Net.Mode.LOCAL:
		device = -1  # the one player this machine steers gets KB+M
	controls = PlayerInput.new(device)
	# Couch mode frames everyone with one shared camera instead.
	camera.enabled = is_multiplayer_authority() and Net.mode != Net.Mode.LOCAL
	# Players live under Main/Players; the level host is their uncle.
	var lh: Node = get_node_or_null("../../LevelHost")
	if lh != null:
		lh.level_loaded.connect(_apply_camera_limits)
		_apply_camera_limits()
	_apply_weapon()


# Pin the follow camera inside the active level so small arenas don't
# show empty space past the walls.
func _apply_camera_limits() -> void:
	var lh: Node = get_node_or_null("../../LevelHost")
	if lh == null:
		return
	var b: Rect2 = lh.bounds
	camera.limit_left = int(b.position.x) - 24
	camera.limit_top = int(b.position.y) - 24
	camera.limit_right = int(b.end.x) + 24
	camera.limit_bottom = int(b.end.y) + 24


# True for bodies steered from this machine: the single authority player
# in solo/networked games, or every couch player in LOCAL mode.
func is_locally_controlled() -> bool:
	return is_multiplayer_authority() and device != -2


# Identity for scores and kill credit. Networked play keys by peer id;
# in LOCAL mode every body shares peer 1, so slots stand in (1-based,
# because attacker key 0 means "nobody" — enemy ships and hazards).
func fighter_key() -> int:
	return slot + 1 if Net.mode == Net.Mode.LOCAL else get_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not is_locally_controlled() or Net.ui_open or _dead or input_locked:
		return
	if controls.is_toggle(event):
		_toggle_weapon()
	elif controls.is_grab(event):
		_try_pickup()
	elif controls.is_throw(event):
		throw_weapon(controls.aim(self))
	elif device == -1 and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				if primary >= 0:
					_switch_weapon(primary)
			KEY_2:
				_switch_weapon(Weapon.PISTOL)


func _physics_process(delta: float) -> void:
	if is_locally_controlled():
		_authority_update(delta)
	else:
		# Remote copy: weapon, health, and death arrive via the
		# synchronizer; a health drop means a hit landed, so flash
		# like the authority.
		if weapon != _shown_weapon:
			_apply_weapon()
		if health < _last_health - 0.01:
			_flash_hit()
		if _dead != _shown_dead:
			_apply_dead_state()
	_last_health = health

	# Shared cosmetics, derived from (possibly synced) state.
	var flipped := absf(gun_pivot.rotation) > PI / 2.0
	gun_sprite.flip_v = flipped
	muzzle.position.y = -_muzzle_y if flipped else _muzzle_y
	gun_sprite.position.x = move_toward(gun_sprite.position.x, _gun_rest_x, GUN_RETURN_SPEED * delta)


func _authority_update(delta: float) -> void:
	if _dead:
		return
	var aim := controls.aim(self)
	gun_pivot.rotation = aim.angle()

	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown == 0.0 and controls.fire_held() and not Net.ui_open and not input_locked:
		_fire(aim)

	# Space drift: only a whisper of friction, so momentum carries
	# until you fire the other way.
	velocity = velocity.move_toward(Vector2.ZERO, DRIFT_FRICTION * delta)
	velocity = velocity.limit_length(MAX_SPEED)

	_ram_cd = maxf(_ram_cd - delta, 0.0)
	var collision := move_and_collide(velocity * delta)
	if collision:
		var normal := collision.get_normal()
		var hit_body := collision.get_collider()
		if _ram_cd == 0.0 and velocity.length() > RAM_SPEED \
				and hit_body is Node2D and (hit_body as Node2D).is_in_group("player") \
				and hit_body.has_method("take_damage"):
			_ram_cd = RAM_COOLDOWN
			hit_body.take_damage(velocity.length() * 0.025, -normal,
					collision.get_position(), fighter_key())
		var rock := hit_body as RigidBody2D
		if rock != null:
			rock.apply_central_impulse(-normal * velocity.length() * PUSH_FACTOR)
			var lever: Vector2 = (collision.get_position() - rock.global_position).normalized()
			rock.angular_velocity = clampf(
				rock.angular_velocity + lever.cross(-normal) * velocity.length() * ROCK_SPIN_TRANSFER,
				-MAX_ROCK_SPIN, MAX_ROCK_SPIN
			)
		_spin = clampf(_spin + normal.cross(velocity) * 0.004, -MAX_BODY_SPIN, MAX_BODY_SPIN)
		velocity = velocity.bounce(normal) * WALL_BOUNCE
		move_and_collide(collision.get_remainder().bounce(normal))

	# Body rotates independently of the gun: A/D (or bumpers) to spin,
	# otherwise whatever the last bump or blast left you with, settling.
	var spin_input := controls.spin_axis()
	if spin_input != 0.0:
		_spin = clampf(_spin + spin_input * SPIN_ACCEL * delta, -MAX_BODY_SPIN, MAX_BODY_SPIN)
	else:
		_spin = move_toward(_spin, 0.0, SPIN_DAMP * delta)
	body_sprite.rotation += _spin * delta

	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
	if camera.enabled:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


# Kicks this player's view: their own camera when they have one, the
# couch-mode shared camera otherwise.
func _add_shake(amount: float) -> void:
	if camera.enabled:
		_shake = maxf(_shake, amount)
		return
	var cam: Node = get_tree().current_scene.get_node_or_null("SharedCamera")
	if cam != null:
		cam.add_shake(amount)


# Equips a weapon carrying exactly `amount` rounds — the load travels
# with the gun, whether it came from the world or another player's hands.
func give_weapon(id: int, amount: int) -> void:
	if id == Weapon.PISTOL:
		return
	primary = id
	ammo[id] = amount
	weapon = id
	_suppress_switch_snd = true
	_apply_weapon()
	_play_fx(SND_RACK)


# Throws the primary toward `aim`; it sails off as a pickup that keeps
# its remaining ammo. You're left with the trusty infinite pistol.
func throw_weapon(aim: Vector2) -> void:
	if primary < 0:
		return
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	_net_throw.rpc_id(1, primary, int(ammo[primary]), aim)
	ammo[primary] = 0
	primary = -1
	if weapon != Weapon.PISTOL:
		_switch_weapon(Weapon.PISTOL)
	_play_fx(SND_SWITCH)


func _try_pickup() -> void:
	var target := _nearest_pickup()
	if target == null:
		return
	var drop_ammo := int(ammo[primary]) if primary >= 0 else 0
	_net_request_pickup.rpc_id(1, str(target.name), primary, drop_ammo)


func _nearest_pickup() -> Node2D:
	var best: Node2D = null
	var best_d := GRAB_RADIUS
	for p in get_tree().get_nodes_in_group("pickups"):
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# Runs on the server, which owns pickup simulation: first claim wins.
# The grabber's old gun (if any) drops in place of the new one, so a
# grab inside the radius is really a swap.
@rpc("any_peer", "call_local", "reliable")
func _net_request_pickup(pickup_name: String, drop_kind: int, drop_ammo: int) -> void:
	if not multiplayer.is_server() \
			or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	var holder := get_tree().current_scene.get_node_or_null("Pickups")
	if holder == null:
		return
	var pickup := holder.get_node_or_null(NodePath(pickup_name))
	if pickup == null or pickup._collected:
		return
	# Lenient range check: positions lag a little over the network.
	if global_position.distance_to(pickup.global_position) > GRAB_RADIUS * 1.5:
		return
	pickup._collected = true
	var got_kind: int = pickup.kind
	var got_ammo: int = pickup.ammo
	pickup.queue_free()
	if drop_kind >= 0 and drop_kind != Weapon.PISTOL and WEAPON_DATA.has(drop_kind):
		get_tree().current_scene.spawn_weapon_pickup(
				drop_kind, drop_ammo, global_position, Vector2.ZERO, randf_range(-1.2, 1.2))
	_net_receive_weapon.rpc_id(get_multiplayer_authority(), got_kind, got_ammo)


@rpc("any_peer", "call_local", "reliable")
func _net_receive_weapon(id: int, amount: int) -> void:
	if not is_multiplayer_authority() or multiplayer.get_remote_sender_id() > 1:
		return
	give_weapon(id, amount)


@rpc("any_peer", "call_local", "reliable")
func _net_throw(kind: int, amount: int, aim: Vector2) -> void:
	if not multiplayer.is_server() \
			or multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if kind < 0 or kind == Weapon.PISTOL or not WEAPON_DATA.has(kind):
		return
	var dir := aim.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	get_tree().current_scene.spawn_weapon_pickup(
			kind, amount,
			global_position + dir * 50.0,
			dir * THROW_SPEED + velocity * 0.5,
			randf_range(-2.0, 2.0),
			fighter_key())


func take_damage(amount: float, dir: Vector2, _at: Vector2, attacker_id := 0) -> void:
	# Runs on whichever peer's projectile landed the hit; route the
	# actual damage to the player's owning peer. The shooter's machine
	# is right here, so this is also where landing a hit gets its punch.
	Juice.hit_landed(amount)
	if is_multiplayer_authority():
		_apply_damage(amount, dir, attacker_id)
	else:
		_apply_damage.rpc_id(get_multiplayer_authority(), amount, dir, attacker_id)


@rpc("any_peer", "call_remote", "reliable")
func _apply_damage(amount: float, dir: Vector2, attacker_id := 0) -> void:
	if not is_multiplayer_authority():
		return
	health -= amount
	velocity += dir * amount * HIT_KNOCKBACK
	_add_shake(5.0)
	_flash_hit()
	Juice.rumble(device, 0.6, 0.4, 0.2)
	if health <= 0.0:
		# The dying peer knows who landed the killing blow; the server
		# keeps score (and ignores suicides and enemy-ship kills).
		# Couch mode is single-process, so it reports directly with the
		# victim's slot key instead of leaning on the RPC sender id.
		var main := get_tree().current_scene
		# Decide the fate before reporting: the report may end the round.
		var out_for_round: bool = main != null \
				and main.has_method("round_fight_active") and main.round_fight_active()
		if Net.mode == Net.Mode.LOCAL:
			if main != null and main.has_method("report_death"):
				main.report_death(fighter_key(), attacker_id)
		elif main != null and main.has_method("_net_report_kill"):
			main._net_report_kill.rpc_id(1, attacker_id)
		if main != null and main.has_method("_net_player_death_fx"):
			main._net_player_death_fx.rpc(global_position, color_idx)
		Juice.hitstop(150)
		Juice.rumble(device, 1.0, 1.0, 0.45)
		if out_for_round:
			eliminate()
		else:
			_respawn()


func _respawn() -> void:
	health = MAX_HEALTH
	velocity = Vector2.ZERO
	_spin = 0.0
	position = Vector2(randf_range(-1400, 1400), randf_range(-750, 750))
	reset_physics_interpolation()


# Out for the round: the body stays in the tree (scoreboard, camera)
# but vanishes from play until revive().
func eliminate() -> void:
	_dead = true
	health = 0.0
	velocity = Vector2.ZERO
	_apply_dead_state()


func revive(at: Vector2) -> void:
	_dead = false
	health = MAX_HEALTH
	velocity = Vector2.ZERO
	_spin = 0.0
	_apply_dead_state()
	global_position = at
	reset_physics_interpolation()


func _apply_dead_state() -> void:
	_shown_dead = _dead
	visible = not _dead
	collision_layer = 0 if _dead else 2
	collision_mask = 0 if _dead else 3


# Back to the starting kit between rounds: shotgun shells + the pistol.
func reset_loadout() -> void:
	for id in ammo:
		ammo[id] = 0
	ammo[Weapon.SHOTGUN] = START_SHELLS
	ammo[Weapon.PISTOL] = -1
	primary = Weapon.SHOTGUN
	weapon = Weapon.SHOTGUN
	_cooldown = 0.0
	_suppress_switch_snd = true
	_apply_weapon()


func _toggle_weapon() -> void:
	if weapon == Weapon.PISTOL and primary >= 0:
		_switch_weapon(primary)
	else:
		_switch_weapon(Weapon.PISTOL)


func _switch_weapon(to: int) -> void:
	if weapon == to:
		return
	if to != Weapon.PISTOL and to != primary:
		return
	weapon = to
	_apply_weapon()


func _apply_weapon() -> void:
	var data: Dictionary = WEAPON_DATA[weapon]
	gun_sprite.texture = data["texture"]
	gun_sprite.position.x = data["sprite_x"]
	gun_sprite.scale = Vector2.ONE * float(data["sprite_scale"])
	muzzle.position.x = data["muzzle_x"]
	_muzzle_y = data["muzzle_y"]
	_gun_rest_x = data["sprite_x"]
	var was := _shown_weapon
	_shown_weapon = weapon
	if was != -1 and was != weapon and not _suppress_switch_snd:
		_play_fx(SND_SWITCH)
	_suppress_switch_snd = false


# Red sting on taking a hit, settling back to the player's color.
func _flash_hit() -> void:
	body_sprite.modulate = Color(1.0, 0.35, 0.3)
	var tween := create_tween()
	tween.tween_property(body_sprite, "modulate",
			COLORS[color_idx % COLORS.size()], 0.18)


func _play_fx(stream: AudioStream) -> void:
	fx_audio.stream = stream
	fx_audio.pitch_scale = randf_range(0.95, 1.05)
	fx_audio.play()


func _fire(aim: Vector2) -> void:
	if ammo[weapon] == 0:
		# Empty click, throttled so holding the button doesn't buzz.
		_cooldown = 0.3
		_play_fx(SND_DRY)
		return
	var data: Dictionary = WEAPON_DATA[weapon]
	if int(ammo[weapon]) > 0:
		ammo[weapon] = int(ammo[weapon]) - 1
	_fire_fx.rpc(aim, weapon)
	_cooldown = data["cooldown"]
	velocity += -aim * data["recoil"]
	_add_shake(data["shake"])
	Juice.rumble(device, 0.0, clampf(float(data["recoil"]) / 1200.0, 0.1, 0.85), 0.12)
	if data.get("spin_kick", false):
		_spin = clampf(_spin + randf_range(-1.5, 1.5), -MAX_BODY_SPIN, MAX_BODY_SPIN)
	# Spent weapons don't break — they stay equipped (dry-clicking) and
	# can be thrown away or swapped at the next pickup.


# Visuals run on every peer; only the shooter's own machine spawns
# projectiles that deal damage, so hits land exactly once.
@rpc("authority", "call_local", "reliable")
func _fire_fx(aim: Vector2, w: int) -> void:
	var data: Dictionary = WEAPON_DATA[w]
	var lethal := is_multiplayer_authority()
	match data.get("fire_mode", "pellets"):
		"beam":
			_fire_beam(aim, lethal)
		_:
			_spawn_projectiles(aim, data, lethal)
	_puff_smoke(int(data["smoke"]), float(data["smoke_scale"]), aim)
	gun_sprite.position.x = _gun_rest_x - float(data["kick"])
	var snd: AudioStream = data["sound"]
	if shot_audio.stream != snd:
		shot_audio.stream = snd
	shot_audio.pitch_scale = float(data["pitch"]) * randf_range(0.94, 1.06)
	shot_audio.play()


func _spawn_projectiles(aim: Vector2, data: Dictionary, lethal: bool) -> void:
	var spread: float = deg_to_rad(data["spread_deg"])
	var excl: Array[RID] = [get_rid()]
	for i in int(data["count"]):
		var p := PROJECTILE_SCENE.instantiate()
		p.velocity = aim.rotated(randf_range(-spread, spread)) \
				* randf_range(data["speed_min"], data["speed_max"])
		p.damage = data["damage"]
		p.lifetime = data["proj_life"]
		p.damping = data["proj_damping"]
		p.modulate = data["proj_color"]
		p.scale = Vector2.ONE * float(data.get("proj_scale", 1.0))
		p.explode_radius = float(data.get("explode_radius", 0.0))
		p.explode_damage = float(data.get("explode_damage", 0.0))
		p.bounces = int(data.get("bounces", 0))
		p.exclude = excl
		p.deals_damage = lethal
		p.shooter_id = fighter_key()
		p.position = muzzle.global_position
		get_tree().current_scene.add_child(p)
		p.reset_physics_interpolation()


func _puff_smoke(amount: int, size: float, aim: Vector2) -> void:
	var puff := SMOKE_PUFF_SCENE.instantiate()
	puff.amount = amount
	puff.rotation = aim.angle()
	puff.scale = Vector2.ONE * size
	puff.position = muzzle.global_position
	get_tree().current_scene.add_child(puff)
	puff.reset_physics_interpolation()


func _fire_beam(aim: Vector2, lethal: bool) -> void:
	var from := muzzle.global_position
	var to := from + aim * BEAM_RANGE
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 3  # world + players; the beam ignores pickups
	var excl: Array[RID] = [get_rid()]
	query.exclude = excl
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		to = hit["position"]
		var target: Object = hit["collider"]
		if lethal and target != null and target.has_method("take_damage"):
			target.take_damage(BEAM_DAMAGE, aim, to, fighter_key())

	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2.ZERO, to - from])
	beam.width = 14.0
	beam.default_color = Color(0.65, 0.9, 1.0, 1.0)
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	beam.position = from
	get_tree().current_scene.add_child(beam)
	beam.reset_physics_interpolation()
	var tween := beam.create_tween()
	tween.tween_property(beam, "modulate:a", 0.0, 0.4)
	tween.tween_callback(beam.queue_free)
