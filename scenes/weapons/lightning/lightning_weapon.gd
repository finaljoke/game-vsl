# scenes/weapons/lightning/lightning_weapon.gd
class_name LightningWeapon
extends WeaponBase

const DEFAULT_LINK_RANGE: float = 160.0   # 连锁跳跃最大间距(默认)

const BOLT_TEX := preload("res://assets/sprites/kenney/fx/lightning_bolt.png")  # 分叉电弧
const GLOW_TEX := preload("res://assets/sprites/kenney/fx/fx_glow.png")         # 命中辉光
const BOLT_FADE: float = 0.18     # 电弧淡出时长
const BOLT_WIDTH_PX: float = 56.0 # 电弧贴图屏上宽度

# 由 WeaponData.levels 反射注入
var damage: float = 22.0
var chains: int = 3               # 一次最多命中(含起跳)的目标数
var shock_dur: float = 0.0                       # >0 时链尾附感电硬直(基础注入；进化不注入→0)
var link_range: float = DEFAULT_LINK_RANGE       # 数据驱动连锁间距
var bolt_tint: Color = Color(0.62, 0.86, 1.0)  # 进化(雷暴)可经 levels 注入改白紫
var sky_strikes: int = 0      # >0：每次攻击额外召唤 N 道随机天雷
var sky_radius: float = 70.0
var sky_damage: float = 0.0

func _ready() -> void:
	super._ready()

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var idx: Array = chain_targets(_player.global_position, positions, chains, link_range)
	if idx.is_empty():
		return
	var dmg: float = damage_for(damage)
	var path: Array = [_player.global_position]
	for i in idx:
		var enemy := targets[i]
		if is_instance_valid(enemy):
			path.append((enemy as Node2D).global_position)
			enemy.take_damage(dmg)
	# 链尾感电硬直(spec §7.7)：仅 shock_dur>0 时触发，对链上最后一个仍存活的敌人
	if shock_dur > 0.0:
		var tail := targets[idx[idx.size() - 1]]
		if is_instance_valid(tail) and tail.has_method("apply_status"):
			tail.apply_status(&"stun", 0.0, shock_dur)
	_spawn_bolt(path)
	GameFeel.shake(&"medium")
	GameFeel.hitstop(0.04)  # 噼啪顿挫;headless 自动跳过
	if sky_strikes > 0 and sky_damage > 0.0:
		_sky_strike(targets)

# 在随机敌人头顶落 sky_strikes 道独立 AoE 落雷。
func _sky_strike(targets: Array) -> void:
	var dmg: float = damage_for(sky_damage)
	var pool: Array = targets.duplicate()
	var strikes: int = mini(sky_strikes, pool.size())
	for _i in range(strikes):
		if pool.is_empty():
			break
		var pick: int = randi() % pool.size()
		var center: Vector2 = (pool[pick] as Node2D).global_position
		pool.remove_at(pick)
		for e in enemies():
			if is_instance_valid(e) and center.distance_to((e as Node2D).global_position) <= sky_radius:
				e.take_damage(dmg)

# 连锁选择(纯函数，便于单测)：从 origin 起，每次跳到最近、未命中、且在 link_range 内的目标，
# 最多 max_links 个。返回 positions 的索引列表(命中顺序)。
static func chain_targets(origin: Vector2, positions: Array, max_links: int, link_range: float) -> Array:
	var result: Array = []
	var used: Dictionary = {}
	var from: Vector2 = origin
	while result.size() < max_links:
		var best := -1
		var best_d := link_range
		for i in range(positions.size()):
			if used.has(i):
				continue
			var d: float = from.distance_to(positions[i])
			if d <= best_d:
				best_d = d
				best = i
		if best < 0:
			break
		used[best] = true
		result.append(best)
		from = positions[best]
	return result

# 沿命中路径逐段铺设分叉电弧贴图(加色发光) + 命中点辉光，给"链"的可读视觉。
func _spawn_bolt(path: Array) -> void:
	if path.size() < 2:
		return
	var ys := get_ysort()
	if ys == null:
		return
	for i in range(path.size() - 1):
		_spawn_segment(ys, path[i], path[i + 1])
	# 命中点(除起点玩家外)闪一下
	for j in range(1, path.size()):
		_spawn_impact(ys, path[j])

# 把一张竖直电弧贴图旋转/拉伸到 a→b 这一段上。
func _spawn_segment(ys: Node, a: Vector2, b: Vector2) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 1.0:
		return
	var s := Sprite2D.new()
	s.texture = BOLT_TEX
	s.material = _additive()
	s.global_position = a + seg * 0.5
	s.rotation = seg.angle() - PI / 2.0  # 贴图竖直(+Y) → 对齐到段方向
	s.scale = Vector2(BOLT_WIDTH_PX / float(BOLT_TEX.get_width()), length / float(BOLT_TEX.get_height()))
	s.modulate = Color(bolt_tint.r, bolt_tint.g, bolt_tint.b, 0.95)
	ys.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, BOLT_FADE)
	tw.finished.connect(func() -> void: if is_instance_valid(s): s.queue_free())

func _spawn_impact(ys: Node, pos: Vector2) -> void:
	var g := Sprite2D.new()
	g.texture = GLOW_TEX
	g.material = _additive()
	g.global_position = pos
	g.scale = Vector2(0.12, 0.12)
	g.modulate = Color(bolt_tint.r, bolt_tint.g, bolt_tint.b, 0.9)
	ys.add_child(g)
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector2(0.22, 0.22), BOLT_FADE)
	tw.tween_property(g, "modulate:a", 0.0, BOLT_FADE)
	tw.finished.connect(func() -> void: if is_instance_valid(g): g.queue_free())
	Vfx.spawn_burst(pos, &"shock_spark", ys)

# 共享的加色混合材质(发光质感)。
static var _add_mat: CanvasItemMaterial = null
static func _additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat
