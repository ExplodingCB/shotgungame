extends RigidBody2D

# kind: -1 = shotgun shells, otherwise a Weapon enum index (0/2/3).
const TEXTURES := {
	-1: preload("res://assets/guns-pixelart/Amo1.png"),
	0: preload("res://assets/guns-assetpack/Shotguns/MP-133.png"),
	2: preload("res://assets/guns-assetpack/SMG's/MP5.png"),
	3: preload("res://assets/guns-pixelart/Sniper-rifle-3.png"),
}
const SHELLS_GIVEN := 4
const SPEED_CAP := 180.0

@export var kind := -1
var init_velocity := Vector2.ZERO
var init_spin := 0.0

var _collected := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D


func _ready() -> void:
	sprite.texture = TEXTURES[kind]
	sprite.scale = Vector2.ONE * (2.0 if kind == -1 else 0.9)
	if multiplayer.is_server():
		linear_velocity = init_velocity
		angular_velocity = init_spin
		area.body_entered.connect(_on_body_entered)
	else:
		# Clients display the server's simulation via the synchronizer.
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if freeze or not multiplayer.is_server():
		return
	var speed := linear_velocity.length()
	if speed > SPEED_CAP:
		linear_velocity *= maxf(SPEED_CAP / speed, 1.0 - 3.0 * delta)


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	var peer_id := body.get_multiplayer_authority()
	if kind < 0:
		body._net_give_shells.rpc_id(peer_id, SHELLS_GIVEN)
	else:
		body._net_give_weapon.rpc_id(peer_id, kind)
	get_tree().current_scene.schedule_pickup_respawn(kind)
	queue_free()
