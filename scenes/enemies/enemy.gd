# scenes/enemies/enemy.gd
class_name Enemy
extends CharacterBody2D

signal died(position: Vector2)

const EnemyBT = preload("res://scenes/enemies/ai/enemy_bt.gd")
const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const ICON_TO_TILE := 6.75  # 旧 icon.svg(108px)→ Kenney tile(16px)换算，保持原有显示尺寸
const EXTERNAL_VELOCITY_DECAY: float = 0.85   # 每物理帧外力衰减(真击退,4.2)
const EXTERNAL_VELOCITY_CUTOFF: float = 1.0   # 低于此速度归零，防长尾抖动

# 伤害通道：DIRECT=武器直击(完整命中反馈)；DOT=持续伤害逐跳(抑制白闪/击退/音效,只留克制跳字)。
enum DamageChannel { DIRECT, DOT }

# ── 状态协同(C2)常量 ──────────────────────────────────────────────────────────
const SHATTER_MULT: float = 1.5      # 冻结目标受直击的脆性增伤(碎裂,不消耗冻结)
const EXECUTE_BASE: float = 0.2      # 硬直处决基础加成(满血)
const EXECUTE_SCALE: float = 0.8     # 硬直处决随缺失血量的额外加成
const GRAVITY_AMP: float = 0.25      # 引力井内受到的全通道增伤
const AMP_DUR: float = 0.25          # amp 状态时长(井每帧刷新,离场约 3 帧自然衰减)
const CONFLAG_RADIUS: float = 60.0   # 燃尽 AoE 半径
const CONFLAG_DAMAGE: float = 10.0   # 燃尽 AoE 一次性火伤(DOT 通道)
const SLOW_VULN_BASE: float = 0.30   # 减速目标的基线易伤(无卡即生效,补 C2 slow 孤儿缺口)
const SLOW_VULN_CAP: float = 0.50    # 易伤硬封(范本 StS Vulnerable/PoE Shock)

# 燃尽重入守卫(模块级):燃尽 AoE 击杀带 burn 邻怪时跳过其再触发,保证单波(见设计 §6)。
static var _conflagrating: bool = false

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
var _status_fx := {}  # StringName -> Node2D(当前挂着的状态指示器)

# 参与可视化的状态种类(顺序固定,便于差分稳定)。
const _STATUS_FX_KINDS: Array[StringName] = [&"burn", &"slow", &"freeze", &"stun"]

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
	_update_status_fx()

# 移动逻辑已迁至行为树（agent 即本节点，由 BT 任务调用 move_and_slide）。

# 纯函数:对比活跃状态与当前指示器,算出要增/要删的 kind。无副作用,可无场景单测。
static func diff_status_fx(active: Array, current: Array) -> Dictionary:
	var to_add: Array[StringName] = []
	var to_remove: Array[StringName] = []
	for k in active:
		if not current.has(k):
			to_add.append(k)
	for k in current:
		if not active.has(k):
			to_remove.append(k)
	return {"add": to_add, "remove": to_remove}

# 每帧按状态系统当前状态,增删头顶/overlay 指示器。状态视觉与 GameFeel 受击闪白互不冲突
# (指示器是独立子节点,不动 _sprite.modulate)。
func _update_status_fx() -> void:
	var active: Array[StringName] = []
	for k in _STATUS_FX_KINDS:
		if has_status(k):
			active.append(k)
	var diff := diff_status_fx(active, _status_fx.keys())
	for k in diff["remove"]:
		var node: Node = _status_fx[k]
		if is_instance_valid(node):
			node.queue_free()
		_status_fx.erase(k)
	for k in diff["add"]:
		var node := Vfx.make_status_indicator(k)
		if node != null:
			add_child(node)
			_status_fx[k] = node

# 物理帧驱动状态底座：结算燃烧 DoT；衰减外力速度。
func _physics_process(delta: float) -> void:
	var burn := status.tick(delta)
	if burn > 0.0:
		take_damage(burn, DamageChannel.DOT)
	external_velocity *= EXTERNAL_VELOCITY_DECAY
	if external_velocity.length() < EXTERNAL_VELOCITY_CUTOFF:
		external_velocity = Vector2.ZERO

# ── 状态底座对外接口 ───────────────────────────────────────────────────────
# 武器命中调 apply_status；BT move atom / 玩家接触结算读 move_speed_mult / is_stunned。
# 在此单点应用玩家元素增益(burn_mult/freeze_dur/shock_dur) → 零武器脚本改动。
func apply_status(kind: StringName, magnitude: float, duration: float) -> void:
	var bm := 1.0
	var fb := 0.0
	var sb := 0.0
	if _player != null and is_instance_valid(_player):
		if "burn_mult" in _player: bm = _player.burn_mult
		if "freeze_dur_bonus" in _player: fb = _player.freeze_dur_bonus
		if "shock_dur_bonus" in _player: sb = _player.shock_dur_bonus
	var adj := modified_status_input(kind, magnitude, duration, bm, fb, sb)
	status.apply(kind, adj["magnitude"], adj["duration"])

# 纯函数(便于单测)：按 kind 应用玩家元素增益。burn→放大 dps；freeze/stun→延长时长；其余不变。
static func modified_status_input(kind: StringName, magnitude: float, duration: float, burn_mult: float, freeze_dur_bonus: float, shock_dur_bonus: float) -> Dictionary:
	var mag := magnitude
	var dur := duration
	if kind == &"burn":
		mag *= burn_mult
	elif kind == &"freeze":
		dur += freeze_dur_bonus
	elif kind == &"stun":
		dur += shock_dur_bonus
	return {"magnitude": mag, "duration": dur}

func move_speed_mult() -> float:
	return status.move_speed_mult()

func is_stunned() -> bool:
	return status.is_stunned()

func has_status(kind: StringName) -> bool:
	return status.has(kind)

# 真击退/拉拽：把方向冲量累加到随帧衰减的外力速度(被 BT move atom 并入移动)。
func apply_impulse(dir: Vector2, strength: float) -> void:
	external_velocity += dir * strength

# 纯函数(便于单测)：状态协同乘区。冻结→碎裂(仅DIRECT,不消耗)；硬直→处决(随缺失血量递增,仅DIRECT)；
# 引力增幅 amp 与减速易伤 slow_vuln 同属"易伤桶"桶内相加；碎裂/处决跨桶相乘
# (C1 桶纪律,防全乘区指数起飞)。slow_vuln_frac 默认 0 → 退化为原式(向后兼容已锁契约)。
static func synergy_multiplier(channel: DamageChannel, frozen: bool, stun: bool, hp_frac: float, amp_frac: float, slow_vuln_frac: float = 0.0) -> float:
	var m := 1.0
	if amp_frac > 0.0 or slow_vuln_frac > 0.0:   # 易伤桶：引力增幅 + 减速易伤，相加；两通道都吃
		m *= (1.0 + amp_frac + slow_vuln_frac)
	if channel == DamageChannel.DIRECT:      # 打击型协同：仅直击
		if frozen:
			m *= SHATTER_MULT
		if stun:                             # key 在 stun,不含 freeze → 与碎裂互斥
			m *= (1.0 + EXECUTE_BASE + EXECUTE_SCALE * (1.0 - hp_frac))
	return m

# 纯函数(便于单测)：减速目标的有效易伤 = (基线 + 攻击方卡加成)，封顶；非减速则 0。
static func effective_slow_vuln(slowed: bool, player_bonus: float) -> float:
	if not slowed:
		return 0.0
	return minf(SLOW_VULN_BASE + player_bonus, SLOW_VULN_CAP)

# 纯函数(便于单测)：把 atom 的期望速度按状态+外力合成最终速度。
# 硬直时自身不动但仍受外力推动。
static func compose_velocity(desired: Vector2, speed_mult: float, stunned: bool, external: Vector2) -> Vector2:
	if stunned:
		return external
	return desired * speed_mult + external

# BT move atom 调用：传入期望速度，返回应写入 velocity 的合成速度(仍只调一次 move_and_slide)。
func resolve_velocity(desired: Vector2) -> Vector2:
	return compose_velocity(desired, move_speed_mult(), is_stunned(), external_velocity)

func take_damage(amount: float, channel: DamageChannel = DamageChannel.DIRECT) -> void:
	# 扣血前快照协同输入(乘区用)。
	var frozen := has_status(&"freeze")
	var stun := has_status(&"stun")
	var had_burn := has_status(&"burn")
	var hp_frac := (hp / MAX_HP) if MAX_HP > 0.0 else 0.0
	var amp := status.magnitude(&"amp")
	# slow 易伤(C2)：减速目标受额外伤害。攻击方加成读 _player(单点接线,基线对所有通道生效)。
	var slow_bonus := 0.0
	if _player != null and is_instance_valid(_player) and "slow_vuln_bonus" in _player:
		slow_bonus = _player.slow_vuln_bonus
	var slow_vuln := effective_slow_vuln(has_status(&"slow"), slow_bonus)
	var final := amount * synergy_multiplier(channel, frozen, stun, hp_frac, amp, slow_vuln)
	hp -= final
	# DIRECT 打击型协同反馈(复用预设,纯 cosmetic,确定性安全)。
	if channel == DamageChannel.DIRECT:
		if frozen:
			Vfx.spawn_burst(global_position, &"ice_shard")
		if stun:
			Vfx.spawn_burst(global_position, &"crit_spark")
	# Boss 受击：先 kill 脉冲并复位 _sprite.modulate，否则白闪 (enemy.modulate) 被脉冲色乘穿。
	# 仅 DIRECT 复位脉冲——DOT 每秒 4 跳，不能把 boss 红脉冲冲掉。
	if channel == DamageChannel.DIRECT and _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
		_sprite.modulate = Color.WHITE
	GameFeel.enemy_hit.emit(final, global_position, self, channel)
	if hp <= 0.0:
		# 燃尽(C2)：死时带 burn → 半径内一次性 DOT 火伤。经模块级重入守卫保证单波(见设计 §6)。
		if had_burn and not Enemy._conflagrating:
			Enemy._conflagrating = true
			Vfx.spawn_burst(global_position, &"fire_burst")
			_trigger_conflagration()
			Enemy._conflagrating = false
		if split_count > 0:
			_spawn_split()
		GameFeel.enemy_died.emit(global_position, self)
		died.emit(global_position)
		queue_free()
		return
	# 0.15s 白闪结束后稍微 buffer 一下再重启脉冲；ignore_time_scale 防 hitstop 拖死。
	if channel == DamageChannel.DIRECT and behavior == "boss":
		var t := get_tree().create_timer(0.2, false, true, true)
		t.timeout.connect(_restart_pulse_if_alive)

# 燃尽(C2)：带 burn 死亡时,对半径内存活邻怪各打一次性 DOT 火伤。不施 burn(不蔓延);
# 走 DOT 通道(抑制白闪/击退/音效,避免一次群伤炸出 N 份完整命中反馈)。
# 单波由调用处的 _conflagrating 守卫保证(邻怪被本波炸死的死亡分支会跳过再触发)。
func _trigger_conflagration() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= CONFLAG_RADIUS:
			e.take_damage(CONFLAG_DAMAGE, DamageChannel.DOT)

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
