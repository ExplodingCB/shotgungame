# An exit gate on the room's far wall. Gates appear with the room so
# you can plan your route, but stay sealed until the chamber is
# cleared; then flying into one carries you through. The reward tells
# the NEXT room what to give you.
class_name DungeonDoor
extends Area2D

enum Reward { ARMORY, REPAIR, TECH, BOSS }

const INFO := {
	Reward.ARMORY: {"label": "ARMORY", "color": Color(1.0, 0.62, 0.1)},
	Reward.REPAIR: {"label": "REPAIR BAY", "color": Color(0.45, 0.95, 0.5)},
	Reward.TECH: {"label": "TECH CACHE", "color": Color(0.75, 0.45, 1.0)},
	Reward.BOSS: {"label": "WARDEN'S GATE", "color": Color(1.0, 0.3, 0.25)},
}

const SND_OPEN := preload("res://audio/gunsounds/Reloads, Cycling & More/MP3/AK Rack MP3.mp3")

const W := 36.0
const H := 170.0

var reward: int = Reward.ARMORY
var locked := true

var _label: Label


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(W + 30.0, H)
	shape.shape = rect_shape
	add_child(shape)
	collision_layer = 0
	collision_mask = 2  # ships; only players are accepted in the handler
	body_entered.connect(_on_body)

	# The label hangs on the room side of the gate (it sits on the wall,
	# so anything to its right would be outside the camera limits).
	var info: Dictionary = INFO[reward]
	_label = Label.new()
	_label.text = info["label"]
	_label.custom_minimum_size = Vector2(300, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = Vector2(-340.0, -14.0)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", info["color"])
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.modulate.a = 0.45
	add_child(_label)


func unlock() -> void:
	if not locked:
		return
	locked = false
	_label.modulate.a = 1.0
	queue_redraw()
	var snd := AudioStreamPlayer2D.new()
	snd.stream = SND_OPEN
	snd.bus = "SFX"
	snd.max_distance = 4000.0
	add_child(snd)
	snd.play()


func _on_body(body: Node2D) -> void:
	if locked or not body.is_in_group("player"):
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("enter_door"):
		main.enter_door(reward)


func _draw() -> void:
	# A flat slot in the wall: faint fill, thin frame. Sealed gates run
	# gray with cross-bars; open ones take the reward color.
	var color: Color = Color(0.45, 0.45, 0.5) if locked else INFO[reward]["color"]
	draw_rect(Rect2(-W / 2.0, -H / 2.0, W, H), Color(color, 0.15))
	draw_rect(Rect2(-W / 2.0, -H / 2.0, W, H), color, false, 2.0)
	if locked:
		for i in 3:
			var y := -H / 2.0 + H * (0.25 + 0.25 * i)
			draw_line(Vector2(-W / 2.0, y), Vector2(W / 2.0, y), color, 2.0)
