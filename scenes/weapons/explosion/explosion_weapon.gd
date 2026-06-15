# scenes/weapons/explosion/explosion_weapon.gd
class_name ExplosionWeapon
extends WeaponBase

const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")
const EXPLOSION_SCRIPT = preload("res://scenes/weapons/explosion/explosion.gd")  # 半径单一来源

# 进化视觉(由 WeaponData.levels 反射注入)：基础武器不指定 → 保持默认无变化。
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
	var center := densest_center(positions, EXPLOSION_SCRIPT.RADIUS)
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = damage_for(explosion.BASE_DAMAGE)
	explosion.base_scale = blast_scale   # 进化形态(核爆)更大
	explosion.modulate = blast_tint      # 进化形态变色；_process 只动 alpha，RGB 保留
	get_ysort().add_child(explosion)
	explosion.global_position = center
	explosion.detonate()

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
