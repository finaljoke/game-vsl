# scenes/collectibles/xp_gem.gd
extends Node2D

const XP_VALUE: float = 10.0
const MAGNET_RADIUS: float = 80.0
const MAGNET_SPEED: float = 300.0
const COLLECT_DIST: float = 8.0

var _player: Node2D = null
var _magnetized: bool = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _process(delta: float) -> void:
	if _player == null:
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist <= MAGNET_RADIUS:
		_magnetized = true
	if _magnetized:
		var dir := (_player.global_position - global_position).normalized()
		global_position += dir * MAGNET_SPEED * delta
		if global_position.distance_to(_player.global_position) <= COLLECT_DIST:
			GameFeel.xp_collected.emit(global_position)
			_player.add_xp(XP_VALUE)
			queue_free()
