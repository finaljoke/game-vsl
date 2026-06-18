# scenes/weapons/explosion/explosion_weapon.gd
class_name ExplosionWeapon
extends WeaponBase

const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")
const EXPLOSION_SCRIPT = preload("res://scenes/weapons/explosion/explosion.gd")
const BURN_FIELD = preload("res://scenes/weapons/explosion/burn_field.gd")

var damage: float = 40.0
var blast_radius: float = 80.0   # 命中半径(数据驱动；默认=Explosion.DEFAULT_RADIUS)
var burn_dps: float = 0.0        # >0 且 field_dur>0 时落点留地火(基础注入；进化不注入→0)
var field_dur: float = 0.0
# 进化视觉(反射注入)
var blast_scale: float = 1.0
var blast_tint: Color = Color.WHITE

func _ready() -> void:
	super._ready()
	# cooldown 由 WeaponData.levels 通过 apply_level() 注入

func attack() -> void:
	var targets := enemies()
	if targets.is_empty():
		return
	# 爆炸定位：落在最密集人堆，最大化 AoE 价值
	var positions: Array[Vector2] = []
	for e in targets:
		positions.append((e as Node2D).global_position)
	var center := densest_center(positions, blast_radius)
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = damage_for(damage)
	explosion.blast_radius = blast_radius
	explosion.base_scale = blast_scale   # 进化形态(核爆)更大
	explosion.modulate = blast_tint      # 进化形态变色；_process 只动 alpha，RGB 保留
	get_ysort().add_child(explosion)
	explosion.global_position = center
	explosion.detonate()
	# 火球地火(spec §7.5)：仅基础注入 burn_dps/field_dur 时生成；nuke 不注入→跳过
	if burn_dps > 0.0 and field_dur > 0.0:
		var field := BURN_FIELD.new()
		field.radius = blast_radius
		field.burn_dps = burn_dps
		field.field_dur = field_dur
		get_ysort().add_child(field)
		field.global_position = center

# 纯函数：返回半径内邻居最多的坐标，便于单测。
# 候选用步长采样限到至多 candidate_cap 个，把最坏复杂度从 O(n²) 降到 O(cap·n)；
# 候选数 ≤ cap 时与全遍历完全一致。
static func densest_center(positions: Array, radius: float, candidate_cap: int = 32) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var n := positions.size()
	var stride := 1 if n <= candidate_cap else int(ceil(float(n) / float(candidate_cap)))
	var best: Vector2 = positions[0]
	var best_count := -1
	var i := 0
	while i < n:
		var p: Vector2 = positions[i]
		var count := 0
		for o in positions:
			if p.distance_to(o) <= radius:
				count += 1
		if count > best_count:
			best_count = count
			best = p
		i += stride
	return best
