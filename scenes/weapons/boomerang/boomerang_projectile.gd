# scenes/weapons/boomerang/boomerang_projectile.gd
# 飞到 max_range 后折返回玩家；来回各能命中 pierce 个敌人(回程刷新)。
extends Node2D

const SPEED: float = 320.0
const HIT_RADIUS: float = 26.0
const RETURN_THRESHOLD: float = 16.0
const SPRITE_TEX := preload("res://assets/sprites/kenney/items/gem.png")

var damage: float = 20.0
var direction: Vector2 = Vector2.RIGHT
var pierce: int = 3              # 每个航程(去/回)最多命中的敌人数
var max_range: float = 240.0

var _player: Node2D = null
var _traveled: float = 0.0
var _returning: bool = false
var _phase_hits: int = 0
var _hit_ids: Dictionary = {}
var _sprite: Sprite2D = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sprite = Sprite2D.new()
	_sprite.texture = SPRITE_TEX
	_sprite.scale = Vector2(0.8, 0.8)
	add_child(_sprite)

func _physics_process(delta: float) -> void:
	if _sprite != null:
		_sprite.rotation += delta * 14.0
	if not _returning:
		global_position += direction * SPEED * delta
		_traveled += SPEED * delta
		if _traveled >= max_range:
			_returning = true
			_phase_hits = 0
			_hit_ids.clear()
	else:
		if _player == null or not is_instance_valid(_player):
			queue_free()
			return
		var to: Vector2 = _player.global_position - global_position
		if to.length() <= RETURN_THRESHOLD:
			queue_free()
			return
		global_position += to.normalized() * SPEED * delta
	_check_hits()

func _check_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if _phase_hits >= pierce:
			return
		if not is_instance_valid(e):
			continue
		var id := (e as Node2D).get_instance_id()
		if _hit_ids.has(id):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= HIT_RADIUS:
			_hit_ids[id] = true
			_phase_hits += 1
			e.take_damage(damage)
