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

# 纯函数(便于单测)：把某状态的"期望速度"合成为最终速度，复用 Enemy.compose_velocity。
# 突进(DASH)是已承诺的扑击 → 免疫硬直归零(stunned 视为 false)，但仍受减速/冻结(speed_mult)缩放
# 与外力(external，重力井/击退)推动；其余状态完全受控(硬直归零、减速缩放、外力叠加)。
static func charge_velocity(state: int, desired: Vector2, speed_mult: float, stunned: bool, external: Vector2) -> Vector2:
	var eff_stunned := stunned and state != DASH
	return Enemy.compose_velocity(desired, speed_mult, eff_stunned, external)

# 纯函数(便于单测)：前摇/恢复倒计时——硬直时冻结(与自爆者引信一致)，让控制能打断蓄力/延长破绽。
static func tick_timer(t: float, delta: float, stunned: bool) -> float:
	return t if stunned else t - delta

# 用 charge_velocity 合成当前状态最终速度(读 agent 实时状态)；替代过去直接写 agent.velocity 的漏接。
func _resolve(desired: Vector2) -> Vector2:
	return charge_velocity(_state, desired, agent.move_speed_mult(), agent.is_stunned(), agent.external_velocity)

func _enter() -> void:
	_state = APPROACH
	_t = 0.0

func _tick(delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	match _state:
		APPROACH:
			agent.velocity = _resolve(_dir_to_player(target) * agent.SPEED)
			agent.move_and_slide()
			if _dist_to_player(target) <= charge_range:
				_state = TELEGRAPH
				_t = telegraph_time
		TELEGRAPH:
			# 停下蓄力——静止本身就是给玩家的"它要冲了"信号；硬直/冻结会冻结前摇倒计时(打断蓄力)
			agent.velocity = _resolve(Vector2.ZERO)
			agent.move_and_slide()
			_t = tick_timer(_t, delta, agent.is_stunned())
			if _t <= 0.0:
				_dash_dir = _dir_to_player(target)  # 锁定方向，此后不再追踪
				_state = DASH
				_t = dash_time
		DASH:
			# 突进是已承诺的扑击：_resolve 内 DASH 免疫硬直归零，但仍受减速/外力；倒计时不被硬直暂停
			agent.velocity = _resolve(_dash_dir * agent.SPEED * dash_speed_mult)
			agent.move_and_slide()
			_t -= delta
			if _t <= 0.0:
				_state = RECOVER
				_t = recover_time
		RECOVER:
			agent.velocity = _resolve(Vector2.ZERO)
			agent.move_and_slide()
			_t = tick_timer(_t, delta, agent.is_stunned())
			if _t <= 0.0:
				_state = APPROACH
	return RUNNING
