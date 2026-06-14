# scenes/weapons/explosion/explosion.gd
extends Node2D

const BASE_DAMAGE: float = 40.0
const RADIUS: float = 80.0
const LIFETIME: float = 0.35

var damage: float = BASE_DAMAGE  # 由 ExplosionWeapon 注入 damage_mult 后设置
var _age: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	scale = Vector2.ONE * (1.0 + _age / LIFETIME * 0.5)
	modulate.a = 1.0 - (_age / LIFETIME)
	if _age >= LIFETIME:
		queue_free()

# 必须在 global_position 赋值之后显式调用，避免在 add_child 时以 (0,0) 判定
func detonate() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= RADIUS:
			enemy.take_damage(damage)
