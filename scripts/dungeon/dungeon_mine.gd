# Proximity mine drifting in a chamber. Arms when a player closes in,
# blinks through a short fuse, then detonates. Shooting it sets it off
# too, so a careful pilot clears a lane from range. Mines damage
# everything in the blast, ships and rocks and other mines alike, so
# tight fields chain. Minelayer enemies seed extra ones mid-fight.
class_name DungeonMine
extends StaticBody2D

const TRIGGER_RANGE := 140.0
const FUSE := 0.55
const BLAST_RADIUS := 150.0
const BLAST_DAMAGE := 30.0

var health := 10.0
var velocity := Vector2.ZERO

var _armed := false
var _fuse := 0.0
var _dead := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	velocity = Vector2.from_angle(randf() * TAU) * randf_range(5.0, 25.0)
	rotation = randf() * TAU


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	if _armed:
		_fuse -= delta
		queue_redraw()
		if _fuse <= 0.0:
			_explode()
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p.visible and global_position.distance_to(p.global_position) < TRIGGER_RANGE:
			_armed = true
			_fuse = FUSE
			queue_redraw()
			return


func take_damage(amount: float, _dir: Vector2, _at: Vector2, attacker_id := 0) -> void:
	health -= amount
	if health <= 0.0:
		_explode(attacker_id)


func _explode(attacker_id := 0) -> void:
	if _dead:
		return
	_dead = true
	Explosions.blast(self, global_position, BLAST_RADIUS, BLAST_DAMAGE, attacker_id, true, self)
	var main := get_tree().current_scene
	if main != null and main.has_method("add_shake"):
		main.add_shake(6.0)
	queue_free()


func _draw() -> void:
	var body := Color(0.3, 0.31, 0.36)
	var edge := Color(0.5, 0.52, 0.6)
	for i in 6:
		var dir := Vector2.from_angle(i * TAU / 6.0)
		draw_line(dir * 10.0, dir * 18.0, edge, 3.0)
	draw_circle(Vector2.ZERO, 12.0, body)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, edge, 1.5)
	# Center light: dim until armed, then a hard blink as the fuse runs.
	var lit := _armed and int(_fuse * 12.0) % 2 == 0
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.25, 0.2) if lit else Color(0.5, 0.2, 0.18))
