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
	for key in stats:
		set(key, stats[key])

func get_nearest_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF
	for e in enemies:
		var d := _player.global_position.distance_to((e as Node2D).global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e as Node2D
	return nearest

func get_ysort() -> Node:
	return get_tree().get_first_node_in_group("ysort")
