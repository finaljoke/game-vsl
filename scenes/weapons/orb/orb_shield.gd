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

func _ready() -> void:
	_player = get_parent()

func _process(delta: float) -> void:
	if _player == null:
		return
	var angle := (TAU / total_orbs) * orbit_index + Time.get_ticks_msec() * 0.001 * ORBIT_SPEED
	global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
	_check_hits()
	_tick_cooldowns(delta)

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
