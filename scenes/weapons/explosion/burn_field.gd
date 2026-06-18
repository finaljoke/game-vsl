# scenes/weapons/explosion/burn_field.gd
# 火球落点的持续燃烧地火：存活 field_dur 秒，每 TICK 对半径内敌人刷新 burn 状态。
# 实际 DoT 伤害由 Enemy 的 StatusComponent(W0)结算；本实体只负责"持续附着"。
class_name BurnField
extends Node2D

const TICK: float = 0.25

var radius: float = 80.0
var burn_dps: float = 6.0
var field_dur: float = 2.0
var _age: float = 0.0
var _tick_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	_tick_accum += delta
	while _tick_accum >= TICK:
		_tick_accum -= TICK
		_apply_burn()
	if _age >= field_dur:
		queue_free()

func _apply_burn() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= radius \
				and e.has_method("apply_status"):
			# 刷新时长 = TICK*2，覆盖到下一拍；敌人离场后 burn 自然过期
			e.apply_status(&"burn", burn_dps, TICK * 2.0)
