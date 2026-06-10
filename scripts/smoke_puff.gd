extends Node2D

@export var amount := 10

@onready var particles: GPUParticles2D = $GPUParticles2D


func _ready() -> void:
	particles.amount = amount
	particles.restart()
	await get_tree().create_timer(2.0).timeout
	queue_free()
