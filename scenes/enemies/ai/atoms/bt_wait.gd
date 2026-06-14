# scenes/enemies/ai/atoms/bt_wait.gd
# 等待 duration 秒后 SUCCESS。Phase 2 多阶段 Boss 间歇用。
extends BTAction

@export var duration: float = 1.0

var _t: float = -1.0

func _enter() -> void:
	_t = duration

func _tick(delta: float) -> Status:
	_t -= delta
	if _t <= 0.0:
		return SUCCESS
	return RUNNING
