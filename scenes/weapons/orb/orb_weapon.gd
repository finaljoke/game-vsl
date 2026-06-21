# scenes/weapons/orb/orb_weapon.gd
class_name OrbWeapon
extends WeaponBase

const ORB_SCENE = preload("res://scenes/weapons/orb/orb_shield.tscn")

var total_orbs: int = 0  # 由 WeaponData.levels 通过 apply_level() 注入
var damage: float = 8.0
var orbit_radius: float = 60.0      # 缚灵数据驱动(注入给每个 OrbShield)
var hit_cooldown: float = 0.5
var dash_enabled: bool = false
var dash_interval: float = 3.0
var dash_aoe_radius: float = 0.0   # 进化(缚刃)注入:扑击到点群伤,逐球传递
var dash_aoe_damage: float = 0.0

func _ready() -> void:
	super._ready()
	cooldown = 9999.0  # 护盾球被动伤害，不走 attack() 路径

# OrbWeapon 在升级时不仅要改 total_orbs，还要按新值动态增/减 OrbShield 节点。
func apply_level(lvl: int) -> void:
	super.apply_level(lvl)
	_sync_shields()

func _sync_shields() -> void:
	var existing: Array = []
	for child in get_parent().get_children():
		if child is OrbShield:
			existing.append(child)
	while existing.size() < total_orbs:
		var orb := ORB_SCENE.instantiate() as OrbShield
		get_parent().add_child(orb)
		existing.append(orb)
	# 重新分布 orbit_index，确保即使中途加球间隔依然均匀
	for i in range(existing.size()):
		existing[i].total_orbs = total_orbs
		existing[i].orbit_index = i
		existing[i].damage = damage
		existing[i].orbit_radius = orbit_radius
		existing[i].hit_cooldown = hit_cooldown
		existing[i].dash_enabled = dash_enabled
		existing[i].dash_interval = dash_interval
		existing[i].dash_aoe_radius = dash_aoe_radius
		existing[i].dash_aoe_damage = dash_aoe_damage

func attack() -> void:
	pass
