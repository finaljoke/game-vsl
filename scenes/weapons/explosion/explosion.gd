# scenes/weapons/explosion/explosion.gd
extends Node2D

const DAMAGE: float = 40.0
const RADIUS: float = 80.0
const LIFETIME: float = 0.35

var _age: float = 0.0

func _ready() -> void:
	_apply_damage()

func _process(delta: float) -> void:
	_age += delta
	scale = Vector2.ONE * (1.0 + _age / LIFETIME * 0.5)
	modulate.a = 1.0 - (_age / LIFETIME)
	if _age >= LIFETIME:
		queue_free()

func _apply_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= RADIUS:
			enemy.take_damage(DAMAGE)
