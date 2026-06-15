# data/weapons/weapon_data.gd
# 描述一种武器：基础场景、各级属性、可选的进化规则。
# 每级属性用 Dictionary 而非 typed Resource——不同武器字段不同（knife.pierce vs orb.total_orbs），
# 靠 WeaponBase.apply_level() 中 set(key, value) 反射写入。
class_name WeaponData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D  # 升级卡片用图；投射物贴图仍在各武器自己的 projectile 场景里
@export var base_scene: PackedScene
@export var max_level: int = 3
@export var levels: Array = []  # Array[Dictionary]，每元素如 {"cooldown": 0.5, "pierce": 2}
# 进化配置；空字典表示不可进化。
# 形如：{"requires_perk": "perk_attack", "evolved_id": "thousand_edge"}
@export var evolution: Dictionary = {}
