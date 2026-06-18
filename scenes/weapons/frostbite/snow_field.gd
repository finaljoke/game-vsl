# scenes/weapons/frostbite/snow_field.gd
# 暴雪雪域：存活 field_dur，每 TICK 刷新 slow、每秒一次 freeze。DoT/控制经 W0 StatusComponent 结算。
class_name SnowField
extends Node2D

const TICK: float = 0.25
const FREEZE_TICK: float = 1.0

var radius: float = 110.0
var slow_factor: float = 0.5
var freeze_dur: float = 0.6
var field_dur: float = 3.0
var _age: float = 0.0
var _slow_accum: float = 0.0
var _freeze_accum: float = 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	_slow_accum += delta
	_freeze_accum += delta
	if _slow_accum >= TICK:
		_slow_accum -= TICK
		_apply(false)
	if _freeze_accum >= FREEZE_TICK:
		_freeze_accum -= FREEZE_TICK
		_apply(true)
	if _age >= field_dur:
		queue_free()

func _apply(freeze: bool) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) > radius or not e.has_method("apply_status"):
			continue
		if freeze:
			e.apply_status(&"freeze", 0.0, freeze_dur)
		else:
			e.apply_status(&"slow", slow_factor, TICK * 2.0)
