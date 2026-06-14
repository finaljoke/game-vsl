# scenes/weapons/knife/knife_projectile.gd
extends Area2D

const SPEED: float = 400.0
const DAMAGE: float = 15.0
const LIFETIME: float = 3.0

var direction: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _hit: bool = false

func _physics_process(delta: float) -> void:
	if _hit:
		return
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies"):
			_hit = true
			body.take_damage(DAMAGE)
			queue_free()
			return
