# scenes/player/player.gd
class_name Player
extends CharacterBody2D

signal leveled_up(new_level: int)
signal died

const SPEED: float = 200.0

var hp: float = 100.0
var max_hp: float = 100.0
var xp: float = 0.0
var xp_threshold: float = 100.0
var level: int = 1
var _dead: bool = false

@onready var hurt_box: Area2D = $HurtBox

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	_check_contact_damage(delta)

func _check_contact_damage(delta: float) -> void:
	for body in hurt_box.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			take_damage((body as Enemy).CONTACT_DAMAGE * delta)
			break

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = max(0.0, hp - amount)
	if hp <= 0.0:
		_dead = true
		died.emit()

func add_xp(amount: float) -> void:
	xp += amount
	if xp >= xp_threshold:
		xp -= xp_threshold
		xp_threshold *= 1.2
		level += 1
		leveled_up.emit(level)

func get_xp_percent() -> float:
	return xp / xp_threshold

func add_weapon(weapon_scene: PackedScene) -> void:
	var weapon := weapon_scene.instantiate()
	add_child(weapon)
