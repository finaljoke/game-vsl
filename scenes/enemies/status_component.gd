# scenes/enemies/status_component.gd
# 敌人状态底座：燃烧 DoT / 减速 / 冻结 / 硬直。纯逻辑(RefCounted)，不持节点引用，便于单测。
# Enemy 每物理帧调 tick(delta) 推进，并据返回值结算燃烧伤害。
class_name StatusComponent
extends RefCounted

# 燃烧 DoT 结算节拍(秒)：每满一拍结算一次 dps*INTERVAL 的伤害。
const BURN_INTERVAL: float = 0.25

# kind(StringName) -> 剩余秒数；过期即 erase。
var _durations: Dictionary = {}
# kind(StringName) -> magnitude(燃烧=dps / 减速=速度乘子 / 冻结|硬直=忽略)。
var _magnitudes: Dictionary = {}
# 燃烧累加器：跨帧累计 delta，满 BURN_INTERVAL 结算一拍。
var _burn_accum: float = 0.0

# 统一入口：施加/刷新一个状态。可刷新不可叠加——magnitude 取最强、duration 取更久者。
func apply(kind: StringName, magnitude: float, duration: float) -> void:
	if duration <= 0.0:
		return
	if not _magnitudes.has(kind) or _is_stronger(kind, magnitude, _magnitudes[kind]):
		_magnitudes[kind] = magnitude
	_durations[kind] = maxf(_durations.get(kind, 0.0), duration)

# 减速取"更慢"(乘子更小)为强；其余(燃烧 dps)取更大为强。
static func _is_stronger(kind: StringName, new_mag: float, old_mag: float) -> bool:
	if kind == &"slow":
		return new_mag < old_mag
	return new_mag > old_mag

# 每物理帧驱动：递减所有时长、清过期，返回本帧应结算的燃烧伤害(无燃烧时为 0)。
func tick(delta: float) -> float:
	for kind in _durations.keys():   # keys() 返回拷贝，循环内 erase 安全
		_durations[kind] -= delta
		if _durations[kind] <= 0.0:
			_durations.erase(kind)
			_magnitudes.erase(kind)
	var burn_damage := 0.0
	if _durations.has(&"burn"):
		_burn_accum += delta
		while _burn_accum >= BURN_INTERVAL:
			_burn_accum -= BURN_INTERVAL
			burn_damage += _magnitudes[&"burn"] * BURN_INTERVAL
	else:
		_burn_accum = 0.0
	return burn_damage

# 速度乘子：冻结=0；否则取最强减速；无减速=1.0。供 BT move atom 读取。
func move_speed_mult() -> float:
	if _durations.has(&"freeze"):
		return 0.0
	if _durations.has(&"slow"):
		return _magnitudes[&"slow"]
	return 1.0

# 硬直：冻结或硬直期间为 true → atom 输出零速、跳过攻击/接触结算。
func is_stunned() -> bool:
	return _durations.has(&"stun") or _durations.has(&"freeze")

# 查询某状态是否生效(霜噬"已减速则升级冻结"等机制循环需要)。
func has(kind: StringName) -> bool:
	return _durations.has(kind)
