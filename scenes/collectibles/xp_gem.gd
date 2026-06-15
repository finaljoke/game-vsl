# scenes/collectibles/xp_gem.gd
extends Node2D

const MAGNET_RADIUS: float = 80.0
const MAGNET_SPEED: float = 300.0
const COLLECT_DIST: float = 8.0

var value: float = 10.0  # 由 EnemySpawner 按时间缩放后注入
var _player: Node2D = null
var _magnetized: bool = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _player == null:
		return
	var dist := global_position.distance_to(_player.global_position)
	# E3 磁化：拾取半径随玩家 pickup_range_mult 放大
	var mult: float = _player.pickup_range_mult if "pickup_range_mult" in _player else 1.0
	if dist <= MAGNET_RADIUS * mult:
		_magnetized = true
	if _magnetized:
		var dir := (_player.global_position - global_position).normalized()
		global_position += dir * MAGNET_SPEED * delta
		if global_position.distance_to(_player.global_position) <= COLLECT_DIST:
			GameFeel.xp_collected.emit(global_position)
			_player.add_xp(value)
			queue_free()
