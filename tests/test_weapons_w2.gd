extends GdUnitTestSuite
# W2 新增 3 把武器的反射 + 机制集成。preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 在 pos 生成一只高血量敌人(避免被一击打死后断言失效)，入 "enemies" 组。
func _tough_enemy_at(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.MAX_HP = 500.0
	e.hp = 500.0
	e.global_position = pos
	return auto_free(e)

# ── 碎 Maul ──
func test_maul_reflects_level1_fields() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var node := _player.get_weapon_node("maul")
	assert_object(node).is_not_null()
	assert_float(node.get("radius")).is_equal_approx(130.0, 0.001)
	assert_float(node.get("knockback")).is_equal_approx(220.0, 0.001)
	assert_float(node.get("stun_dur")).is_equal_approx(0.4, 0.001)

func test_maul_damages_knocks_and_stuns_enemy_in_radius() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var maul := _player.get_weapon_node("maul")
	var e := _tough_enemy_at(_player.global_position + Vector2(50, 0))   # 半径 130 内
	await get_tree().process_frame
	maul.attack()
	assert_float(e.hp).is_less(500.0)                       # 受伤
	assert_bool(e.is_stunned()).is_true()                   # 硬直
	assert_float(e.external_velocity.length()).is_greater(0.0)   # 击退冲量(朝 +x 远离玩家)
	assert_float(e.external_velocity.x).is_greater(0.0)

func test_maul_ignores_enemy_out_of_radius() -> void:
	CardPool.apply({"id": "maul"}, _player)
	var maul := _player.get_weapon_node("maul")
	var e := _tough_enemy_at(_player.global_position + Vector2(400, 0))  # 半径外
	await get_tree().process_frame
	maul.attack()
	assert_float(e.hp).is_equal(500.0)
	assert_bool(e.is_stunned()).is_false()

# ── 霜噬 Frostbite ──
func test_frostbite_reflects_level1_fields() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var node := _player.get_weapon_node("frostbite")
	assert_object(node).is_not_null()
	assert_float(node.get("area")).is_equal_approx(90.0, 0.001)
	assert_float(node.get("slow_factor")).is_equal_approx(0.6, 0.001)

func test_frostbite_slows_then_freezes_on_second_hit() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var fb := _player.get_weapon_node("frostbite")
	var e := _tough_enemy_at(_player.global_position + Vector2(20, 0))  # 唯一敌=最密集落点, 在 area 内
	await get_tree().process_frame
	fb.attack()
	assert_bool(e.has_status(&"slow")).is_true()    # 首次命中 → 减速
	assert_bool(e.has_status(&"freeze")).is_false()
	fb.attack()
	assert_bool(e.has_status(&"freeze")).is_true()  # 已减速 → 升级冻结

func test_frostbite_no_target_is_safe() -> void:
	CardPool.apply({"id": "frostbite"}, _player)
	var fb := _player.get_weapon_node("frostbite")
	fb.attack()   # 无敌人 → 不崩
	assert_bool(true).is_true()
