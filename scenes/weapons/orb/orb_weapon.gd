# scenes/weapons/orb/orb_weapon.gd
class_name OrbWeapon
extends WeaponBase

const ORB_SCENE = preload("res://scenes/weapons/orb/orb_shield.tscn")
const NUM_ORBS: int = 2

func _ready() -> void:
	super._ready()
	cooldown = 9999.0
	for i in range(NUM_ORBS):
		var orb := ORB_SCENE.instantiate()
		get_parent().add_child(orb)
		orb.orbit_index = i
		orb.total_orbs = NUM_ORBS

func attack() -> void:
	pass
