# scenes/enemies/enemy.gd
class_name Enemy
extends CharacterBody2D

signal died(position: Vector2)

const EnemyBT = preload("res://scenes/enemies/ai/enemy_bt.gd")

var SPEED: float = 80.0
var MAX_HP: float = 20.0
var CONTACT_DAMAGE: float = 8.0
var tint: Color = Color(1.0, 0.2, 0.2)   # 由 EnemySpawner 按原型注入
var body_scale: float = 0.30
var behavior: String = "chase"           # 由 EnemySpawner 按原型注入；决定行为树

var hp: float = MAX_HP
var _player: Node2D = null

@onready var _sprite: Sprite2D = $Sprite2D

func _enter_tree() -> void:
	# 必须在 BTPlayer._ready 之前装配（父 _enter_tree 早于子 _ready），
	# 这样 BTPlayer 初始化时就能拿到 behavior_tree 并实例化。
	$BTPlayer.behavior_tree = EnemyBT.build(behavior)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sprite.modulate = tint
	_sprite.scale = Vector2(body_scale, body_scale)

# 移动逻辑已迁至行为树（agent 即本节点，由 BT 任务调用 move_and_slide）。

func take_damage(amount: float) -> void:
	hp -= amount
	GameFeel.enemy_hit.emit(amount, global_position, self)
	if hp <= 0.0:
		GameFeel.enemy_died.emit(global_position)
		died.emit(global_position)
		queue_free()
