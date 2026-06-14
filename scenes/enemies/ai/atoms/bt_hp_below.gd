# scenes/enemies/ai/atoms/bt_hp_below.gd
# Selector 阶段切换守卫：agent.hp / agent.MAX_HP < threshold 时 SUCCESS。
extends BTCondition

@export var threshold: float = 0.5

func _tick(_delta: float) -> Status:
	if agent == null or not "hp" in agent or not "MAX_HP" in agent:
		return FAILURE
	if agent.MAX_HP <= 0.0:
		return FAILURE
	return SUCCESS if (agent.hp / agent.MAX_HP) < threshold else FAILURE
