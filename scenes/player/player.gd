# scenes/player/player.gd
class_name Player
extends CharacterBody2D

signal leveled_up(new_level: int)
signal died

const SPEED: float = 200.0
const CONTACT_MAX_SOURCES: int = 6  # 每帧最多被多少只敌人造成接触伤害
const MAX_WEAPON_SLOTS: int = 6     # 武器槽上限：base 武器多于槽位 → 产生"装不下"的取舍

# 行走动感：sin 驱动的轻微上下 bob + 横向 squash（纯视觉，不影响碰撞/移动）
const BASE_SCALE: float = 2.5
const BOB_FREQ: float = 12.0
const BOB_AMP: float = 2.5
const SETTLE_SPEED: float = 12.0  # 停下时回正速度

var hp: float = 100.0
var max_hp: float = 100.0
var xp: float = 0.0
var xp_threshold: float = 100.0
var level: int = 1
var _dead: bool = false
# owned_weapons: { String id -> { "node": WeaponBase, "level": int } }
var owned_weapons: Dictionary = {}
var speed_mult: float = 1.0
var attack_speed_mult: float = 1.0
var xp_mult: float = 1.0
var damage_mult: float = 1.0
var perk_stacks: Dictionary = {}
var reroll_tokens: int = 0   # 重抽券：小Boss/终局Boss 掉落，选卡界面消耗(重抽/ban)
# 质变 modifier(E3)：武器/拾取在运行时读取
var global_pierce: int = 0        # 所有投射武器额外穿透
var extra_projectiles: int = 0    # 飞刀类额外弹数
var pickup_range_mult: float = 1.0  # XP 拾取磁化半径倍率
var lifesteal: float = 0.0        # 每次击杀回血量

@onready var hurt_box: Area2D = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D

var _sprite_base_y: float = 0.0
var _walk_t: float = 0.0

func _ready() -> void:
	_sprite_base_y = _sprite.position.y
	GameFeel.enemy_died.connect(_lifesteal_on_death)

# 嗜血(E3)：每次敌人死亡回少量血(值小，防高频击杀回满)。
func _lifesteal_on_death(_position: Vector2, _enemy: Node2D) -> void:
	if _dead or lifesteal <= 0.0:
		return
	hp = minf(hp + lifesteal, max_hp)

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED * speed_mult
	move_and_slide()
	_update_visuals(delta)
	_check_contact_damage(delta)

# 朝向翻转 + 行走 bob/squash；受击闪白由 GameFeel 改 root.modulate，互不干扰。
func _update_visuals(delta: float) -> void:
	if velocity.length() > 5.0:
		if absf(velocity.x) > 1.0:
			_sprite.flip_h = velocity.x < 0.0
		_walk_t += delta * BOB_FREQ
		var s := sin(_walk_t)
		_sprite.position.y = _sprite_base_y - absf(s) * BOB_AMP
		_sprite.scale = Vector2(BASE_SCALE + s * 0.06, BASE_SCALE - absf(s) * 0.05)
	else:
		_walk_t = 0.0
		_sprite.position.y = lerpf(_sprite.position.y, _sprite_base_y, delta * SETTLE_SPEED)
		_sprite.scale = _sprite.scale.lerp(Vector2(BASE_SCALE, BASE_SCALE), delta * SETTLE_SPEED)

func _check_contact_damage(delta: float) -> void:
	var n := 0
	var total := 0.0
	for body in hurt_box.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			total += body.CONTACT_DAMAGE * delta
			n += 1
			if n >= CONTACT_MAX_SOURCES:
				break
	if total > 0.0:
		take_damage(total)

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = max(0.0, hp - amount)
	GameFeel.player_hit.emit(amount)
	if hp <= 0.0:
		_dead = true
		GameFeel.player_died.emit()
		died.emit()

func add_xp(amount: float) -> void:
	xp += amount * xp_mult
	while xp >= xp_threshold:
		xp -= xp_threshold
		xp_threshold *= 1.15
		level += 1
		GameFeel.player_leveled_up.emit(level)
		leveled_up.emit(level)

func get_xp_percent() -> float:
	return xp / xp_threshold

# 武器持有/升级 ────────────────────────────────────────────────────────

func has_weapon(id: String) -> bool:
	return owned_weapons.has(id)

func get_weapon_level(id: String) -> int:
	if not owned_weapons.has(id):
		return 0
	return int(owned_weapons[id]["level"])

func get_weapon_node(id: String) -> WeaponBase:
	if not owned_weapons.has(id):
		return null
	return owned_weapons[id]["node"]

# 实例化武器场景、设定 data、加为 child、应用 Lv1 属性。新武器入口。
func grant_weapon(data: WeaponData) -> WeaponBase:
	if data == null:
		push_error("Player.grant_weapon: data is null")
		return null
	# 槽位已满则拒绝(进化走 replace_weapon：先 erase 再 grant，净不增，安全)
	if owned_weapons.size() >= MAX_WEAPON_SLOTS:
		push_warning("Player.grant_weapon: 武器槽已满(%d)，拒绝 %s" % [MAX_WEAPON_SLOTS, data.id])
		return null
	var weapon: WeaponBase = data.base_scene.instantiate()
	weapon.data = data
	add_child(weapon)
	weapon.apply_level(1)
	owned_weapons[data.id] = {"node": weapon, "level": 1}
	return weapon

# 升级已持有的武器到下一级（受 max_level 限制）。
func level_up_weapon(id: String) -> void:
	if not owned_weapons.has(id):
		push_warning("Player.level_up_weapon: %s not owned" % id)
		return
	var entry: Dictionary = owned_weapons[id]
	var weapon: WeaponBase = entry["node"]
	var new_level := int(entry["level"]) + 1
	if weapon.data == null or new_level > weapon.data.max_level:
		push_warning("Player.level_up_weapon: %s already at max" % id)
		return
	weapon.apply_level(new_level)
	entry["level"] = new_level

# 进化：销毁旧武器，授予新武器形态。供 CardPool 的 evolve_* 卡使用。
func replace_weapon(old_id: String, new_data: WeaponData) -> WeaponBase:
	if not owned_weapons.has(old_id):
		push_warning("Player.replace_weapon: %s not owned" % old_id)
		return null
	var old_entry: Dictionary = owned_weapons[old_id]
	var old_weapon: WeaponBase = old_entry["node"]
	owned_weapons.erase(old_id)
	old_weapon.queue_free()
	return grant_weapon(new_data)
