extends GdUnitTestSuite
# 亡者召唤：随从自主索敌/接触/退场/分裂 + 武器维持上限 + 群尸进化。
# preload 引用脚本；敌人实例化 enemy.tscn(headless 加载 LimboAI)。

const RoamingMinionScript := preload("res://scenes/weapons/reanimate/roaming_minion.gd")
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

# 召唤物经 get_ysort() 落位 → 测试建一个 "ysort" 桩，避免回退 null。
func _ysort_stub() -> Node2D:
	var ys: Node2D = auto_free(Node2D.new()) as Node2D
	add_child(ys)
	ys.add_to_group("ysort")
	return ys

func test_minion_moves_toward_nearest_enemy() -> void:
	var m: RoamingMinion = auto_free(RoamingMinionScript.new()) as RoamingMinion
	m.speed = 140.0
	m.lifetime = 99.0
	add_child(m)
	m.global_position = Vector2.ZERO
	_tough_enemy_at(Vector2(300, 0))
	var start_x: float = m.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	assert_float(m.global_position.x).is_greater(start_x + 5.0)

func test_minion_damages_adjacent_enemy() -> void:
	var m: RoamingMinion = auto_free(RoamingMinionScript.new()) as RoamingMinion
	m.damage = 12.0
	m.speed = 0.0          # 不移动，纯测接触
	m.lifetime = 99.0
	add_child(m)
	m.global_position = Vector2.ZERO
	var e := _tough_enemy_at(Vector2(8, 0))   # 接触半径内
	for i in range(3):
		await get_tree().physics_frame
	assert_float(e.hp).is_less(500.0)

func test_minion_expires_after_lifetime() -> void:
	var m: RoamingMinion = RoamingMinionScript.new() as RoamingMinion
	m.lifetime = 0.05
	add_child(m)
	for i in range(10):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(m)).is_false()

func test_minion_splits_on_death_when_chance_full() -> void:
	var m: RoamingMinion = RoamingMinionScript.new() as RoamingMinion
	m.split_chance = 1.0   # 必裂
	add_child(m)
	m.global_position = Vector2(50, 50)
	m._die()
	await get_tree().process_frame
	var found := false
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s != m:
			found = true
	assert_bool(found).is_true()
	# 清理分裂出的子随从，防止泄漏到下一个测试
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s != m:
			s.queue_free()
	await get_tree().process_frame

func test_minion_no_split_when_chance_zero() -> void:
	var m: RoamingMinion = RoamingMinionScript.new() as RoamingMinion
	m.split_chance = 0.0
	add_child(m)
	m._die()
	await get_tree().process_frame
	var count := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			count += 1
	assert_int(count).is_equal(0)
