# scenes/weapons/explosion/explosion.gd
class_name Explosion
extends Node2D

const BASE_DAMAGE: float = 40.0
const DEFAULT_RADIUS: float = 80.0   # 默认命中半径(nuke 等不注入者沿用)
const LIFETIME: float = 0.35

var damage: float = BASE_DAMAGE  # 由 ExplosionWeapon 注入 damage_mult 后设置
var blast_radius: float = DEFAULT_RADIUS   # 由 ExplosionWeapon 注入(火球数据驱动)
var base_scale: float = 1.0      # 进化形态(核爆)放大视觉用；由 ExplosionWeapon 注入
var _age: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	scale = Vector2.ONE * base_scale * (1.0 + _age / LIFETIME * 0.5)
	modulate.a = 1.0 - (_age / LIFETIME)
	if _age >= LIFETIME:
		queue_free()

# 必须在 global_position 赋值之后显式调用，避免在 add_child 时以 (0,0) 判定
func detonate() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= blast_radius:
			enemy.take_damage(damage)
	var is_nuke := base_scale > 1.0
	var anim: StringName = &"explosion_ground" if is_nuke else &"explosion_regular"
	var fx := Vfx.spawn_anim(global_position, anim, get_parent())
	if fx != null:
		fx.scale = Vector2.ONE * base_scale
		fx.material = Vfx.make_shader_material(&"fire")
	if is_nuke:
		GameFeel.shake(&"heavy")
		GameFeel.hitstop(0.06)
	else:
		GameFeel.shake(&"medium")
