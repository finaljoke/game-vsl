# scenes/weapons/lightning/lightning_weapon.gd
class_name LightningWeapon
extends WeaponBase

const BASE_DAMAGE: float = 22.0
const LINK_RANGE: float = 160.0   # 连锁跳跃的最大间距

# 由 WeaponData.levels 反射注入
var chains: int = 3               # 一次最多命中(含起跳)的目标数

func _ready() -> void:
	super._ready()

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	var positions: Array = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var idx: Array = chain_targets(_player.global_position, positions, chains, LINK_RANGE)
	if idx.is_empty():
		return
	var dmg: float = damage_for(BASE_DAMAGE)
	var path: Array = [_player.global_position]
	for i in idx:
		var enemy := targets[i]
		if is_instance_valid(enemy):
			path.append((enemy as Node2D).global_position)
			enemy.take_damage(dmg)
	_spawn_bolt(path)

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

# 用一条快速淡出的 Line2D 串起命中路径，给"链"的可读视觉。
func _spawn_bolt(path: Array) -> void:
	if path.size() < 2:
		return
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.6, 0.85, 1.0, 0.9)
	for p in path:
		line.add_point(p)
	get_ysort().add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.18)
	tween.finished.connect(func() -> void: if is_instance_valid(line): line.queue_free())
