extends RigidBody2D

# A weapon drifting in space. kind is a WeaponDB.Weapon id; ammo is
# whatever load it carries — a full magazine from world spawns, or the
# remainder when a player throws one away. Players grab it with E when
# inside their GRAB_RADIUS (see player.gd); the server arbitrates so a
# pickup can only be claimed once.
const SPEED_CAP := 180.0

# A hard-thrown gun is a weapon in itself: while it's still moving fast
# it bonks the first ship it meets, crediting the thrower. It disarms
# once drag slows it down (or after the hit), then it's just a pickup.
const ARM_SPEED := 300.0
const DISARM_SPEED := 200.0
const ARM_GRACE := 0.15  # don't clobber the thrower's own face
const BONK_RADIUS := 26.0

@export var kind := 0
@export var ammo := 0
var init_velocity := Vector2.ZERO
var init_spin := 0.0
var thrower := 0

var _collected := false
var _armed := false
var _arm_grace := 0.0
var _prompt: HBoxContainer
var _prompt_icon: TextureRect
var _prompt_key: Label

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("pickups")
	sprite.texture = WeaponDB.DATA[kind]["texture"]
	sprite.scale = Vector2.ONE * 0.9

	var glow := RarityGlow.new()
	glow.color = WeaponDB.rarity_color(kind)
	glow.z_index = -1
	add_child(glow)

	# Grab prompt floats above the gun; top_level so the rigid body's
	# spin doesn't whirl it around. Shows the X button to pad players
	# and the E keycap to keyboard players (swapped per frame for
	# whoever is standing closest).
	_prompt = HBoxContainer.new()
	_prompt.top_level = true
	_prompt.visible = false
	_prompt.add_theme_constant_override("separation", 7)
	_prompt_icon = ButtonIcons.icon("x", 30.0)
	_prompt.add_child(_prompt_icon)
	_prompt_key = ButtonIcons.keycap("E")
	_prompt.add_child(_prompt_key)
	var prompt_name := Label.new()
	prompt_name.text = WeaponDB.DATA[kind]["name"]
	prompt_name.add_theme_font_size_override("font_size", 15)
	prompt_name.add_theme_color_override("font_color", WeaponDB.rarity_color(kind))
	prompt_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt_name.add_theme_constant_override("outline_size", 4)
	prompt_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.add_child(prompt_name)
	add_child(_prompt)

	if multiplayer.is_server():
		linear_velocity = init_velocity
		angular_velocity = init_spin
		_armed = init_velocity.length() > ARM_SPEED
		_arm_grace = ARM_GRACE
	else:
		# Clients display the server's simulation via the synchronizer.
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true


func _process(_delta: float) -> void:
	var lp := _local_player()
	_prompt.visible = lp != null \
			and lp.global_position.distance_to(global_position) < lp.GRAB_RADIUS
	if _prompt.visible:
		var pad: bool = lp.device >= 0
		_prompt_icon.visible = pad
		_prompt_key.visible = not pad
		_prompt.global_position = global_position \
				+ Vector2(-_prompt.size.x / 2.0, -76.0)


# Nearest player steered from this machine — couch mode has several.
func _local_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not p.is_locally_controlled() or not p.visible:
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _physics_process(delta: float) -> void:
	if freeze or not multiplayer.is_server():
		return
	var speed := linear_velocity.length()
	if speed > SPEED_CAP:
		linear_velocity *= maxf(SPEED_CAP / speed, 1.0 - 3.0 * delta)
	if _armed:
		_arm_grace = maxf(_arm_grace - delta, 0.0)
		if speed < DISARM_SPEED:
			_armed = false
		elif _arm_grace == 0.0:
			_check_bonk()


# Overlap query instead of physical contact: guns don't collide with
# ships (grabbing would kick them away), so an armed throw checks for
# bodies in its path itself.
func _check_bonk() -> void:
	if not _armed or _collected:
		return
	var shape := CircleShape2D.new()
	shape.radius = BONK_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = 2  # ships
	for h in get_world_2d().direct_space_state.intersect_shape(q, 4):
		var c: Object = h["collider"]
		if c is Node2D and c.has_method("take_damage"):
			var dir := linear_velocity.normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			c.take_damage(20.0 + linear_velocity.length() * 0.03,
					dir, global_position, thrower)
			_armed = false
			linear_velocity *= 0.3
			return


# Soft pulsing disc + ring in the weapon's rarity color, drawn behind
# the gun sprite so you can read tier at a glance from across the map.
class RarityGlow extends Node2D:
	var color := Color.WHITE
	var _t := randf() * TAU

	func _process(delta: float) -> void:
		_t += delta * 3.0
		modulate.a = 0.8 + 0.2 * sin(_t)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 34.0, Color(color, 0.16))
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 48, Color(color, 0.55), 2.5)
