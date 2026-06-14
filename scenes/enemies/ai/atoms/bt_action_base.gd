# scenes/enemies/ai/atoms/bt_action_base.gd
# 共享 BTAction 基类：把"找 player + 算方向/距离"挪到一处，避免每个 atom 重写。
# 不用 class_name —— 子类靠 preload 引用，headless 全局类缓存更稳。
extends BTAction

func _player() -> Node2D:
	return agent.get_tree().get_first_node_in_group("player")

func _dir_to_player(p: Node2D) -> Vector2:
	return (p.global_position - agent.global_position).normalized()

func _dist_to_player(p: Node2D) -> float:
	return agent.global_position.distance_to(p.global_position)
