# scenes/enemies/ai/enemy_bt.gd
# 行为树工厂：按 behavior 字符串组装 BehaviorTree。
# 用 preload + add_child 而非 class_name —— 规避 headless 全局类缓存陷阱。
extends RefCounted

const _ChaseTarget    = preload("res://scenes/enemies/ai/atoms/bt_chase_target.gd")
const _KiteTarget     = preload("res://scenes/enemies/ai/atoms/bt_kite_target.gd")
const _BomberAttack   = preload("res://scenes/enemies/ai/atoms/bt_bomber_attack.gd")
const _HpBelow        = preload("res://scenes/enemies/ai/atoms/bt_hp_below.gd")

# 把一组任务塞进 composite。便于把 Selector/Sequence 写成数据。
static func _compose(composite: BTComposite, tasks: Array) -> BTComposite:
	for t in tasks:
		composite.add_child(t)
	return composite

static func _hp_below(threshold: float) -> BTTask:
	var c := _HpBelow.new()
	c.threshold = threshold
	return c

static func _phase1_tree() -> BTTask:
	# 占位：Phase 2 内容期再填具体行为
	return _ChaseTarget.new()

static func _phase2_tree() -> BTTask:
	return _ChaseTarget.new()

static func _phase3_tree() -> BTTask:
	return _ChaseTarget.new()

# Boss 阶段切换：HP 越低优先走更激进的子树。
# 顺序 Selector：第一个 Sequence 命中 (HpBelow + 子树) 即返回，没命中则跌穿到 phase1。
static func _build_boss_phases() -> BTComposite:
	var root := BTSelector.new()
	_compose(root, [
		_compose(BTSequence.new(), [_hp_below(0.3), _phase3_tree()]),
		_compose(BTSequence.new(), [_hp_below(0.7), _phase2_tree()]),
		_phase1_tree(),
	])
	return root

static func build(behavior: String) -> BehaviorTree:
	var bt := BehaviorTree.new()
	match behavior:
		"ranged":
			bt.root_task = _KiteTarget.new()
		"bomber":
			bt.root_task = _BomberAttack.new()
		"boss":
			bt.root_task = _build_boss_phases()
		_:
			bt.root_task = _ChaseTarget.new()
	return bt
