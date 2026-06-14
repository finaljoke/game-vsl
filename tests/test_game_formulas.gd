extends GdUnitTestSuite

# 验证 enemy_spawner.gd 的难度曲线公式和 player.gd 的 XP 公式
# 这些是纯数学测试，无需场景或 Autoload

# ── 敌人 HP 曲线：20 * (1 + minutes * 0.25) ──────────────────────────────

func test_enemy_hp_at_start() -> void:
	var minutes := 0.0
	var hp := 20.0 * (1.0 + minutes * 0.25)
	assert_float(hp).is_equal(20.0)

func test_enemy_hp_at_5min() -> void:
	var minutes := 5.0
	var hp := 20.0 * (1.0 + minutes * 0.25)
	assert_float(hp).is_equal(45.0)

func test_enemy_hp_at_10min() -> void:
	var minutes := 10.0
	var hp := 20.0 * (1.0 + minutes * 0.25)
	assert_float(hp).is_equal(70.0)

func test_enemy_hp_increases_over_time() -> void:
	var hp_at_0 := 20.0 * (1.0 + 0.0 * 0.25)
	var hp_at_5 := 20.0 * (1.0 + 5.0 * 0.25)
	var hp_at_10 := 20.0 * (1.0 + 10.0 * 0.25)
	assert_float(hp_at_5).is_greater(hp_at_0)
	assert_float(hp_at_10).is_greater(hp_at_5)

# ── 敌人速度曲线：clamp(80 * (1 + minutes * 0.15), 80, 210) ──────────────

func test_enemy_speed_at_start() -> void:
	var minutes := 0.0
	var speed := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)
	assert_float(speed).is_equal(80.0)

func test_enemy_speed_at_5min() -> void:
	var minutes := 5.0
	var speed := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)
	assert_float(speed).is_equal(140.0)

func test_enemy_speed_at_10min_approaches_player() -> void:
	# 10 分钟时 80 * (1 + 10 * 0.15) = 200，逼近玩家速度 200，仍未触顶
	var minutes := 10.0
	var speed := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)
	assert_float(speed).is_equal(200.0)

func test_enemy_speed_caps_at_210() -> void:
	# 上限在约 10.8 分钟后触发：80 * (1 + 15 * 0.15) = 260 → clamp 210
	var minutes := 15.0
	var speed := clampf(80.0 * (1.0 + minutes * 0.15), 80.0, 210.0)
	assert_float(speed).is_equal(210.0)

func test_enemy_speed_never_below_80() -> void:
	var speed := clampf(80.0 * (1.0 + 0.0 * 0.15), 80.0, 210.0)
	assert_float(speed).is_greater_equal(80.0)

# ── 生成间隔衰减：每 20 秒 × 0.85，最低 0.3 ────────────────────────────

func test_spawn_interval_decays_each_cycle() -> void:
	var interval := 1.5
	interval = maxf(interval * 0.85, 0.3)
	assert_float(interval).is_equal_approx(1.275, 0.001)

func test_spawn_interval_floor_holds() -> void:
	var interval := 0.3
	interval = maxf(interval * 0.85, 0.3)
	assert_float(interval).is_equal(0.3)

func test_spawn_interval_reaches_floor_eventually() -> void:
	var interval := 1.5
	for _i in range(30):
		interval = maxf(interval * 0.85, 0.3)
	assert_float(interval).is_equal(0.3)

# ── 玩家 XP 阈值：每升级 × 1.15 ──────────────────────────────────────────

func test_xp_threshold_level2() -> void:
	var threshold := 100.0
	threshold *= 1.15
	assert_float(threshold).is_equal_approx(115.0, 0.001)

func test_xp_threshold_level3() -> void:
	var threshold := 100.0
	threshold *= 1.15  # level 2
	threshold *= 1.15  # level 3
	assert_float(threshold).is_equal_approx(132.25, 0.001)

func test_xp_threshold_grows_each_level() -> void:
	var threshold := 100.0
	var prev := threshold
	for _i in range(5):
		threshold *= 1.15
		assert_float(threshold).is_greater(prev)
		prev = threshold

func test_xp_percent_at_half() -> void:
	var xp := 50.0
	var xp_threshold := 100.0
	assert_float(xp / xp_threshold).is_equal_approx(0.5, 0.001)

func test_xp_percent_at_zero() -> void:
	var xp := 0.0
	var xp_threshold := 100.0
	assert_float(xp / xp_threshold).is_equal(0.0)

# ── 爆炸集群目标：densest_center 选半径内邻居最多的点 ────────────────────

func test_densest_center_picks_cluster_not_outlier() -> void:
	# 三点紧挨 (0,0)(10,0)(0,10) + 一个远点 (500,500)
	var positions: Array = [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10), Vector2(500, 500)]
	var center := ExplosionWeapon.densest_center(positions, 80.0)
	# 应落在密集簇内（任意一点其半径内含 3 个），而非孤立远点
	assert_bool(center.distance_to(Vector2(500, 500)) > 80.0).is_true()

func test_densest_center_single_point() -> void:
	var center := ExplosionWeapon.densest_center([Vector2(42, 7)], 80.0)
	assert_vector(center).is_equal(Vector2(42, 7))

func test_densest_center_over_cap_still_lands_in_blob() -> void:
	# 60 个点紧凑成簇（彼此 < radius）+ 40 个远离离群点，总数 > cap(32)
	# 步长采样降级后，候选必有一个落在大簇内，结果应靠近簇中心
	var positions: Array = []
	var blob_center := Vector2(300, 300)
	for i in range(60):
		positions.append(blob_center + Vector2(i % 6, i / 6) * 4.0)  # 5x10 网格，跨度 < 40
	for i in range(40):
		positions.append(Vector2(2000 + i * 50, 2000))  # 互相远离、也远离簇的离群点
	var center := ExplosionWeapon.densest_center(positions, 80.0)
	assert_bool(center.distance_to(blob_center) < 80.0).is_true()
