# scenes/enemies/spawn_director.gd
# 节拍调度策略：决定"何时、哪种节拍事件"。纯逻辑、无场景依赖，完全可单测。
# enemy_spawner 每帧用 elapsed 询问 is_due()，到点则 advance() 取事件描述并执行实际刷怪。
# 把平直的 trickle 强度曲线改成锯齿：铺垫(trickle) → 爆发(rush/pincer/elite) → 喘息(breather)。
# 不用 class_name —— 调用方靠 preload 引用，headless 全局类缓存更稳(与 enemy_bt 同理)。
extends RefCounted

const FIRST_EVENT: float = 45.0     # 首拍时间
const EVENT_INTERVAL: float = 50.0  # 之后每拍间隔
# 固定循环序列，含周期性 breather 制造张弛；spawner 按 type 组织具体刷怪。
const EVENT_SEQUENCE := ["swarm_rush", "pincer", "breather", "elite_pack"]

var events_fired: int = 0

# 下一拍的触发时间。
func next_event_time() -> float:
	return FIRST_EVENT + float(events_fired) * EVENT_INTERVAL

# 是否到了下一拍。
func is_due(elapsed: float) -> bool:
	return elapsed >= next_event_time()

# 第 index 拍的事件类型(循环)。纯函数，便于单测序列。
func event_type_at(index: int) -> String:
	return EVENT_SEQUENCE[index % EVENT_SEQUENCE.size()]

# 推进一拍：返回 {type} 事件描述并自增计数。spawner 据此执行。
func advance(_elapsed: float) -> Dictionary:
	var type := event_type_at(events_fired)
	events_fired += 1
	return {"type": type}
