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
	await get_tree().process_frame   # 让 BT 初始化(可能 tick 一次)
	e.apply_status(&"freeze", 999.0, 999.0)   # 长时长，确保测试期间不过期
	for i in range(20):
		await get_tree().process_frame   # BT 走 IDLE，process_frame 驱动其 tick
	# 冻结 → chase atom 每 tick 经 resolve_velocity 得零自身运动(仅外力=0) → velocity 恒为零
	assert_vector(e.velocity).is_equal(Vector2.ZERO)

func test_unimpeded_enemy_chases_player() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("chase")
	e.global_position = Vector2.ZERO
	# 帧无关：无状态/无外力时 resolve_velocity 恒等(不阻碍全速)
	assert_vector(e.resolve_velocity(Vector2(80.0, 0.0))).is_equal(Vector2(80.0, 0.0))
	# 让 chase atom 经 resolve_velocity 写 velocity(BT 走 IDLE → process_frame 驱动)
	for i in range(5):
		await get_tree().process_frame
	# 朝玩家(+x)产生自身运动 → 证明 atom 确实路由 resolve_velocity 且在追击
	assert_float(e.velocity.x).is_greater(0.0)

# ── 冲锋者(charger) _tick 接线集成验证(A1)：证明 _tick 真的经 _resolve 路由控制，──────
# 而非仅纯函数 charge_velocity 正确。修复前 bt_charger 直接写 agent.velocity，冻结也照常推进。
# 玩家放远处(dist 400 > charge_range 220)使冲锋者停在 APPROACH 阶段。

func test_frozen_charger_does_not_advance() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("charger")
	e.global_position = Vector2.ZERO
	await get_tree().process_frame   # 让 BT 初始化
	e.apply_status(&"freeze", 999.0, 999.0)   # 长时长，测试期间不过期
	for i in range(20):
		await get_tree().process_frame
	# 冻结 → APPROACH 经 _resolve → compose_velocity 得零自身运动(仅外力=0) → velocity 恒为零。
	# 若 _tick 退回直接写 agent.velocity 的漏接，本断言会失败。
	assert_vector(e.velocity).is_equal(Vector2.ZERO)

func test_unimpeded_charger_advances() -> void:
	_make_player(400.0)
	await get_tree().process_frame
	var e := _make_enemy("charger")
	e.global_position = Vector2.ZERO
	for i in range(5):
		await get_tree().process_frame
	# 无状态：APPROACH 朝玩家(+x)产生自身运动 → 证明 _tick 确实路由 _resolve 且在推进
	assert_float(e.velocity.x).is_greater(0.0)

func test_take_damage_shatters_frozen_enemy_on_direct() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"freeze", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	# 10 × 1.5 = 15 → hp 85
	assert_float(e.hp).is_equal_approx(85.0, 0.001)

func test_take_damage_dot_does_not_shatter_frozen() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"freeze", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DOT)
	# 碎裂不沾 DoT → 10 × 1.0 = 10 → hp 90
	assert_float(e.hp).is_equal_approx(90.0, 0.001)

func test_take_damage_executes_full_hp_stun() -> void:
	var e := _make_enemy()
	e.MAX_HP = 100.0
	e.hp = 100.0
	e.apply_status(&"stun", 0.0, 1.0)
	e.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	# 满血处决 ×1.2 → 12 → hp 88
	assert_float(e.hp).is_equal_approx(88.0, 0.001)

func test_take_damage_execute_scales_with_missing_hp() -> void:
	# 同样 10 直击,残血硬直怪掉血显著多于满血硬直怪。
	var full := _make_enemy()
	full.MAX_HP = 100.0
	full.hp = 100.0
	full.apply_status(&"stun", 0.0, 1.0)
	full.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	var full_loss := 100.0 - full.hp

	var low := _make_enemy()
	low.MAX_HP = 100.0
	low.hp = 20.0   # hp_frac 0.2 → ×(1+0.2+0.8*0.8)=×1.84
	low.apply_status(&"stun", 0.0, 1.0)
	var before := low.hp
	low.take_damage(10.0, Enemy.DamageChannel.DIRECT)
	var low_loss := before - low.hp
	assert_float(low_loss).is_greater(full_loss)
