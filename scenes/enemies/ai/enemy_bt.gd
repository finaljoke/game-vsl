# scenes/enemies/ai/enemy_bt.gd
# 行为树工厂：按 behavior 字符串构建对应 BehaviorTree（代码构建，可进版本库、可单测）。
# 现阶段每种行为是单任务；将来要复合行为，在此把 root_task 换成 BTSequence/BTSelector 即可。
# 用 preload 引用任务脚本而非 class_name，规避 headless 全局类缓存陷阱。
extends RefCounted

const _Chase = preload("res://scenes/enemies/ai/bt_chase.gd")
const _Ranged = preload("res://scenes/enemies/ai/bt_ranged_kite.gd")
const _Bomber = preload("res://scenes/enemies/ai/bt_bomber.gd")

static func build(behavior: String) -> BehaviorTree:
	var bt := BehaviorTree.new()
	match behavior:
		"ranged":
			bt.root_task = _Ranged.new()
		"bomber":
			bt.root_task = _Bomber.new()
		_:
			bt.root_task = _Chase.new()
	return bt
