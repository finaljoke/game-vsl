# scenes/enemies/ai/atoms/bt_move_to_target.gd
# 通用追击：往玩家方向移动到 desired_dist；desired_dist=0 等于撞，>0 则在范围外移动、范围内停下。
# Phase 2 多阶段 Boss 用：例：phase 1 = MoveToTarget(0)（撞）、phase 2 = MoveToTarget(200)（保距）。
extends "res://scenes/enemies/ai/atoms/bt_action_base.gd"

@export var desired_dist: float = 0.0

func _tick(_delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var dist := _dist_to_player(target)
	if dist <= desired_dist:
		agent.velocity = agent.resolve_velocity(Vector2.ZERO)
		agent.move_and_slide()
		return SUCCESS
	agent.velocity = agent.resolve_velocity(_dir_to_player(target) * agent.SPEED)
	agent.move_and_slide()
	return RUNNING
