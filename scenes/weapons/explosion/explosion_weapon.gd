# scenes/weapons/explosion/explosion_weapon.gd
class_name ExplosionWeapon
extends WeaponBase

const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")

func _ready() -> void:
	cooldown = 3.0

func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var explosion := EXPLOSION_SCENE.instantiate()
	get_ysort().add_child(explosion)
	explosion.global_position = target.global_position
