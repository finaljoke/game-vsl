# scenes/weapons/gravity_well/gravity_well.gd
# 引力井场实体：存活 field_dur 秒，每物理帧把半径内敌人朝井心 apply_impulse + 周期轻伤。
# 位移/伤害都走 W0/既有通道，本实体只负责"持续施力 + 计时"。
class_name GravityWell
extends Node2D

const TICK: float = 0.25

var radius: float = 140.0
var pull_strength: float = 120.0   # 朝井心的拉力(经 apply_impulse*delta；最终强度 W4 调)
var field_dur: float = 2.0
var tick_damage: float = 3.0       # 每秒轻伤(每拍结算 *TICK)
var collapse_damage: float = 0.0   # 到期坍缩引爆伤害(0=无效果，奇点进化专用)
var _age: float = 0.0
var _tick_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to_center: Vector2 = global_position - (e as Node2D).global_position
		if to_center.length() <= radius and e.has_method("apply_impulse"):
			e.apply_impulse(to_center.normalized(), pull_strength * delta)
	_tick_accum += delta
	while _tick_accum >= TICK:
		_tick_accum -= TICK
		_apply_tick_damage()
	if _age >= field_dur:
		_collapse()
		queue_free()

# 坍缩引爆：场到期时对半径内敌人一次高伤(奇点)。
func _collapse() -> void:
	if collapse_damage <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(collapse_damage)
	GameFeel.shake(&"medium")

func _apply_tick_damage() -> void:
	if tick_damage <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(tick_damage * TICK)
