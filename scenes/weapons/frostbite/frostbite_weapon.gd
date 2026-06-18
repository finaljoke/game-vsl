# scenes/weapons/frostbite/frostbite_weapon.gd
# 霜噬 Frostbite（冰系毁灭）：朝最密集处放冰爆 → area 内伤害 + 减速；命中已减速者则升级为冻结。
class_name FrostbiteWeapon
extends WeaponBase

const ExplosionWeaponScript := preload("res://scenes/weapons/explosion/explosion_weapon.gd")  # 复用 densest_center

# 由 WeaponData.levels 反射注入
var damage: float = 16.0
var area: float = 90.0
var slow_factor: float = 0.6     # 速度乘子(越小越慢)
var slow_dur: float = 1.5
var freeze_dur: float = 0.6

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center: Vector2 = ExplosionWeaponScript.densest_center(positions, area)
	var dmg: float = damage_for(damage)
	for e in targets:
		if not is_instance_valid(e):
			continue
		if center.distance_to((e as Node2D).global_position) > area:
			continue
		e.take_damage(dmg)
		if not is_instance_valid(e):
			continue
		if e.has_method("apply_status") and e.has_method("has_status"):
			if e.has_status(&"slow"):
				e.apply_status(&"freeze", 0.0, freeze_dur)   # 二次命中 → 冻结
			else:
				e.apply_status(&"slow", slow_factor, slow_dur)
