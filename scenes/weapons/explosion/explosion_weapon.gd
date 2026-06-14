# scenes/weapons/explosion/explosion_weapon.gd
class_name ExplosionWeapon
extends WeaponBase

const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")

func _ready() -> void:
	super._ready()
	cooldown = 3.0

func attack() -> void:
	var target := get_nearest_enemy()
	if target == null:
		return
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = explosion.BASE_DAMAGE * (_player as Player).damage_mult
	get_ysort().add_child(explosion)
	explosion.global_position = target.global_position
	explosion.detonate()
