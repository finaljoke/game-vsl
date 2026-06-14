# scenes/enemies/ai/atoms/bt_cooldown_ready.gd
# 内部冷却闸门：cooldown 走完后 SUCCESS（开门），随后重置；未到则 FAILURE。
# 用在 Sequence[CooldownReady, FireProjectile] 这种"每 X 秒发一次"的组合。
extends BTCondition

@export var cooldown: float = 1.0

var _next: float = 0.0

func _enter() -> void:
	# 第一次进入立即可用
	if _next == 0.0:
		_next = -1.0

func _tick(delta: float) -> Status:
	if _next > 0.0:
		_next -= delta
		return FAILURE
	_next = cooldown
	return SUCCESS
