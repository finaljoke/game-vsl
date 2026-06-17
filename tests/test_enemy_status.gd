extends GdUnitTestSuite
# Enemy 接入状态/击退的集成验证(实例化 enemy.tscn → 依赖 LimboAI；headless 测试进程会加载)。
# 后续 Task 3/4 会向本文件追加击退与移动门控的测试。

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")

# 建一只敌人并入树(触发 _enter_tree 建 BT + _ready)。无玩家时 chase atom 直接 FAILURE 不移动，
# 适合隔离验证状态/外力本身。
func _make_enemy(behavior: String = "chase") -> Enemy:
	var e: Enemy = EnemyScene.instantiate()
	e.behavior = behavior
	add_child(e)
	e.add_to_group("enemies")
	return auto_free(e)

func test_apply_burn_damages_over_physics_frames() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"burn", 8.0, 1.0)   # 8 dps, 1s
	for i in range(60):                  # ~1 秒 @60fps
		await get_tree().physics_frame
	# 8 dps × ~1s ≈ 8 伤害(4 拍 × 2.0)；给 ±2 容差吸收帧边界
	assert_float(e.hp).is_less(100.0)
	assert_float(e.hp).is_equal_approx(92.0, 2.0)

func test_freeze_stuns_and_zeroes_speed_mult() -> void:
	var e := _make_enemy()
	e.apply_status(&"freeze", 0.0, 1.0)
	assert_bool(e.is_stunned()).is_true()
	assert_float(e.move_speed_mult()).is_equal(0.0)

func test_slow_reduces_speed_mult_without_stun() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	assert_float(e.move_speed_mult()).is_equal_approx(0.5, 0.001)
	assert_bool(e.is_stunned()).is_false()

func test_stun_sets_stunned() -> void:
	var e := _make_enemy()
	e.apply_status(&"stun", 0.0, 1.0)
	assert_bool(e.is_stunned()).is_true()

func test_has_status_reports_active() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	assert_bool(e.has_status(&"slow")).is_true()
	assert_bool(e.has_status(&"freeze")).is_false()

func test_apply_impulse_sets_external_velocity() -> void:
	var e := _make_enemy()
	e.apply_impulse(Vector2.RIGHT, 200.0)
	assert_vector(e.external_velocity).is_equal(Vector2(200.0, 0.0))

func test_external_velocity_decays_over_physics_frames() -> void:
	var e := _make_enemy()   # 无玩家 → chase atom FAILURE 不写 velocity，隔离衰减
	e.apply_impulse(Vector2.RIGHT, 200.0)
	var before := e.external_velocity.length()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(e.external_velocity.length()).is_less(before)

func test_resolve_velocity_uses_status_and_external() -> void:
	var e := _make_enemy()
	e.apply_status(&"slow", 0.5, 1.0)
	e.apply_impulse(Vector2(0, 100), 1.0)   # external = (0,100)
	var v := e.resolve_velocity(Vector2(80, 0))
	assert_vector(v).is_equal(Vector2(40, 100))   # 80*0.5 + (0,100)

# 在 (px,0) 放一名玩家(入 "player" 组供 BT 索敌)，返回玩家。
func _make_player(px: float) -> Player:
	var p: Player = PlayerScene.instantiate()
	add_child(p)
	p.add_to_group("player")
	p.global_position = Vector2(px, 0)
	return auto_free(p)

func test_frozen_enemy_does_not_chase_player() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("chase")
	e.global_position = Vector2.ZERO
	await get_tree().process_frame
	e.apply_status(&"freeze", 0.0, 5.0)
	var start_x := e.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	# 冻结期间 resolve_velocity → 仅外力(=0) → 不应朝玩家(+x)移动
	assert_float(e.global_position.x).is_equal_approx(start_x, 2.0)

func test_unimpeded_enemy_chases_player() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("chase")
	e.global_position = Vector2.ZERO
	var start_x := e.global_position.x
	for i in range(20):
		await get_tree().physics_frame
	assert_float(e.global_position.x).is_greater(start_x + 1.0)
