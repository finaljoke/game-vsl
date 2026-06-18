# scenes/weapons/maul/maul_weapon.gd
# 碎 Maul（双手近战）：慢速大范围砸击，命中半径内全体 → 伤害 + 径向击退 + 硬直。低频高冲击控场。
class_name MaulWeapon
extends WeaponBase

# 由 WeaponData.levels 反射注入
var damage: float = 60.0
var radius: float = 130.0
var knockback: float = 220.0     # apply_impulse 强度(径向远离玩家)
var stun_dur: float = 0.4

func attack() -> void:
	var origin: Vector2 = _player.global_position
	var dmg: float = damage_for(damage)
	for e in enemies():
		if not is_instance_valid(e):
			continue
		var epos: Vector2 = (e as Node2D).global_position
		if origin.distance_to(epos) > radius:
			continue
		e.take_damage(dmg)
		if not is_instance_valid(e):
			continue   # 可能被打死
		if e.has_method("apply_impulse"):
			var dir := (epos - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			e.apply_impulse(dir, knockback)
		if e.has_method("apply_status"):
			e.apply_status(&"stun", 0.0, stun_dur)
