# scenes/weapons/whip/whip_weapon.gd
class_name WhipWeapon
extends WeaponBase

const BASE_DAMAGE: float = 30.0

# 由 WeaponData.levels 反射注入
var arc_deg: float = 120.0        # 扇形张角
var swing_range: float = 130.0    # 扇形半径
var double_sided: bool = false    # 进化形态：前后双向横扫

var _facing: Vector2 = Vector2.RIGHT  # 跟随玩家移动方向；静止时保留上一次朝向

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	# 先跑 WeaponBase 的冷却/attack 调度，再更新朝向
	super._process(delta)
	var v: Vector2 = (_player as Node2D).velocity if "velocity" in _player else Vector2.ZERO
	if v.length() > 5.0:
		_facing = v.normalized()

func attack() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	var dmg: float = BASE_DAMAGE * (_player as Player).damage_mult
	var origin: Vector2 = _player.global_position
	for e in enemies:
		var pos: Vector2 = (e as Node2D).global_position
		var hit := in_cone(pos, origin, _facing, arc_deg, swing_range)
		if not hit and double_sided:
			hit = in_cone(pos, origin, -_facing, arc_deg, swing_range)
		if hit and is_instance_valid(e):
			e.take_damage(dmg)
	_spawn_swipe(origin)

# 扇形命中判定(纯函数，便于单测)：enemy 是否落在以 facing 为中心、
# 半角 arc_deg/2、半径 range 的扇形内。原点重合算命中。
static func in_cone(enemy_pos: Vector2, origin: Vector2, facing: Vector2, arc_deg: float, range: float) -> bool:
	var to: Vector2 = enemy_pos - origin
	var dist: float = to.length()
	if dist == 0.0:
		return true
	if dist > range:
		return false
	var ang: float = rad_to_deg(absf(facing.normalized().angle_to(to / dist)))
	return ang <= arc_deg * 0.5

# 朝 _facing 画一段快速淡出的弧线，给横扫的可读视觉。
func _spawn_swipe(origin: Vector2) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(1.0, 0.9, 0.4, 0.9)
	var base := _facing.angle()
	var half := deg_to_rad(arc_deg * 0.5)
	var steps := 10
	for i in range(steps + 1):
		var a := base - half + (2.0 * half) * float(i) / float(steps)
		line.add_point(origin + Vector2(cos(a), sin(a)) * swing_range)
	get_ysort().add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.16)
	tween.finished.connect(func() -> void: if is_instance_valid(line): line.queue_free())
