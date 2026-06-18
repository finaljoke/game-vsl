# scenes/weapons/knife/knife_projectile.gd
extends Area2D

const SPEED: float = 400.0   # 默认弹速
const BASE_DAMAGE: float = 15.0
const LIFETIME: float = 3.0

var damage: float = BASE_DAMAGE  # 由 KnifeWeapon 注入 damage_mult 后设置
var direction: Vector2 = Vector2.RIGHT
var pierce: int = 1  # 可穿透的敌人数；由 KnifeWeapon 注入
var speed: float = SPEED      # 由 KnifeWeapon 注入(长弓更快)
var is_crit: bool = false  # 由 KnifeWeapon 注入(长弓暴击);决定命中火花颜色/震屏
var _age: float = 0.0
var _hit_ids: Dictionary = {}  # 已命中敌人去重，避免同一目标重复扣血

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or not is_instance_valid(body):
			continue
		var id := body.get_instance_id()
		if id in _hit_ids:
			continue
		_hit_ids[id] = true
		body.take_damage(damage)
		var _burst_preset: StringName = &"crit_spark" if is_crit else &"hit_spark"
		Vfx.spawn_burst(global_position, _burst_preset, get_parent())
		pierce -= 1
		if pierce <= 0:
			queue_free()
			return
