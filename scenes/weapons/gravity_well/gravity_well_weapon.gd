# scenes/weapons/gravity_well/gravity_well_weapon.gd
# 引力井 Gravity Well（变幻系）：在最密集处生成持续引力井，拉拽聚怪 + 轻伤。力量倍增器(与直伤正交)。
class_name GravityWellWeapon
extends WeaponBase

const GRAVITY_WELL := preload("res://scenes/weapons/gravity_well/gravity_well.gd")
const ExplosionWeaponScript := preload("res://scenes/weapons/explosion/explosion_weapon.gd")

# 由 WeaponData.levels 反射注入
var field_dur: float = 2.0
var radius: float = 140.0
var pull_strength: float = 120.0
var tick_damage: float = 3.0
var collapse_damage: float = 0.0

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center: Vector2 = ExplosionWeaponScript.densest_center(positions, radius)
	var well := GRAVITY_WELL.new()
	well.radius = radius
	well.pull_strength = pull_strength
	well.field_dur = field_dur
	well.tick_damage = damage_for(tick_damage)   # 轻伤吃玩家伤害加成
	well.collapse_damage = damage_for(collapse_damage)
	get_ysort().add_child(well)
	well.global_position = center
	Vfx.spawn_burst(center, &"magic_burst", get_ysort())
	well.add_child(Vfx.make_trail(Color(0.7, 0.5, 1.0, 0.6), true))
