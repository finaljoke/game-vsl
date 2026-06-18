extends GdUnitTestSuite
## VFX-W2 武器命中视效集成测试（任务 2：斩/回旋斩）。
## 后续任务在此文件追加各自的 test_* 函数。

const WhipScript := preload("res://scenes/weapons/whip/whip_weapon.gd")

# 造一个挂着武器的最小玩家 + ysort，便于攻击产出 FX。
func _make_player() -> Player:
	var p: Player = load("res://scenes/player/player.tscn").instantiate() as Player
	add_child(p)
	return p

func _make_enemy_at(pos: Vector2) -> Node2D:
	var e: Node2D = load("res://scenes/enemies/enemy.tscn").instantiate() as Node2D
	add_child(e)
	e.global_position = pos
	e.add_to_group("enemies")
	return e

func _ysort_child_count() -> int:
	var ys := get_tree().get_first_node_in_group("ysort")
	return ys.get_child_count() if ys != null else get_tree().current_scene.get_child_count()

func test_whirlwind_hit_spawns_blood_burst() -> void:
	# 建一个 ysort 节点让 whip._spawn_swipe 和 Vfx.spawn_burst 都能挂载节点
	var ys: Node2D = auto_free(Node2D.new()) as Node2D
	add_child(ys)
	ys.add_to_group("ysort")

	var player: Player = auto_free(_make_player()) as Player
	var whip: WhipWeapon = auto_free(WhipScript.new()) as WhipWeapon
	whip.data = null
	player.add_child(whip)
	await get_tree().process_frame
	whip.full_circle = true   # 回旋斩(全向)形态 — 血雾门控条件
	whip.swing_range = 200.0
	var enemy: Node2D = auto_free(_make_enemy_at(player.global_position + Vector2(40, 0))) as Node2D
	await get_tree().process_frame
	var before: int = _ysort_child_count()
	whip.attack()
	await get_tree().process_frame
	# full_circle 命中：斩光(swipe)+ 血雾(blood_burst) → 至少比 before 多 2
	assert_int(_ysort_child_count()).is_greater_equal(before + 2)


const KnifeProjScript := preload("res://scenes/weapons/knife/knife_projectile.gd")

func test_knife_hit_spawns_spark() -> void:
	var player: Player = auto_free(_make_player()) as Player
	await get_tree().process_frame
	var proj: Area2D = auto_free(KnifeProjScript.new()) as Area2D
	proj.damage = 5.0
	proj.pierce = 1
	add_child(proj)
	proj.global_position = player.global_position
	var enemy: Node2D = auto_free(_make_enemy_at(player.global_position)) as Node2D
	await get_tree().process_frame
	var before: int = get_child_count()
	await get_tree().physics_frame
	await get_tree().process_frame
	# 命中应产出火花粒子(spawn_burst 挂到 get_parent() → 测试套件本身)
	assert_int(get_child_count()).is_greater_equal(before)


const BoomerangProjScript := preload("res://scenes/weapons/boomerang/boomerang_projectile.gd")

func test_boomerang_has_trail_child() -> void:
	var player: Player = auto_free(_make_player()) as Player
	await get_tree().process_frame
	var proj: Node2D = auto_free(BoomerangProjScript.new()) as Node2D
	add_child(proj)
	await get_tree().process_frame
	var has_trail: bool = false
	for c: Node in proj.get_children():
		if c is CPUParticles2D:
			has_trail = true
	assert_bool(has_trail).is_true()
	player.queue_free(); proj.queue_free()


const ExplosionScript := preload("res://scenes/weapons/explosion/explosion.gd")

func test_explosion_spawns_anim_sprite() -> void:
	# Explosion.detonate 附带序列帧爆炸 FX。
	var enemy: Node2D = auto_free(_make_enemy_at(Vector2(500, 500))) as Node2D
	var expl: Node2D = auto_free(ExplosionScript.new()) as Node2D
	add_child(expl)
	expl.set("damage", 1.0)
	expl.global_position = Vector2(500, 500)
	await get_tree().process_frame
	expl.detonate()
	await get_tree().process_frame
	# detonate() 用 get_parent() 作为父节点，在测试中 get_parent() = 测试套件自身
	assert_bool(_suite_has_animated_sprite()).is_true()
	if is_instance_valid(enemy): enemy.queue_free()
	if is_instance_valid(expl): expl.queue_free()

func _suite_has_animated_sprite() -> bool:
	for c: Node in get_children():
		if c is AnimatedSprite2D:
			return true
	return false
