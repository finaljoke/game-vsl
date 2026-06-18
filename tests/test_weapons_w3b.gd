extends GdUnitTestSuite
# W3b 进化质变：反射 + 机制。preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

func _tough_enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.MAX_HP = 500.0
	e.hp = 500.0
	e.global_position = pos
	return auto_free(e)

func _ysort_stub() -> void:
	var ys: Node2D = auto_free(Node2D.new()) as Node2D
	add_child(ys)
	ys.add_to_group("ysort")

# 拉满基础武器并进化(apply 跳过条件，直接走效果)
func _evolve(base_id: String, evolved_id: String) -> WeaponBase:
	_ysort_stub()
	CardPool.apply({"id": base_id}, _player)
	CardPool.apply({"id": "evolve_%s" % base_id, "type": "evolution"}, _player)
	return _player.get_weapon_node(evolved_id)

# ── 回旋斩 Whirlwind ──
func test_whirlwind_reflects_quale_fields() -> void:
	var w := _evolve("whip", "bloody_whip")
	assert_object(w).is_not_null()
	assert_bool(w.get("full_circle")).is_true()
	assert_float(w.get("bleed_dps")).is_greater(0.0)
	assert_float(w.get("lifesteal_on_hit")).is_greater(0.0)

func test_whirlwind_hits_enemy_behind_player() -> void:
	var w := _evolve("whip", "bloody_whip")
	_player.global_position = Vector2.ZERO
	w._facing = Vector2.RIGHT
	var e := _tough_enemy_at(Vector2(-60, 0))   # 在身后(锥形外)，但 360° 内
	await get_tree().process_frame
	w.attack()
	assert_float(e.hp).is_less(500.0)            # 全向命中
	assert_bool(e.has_status(&"burn")).is_true() # 流血(复用 burn)
