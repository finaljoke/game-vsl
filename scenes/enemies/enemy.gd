# scenes/enemies/enemy.gd
class_name Enemy
extends CharacterBody2D

signal died(position: Vector2)

const SPEED: float = 80.0
const MAX_HP: float = 20.0
const CONTACT_DAMAGE: float = 8.0

var hp: float = MAX_HP
var _player: Node2D = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var dir := (_player.global_position - global_position).normalized()
	velocity = dir * SPEED
	move_and_slide()

func take_damage(amount: float) -> void:
	hp -= amount
	GameFeel.enemy_hit.emit(amount, global_position, self)
	if hp <= 0.0:
		GameFeel.enemy_died.emit(global_position)
		died.emit(global_position)
		queue_free()
