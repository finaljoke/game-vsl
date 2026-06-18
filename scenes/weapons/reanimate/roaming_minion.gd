# scenes/weapons/reanimate/roaming_minion.gd
# 漫游随从：自主朝最近敌移动、接触近战；lifetime 到点退场。不挂 LimboAI(轻量自驱)。
# 经 ReanimateWeapon 程序化生成(无 .tscn)；_ready 自建碰撞形状 + 占位贴图。
class_name RoamingMinion
extends CharacterBody2D

const CONTACT_RADIUS: float = 18.0
const HIT_COOLDOWN: float = 0.5
const SPLIT_LIFETIME: float = 4.0   # 裂出小尸的寿命

var damage: float = 14.0
var speed: float = 120.0
var lifetime: float = 12.0
var max_hp: float = 30.0       # 预留(当前敌人 AI 不索敌 summons → 随从靠 lifetime 退场)
var split_chance: float = 0.0  # 群尸：死亡分裂概率(基础=0=不裂)
var _age: float = 0.0
var _hit_cd: float = 0.0

func _ready() -> void:
	add_to_group("summons")
	collision_layer = 0   # 纯运动学位移，不与玩家/敌人物理碰撞
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = CONTACT_RADIUS
	cs.shape = circ
	add_child(cs)
	var spr := Sprite2D.new()    # 占位视觉(VFX 通道换骷髅拼装)
	spr.texture = preload("res://assets/sprites/kenney/items/dagger.png")
	spr.scale = Vector2(0.4, 0.4)
	spr.modulate = Color(0.6, 0.9, 0.7)   # 幽绿，区分友军
	add_child(spr)
	spr.material = Vfx.make_shader_material(&"summon")
	add_child(Vfx.make_trail(Color(0.5, 0.6, 1.0, 0.8), true))

func _physics_process(delta: float) -> void:
	_age += delta
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	var target := _nearest_enemy()
	if target != null:
		var to := target.global_position - global_position
		velocity = to.normalized() * speed
		move_and_slide()
		if _hit_cd <= 0.0 and global_position.distance_to(target.global_position) <= CONTACT_RADIUS + 8.0:
			target.take_damage(damage)
			_hit_cd = HIT_COOLDOWN
	if _age >= lifetime:
		_die()

func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = e as Node2D
	return nearest

# 退场：群尸概率原地裂出一个不再分裂的短命小尸。
func _die() -> void:
	if split_chance > 0.0 and randf() < split_chance:
		var child = get_script().new()
		child.damage = damage
		child.speed = speed
		child.lifetime = SPLIT_LIFETIME
		child.max_hp = max_hp
		child.split_chance = 0.0
		var parent := get_parent()
		if parent != null:
			parent.add_child(child)
			child.global_position = global_position
	queue_free()
