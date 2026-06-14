# scenes/enemies/enemy_projectile.gd
# 远程敌人发射的子弹：直线飞行，命中玩家造成伤害后自毁。
extends Area2D

const SPEED: float = 220.0
const LIFETIME: float = 3.0

var direction: Vector2 = Vector2.RIGHT  # 由 bt_ranged_kite 注入
var damage: float = 6.0                 # ⚙️可调
var _age: float = 0.0

func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(damage)
			queue_free()
			return
