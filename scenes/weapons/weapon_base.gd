# scenes/weapons/weapon_base.gd
class_name WeaponBase
extends Node

var data: WeaponData = null
var level: int = 1

var cooldown: float = 1.0
var _timer: float = 0.0

var _player: Node2D = null

func _ready() -> void:
	_player = get_parent() as Node2D

func _process(delta: float) -> void:
	_timer += delta
	var effective_cd := cooldown / (_player as Player).attack_speed_mult
	if _timer >= effective_cd:
		_timer = 0.0
		attack()

func attack() -> void:
	pass

# 把 data.levels[lvl-1] 字典里的每个键反射写到 self。
# 子类可重写以处理副作用（例如 OrbWeapon 同步护盾球数量）。
func apply_level(lvl: int) -> void:
	if data == null:
		push_warning("WeaponBase.apply_level: data not set on %s" % name)
		return
	if lvl < 1 or lvl > data.levels.size():
		push_warning("WeaponBase.apply_level: invalid level %d for %s" % [lvl, data.id])
		return
	level = lvl
	var stats: Dictionary = data.levels[lvl - 1]
	# 校验：.tres 里若有脚本未声明的字段(拼写错误)，set() 会静默失效 → 提前告警。
	var unknown := filter_unknown(_property_names(), stats)
	if not unknown.is_empty():
		push_warning("WeaponBase.apply_level: %s 的 levels[%d] 含未知字段 %s（拼写错误？会被忽略）"
				% [data.id, lvl, str(unknown)])
	for key in stats:
		set(key, stats[key])

func _property_names() -> Array:
	var names: Array = []
	for p in get_property_list():
		names.append(p.name)
	return names

# 纯函数(便于单测)：返回 stats 里不在 known 名单中的键。
static func filter_unknown(known: Array, stats: Dictionary) -> Array:
	var result: Array = []
	for key in stats:
		if not known.has(key):
			result.append(key)
	return result

# 统一的全局质变 modifier 读取(取代各武器自写的 _mod_int / _global_pierce)：
# 玩家若无该字段则视为 0。
func mod_int(field: String) -> int:
	if _player != null and field in _player:
		return int(_player.get(field))
	return 0

# 伤害 = 基础伤害 × 玩家全局伤害加成。各武器统一走这里，改平衡只动一处口径。
func damage_for(base: float) -> float:
	return base * (_player as Player).damage_mult

# 当前场上所有敌人节点(薄封装，统一组查询写法)。
# 返回 Array[Node]（与 get_nodes_in_group 一致），保留下游索引取值的类型可推断。
func enemies() -> Array[Node]:
	return get_tree().get_nodes_in_group("enemies")

func get_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies():
		var d := _player.global_position.distance_to((e as Node2D).global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e as Node2D
	return nearest

func get_ysort() -> Node:
	# 所有生成视觉/投射体的武器都经此挂载；ysort 缺失时回退到当前场景根，
	# 避免 get_first_node_in_group 返回 null 后 .add_child 崩溃。
	var ys := get_tree().get_first_node_in_group("ysort")
	return ys if ys != null else get_tree().current_scene
