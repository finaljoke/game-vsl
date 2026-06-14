# scenes/player/player.gd
class_name Player
extends CharacterBody2D

signal leveled_up(new_level: int)
signal died

const SPEED: float = 200.0
const CONTACT_MAX_SOURCES: int = 6  # 每帧最多被多少只敌人造成接触伤害

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

@onready var hurt_box: Area2D = $HurtBox

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED * speed_mult
	move_and_slide()
	_check_contact_damage(delta)

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
