# scenes/enemies/ai/bt_ranged_kite.gd
# 行为：远程风筝——保持 preferred 距离的环带，区间内停下按冷却向玩家发射子弹。
extends BTAction

const PROJECTILE = preload("res://scenes/enemies/enemy_projectile.tscn")

@export var preferred: float = 260.0      # ⚙️可调：理想交战距离
@export var band: float = 40.0            # ⚙️可调：环带半宽（区间内即停火）
@export var shoot_cooldown: float = 1.4   # ⚙️可调
@export var projectile_damage: float = 6.0  # ⚙️可调

var _cd: float = 0.0

# 纯函数：按距离决定移动方向。1=靠近 / -1=后退 / 0=驻守（开火）。便于单测。
static func kite_move(dist: float, preferred_dist: float, band_half: float) -> int:
	if dist > preferred_dist + band_half:
		return 1
	if dist < preferred_dist - band_half:
		return -1
	return 0

func _tick(delta: float) -> Status:
	var target := agent.get_tree().get_first_node_in_group("player")
	if target == null:
		return FAILURE
	var to_target: Vector2 = target.global_position - agent.global_position
	var dist := to_target.length()
	var dir := to_target.normalized()
	var move := kite_move(dist, preferred, band)
	agent.velocity = dir * agent.SPEED * float(move)
	agent.move_and_slide()
	_cd -= delta
	if move == 0 and _cd <= 0.0:
		_cd = shoot_cooldown
		_shoot(dir)
	return RUNNING

func _shoot(dir: Vector2) -> void:
	var p := PROJECTILE.instantiate()
	p.direction = dir
	p.damage = projectile_damage
	agent.get_parent().add_child(p)
	p.global_position = agent.global_position
