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

# ── ReanimateWeapon ──
func _count_summons() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s):
			n += 1
	return n

func test_reanimate_reflects_level1_fields() -> void:
	CardPool.apply({"id": "reanimate"}, _player)
	var rw := _player.get_weapon_node("reanimate")
	assert_object(rw).is_not_null()
	assert_int(rw.get("max_minions")).is_equal(1)
	assert_float(rw.get("lifetime")).is_equal_approx(9.0, 0.001)

func test_reanimate_spawns_up_to_max_minions() -> void:
	_ysort_stub()
	CardPool.apply({"id": "reanimate"}, _player)
	var rw := _player.get_weapon_node("reanimate")
	rw.attack()
	rw.attack()   # Lv1 max=1 → 第二次不再生成
	await get_tree().process_frame
	assert_int(_count_summons()).is_equal(1)

func test_evolve_reanimate_grants_horde() -> void:
	CardPool.apply({"id": "reanimate"}, _player)
	CardPool.apply({"id": "evolve_reanimate", "type": "evolution"}, _player)
	assert_bool(_player.has_weapon("horde")).is_true()
	assert_bool(_player.has_weapon("reanimate")).is_false()
	var hw := _player.get_weapon_node("horde")
	assert_int(hw.get("max_minions")).is_greater(3)        # 上限大增
	assert_float(hw.get("split_chance")).is_greater(0.0)   # 死亡分裂开启

func test_horde_minion_carries_split_chance() -> void:
	_ysort_stub()
	CardPool.apply({"id": "reanimate"}, _player)
	CardPool.apply({"id": "evolve_reanimate", "type": "evolution"}, _player)
	var hw := _player.get_weapon_node("horde")
	hw.attack()
	await get_tree().process_frame
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s is RoamingMinion:
			assert_float(s.split_chance).is_greater(0.0)

# ── 群尸 §3c 防御杠杆:随从命中给本体回血(纯 DPS 救不了无防护本体) ──────────────
func test_minion_heals_player_on_hit_when_enabled() -> void:
	_player.global_position = Vector2(3000, 3000)   # 远离敌人,排除本体被接触伤害污染
	_player.hp = _player.max_hp - 20.0   # 留回血空间(heal 封顶 max_hp)
	var hp0 := _player.hp
	var m: RoamingMinion = auto_free(RoamingMinionScript.new()) as RoamingMinion
	m.damage = 12.0
	m.speed = 0.0          # 不移动,纯测接触
	m.lifetime = 99.0
	m.heal_on_hit = 5.0
	add_child(m)
	m.global_position = Vector2.ZERO
	_tough_enemy_at(Vector2(8, 0))   # 接触半径内
	for i in range(3):
		await get_tree().physics_frame
	assert_float(_player.hp).is_greater(hp0)   # 命中敌人时给玩家回血(经 player 组查找,与距离无关)

func test_base_minion_does_not_heal_by_default() -> void:
	_player.global_position = Vector2(3000, 3000)   # 远离敌人
	_player.hp = _player.max_hp - 20.0
	var hp0 := _player.hp
	var m: RoamingMinion = auto_free(RoamingMinionScript.new()) as RoamingMinion
	m.damage = 12.0
	m.speed = 0.0
	m.lifetime = 99.0   # heal_on_hit 默认 0
	add_child(m)
	m.global_position = Vector2.ZERO
	_tough_enemy_at(Vector2(8, 0))
	for i in range(3):
		await get_tree().physics_frame
	assert_float(_player.hp).is_equal_approx(hp0, 0.001)   # 基础随从不回血

func test_horde_minion_carries_heal_on_hit() -> void:
	_ysort_stub()
	CardPool.apply({"id": "reanimate"}, _player)
	CardPool.apply({"id": "evolve_reanimate", "type": "evolution"}, _player)
	var hw := _player.get_weapon_node("horde")
	hw.attack()
	await get_tree().process_frame
	for s in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(s) and s is RoamingMinion:
			assert_float(s.heal_on_hit).is_greater(0.0)
