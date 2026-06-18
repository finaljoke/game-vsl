# scenes/weapons/orb/orb_shield.gd
class_name OrbShield
extends Node2D

const DEFAULT_ORBIT_RADIUS: float = 60.0
const ORBIT_SPEED: float = 2.0
const DEFAULT_HIT_COOLDOWN: float = 0.5
const ORB_RADIUS: float = 14.0

var orbit_index: int = 0
var total_orbs: int = 2
var orbit_radius: float = DEFAULT_ORBIT_RADIUS   # 由 OrbWeapon 注入(缚灵数据驱动)
var hit_cooldown: float = DEFAULT_HIT_COOLDOWN   # 由 OrbWeapon 注入
var damage: float = 8.0
var _player: Node2D = null
var _hit_cooldowns: Dictionary = {}

var dash_enabled: bool = false      # 进化(缚刃)：周期脱轨扑击
var dash_interval: float = 3.0
const DASH_SPEED: float = 600.0
var _dash_t: float = 0.0
var _dashing: bool = false
var _dash_target: Node2D = null

func _ready() -> void:
	_player = get_parent()

func _process(delta: float) -> void:
	if _player == null:
		return
	if dash_enabled and _update_dash(delta):
		_check_hits()
		_tick_cooldowns(delta)
		return
	var angle := (TAU / total_orbs) * orbit_index + Time.get_ticks_msec() * 0.001 * ORBIT_SPEED
	global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
	_check_hits()
	_tick_cooldowns(delta)

# 返回 true 表示本帧处于脱轨冲刺(已自行定位)，false 表示走默认轨道。
func _update_dash(delta: float) -> bool:
	if not _dashing:
		_dash_t += delta
		if _dash_t < dash_interval:
			return false
		_dash_target = _nearest_enemy()
		if _dash_target == null:
			_dash_t = 0.0
			return false
		_dashing = true
	if _dash_target == null or not is_instance_valid(_dash_target):
		_dashing = false
		_dash_t = 0.0
		return false
	global_position = global_position.move_toward(_dash_target.global_position, DASH_SPEED * delta)
	if global_position.distance_to(_dash_target.global_position) <= ORB_RADIUS:
		_dashing = false
		_dash_t = 0.0
	return true

func _nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < nd:
			nd = d
			nearest = e as Node2D
	return nearest

func _check_hits() -> void:
	var player := _player as Player
	var dmg := damage * player.damage_mult
	var cd := hit_cooldown / maxf(player.attack_speed_mult, 0.01)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy in _hit_cooldowns:
			continue
		if global_position.distance_to((enemy as Node2D).global_position) <= ORB_RADIUS:
			(enemy as Enemy).take_damage(dmg)
			_hit_cooldowns[enemy] = cd

func _tick_cooldowns(delta: float) -> void:
	for key in _hit_cooldowns.keys():
		_hit_cooldowns[key] -= delta
		if _hit_cooldowns[key] <= 0.0:
			_hit_cooldowns.erase(key)
