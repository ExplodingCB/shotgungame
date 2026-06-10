extends Node2D


func _ready() -> void:
	await get_tree().create_timer(2.4).timeout
	queue_free()
