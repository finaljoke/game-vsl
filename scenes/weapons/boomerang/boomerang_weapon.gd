# scenes/weapons/boomerang/boomerang_weapon.gd
class_name BoomerangWeapon
extends WeaponBase

const PROJECTILE := preload("res://scenes/weapons/boomerang/boomerang_projectile.gd")

# 由 WeaponData.levels 反射注入
var damage: float = 20.0          # 由 WeaponData.levels 反射注入(默认=旧 BASE_DAMAGE；进化不注入则不变)
var pierce: int = 3
var throw_range: float = 240.0
var count: int = 1                # 进化形态(旋风)同时抛多发
var orbit_return: bool = false

var _facing: Vector2 = Vector2.RIGHT

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	super._process(delta)
	var v: Vector2 = (_player as Node2D).velocity if "velocity" in _player else Vector2.ZERO
	if v.length() > 5.0:
		_facing = v.normalized()

func attack() -> void:
	var target := get_nearest_enemy()
	var base_dir: Vector2 = _facing
	if target != null:
		base_dir = _player.global_position.direction_to(target.global_position)
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT
	var dmg: float = damage_for(damage)
	var eff_pierce: int = pierce + mod_int("global_pierce")
	# count>1 时围绕 base_dir 做小角度扇形铺开
	var spread := deg_to_rad(28.0)
	for i in range(count):
		var dir := base_dir
		if count > 1:
			var t := float(i) / float(count - 1) - 0.5  # [-0.5, 0.5]
			dir = base_dir.rotated(t * spread * float(count))
		var proj := PROJECTILE.new()
		proj.damage = dmg
		proj.direction = dir.normalized()
		proj.pierce = eff_pierce
		proj.max_range = throw_range
		proj.orbit_return = orbit_return
		get_ysort().add_child(proj)
		proj.global_position = _player.global_position
