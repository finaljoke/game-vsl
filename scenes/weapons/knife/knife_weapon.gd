# scenes/weapons/knife/knife_weapon.gd
class_name KnifeWeapon
extends WeaponBase

const PROJECTILE_SCENE = preload("res://scenes/weapons/knife/knife_projectile.tscn")

var pierce: int = 2  # 飞刀定位：穿透直线，可串多个敌人

func _ready() -> void:
	super._ready()
	cooldown = 1.0

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
