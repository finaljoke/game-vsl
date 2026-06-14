# scenes/enemies/ai/bt_chase.gd
# 行为：径直冲向玩家（normal/swarm/brute 共用，等价于旧 enemy._physics_process）。
extends BTAction

func _tick(_delta: float) -> Status:
	var target := agent.get_tree().get_first_node_in_group("player")
	if target == null:
		return FAILURE
	var dir: Vector2 = (target.global_position - agent.global_position).normalized()
	agent.velocity = dir * agent.SPEED
	agent.move_and_slide()
	return RUNNING
