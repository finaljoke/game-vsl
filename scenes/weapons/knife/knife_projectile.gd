# scenes/weapons/knife/knife_projectile.gd
extends Area2D

const SPEED: float = 400.0
const DAMAGE: float = 15.0
const LIFETIME: float = 3.0

var direction: Vector2 = Vector2.RIGHT
var _age: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		(body as Enemy).take_damage(DAMAGE)
		queue_free()
