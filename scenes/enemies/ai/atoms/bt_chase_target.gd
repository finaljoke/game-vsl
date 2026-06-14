# scenes/enemies/ai/atoms/bt_chase_target.gd
# 行为：径直冲向玩家（chase/swarm/brute 共用，等价于旧 bt_chase.gd）。
extends "res://scenes/enemies/ai/atoms/bt_action_base.gd"

func _tick(_delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	agent.velocity = _dir_to_player(target) * agent.SPEED
	agent.move_and_slide()
	return RUNNING
