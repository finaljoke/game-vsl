# scenes/weapons/explosion/explosion_weapon.gd
class_name ExplosionWeapon
extends WeaponBase

const EXPLOSION_SCENE = preload("res://scenes/weapons/explosion/explosion.tscn")
const EXPLOSION_SCRIPT = preload("res://scenes/weapons/explosion/explosion.gd")  # 半径单一来源

func _ready() -> void:
	super._ready()
	cooldown = 3.0

func attack() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	# 爆炸定位：落在最密集人堆，最大化 AoE 价值
	var positions: Array[Vector2] = []
	for e in enemies:
		positions.append((e as Node2D).global_position)
	var center := densest_center(positions, EXPLOSION_SCRIPT.RADIUS)
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.damage = explosion.BASE_DAMAGE * (_player as Player).damage_mult
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
