extends GdUnitTestSuite
# W1 新机制单测：纯函数 + 数据驱动反射 + 状态附着。preload 引用脚本。

const KnifeScript := preload("res://scenes/weapons/knife/knife_weapon.gd")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _player: Player

func before_test() -> void:
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	_player = auto_free(scene.instantiate() as Player)
	add_child(_player)
	await get_tree().process_frame

# 在玩家附近 dist 处生成一只敌人(入 "enemies" 组)，返回之。
func _spawn_enemy_near(dist: float) -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = "chase"
	add_child(e)
	e.add_to_group("enemies")
	e.global_position = _player.global_position + Vector2(dist, 0)
	return auto_free(e)

# ── 回旋斧(boomerang) Lv1 冷却数据 ──
func test_throwing_axe_lv1_cooldown() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	assert_float(_player.get_weapon_node("boomerang").cooldown).is_equal_approx(1.5, 0.001)

func test_throwing_axe_lv1_damage() -> void:
	CardPool.apply({"id": "boomerang"}, _player)
	assert_float(_player.get_weapon_node("boomerang").get("damage")).is_equal_approx(20.0, 0.001)
