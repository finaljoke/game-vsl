# scenes/enemies/ai/atoms/bt_charger.gd
# 行为：冲锋者——接近玩家至 charge_range → 预警停顿(可读前摇) → 锁定方向高速突进
#       → 突进后硬直 → 循环。突进方向在前摇结束时锁定，玩家可在突进瞬间侧移躲开。
# 给后期增加可躲避的爆发威胁，并为闪避(P1-D)提供有意义的应对目标。
extends "res://scenes/enemies/ai/atoms/bt_action_base.gd"

@export var charge_range: float = 220.0   # ⚙️进入该距离开始预警
@export var telegraph_time: float = 0.5   # ⚙️前摇时长(停下，给玩家反应窗口)
@export var dash_speed_mult: float = 3.2  # ⚙️突进速度 = agent.SPEED * 此倍率
@export var dash_time: float = 0.35       # ⚙️突进持续
@export var recover_time: float = 0.6     # ⚙️突进后硬直

enum { APPROACH, TELEGRAPH, DASH, RECOVER }

var _state: int = APPROACH
var _t: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO

func _enter() -> void:
	_state = APPROACH
	_t = 0.0

func _tick(delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	match _state:
		APPROACH:
			agent.velocity = _dir_to_player(target) * agent.SPEED
			agent.move_and_slide()
			if _dist_to_player(target) <= charge_range:
				_state = TELEGRAPH
				_t = telegraph_time
		TELEGRAPH:
			# 停下蓄力——静止本身就是给玩家的"它要冲了"信号
			agent.velocity = Vector2.ZERO
			agent.move_and_slide()
			_t -= delta
			if _t <= 0.0:
				_dash_dir = _dir_to_player(target)  # 锁定方向，此后不再追踪
				_state = DASH
				_t = dash_time
		DASH:
			agent.velocity = _dash_dir * agent.SPEED * dash_speed_mult
			agent.move_and_slide()
			_t -= delta
			if _t <= 0.0:
				_state = RECOVER
				_t = recover_time
		RECOVER:
			agent.velocity = Vector2.ZERO
			agent.move_and_slide()
			_t -= delta
			if _t <= 0.0:
				_state = APPROACH
	return RUNNING
