# scenes/weapons/knife/knife_weapon.gd
class_name KnifeWeapon
extends WeaponBase

const PROJECTILE_SCENE = preload("res://scenes/weapons/knife/knife_projectile.tscn")

var pierce: int = 2  # 飞刀定位：穿透直线，可串多个敌人
# 进化视觉(由 WeaponData.levels 反射注入)：基础武器不指定 → 保持默认无变化。
var proj_scale: float = 1.0
var proj_tint: Color = Color.WHITE

func _ready() -> void:
	super._ready()
	# cooldown 与 pierce 由 WeaponData.levels 通过 apply_level() 注入

func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.damage = projectile.BASE_DAMAGE * (_player as Player).damage_mult
	projectile.pierce = pierce
	get_ysort().add_child(projectile)
	projectile.global_position = _player.global_position
	projectile.direction = (_player.global_position.direction_to(target.global_position))
	# dagger 贴图默认朝上((0,-1))，+PI/2 把刀尖对齐到飞行方向
	projectile.rotation = projectile.direction.angle() + PI / 2
	projectile.scale *= proj_scale   # 进化形态(千刃)更大
	projectile.modulate = proj_tint  # 进化形态变色
