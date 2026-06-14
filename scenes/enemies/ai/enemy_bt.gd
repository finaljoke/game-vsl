# scenes/enemies/ai/enemy_bt.gd
# 行为树工厂：按 behavior 字符串组装 BehaviorTree。
# 用 preload + add_child 而非 class_name —— 规避 headless 全局类缓存陷阱。
extends RefCounted

const _ChaseTarget    = preload("res://scenes/enemies/ai/atoms/bt_chase_target.gd")
const _KiteTarget     = preload("res://scenes/enemies/ai/atoms/bt_kite_target.gd")
const _BomberAttack   = preload("res://scenes/enemies/ai/atoms/bt_bomber_attack.gd")
const _HpBelow        = preload("res://scenes/enemies/ai/atoms/bt_hp_below.gd")
const _MoveToTarget   = preload("res://scenes/enemies/ai/atoms/bt_move_to_target.gd")
const _SpawnMinions   = preload("res://scenes/enemies/ai/atoms/bt_spawn_minions.gd")
const _CooldownReady  = preload("res://scenes/enemies/ai/atoms/bt_cooldown_ready.gd")
const _FireProjectile = preload("res://scenes/enemies/ai/atoms/bt_fire_projectile.gd")
const _Wait           = preload("res://scenes/enemies/ai/atoms/bt_wait.gd")

# 把一组任务塞进 composite。便于把 Selector/Sequence 写成数据。
static func _compose(composite: BTComposite, tasks: Array) -> BTComposite:
	for t in tasks:
		composite.add_child(t)
	return composite

static func _hp_below(threshold: float) -> BTTask:
	var c := _HpBelow.new()
	c.threshold = threshold
	return c

static func _move_to_target(desired_dist: float) -> BTTask:
	var m := _MoveToTarget.new()
	m.desired_dist = desired_dist
	return m

static func _cooldown(seconds: float) -> BTTask:
	var c := _CooldownReady.new()
	c.cooldown = seconds
	return c

# Phase 1（HP > 70%）：纯追击。
static func _phase1_tree() -> BTTask:
	return _move_to_target(0.0)

# Phase 2（HP <70%）：周期性环形召唤 + 持续追击。
# Selector 模型：CD 到则召唤（Sequence SUCCESS），未到则跌穿到追击。
static func _phase2_tree() -> BTTask:
	var summon := _SpawnMinions.new()
	summon.count = 3
	summon.radius = 120.0
	summon.behavior = "chase"
	var summon_seq := _compose(BTSequence.new(), [_cooldown(8.0), summon])
	return _compose(BTSelector.new(), [summon_seq, _move_to_target(0.0)])

# Phase 3（HP <30%）：扇形 5 连发抛射物 + 短硬直，期间继续追击。
static func _phase3_tree() -> BTTask:
	var fire := _FireProjectile.new()
	fire.damage = 8.0
	fire.count = 5
	fire.spread = 1.0  # 弧度，约 57°
	var wait := _Wait.new()
	wait.duration = 0.4
	var fire_seq := _compose(BTSequence.new(), [_cooldown(2.0), fire, wait])
	return _compose(BTSelector.new(), [fire_seq, _move_to_target(0.0)])

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
