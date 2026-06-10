extends RigidBody2D

# A weapon drifting in space. kind is a WeaponDB.Weapon id; ammo is
# whatever load it carries — a full magazine from world spawns, or the
# remainder when a player throws one away. Players grab it with E when
# inside their GRAB_RADIUS (see player.gd); the server arbitrates so a
# pickup can only be claimed once.
const SPEED_CAP := 180.0

@export var kind := 0
@export var ammo := 0
var init_velocity := Vector2.ZERO
var init_spin := 0.0

var _collected := false
var _prompt: Label

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
	# spin doesn't whirl the text around.
	_prompt = Label.new()
	_prompt.text = "E  —  %s" % WeaponDB.DATA[kind]["name"]
	_prompt.top_level = true
	_prompt.visible = false
	_prompt.custom_minimum_size = Vector2(220, 0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", WeaponDB.rarity_color(kind))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override("outline_size", 4)
	add_child(_prompt)

	if multiplayer.is_server():
		linear_velocity = init_velocity
		angular_velocity = init_spin
	else:
		# Clients display the server's simulation via the synchronizer.
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true


func _process(_delta: float) -> void:
	var lp := _local_player()
	_prompt.visible = lp != null \
			and lp.global_position.distance_to(global_position) < lp.GRAB_RADIUS
	if _prompt.visible:
		_prompt.global_position = global_position + Vector2(-110.0, -72.0)


func _local_player() -> Node2D:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null


func _physics_process(delta: float) -> void:
	if freeze or not multiplayer.is_server():
		return
	var speed := linear_velocity.length()
	if speed > SPEED_CAP:
		linear_velocity *= maxf(SPEED_CAP / speed, 1.0 - 3.0 * delta)


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
