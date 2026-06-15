# scenes/weapons/aura/aura_weapon.gd
class_name AuraWeapon
extends WeaponBase

const BASE_DAMAGE: float = 12.0
const RING_TEX := preload("res://assets/sprites/kenney/particles/orb_ring.png")

# 由 WeaponData.levels 反射注入
var radius: float = 90.0
var lifesteal_on_hit: float = 0.0   # 进化形态(炼狱)：每命中一敌回血

var _ring: Sprite2D = null

func _ready() -> void:
	super._ready()
	_setup_ring()

# 进化/升级改 radius 后同步视觉
func apply_level(lvl: int) -> void:
	super.apply_level(lvl)
	if _ring != null:
		_update_ring()

# 武器被替换(进化)时随之移除光环视觉，避免残留在玩家身上
func _exit_tree() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
		_ring = null

func _setup_ring() -> void:
	_ring = Sprite2D.new()
	_ring.texture = RING_TEX
	# 光环挂在玩家(Node2D)下，自动跟随；半透明不挡视线
	(_player as Node2D).add_child(_ring)
	_update_ring()

func _update_ring() -> void:
	var tex_w := float(RING_TEX.get_width())
	if tex_w <= 0.0:
		tex_w = 64.0
	var s := (2.0 * radius) / tex_w
	_ring.scale = Vector2(s, s)
	_ring.modulate = Color(1.0, 0.45, 0.2, 0.34) if lifesteal_on_hit > 0.0 \
			else Color(0.6, 0.9, 1.0, 0.26)

func attack() -> void:
	var dmg: float = damage_for(BASE_DAMAGE)
	var origin: Vector2 = _player.global_position
	for e in enemies():
		if not is_instance_valid(e):
			continue
		if origin.distance_to((e as Node2D).global_position) <= radius:
			e.take_damage(dmg)
			if lifesteal_on_hit > 0.0 and "hp" in _player:
				_player.hp = minf(_player.hp + lifesteal_on_hit, _player.max_hp)
