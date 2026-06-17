# scenes/enemies/enemy.gd
class_name Enemy
extends CharacterBody2D

signal died(position: Vector2)

const EnemyBT = preload("res://scenes/enemies/ai/enemy_bt.gd")
const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const ICON_TO_TILE := 6.75  # 旧 icon.svg(108px)→ Kenney tile(16px)换算，保持原有显示尺寸
const EXTERNAL_VELOCITY_DECAY: float = 0.85   # 每物理帧外力衰减(真击退,4.2)
const EXTERNAL_VELOCITY_CUTOFF: float = 1.0   # 低于此速度归零，防长尾抖动

var SPEED: float = 80.0
var MAX_HP: float = 20.0
var CONTACT_DAMAGE: float = 8.0
var tint: Color = Color(1.0, 0.2, 0.2)   # 由 EnemySpawner 按原型注入；现仅用于 GameFeel 受击闪白
var body_scale: float = 0.30
var sprite_texture: Texture2D = null     # 由 EnemySpawner 按原型注入；决定外观
var behavior: String = "chase"           # 由 EnemySpawner 按原型注入；决定行为树
var split_count: int = 0                 # >0 时死亡分裂出 N 只小怪(由 splitter 原型注入)

var hp: float = MAX_HP
var _player: Node2D = null
var _pulse_tween: Tween = null  # boss 专属红脉冲；受击期间被 kill 让位给白闪
var status: StatusComponent = StatusComponent.new()   # 燃烧/减速/冻结/硬直底座(4.1)
var external_velocity: Vector2 = Vector2.ZERO   # 随物理帧衰减的外力速度(击退/拉拽)

@onready var _sprite: Sprite2D = $Sprite2D

func _enter_tree() -> void:
	# 必须在 BTPlayer._ready 之前装配（父 _enter_tree 早于子 _ready），
	# 这样 BTPlayer 初始化时就能拿到 behavior_tree 并实例化。
	$BTPlayer.behavior_tree = EnemyBT.build(behavior)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if sprite_texture:
		_sprite.texture = sprite_texture
	# 按原型 tint 给贴图上色，让共用贴图的原型(charger/bomber、splitter/swarm…)也一眼可辨。
	# 受击闪白由 GameFeel 改根节点 modulate(过曝)叠加在此之上，互不冲突。
	_sprite.modulate = tint
	_sprite.scale = Vector2(body_scale, body_scale) * ICON_TO_TILE
	if behavior == "boss":
		_start_boss_pulse()

# 按移动方向翻转贴图。velocity 由各 BT atom 的 _tick 写入（chase/kite/bomber/move_to_target）。
func _process(_delta: float) -> void:
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0.0

# 移动逻辑已迁至行为树（agent 即本节点，由 BT 任务调用 move_and_slide）。

# 物理帧驱动状态底座：结算燃烧 DoT；衰减外力速度。
func _physics_process(delta: float) -> void:
	var burn := status.tick(delta)
	if burn > 0.0:
		take_damage(burn)
	external_velocity *= EXTERNAL_VELOCITY_DECAY
	if external_velocity.length() < EXTERNAL_VELOCITY_CUTOFF:
		external_velocity = Vector2.ZERO

# ── 状态底座对外接口 ───────────────────────────────────────────────────────
# 武器命中调 apply_status；BT move atom / 玩家接触结算读 move_speed_mult / is_stunned。
func apply_status(kind: StringName, magnitude: float, duration: float) -> void:
	status.apply(kind, magnitude, duration)

func move_speed_mult() -> float:
	return status.move_speed_mult()

func is_stunned() -> bool:
	return status.is_stunned()

func has_status(kind: StringName) -> bool:
	return status.has(kind)

# 真击退/拉拽：把方向冲量累加到随帧衰减的外力速度(被 BT move atom 并入移动)。
func apply_impulse(dir: Vector2, strength: float) -> void:
	external_velocity += dir * strength

# 纯函数(便于单测)：把 atom 的期望速度按状态+外力合成最终速度。
# 硬直时自身不动但仍受外力推动。
static func compose_velocity(desired: Vector2, speed_mult: float, stunned: bool, external: Vector2) -> Vector2:
	if stunned:
		return external
	return desired * speed_mult + external

# BT move atom 调用：传入期望速度，返回应写入 velocity 的合成速度(仍只调一次 move_and_slide)。
func resolve_velocity(desired: Vector2) -> Vector2:
	return compose_velocity(desired, move_speed_mult(), is_stunned(), external_velocity)

func take_damage(amount: float) -> void:
	hp -= amount
	# Boss 受击：先 kill 脉冲并复位 _sprite.modulate，否则白闪 (enemy.modulate) 被脉冲色乘穿。
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
		_sprite.modulate = Color.WHITE
	GameFeel.enemy_hit.emit(amount, global_position, self)
	if hp <= 0.0:
		if split_count > 0:
			_spawn_split()
		GameFeel.enemy_died.emit(global_position, self)
		died.emit(global_position)
		queue_free()
		return
	# 0.15s 白闪结束后稍微 buffer 一下再重启脉冲；ignore_time_scale 防 hitstop 拖死。
	if behavior == "boss":
		var t := get_tree().create_timer(0.2, false, true, true)
		t.timeout.connect(_restart_pulse_if_alive)

# Splitter 死亡分裂：在自身位置附近生成 split_count 只小型 chase 怪。
# offspring 从自身(已时缩)属性派生 → 自动随游戏时间成长；split_count=0 防无限递归。
func _spawn_split() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in range(split_count):
		var angle := TAU * float(i) / float(split_count)
		var child := ENEMY_SCENE.instantiate()
		child.behavior = "chase"
		child.MAX_HP = maxf(MAX_HP * 0.35, 5.0)
		child.hp = child.MAX_HP
		child.SPEED = SPEED * 1.25
		child.CONTACT_DAMAGE = CONTACT_DAMAGE
		child.body_scale = body_scale * 0.65
		child.sprite_texture = sprite_texture
		child.tint = tint
		child.split_count = 0
		parent.add_child(child)
		child.global_position = global_position + Vector2(cos(angle), sin(angle)) * 24.0
		child.add_to_group("enemies")

func _restart_pulse_if_alive() -> void:
	if is_instance_valid(self) and behavior == "boss":
		_start_boss_pulse()

func _start_boss_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops().bind_node(_sprite)
	_pulse_tween.tween_property(_sprite, "modulate", Color(1.4, 0.5, 0.5), 0.3)
	_pulse_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.3)

# GameFeel._on_enemy_hit 调用：sprite-only 击退，不动节点 position 以免与 BT move_and_slide 冲突。
# from_pos 通常就是 enemy 自身位置（take_damage 默认这么传），dir 会退化为零；此时回退到 "远离玩家" 方向。
func _apply_knockback(from_pos: Vector2) -> void:
	var dir := (global_position - from_pos).normalized()
	if dir == Vector2.ZERO and _player != null and is_instance_valid(_player):
		dir = (global_position - _player.global_position).normalized()
	if dir == Vector2.ZERO:
		return
	var tween := create_tween().bind_node(_sprite)
	tween.tween_property(_sprite, "position", dir * 12.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
