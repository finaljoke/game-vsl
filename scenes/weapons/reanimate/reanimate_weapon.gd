# scenes/weapons/reanimate/reanimate_weapon.gd
# 亡者召唤（召唤·进攻）：按 cooldown 节律维持最多 max_minions 个自主随从。
class_name ReanimateWeapon
extends WeaponBase

const MINION := preload("res://scenes/weapons/reanimate/roaming_minion.gd")

# 由 WeaponData.levels 反射注入(cooldown 即 summon_interval，走 WeaponBase 调度)
var max_minions: int = 1
var damage: float = 14.0
var minion_hp: float = 30.0
var minion_speed: float = 120.0
var lifetime: float = 12.0
var split_chance: float = 0.0   # 群尸进化注入；基础=0

func attack() -> void:
	if _count_minions() >= max_minions:
		return
	var m := MINION.new()
	m.damage = damage_for(damage)
	m.speed = minion_speed
	m.lifetime = lifetime
	m.max_hp = minion_hp
	m.split_chance = split_chance
	get_ysort().add_child(m)
	m.global_position = _player.global_position

func _count_minions() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if s is RoamingMinion and is_instance_valid(s):
			n += 1
	return n
