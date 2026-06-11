# Routes one player's controls to a physical device, so several couch
# players can share a machine. device identifies the source:
#   -2  remote-replicated copy, no local input at all
#   -1  keyboard + mouse
#   0+  joypad with that device id (twin-stick: left stick aims,
#       right trigger fires, X grab, Y throw, B toggle, LB/RB spin,
#       A lobs a grenade)
class_name PlayerInput
extends RefCounted

const STICK_DEADZONE := 0.3
const TRIGGER_THRESHOLD := 0.4

var device := -2
var _last_aim := Vector2.RIGHT


func _init(dev := -2) -> void:
	device = dev


func aim(player: Node2D) -> Vector2:
	if device == -1:
		var dir := player.global_position.direction_to(player.get_global_mouse_position())
		return dir if dir != Vector2.ZERO else Vector2.RIGHT
	if device >= 0:
		# Stick aim holds the last direction when released, so recoil
		# keeps pushing the same way between flicks.
		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		if stick.length() > STICK_DEADZONE:
			_last_aim = stick.normalized()
		return _last_aim
	return Vector2.RIGHT


func fire_held() -> bool:
	if device == -1:
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if device >= 0:
		return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD
	return false


func spin_axis() -> float:
	var v := 0.0
	if device == -1:
		if Input.is_key_pressed(KEY_A):
			v -= 1.0
		if Input.is_key_pressed(KEY_D):
			v += 1.0
	elif device >= 0:
		if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
			v -= 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
			v += 1.0
	return v


func is_grab(event: InputEvent) -> bool:
	if device == -1:
		return _key(event, KEY_E)
	return _pad(event, JOY_BUTTON_X)


func is_throw(event: InputEvent) -> bool:
	if device == -1:
		return _key(event, KEY_Q)
	return _pad(event, JOY_BUTTON_Y)


func is_grenade(event: InputEvent) -> bool:
	if device == -1:
		return _key(event, KEY_G)
	return _pad(event, JOY_BUTTON_A)


func is_toggle(event: InputEvent) -> bool:
	if device == -1:
		return event is InputEventMouseButton and event.pressed \
				and (event.button_index == MOUSE_BUTTON_WHEEL_UP
					or event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	return _pad(event, JOY_BUTTON_B)


func _key(event: InputEvent, keycode: int) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == keycode


func _pad(event: InputEvent, button: int) -> bool:
	return device >= 0 and event is InputEventJoypadButton and event.pressed \
			and event.device == device and event.button_index == button
