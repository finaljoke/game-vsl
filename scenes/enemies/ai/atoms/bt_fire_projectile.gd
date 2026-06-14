# scenes/enemies/ai/atoms/bt_fire_projectile.gd
# 朝玩家发射 enemy_projectile，可配置 damage 与扇形 spread（弧度，count 颗散开）。
# 一次触发即 SUCCESS（适合放在 Sequence 中）。
extends "res://scenes/enemies/ai/atoms/bt_action_base.gd"

const PROJECTILE = preload("res://scenes/enemies/enemy_projectile.tscn")

@export var damage: float = 6.0
@export var count: int = 1
@export var spread: float = 0.0  # 弧度，count > 1 时均分

func _tick(_delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var base_dir := _dir_to_player(target)
	if count <= 1:
		_spawn(base_dir)
	else:
		var step := spread / float(count - 1) if count > 1 else 0.0
		var start := -spread * 0.5
		for i in range(count):
			_spawn(base_dir.rotated(start + step * float(i)))
	return SUCCESS

func _spawn(dir: Vector2) -> void:
	var p := PROJECTILE.instantiate()
	p.direction = dir
	p.damage = damage
	agent.get_parent().add_child(p)
	p.global_position = agent.global_position
