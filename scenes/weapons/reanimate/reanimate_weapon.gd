# scenes/weapons/reanimate/reanimate_weapon.gd
# 亡者召唤（召唤·进攻）：按 cooldown 节律维持最多 max_minions 个自主随从。
class_name ReanimateWeapon
extends WeaponBase

const MINION := preload("res://scenes/weapons/reanimate/roaming_minion.gd")
const _RUNE_TEX := preload("res://assets/sprites/kenney/runes/runeBlue_tile_001.png")

# 由 WeaponData.levels 反射注入(cooldown 即 summon_interval，走 WeaponBase 调度)
var max_minions: int = 1
var damage: float = 14.0
var minion_hp: float = 30.0
var minion_speed: float = 120.0
var lifetime: float = 12.0
var split_chance: float = 0.0   # 群尸进化注入；基础=0
var heal_on_hit: float = 0.0    # 群尸 §3c 防御杠杆:随从命中给本体回血;基础=0

func attack() -> void:
	if _count_minions() >= max_minions:
		return
	var m := MINION.new()
	m.damage = damage_for(damage)
	m.speed = minion_speed
	m.lifetime = lifetime
	m.max_hp = minion_hp
	m.split_chance = split_chance
	m.heal_on_hit = heal_on_hit
	get_ysort().add_child(m)
	m.global_position = _player.global_position
	Vfx.spawn_burst(m.global_position, &"magic_burst", get_ysort())
	_spawn_rune_flash(m.global_position)
	GameFeel.shake(&"light")

func _spawn_rune_flash(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = _RUNE_TEX
	s.modulate = Color(0.5, 0.7, 1.0, 0.9)
	s.scale = Vector2(0.5, 0.5)
	get_ysort().add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.4)
	tw.finished.connect(func() -> void: if is_instance_valid(s): s.queue_free())

func _count_minions() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if s is RoamingMinion and is_instance_valid(s):
			n += 1
	return n
