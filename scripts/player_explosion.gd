# A ship coming apart: a white flash and a spray of debris shards in
# the dead player's color, spinning off and fading over a second.
class_name PlayerExplosion
extends Node2D

const SND_EXPLOSION := preload("res://audio/gunsounds/20 Gauge/MP3/20 Gauge Single Isolated.mp3")
const LIFETIME := 1.0

var color := Color.WHITE

var _t := 0.0
var _chunks: Array = []
var _flash: Polygon2D


func _ready() -> void:
	z_index = 5
	for i in 10:
		var chunk := Polygon2D.new()
		var r := randf_range(4.0, 11.0)
		var pts := PackedVector2Array()
		for a in 4:
			pts.append(Vector2.from_angle(a * TAU / 4.0 + randf_range(-0.4, 0.4))
					* r * randf_range(0.6, 1.3))
		chunk.polygon = pts
		chunk.color = color.lightened(randf_range(-0.25, 0.25))
		chunk.position = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 12.0)
		add_child(chunk)
		_chunks.append({
			"node": chunk,
			"vel": Vector2.from_angle(randf() * TAU) * randf_range(120.0, 420.0),
			"spin": randf_range(-9.0, 9.0),
		})

	_flash = Polygon2D.new()
	var circle := PackedVector2Array()
	for a in 14:
		circle.append(Vector2.from_angle(a * TAU / 14.0) * 30.0)
	_flash.polygon = circle
	_flash.color = Color(1.0, 1.0, 1.0, 0.9)
	add_child(_flash)

	var snd := AudioStreamPlayer2D.new()
	snd.stream = SND_EXPLOSION
	snd.pitch_scale = 0.55 * randf_range(0.92, 1.08)
	snd.volume_db = 2.0
	snd.max_distance = 4000.0
	snd.bus = "SFX"
	add_child(snd)
	snd.play()


func _process(delta: float) -> void:
	_t += delta
	var k := _t / LIFETIME
	for c in _chunks:
		var node: Polygon2D = c["node"]
		node.position += c["vel"] * delta
		node.rotation += c["spin"] * delta
		node.color.a = 1.0 - k
	_flash.scale = Vector2.ONE * (1.0 + k * 3.0)
	_flash.color.a = maxf(0.9 - k * 4.0, 0.0)
	if _t >= LIFETIME:
		queue_free()
