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
	var base_dir := _player.global_position.direction_to(target.global_position)
	# E3 质变：global_pierce 加穿透；extra_projectiles 多发小角度扇形散开
	var eff_pierce: int = pierce + mod_int("global_pierce")
	var n: int = 1 + mod_int("extra_projectiles")
	var spread := deg_to_rad(12.0)
	for i in range(n):
		var dir := base_dir
		if n > 1:
			dir = base_dir.rotated((float(i) - float(n - 1) * 0.5) * spread)
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.damage = damage_for(projectile.BASE_DAMAGE)
		projectile.pierce = eff_pierce
		get_ysort().add_child(projectile)
		projectile.global_position = _player.global_position
		projectile.direction = dir
		# dagger 贴图默认朝上((0,-1))，+PI/2 把刀尖对齐到飞行方向
		projectile.rotation = dir.angle() + PI / 2
		projectile.scale *= proj_scale   # 进化形态(千刃)更大
		projectile.modulate = proj_tint  # 进化形态变色
