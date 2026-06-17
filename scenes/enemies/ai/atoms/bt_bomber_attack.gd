# scenes/enemies/ai/atoms/bt_bomber_attack.gd
# 行为：自爆——贴近玩家至 fuse_range 后停下点引信，引信到点炸出 AoE 伤害玩家并自毁。
extends "res://scenes/enemies/ai/atoms/bt_action_base.gd"

const EXPLOSION = preload("res://scenes/weapons/explosion/explosion.tscn")

@export var fuse_range: float = 70.0    # ⚙️可调：触发引信的距离
@export var fuse_time: float = 0.6      # ⚙️可调：引信时长（给玩家逃离窗口）
@export var blast_radius: float = 90.0  # ⚙️可调：爆炸命中半径
@export var blast_damage: float = 25.0  # ⚙️可调

var _fuse: float = -1.0  # <0 表示未点燃；>=0 表示引信倒计时中

func _tick(delta: float) -> Status:
	var target := _player()
	if target == null:
		return FAILURE
	var dist := _dist_to_player(target)
	if _fuse < 0.0:
		# 阶段一：追击直到进入引信范围
		agent.velocity = agent.resolve_velocity(_dir_to_player(target) * agent.SPEED)
		agent.move_and_slide()
		if dist <= fuse_range:
			_fuse = fuse_time
		return RUNNING
	# 阶段二：停下倒计时(硬直会暂停引信；仍受击退外力推动)
	agent.velocity = agent.resolve_velocity(Vector2.ZERO)
	agent.move_and_slide()
	if not agent.is_stunned():
		_fuse -= delta
	if _fuse <= 0.0:
		_detonate(target)
		return SUCCESS
	return RUNNING

func _detonate(target: Node2D) -> void:
	# 仅借用 explosion.tscn 作视觉；不调用其 detonate()（那只打 enemies 组）。
	var fx := EXPLOSION.instantiate()
	agent.get_parent().add_child(fx)
	fx.global_position = agent.global_position
	if agent.global_position.distance_to(target.global_position) <= blast_radius:
		target.take_damage(blast_damage)
	agent.queue_free()
