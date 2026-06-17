# scenes/weapons/whip/whip_weapon.gd
class_name WhipWeapon
extends WeaponBase

const SLASH_TEX := preload("res://assets/sprites/kenney/fx/whip_slash.png")  # 新月挥砍弧
const SWIPE_FADE: float = 0.18    # 挥砍淡出时长

# 由 WeaponData.levels 反射注入
var damage: float = 30.0          # 由 WeaponData.levels 反射注入(默认=旧 BASE_DAMAGE；进化不注入则不变)
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
	var targets := enemies()
	if targets.is_empty():
		return
	var dmg: float = damage_for(damage)
	var origin: Vector2 = _player.global_position
	for e in targets:
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

# 朝 _facing 甩出一片新月挥砍弧贴图(绕玩家扫动 + 快速淡出)，给横扫的可读视觉。
func _spawn_swipe(origin: Vector2) -> void:
	var ys := get_ysort()
	if ys == null:
		return
	_spawn_slash(ys, origin, _facing)
	if double_sided:
		_spawn_slash(ys, origin, -_facing)

func _spawn_slash(ys: Node, origin: Vector2, dir: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = SLASH_TEX
	# 进化(血鞭 double_sided)染红，基础金色
	var col := Color(1.0, 0.32, 0.24) if double_sided else Color(1.0, 0.88, 0.42)
	s.modulate = Color(col.r, col.g, col.b, 0.9)
	# 贴图凸面朝 +X；以玩家为枢轴旋转，新月弧即在 swing_range 半径处划过
	s.global_position = origin
	var ang := dir.angle()
	s.rotation = ang - deg_to_rad(arc_deg * 0.35)
	var sc := (2.0 * swing_range) / float(SLASH_TEX.get_width())
	s.scale = Vector2(sc, sc)
	ys.add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "rotation", ang + deg_to_rad(arc_deg * 0.35), SWIPE_FADE)
	tw.tween_property(s, "modulate:a", 0.0, SWIPE_FADE)
	tw.finished.connect(func() -> void: if is_instance_valid(s): s.queue_free())
