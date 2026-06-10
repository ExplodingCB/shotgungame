extends CharacterBody2D

enum Weapon { SHOTGUN, PISTOL, SMG, SNIPER }

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const SMOKE_PUFF_SCENE := preload("res://scenes/smoke_puff.tscn")

const SND_SHOTGUN := preload("res://audio/gunsounds/20 Gauge/MP3/20 Gauge Single Isolated.mp3")
const SND_PISTOL := preload("res://audio/gunsounds/9mm/MP3/9mm Single Isolated.mp3")
const SND_SMG := preload("res://audio/gunsounds/5.56/MP3/556 Single Isolated MP3.mp3")
const SND_SNIPER := preload("res://audio/gunsounds/7.62x54R/MP3/762x54r Single Isolated MP3.mp3")
const SND_DRY := preload("res://audio/gunsounds/Pistol/MP3/9mm Pistol Dry Fire.mp3")
const SND_SWITCH := preload("res://audio/gunsounds/Pistol/MP3/9mm Pistol Slide Release.mp3")
const SND_RACK := preload("res://audio/gunsounds/Reloads, Cycling & More/MP3/AK Rack MP3.mp3")
const SND_SHELL := preload("res://audio/gunsounds/Reloads, Cycling & More/MP3/Pump Shell Load MP3.mp3")

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

const MAX_SHELLS := 24
const START_SHELLS := 8

const WEAPON_DATA := {
	Weapon.SHOTGUN: {
		"texture": preload("res://assets/guns-assetpack/Shotguns/MP-133.png"),
		"recoil": 600.0,
		"cooldown": 0.4,
		"shake": 9.0,
		"kick": 10.0,
		"sprite_x": 26.0,
		"sprite_scale": 0.85,
		"muzzle_x": 66.0,
		"muzzle_y": -5.0,
		"max_ammo": MAX_SHELLS,
		"pickup_ammo": 4,
		"damage": 6.0,
		"count": 12,
		"spread_deg": 8.0,
		"speed_min": 900.0,
		"speed_max": 1500.0,
		"proj_life": 0.45,
		"proj_damping": 1400.0,
		"proj_color": Color(1.0, 0.92, 0.6),
		"sound": SND_SHOTGUN,
		"pitch": 1.0,
	},
	Weapon.PISTOL: {
		"texture": preload("res://assets/guns-assetpack/Handguns/M1911.png"),
		"recoil": 80.0,
		"cooldown": 0.5,
		"shake": 3.0,
		"kick": 5.0,
		"sprite_x": 16.0,
		"sprite_scale": 1.1,
		"muzzle_x": 34.0,
		"muzzle_y": -5.0,
		"max_ammo": -1,
		"pickup_ammo": 0,
		"damage": 8.0,
		"count": 1,
		"spread_deg": 0.0,
		"speed_min": 650.0,
		"speed_max": 650.0,
		"proj_life": 0.16,
		"proj_damping": 0.0,
		"proj_color": Color(1.0, 0.95, 0.8),
		"sound": SND_PISTOL,
		"pitch": 1.0,
	},
	Weapon.SMG: {
		"texture": preload("res://assets/guns-assetpack/SMG's/MP5.png"),
		"recoil": 45.0,
		"cooldown": 0.06,
		"shake": 2.0,
		"kick": 3.0,
		"sprite_x": 22.0,
		"sprite_scale": 0.9,
		"muzzle_x": 49.0,
		"muzzle_y": -7.0,
		"max_ammo": 96,
		"pickup_ammo": 48,
		"damage": 4.0,
		"count": 1,
		"spread_deg": 2.5,
		"speed_min": 1100.0,
		"speed_max": 1100.0,
		"proj_life": 0.35,
		"proj_damping": 0.0,
		"proj_color": Color(1.0, 0.8, 0.45),
		"sound": SND_SMG,
		"pitch": 1.2,
	},
	Weapon.SNIPER: {
		"texture": preload("res://assets/guns-pixelart/Sniper-rifle-3.png"),
		"recoil": 1100.0,
		"cooldown": 1.5,
		"shake": 16.0,
		"kick": 14.0,
		"sprite_x": 26.0,
		"sprite_scale": 1.0,
		"muzzle_x": 58.0,
		"muzzle_y": -3.0,
		"max_ammo": 6,
		"pickup_ammo": 3,
		"sound": SND_SNIPER,
		"pitch": 0.95,
	},
}

var weapon: int = Weapon.SHOTGUN
var primary: int = Weapon.SHOTGUN  # the one big-gun slot; -1 = empty
var ammo := {
	Weapon.SHOTGUN: START_SHELLS,
	Weapon.PISTOL: -1,  # infinite
	Weapon.SMG: 0,
	Weapon.SNIPER: 0,
}
var color_idx := 0
var health := MAX_HEALTH
var max_health := MAX_HEALTH

@onready var body_sprite: Sprite2D = $Body
@onready var gun_pivot: Node2D = $GunPivot
@onready var gun_sprite: Sprite2D = $GunPivot/GunSprite
@onready var muzzle: Marker2D = $GunPivot/Muzzle
@onready var camera: Camera2D = $Camera2D
@onready var shot_audio: AudioStreamPlayer2D = $ShotAudio
@onready var fx_audio: AudioStreamPlayer2D = $FxAudio

var _cooldown := 0.0
var _shake := 0.0
var _gun_rest_x := 0.0
var _spin := 0.0
var _saved_shells := START_SHELLS
var _shown_weapon := -1
var _suppress_switch_snd := false
var _muzzle_y := -5.0


func _enter_tree() -> void:
	# Node is named after its owning peer id by the spawner.
	if str(name).is_valid_int():
		set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	body_sprite.modulate = COLORS[color_idx % COLORS.size()]
	camera.enabled = is_multiplayer_authority()
	_apply_weapon()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or Net.ui_open:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP \
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_toggle_weapon()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				if primary >= 0:
					_switch_weapon(primary)
			KEY_2:
				_switch_weapon(Weapon.PISTOL)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_authority_update(delta)
	elif weapon != _shown_weapon:
		# Remote copy: weapon arrives via the synchronizer.
		_apply_weapon()

	# Shared cosmetics, derived from (possibly synced) state.
	var flipped := absf(gun_pivot.rotation) > PI / 2.0
	gun_sprite.flip_v = flipped
	muzzle.position.y = -_muzzle_y if flipped else _muzzle_y
	gun_sprite.position.x = move_toward(gun_sprite.position.x, _gun_rest_x, GUN_RETURN_SPEED * delta)


func _authority_update(delta: float) -> void:
	var aim := global_position.direction_to(get_global_mouse_position())
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	gun_pivot.rotation = aim.angle()

	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown == 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Net.ui_open:
		_fire(aim)

	# Space drift: only a whisper of friction, so momentum carries
	# until you fire the other way.
	velocity = velocity.move_toward(Vector2.ZERO, DRIFT_FRICTION * delta)
	velocity = velocity.limit_length(MAX_SPEED)

	var collision := move_and_collide(velocity * delta)
	if collision:
		var normal := collision.get_normal()
		var rock := collision.get_collider() as RigidBody2D
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

	# Body rotates independently of the gun: A/D to spin, otherwise
	# whatever the last bump or blast left you with, slowly settling.
	var spin_input := 0.0
	if Input.is_key_pressed(KEY_A):
		spin_input -= 1.0
	if Input.is_key_pressed(KEY_D):
		spin_input += 1.0
	if spin_input != 0.0:
		_spin = clampf(_spin + spin_input * SPIN_ACCEL * delta, -MAX_BODY_SPIN, MAX_BODY_SPIN)
	else:
		_spin = move_toward(_spin, 0.0, SPIN_DAMP * delta)
	body_sprite.rotation += _spin * delta

	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


func add_shells(amount: int) -> bool:
	if primary != Weapon.SHOTGUN or int(ammo[Weapon.SHOTGUN]) >= MAX_SHELLS:
		return false
	ammo[Weapon.SHOTGUN] = mini(int(ammo[Weapon.SHOTGUN]) + amount, MAX_SHELLS)
	_play_fx(SND_SHELL)
	return true


func give_weapon(id: int) -> void:
	if id == Weapon.PISTOL:
		return
	var data: Dictionary = WEAPON_DATA[id]
	if primary == id:
		ammo[id] = mini(int(ammo[id]) + int(data["pickup_ammo"]), int(data["max_ammo"]))
	else:
		if primary == Weapon.SHOTGUN:
			_saved_shells = int(ammo[Weapon.SHOTGUN])
		primary = id
		ammo[id] = START_SHELLS if id == Weapon.SHOTGUN else int(data["pickup_ammo"])
	weapon = id
	_suppress_switch_snd = true
	_apply_weapon()
	_play_fx(SND_RACK)


# Pickup awards arrive from the server, which owns pickup simulation.
@rpc("any_peer", "call_local", "reliable")
func _net_give_shells(amount: int) -> void:
	if not is_multiplayer_authority() or multiplayer.get_remote_sender_id() > 1:
		return
	add_shells(amount)


@rpc("any_peer", "call_local", "reliable")
func _net_give_weapon(id: int) -> void:
	if not is_multiplayer_authority() or multiplayer.get_remote_sender_id() > 1:
		return
	give_weapon(id)


func take_damage(amount: float, dir: Vector2, _at: Vector2) -> void:
	# Runs on whichever peer's projectile landed the hit; route the
	# actual damage to the player's owning peer.
	if is_multiplayer_authority():
		_apply_damage(amount, dir)
	else:
		_apply_damage.rpc_id(get_multiplayer_authority(), amount, dir)


@rpc("any_peer", "call_remote", "reliable")
func _apply_damage(amount: float, dir: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	health -= amount
	velocity += dir * amount * HIT_KNOCKBACK
	_shake = maxf(_shake, 5.0)
	if health <= 0.0:
		_respawn()


func _respawn() -> void:
	health = MAX_HEALTH
	velocity = Vector2.ZERO
	_spin = 0.0
	position = Vector2(randf_range(-1400, 1400), randf_range(-750, 750))
	reset_physics_interpolation()


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
	_shake = data["shake"]
	if weapon == Weapon.SHOTGUN:
		_spin = clampf(_spin + randf_range(-1.5, 1.5), -MAX_BODY_SPIN, MAX_BODY_SPIN)

	# Pickup weapons break when spent and the trusty shotgun returns,
	# with whatever shells it had when it was replaced.
	if weapon != Weapon.PISTOL and weapon != Weapon.SHOTGUN and int(ammo[weapon]) == 0:
		primary = Weapon.SHOTGUN
		ammo[Weapon.SHOTGUN] = _saved_shells
		_switch_weapon(Weapon.SHOTGUN)


# Visuals run on every peer; only the shooter's own machine spawns
# projectiles that deal damage, so hits land exactly once.
@rpc("authority", "call_local", "reliable")
func _fire_fx(aim: Vector2, w: int) -> void:
	var data: Dictionary = WEAPON_DATA[w]
	var lethal := is_multiplayer_authority()
	match w:
		Weapon.SHOTGUN:
			_spawn_projectiles(aim, data, lethal)
			_puff_smoke(14, 1.0, aim)
		Weapon.PISTOL:
			_spawn_projectiles(aim, data, lethal)
			_puff_smoke(5, 0.6, aim)
		Weapon.SMG:
			_spawn_projectiles(aim, data, lethal)
			_puff_smoke(2, 0.5, aim)
		Weapon.SNIPER:
			_fire_beam(aim, lethal)
			_puff_smoke(20, 1.5, aim)
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
		p.exclude = excl
		p.deals_damage = lethal
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
			target.take_damage(BEAM_DAMAGE, aim, to)

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
