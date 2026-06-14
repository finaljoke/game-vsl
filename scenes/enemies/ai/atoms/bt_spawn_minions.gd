# scenes/enemies/ai/atoms/bt_spawn_minions.gd
# Boss 召唤小怪占位：在 agent 附近实例化 count 只 ENEMY_SCENE。
# 当前直接复用 enemy.tscn + 默认 chase 行为；Phase 2 可换专属 minion 原型 .tres。
extends BTAction

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

@export var count: int = 3
@export var radius: float = 80.0
@export var behavior: String = "chase"

func _tick(_delta: float) -> Status:
	var parent := agent.get_parent()
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var offset := Vector2(cos(angle), sin(angle)) * radius
		var minion := ENEMY_SCENE.instantiate()
		minion.behavior = behavior
		parent.add_child(minion)
		minion.global_position = agent.global_position + offset
	return SUCCESS
