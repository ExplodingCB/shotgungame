# Dungeon hostiles. One script drives the whole roster: the DATA table
# sets art and stats, `kind` picks the brain in _physics_process. New
# silhouettes come from recoloring and rescaling the two ship sprites —
# tint + size + behavior keeps every kind readable at a glance.
class_name DungeonEnemy
extends CharacterBody2D

enum Kind {
	DRIFTER, GUNNER, SWARMLING, CHARGER, TURRET, SPLITTER, WARDEN,
	KAMIKAZE, BOMBER, SNIPER, MINELAYER,
}
enum State { CRUISE, WINDUP, DASH, RECOVER }

signal died(kind: int, at: Vector2, killer_id: int)

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const BREAK_EFFECT := preload("res://scenes/asteroid_break.tscn")
const BEHOLDER := preload("res://assets/spaceships/Beholder/Beholder.png")
const EMISSARY := preload("res://assets/spaceships/Emissary/Emissary.png")

const DATA := {
	Kind.DRIFTER: {  # the basic rammer
		"texture": BEHOLDER, "tint": Color.WHITE, "scale": 1.4, "sprite_rot": 0.0,
		"radius": 18.0, "health": 40.0, "speed": 260.0, "accel": 330.0, "contact": 14.0,
	},
	Kind.GUNNER: {  # orbits and takes potshots
		"texture": EMISSARY, "tint": Color.WHITE, "scale": 1.4, "sprite_rot": PI / 2.0,
		"radius": 18.0, "health": 30.0, "speed": 190.0, "accel": 250.0, "contact": 10.0,
	},
	Kind.SWARMLING: {  # fast, fragile, comes in packs
		"texture": BEHOLDER, "tint": Color(1.0, 0.85, 0.35), "scale": 0.9, "sprite_rot": 0.0,
		"radius": 12.0, "health": 12.0, "speed": 345.0, "accel": 520.0, "contact": 8.0,
	},
	Kind.CHARGER: {  # telegraphs, then dashes like a battering ram
		"texture": BEHOLDER, "tint": Color(1.0, 0.42, 0.42), "scale": 1.9, "sprite_rot": 0.0,
		"radius": 24.0, "health": 70.0, "speed": 190.0, "accel": 240.0, "contact": 22.0,
	},
	Kind.TURRET: {  # anchored weapons platform, fans of fire
		"texture": EMISSARY, "tint": Color(0.55, 0.8, 1.0), "scale": 2.0, "sprite_rot": PI / 2.0,
		"radius": 26.0, "health": 90.0, "speed": 0.0, "accel": 0.0, "contact": 10.0,
	},
	Kind.SPLITTER: {  # slow tank; bursts into swarmlings when it pops
		"texture": EMISSARY, "tint": Color(0.5, 1.0, 0.55), "scale": 2.4, "sprite_rot": PI / 2.0,
		"radius": 30.0, "health": 140.0, "speed": 125.0, "accel": 160.0, "contact": 16.0,
	},
	Kind.WARDEN: {  # the boss: rings, volleys, summons, charges
		"texture": BEHOLDER, "tint": Color(0.85, 0.55, 1.0), "scale": 4.2, "sprite_rot": 0.0,
		"radius": 52.0, "health": 300.0, "speed": 170.0, "accel": 200.0, "contact": 24.0,
	},
	Kind.KAMIKAZE: {  # rushes in and self-destructs; pop it from range
		"texture": BEHOLDER, "tint": Color(1.0, 0.6, 0.2), "scale": 1.1, "sprite_rot": 0.0,
		"radius": 14.0, "health": 18.0, "speed": 380.0, "accel": 560.0, "contact": 8.0,
	},
	Kind.BOMBER: {  # lobs explosive shells from a wide orbit
		"texture": EMISSARY, "tint": Color(1.0, 0.75, 0.35), "scale": 1.8, "sprite_rot": PI / 2.0,
		"radius": 24.0, "health": 80.0, "speed": 160.0, "accel": 200.0, "contact": 12.0,
	},
	Kind.SNIPER: {  # hangs far back; a warning line, then an instant beam
		"texture": EMISSARY, "tint": Color(0.8, 0.7, 1.0), "scale": 1.6, "sprite_rot": PI / 2.0,
		"radius": 20.0, "health": 45.0, "speed": 230.0, "accel": 280.0, "contact": 10.0,
	},
	Kind.MINELAYER: {  # fast strafer that seeds proximity mines
		"texture": BEHOLDER, "tint": Color(0.4, 0.9, 0.85), "scale": 1.6, "sprite_rot": 0.0,
		"radius": 20.0, "health": 60.0, "speed": 210.0, "accel": 260.0, "contact": 12.0,
	},
}

const RAM_COOLDOWN := 0.9
const GUNNER_RANGE := 800.0
const GUNNER_INTERVAL := 1.7
const GUNNER_ORBIT := 420.0
const TURRET_RANGE := 950.0
const TURRET_INTERVAL := 2.4
const CHARGE_TRIGGER := 720.0
const WINDUP_TIME := 0.55
const DASH_TIME := 0.65
const DASH_SPEED := 950.0
const RECOVER_TIME := 0.9
const CHARGE_COOLDOWN := 3.0
const WARDEN_ORBIT := 480.0
const WARDEN_ATTACK_GAP := 2.6
const HIT_KNOCKBACK := 3.0
const KAMIKAZE_TRIGGER := 120.0
const KAMIKAZE_FUSE := 0.45
const KAMIKAZE_BLAST_RADIUS := 130.0
const KAMIKAZE_BLAST_DAMAGE := 26.0
const BOMBER_ORBIT := 620.0
const BOMBER_RANGE := 950.0
const BOMBER_INTERVAL := 2.6
const SNIPER_ORBIT := 900.0
const SNIPER_RANGE := 1400.0
const SNIPER_INTERVAL := 3.2
const SNIPER_AIM_TIME := 0.7
const SNIPER_DAMAGE := 16.0
const MINELAYER_ORBIT := 520.0
const MINELAYER_INTERVAL := 3.5
const MAX_FIELD_MINES := 8

var kind: int = Kind.DRIFTER
var hp_mult := 1.0

var health := 40.0
var max_health := 40.0
var _dead := false
var _speed := 260.0
var _accel := 330.0
var _contact := 14.0
var _tint := Color.WHITE
var _ram_cd := 0.0
var _fire_cd := randf_range(1.0, 2.2)
var _state: int = State.CRUISE
var _state_t := 0.0
var _dash_dir := Vector2.RIGHT
var _charge_cd := randf_range(0.6, 1.6)
var _enraged := false
var _fuse := -1.0           # kamikaze: >= 0 once armed
var _aim_t := -1.0          # sniper: >= 0 while drawing a bead
var _aim_point := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	var d: Dictionary = DATA[kind]
	sprite.texture = d["texture"]
	sprite.rotation = d["sprite_rot"]
	sprite.scale = Vector2.ONE * float(d["scale"])
	_tint = d["tint"]
	sprite.modulate = _tint
	# Shape resources are shared between instances, so each body gets
	# its own circle sized to its kind.
	var circle := CircleShape2D.new()
	circle.radius = d["radius"]
	shape.shape = circle
	health = float(d["health"]) * hp_mult
	max_health = health
	_speed = d["speed"]
	_accel = d["accel"]
	_contact = d["contact"]
	# Health bars sit a fixed distance above the hull, whatever the size.
	$HealthBar.position.y = 18.0 - float(d["radius"])
	add_to_group("enemies")
	# Pop-in: scale up from nothing so spawns read as arrivals.
	sprite.scale = Vector2.ONE * float(d["scale"]) * 0.2
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2.ONE * float(d["scale"]), 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_ram_cd = maxf(_ram_cd - delta, 0.0)
	var target := _nearest_player()
	var desired := Vector2.ZERO
	if target != null:
		desired = _think(target, delta)
	if _speed > 0.0 or _state == State.DASH:
		velocity = velocity.move_toward(desired, _dash_accel(delta))
		var collision := move_and_collide(velocity * delta)
		if collision:
			_handle_collision(collision)


func _think(target: Node2D, delta: float) -> Vector2:
	var to_target: Vector2 = target.global_position - global_position
	var face := to_target.angle()
	var desired := Vector2.ZERO

	match kind:
		Kind.DRIFTER, Kind.SWARMLING, Kind.SPLITTER:
			desired = to_target.normalized() * _speed

		Kind.GUNNER:
			desired = _orbit(to_target, GUNNER_ORBIT, 0.55)
			_fire_cd -= delta
			if _fire_cd <= 0.0 and to_target.length() < GUNNER_RANGE:
				_fire_cd = GUNNER_INTERVAL
				_shoot(to_target.normalized().rotated(randf_range(-0.06, 0.06)),
						430.0, 7.0, 2.2, Color(0.45, 1.0, 0.9))

		Kind.TURRET:
			_fire_cd -= delta
			if _fire_cd <= 0.0 and to_target.length() < TURRET_RANGE:
				_fire_cd = TURRET_INTERVAL + randf_range(-0.4, 0.4)
				_fan(to_target.normalized(), 4, 0.5, 430.0, 8.0, Color(0.55, 0.8, 1.0))

		Kind.CHARGER:
			desired = _charger_brain(to_target, delta, DASH_SPEED)
			if _state == State.DASH:
				face = _dash_dir.angle()

		Kind.WARDEN:
			desired = _warden_brain(to_target, delta)
			if _state == State.DASH:
				face = _dash_dir.angle()

		Kind.KAMIKAZE:
			if _fuse >= 0.0:
				_fuse -= delta
				if _fuse <= 0.0:
					take_damage(99999.0, Vector2.ZERO, global_position, 0)
					return Vector2.ZERO
				desired = to_target.normalized() * _speed * 0.4
			else:
				desired = to_target.normalized() * _speed
				if to_target.length() < KAMIKAZE_TRIGGER:
					_fuse = KAMIKAZE_FUSE
					_windup_flash()

		Kind.BOMBER:
			desired = _orbit(to_target, BOMBER_ORBIT, 0.5)
			_fire_cd -= delta
			if _fire_cd <= 0.0 and to_target.length() < BOMBER_RANGE:
				_fire_cd = BOMBER_INTERVAL
				_lob(to_target.normalized())

		Kind.SNIPER:
			desired = _sniper_brain(to_target, delta)

		Kind.MINELAYER:
			desired = _orbit(to_target, MINELAYER_ORBIT, 0.7)
			_fire_cd -= delta
			if _fire_cd <= 0.0:
				_fire_cd = MINELAYER_INTERVAL
				_lay_mine()

	if _state != State.WINDUP:
		rotation = lerp_angle(rotation, face, 6.0 * delta)
	return desired


# Hold a ring around the player, strafing sideways while drifting in
# or out toward the preferred distance.
func _orbit(to_target: Vector2, dist: float, strafe: float) -> Vector2:
	var dir := to_target.normalized()
	var dist_err := clampf((to_target.length() - dist) / 200.0, -1.0, 1.0)
	return dir * dist_err * _speed * 0.9 + dir.orthogonal() * _speed * strafe


# Shared windup/dash/recover cycle for chargers (and the Warden's
# charge attack). Returns the desired velocity for this frame.
func _charger_brain(to_target: Vector2, delta: float, dash_speed: float) -> Vector2:
	_state_t -= delta
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	match _state:
		State.CRUISE:
			if _charge_cd == 0.0 and to_target.length() < CHARGE_TRIGGER:
				_state = State.WINDUP
				_state_t = WINDUP_TIME
				_windup_flash()
			return to_target.normalized() * _speed
		State.WINDUP:
			# Track the player until the last instant, then commit.
			if _state_t > 0.15:
				_dash_dir = to_target.normalized()
				rotation = lerp_angle(rotation, _dash_dir.angle(), 12.0 * delta)
			if _state_t <= 0.0:
				_state = State.DASH
				_state_t = DASH_TIME
			return Vector2.ZERO
		State.DASH:
			if _state_t <= 0.0:
				_end_dash()
			return _dash_dir * dash_speed
		_:  # RECOVER
			if _state_t <= 0.0:
				_state = State.CRUISE
				_charge_cd = CHARGE_COOLDOWN
			return Vector2.ZERO
	return Vector2.ZERO


func _warden_brain(to_target: Vector2, delta: float) -> Vector2:
	if not _enraged and health < max_health * 0.5:
		_enraged = true
		sprite.modulate = _tint.lightened(0.15)
	# Mid-charge the warden uses the charger cycle wholesale.
	if _state != State.CRUISE:
		return _charger_brain(to_target, delta, DASH_SPEED * 0.9)

	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd = WARDEN_ATTACK_GAP * (0.7 if _enraged else 1.0)
		_warden_attack(to_target)
	return _orbit(to_target, WARDEN_ORBIT, 0.4)


func _warden_attack(to_target: Vector2) -> void:
	var bullet_speed := 330.0 * (1.25 if _enraged else 1.0)
	var roll := randi() % 4
	match roll:
		0:  # bullet ring
			var n := 20
			for i in n:
				_shoot(Vector2.from_angle(i * TAU / n + randf() * 0.2),
						bullet_speed, 7.0, 2.6, Color(0.95, 0.5, 1.0))
		1:  # aimed fan volley
			_fan(to_target.normalized(), 7, 0.7, bullet_speed * 1.45, 8.0,
					Color(0.95, 0.5, 1.0))
		2:  # call in swarmlings
			var main := Arena.of(self)
			if main != null and main.has_method("spawn_enemy") \
					and int(main.enemies_alive) < 8:
				for i in 3:
					var off := Vector2.from_angle(randf() * TAU) * randf_range(80.0, 140.0)
					main.spawn_enemy(Kind.SWARMLING, global_position + off, false)
			else:
				_fan(to_target.normalized(), 7, 0.7, bullet_speed * 1.45, 8.0,
						Color(0.95, 0.5, 1.0))
		3:  # telegraphed body slam
			_state = State.WINDUP
			_state_t = WINDUP_TIME + 0.15
			_windup_flash()


func _windup_flash() -> void:
	# Blink while winding up so the dash is dodgeable on reaction.
	sprite.modulate = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	var base := _tint.lightened(0.15) if _enraged else _tint
	for i in 3:
		tween.tween_property(sprite, "modulate", Color(1.0, 0.6, 0.5), 0.09)
		tween.tween_property(sprite, "modulate", base, 0.09)


func _end_dash() -> void:
	_state = State.RECOVER
	_state_t = RECOVER_TIME
	velocity *= 0.25


func _dash_accel(delta: float) -> float:
	# Dashes snap to speed; everything else eases.
	return 4000.0 * delta if _state == State.DASH else _accel * delta


func _handle_collision(collision: KinematicCollision2D) -> void:
	var col := collision.get_collider()
	if _ram_cd == 0.0 and col is Node2D and (col as Node2D).is_in_group("player") \
			and col.has_method("take_damage"):
		_ram_cd = RAM_COOLDOWN
		var dmg := _contact * (1.6 if _state == State.DASH else 1.0)
		col.take_damage(dmg, -collision.get_normal(), collision.get_position())
	if _state == State.DASH:
		_end_dash()
	velocity = velocity.bounce(collision.get_normal()) * 0.6


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not p.visible:
			continue
		var d: float = global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


# Sniper cycle: hold way out, then stop, draw a visible bead on the
# player (tracking at first, locked near the end), and cut an instant
# beam. Rocks and hull blocks break the shot, so cover works.
func _sniper_brain(to_target: Vector2, delta: float) -> Vector2:
	if _aim_t >= 0.0:
		_aim_t -= delta
		if _aim_t > SNIPER_AIM_TIME * 0.35:
			_aim_point = global_position + to_target
		queue_redraw()
		if _aim_t <= 0.0:
			_fire_beam(global_position.direction_to(_aim_point))
			_fire_cd = SNIPER_INTERVAL
		return Vector2.ZERO
	_fire_cd -= delta
	if _fire_cd <= 0.0 and to_target.length() < SNIPER_RANGE:
		_aim_t = SNIPER_AIM_TIME
		_aim_point = global_position + to_target
	return _orbit(to_target, SNIPER_ORBIT, 0.35)


func _fire_beam(dir: Vector2) -> void:
	var from := global_position + dir * (float(DATA[kind]["radius"]) + 10.0)
	var to := from + dir * SNIPER_RANGE
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 3
	var excl: Array[RID] = [get_rid()]
	query.exclude = excl
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		to = hit["position"]
		var target: Object = hit["collider"]
		if target != null and target.has_method("take_damage"):
			target.take_damage(SNIPER_DAMAGE, dir, to, 0)
	var beam := Line2D.new()
	beam.points = PackedVector2Array([Vector2.ZERO, to - from])
	beam.width = 4.0
	beam.default_color = Color(0.8, 0.7, 1.0)
	beam.position = from
	Arena.of(self).add_child(beam)
	beam.reset_physics_interpolation()
	var tween := beam.create_tween()
	tween.tween_property(beam, "modulate:a", 0.0, 0.25)
	tween.tween_callback(beam.queue_free)
	queue_redraw()


func _lay_mine() -> void:
	var main := Arena.of(self)
	var holder := main.get_node_or_null("Props") if main != null else null
	if holder == null:
		return
	var mines := 0
	for c in holder.get_children():
		if c is DungeonMine and not c.is_queued_for_deletion():
			mines += 1
	if mines >= MAX_FIELD_MINES:
		return
	var mine := DungeonMine.new()
	mine.position = global_position - velocity.normalized() * 40.0 \
			if velocity != Vector2.ZERO else global_position
	holder.add_child(mine)


# Explosive shell: slow, fat, and detonating on impact or fuse end.
func _lob(dir: Vector2) -> void:
	var p := PROJECTILE_SCENE.instantiate()
	var excl: Array[RID] = [get_rid()]
	p.velocity = dir.rotated(randf_range(-0.05, 0.05)) * 400.0
	p.damage = 10.0
	p.lifetime = 1.7
	p.damping = 150.0
	p.modulate = Color(1.0, 0.6, 0.2)
	p.scale = Vector2.ONE * 2.0
	p.explode_radius = 110.0
	p.explode_damage = 20.0
	p.exclude = excl
	p.position = global_position + dir * (float(DATA[kind]["radius"]) + 14.0)
	Arena.of(self).add_child(p)
	p.reset_physics_interpolation()


# Only the sniper draws anything itself: the warning bead while aiming.
func _draw() -> void:
	if kind != Kind.SNIPER or _aim_t < 0.0:
		return
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	var a := 0.25 + 0.5 * (1.0 - _aim_t / SNIPER_AIM_TIME)
	draw_line(global_position, _aim_point, Color(0.8, 0.7, 1.0, a), 2.0)
	draw_set_transform_matrix(Transform2D())


func _shoot(dir: Vector2, speed: float, dmg: float, life: float, color: Color) -> void:
	var p := PROJECTILE_SCENE.instantiate()
	var excl: Array[RID] = [get_rid()]
	p.velocity = dir * speed
	p.damage = dmg
	p.lifetime = life
	p.modulate = color
	p.exclude = excl
	p.position = global_position + dir * (float(DATA[kind]["radius"]) + 14.0)
	Arena.of(self).add_child(p)
	p.reset_physics_interpolation()


func _fan(dir: Vector2, count: int, total_spread: float, speed: float,
		dmg: float, color: Color) -> void:
	for i in count:
		var t := float(i) / maxf(count - 1, 1) - 0.5
		_shoot(dir.rotated(t * total_spread), speed, dmg, 2.0, color)


func take_damage(amount: float, dir: Vector2, _at: Vector2, attacker_id := 0) -> void:
	# The body stays in physics space until queue_free runs at end of
	# frame, so a multi-pellet blast can land several hits on a corpse;
	# only the killing blow may emit died.
	if _dead:
		return
	Juice.hit_landed(amount * 0.6)
	health -= amount
	# Heavies barely budge; it sells their mass.
	var heft := 0.25 if kind == Kind.TURRET or kind == Kind.WARDEN else 1.0
	velocity += dir * amount * HIT_KNOCKBACK * heft
	if _state != State.WINDUP:
		sprite.modulate = Color(1.0, 0.45, 0.4)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate",
				_tint.lightened(0.15) if _enraged else _tint, 0.15)
	if health <= 0.0:
		_dead = true
		var fx := BREAK_EFFECT.instantiate()
		fx.scale = Vector2.ONE * (1.6 if kind == Kind.WARDEN else 0.7)
		fx.position = global_position
		Arena.of(self).add_child(fx)
		fx.reset_physics_interpolation()
		if kind == Kind.KAMIKAZE:
			# Dies as a bomb whether it reached you or got shot down;
			# whoever set it off gets credit for the blast's kills.
			Explosions.blast(self, global_position, KAMIKAZE_BLAST_RADIUS,
					KAMIKAZE_BLAST_DAMAGE, attacker_id, true, self)
		died.emit(kind, global_position, attacker_id)
		queue_free()
