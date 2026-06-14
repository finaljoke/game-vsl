# scenes/weapons/knife/knife_weapon.gd
class_name KnifeWeapon
extends WeaponBase

const PROJECTILE_SCENE = preload("res://scenes/weapons/knife/knife_projectile.tscn")

func _ready() -> void:
	cooldown = 1.0

func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	get_ysort().add_child(projectile)
	projectile.global_position = _player.global_position
	projectile.direction = (_player.global_position.direction_to(target.global_position))
