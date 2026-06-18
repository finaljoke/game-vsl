# scenes/weapons/knife/knife_weapon.gd
class_name KnifeWeapon
extends WeaponBase

const PROJECTILE_SCENE = preload("res://scenes/weapons/knife/knife_projectile.tscn")

# 基础伤害：由 WeaponData.levels[].damage 反射注入
# 默认 15.0 = 旧 knife_projectile.BASE_DAMAGE，保证 thousand_edge(不注入 damage)不回归
var damage: float = 15.0
var pierce: int = 2
var crit_range: float = 99999.0   # 目标距离 > 此值触发暴击加成(默认极大=不触发)
var crit_bonus: float = 0.0       # >0 时附距离/满血暴击率加成(基础注入；进化不注入→0→不暴)
var proj_speed: float = 400.0     # 弹速(长弓更快；默认=原 SPEED)
# 进化视觉(反射注入)：基础不指定 → 默认无变化
var proj_scale: float = 1.0
var proj_tint: Color = Color.WHITE
var volley: int = 0   # >0：每次齐射 volley 发(箭雨)，替代默认单发

func _ready() -> void:
	super._ready()
	# cooldown 与各字段由 WeaponData.levels 通过 apply_level() 反射注入

func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var base_dir := _player.global_position.direction_to(target.global_position)
	# 距离/满血暴击：按主目标判定，应用到本次齐射所有弹
	var dist := _player.global_position.distance_to(target.global_position)
	var full_hp: bool = ("hp" in target) and ("MAX_HP" in target) and target.hp >= target.MAX_HP
	var applied_bonus := longbow_crit_bonus(dist, crit_range, full_hp, crit_bonus)
	# E3 质变：global_pierce 加穿透；extra_projectiles 多发小角度扇形
	var eff_pierce: int = pierce + mod_int("global_pierce")
	var base_count: int = volley if volley > 0 else 1
	var n: int = base_count + mod_int("extra_projectiles")
	var spread := deg_to_rad(12.0)
	for i in range(n):
		var dir := base_dir
		if n > 1:
			dir = base_dir.rotated((float(i) - float(n - 1) * 0.5) * spread)
		var projectile := PROJECTILE_SCENE.instantiate()
		projectile.damage = damage_for(damage, true, applied_bonus)
		projectile.pierce = eff_pierce
		projectile.speed = proj_speed
		get_ysort().add_child(projectile)
		projectile.global_position = _player.global_position
		projectile.rotation = dir.angle() + PI / 2
		projectile.scale *= proj_scale
		projectile.modulate = proj_tint
		projectile.direction = dir

# 纯函数(便于单测)：目标距离 > crit_range 或满血 → 返回 crit_bonus，否则 0。
# crit_bonus 为 0(进化默认)时恒返回 0 → 配合 player.crit_chance=0 永不暴击。
static func longbow_crit_bonus(dist: float, crit_range: float, full_hp: bool, crit_bonus: float) -> float:
	if dist > crit_range or full_hp:
		return crit_bonus
	return 0.0
