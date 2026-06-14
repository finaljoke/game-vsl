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
		xp_threshold *= 1.2
		level += 1
		GameFeel.player_leveled_up.emit(level)
		leveled_up.emit(level)

func get_xp_percent() -> float:
	return xp / xp_threshold

func add_weapon(weapon_scene: PackedScene) -> void:
	var weapon := weapon_scene.instantiate()
	add_child(weapon)
