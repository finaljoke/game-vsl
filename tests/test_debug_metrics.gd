# tests/test_debug_metrics.gd
extends GdUnitTestSuite

# DebugMetrics 是 autoload 单例(全局可达)。这些用例直接调它的信号处理器/getter,
# 不依赖完整场景。每个用例先清零,避免跨用例污染累计值。

func before_test() -> void:
	DebugMetrics.reset_metrics()

func test_enemy_hit_accumulates_dmg_dealt() -> void:
	DebugMetrics._on_enemy_hit(10.0, Vector2.ZERO, null)
	DebugMetrics._on_enemy_hit(5.0, Vector2.ZERO, null)
	assert_float(DebugMetrics.get_dmg_dealt_total()).is_equal_approx(15.0, 0.001)

func test_player_hit_accumulates_dmg_taken() -> void:
	DebugMetrics._on_player_hit(8.0)
	DebugMetrics._on_player_hit(2.0)
	assert_float(DebugMetrics.get_dmg_taken_total()).is_equal_approx(10.0, 0.001)

func test_enemy_died_accumulates_kills() -> void:
	DebugMetrics._on_enemy_died(Vector2.ZERO, null)
	DebugMetrics._on_enemy_died(Vector2.ZERO, null)
	assert_int(DebugMetrics.get_kills_total()).is_equal(2)

func test_danger_accumulates_when_hp_low() -> void:
	# 直接喂 HP 采样:低于 25% 阈值 → 危险时长累加
	DebugMetrics._sample_hp(20.0, 100.0, 0.5)   # hp_pct=0.20 < 0.25 → +0.5s
	DebugMetrics._sample_hp(20.0, 100.0, 0.5)   # 再 +0.5s
	assert_float(DebugMetrics.get_danger_total()).is_equal_approx(1.0, 0.001)

func test_danger_not_accumulated_when_hp_high() -> void:
	DebugMetrics._sample_hp(80.0, 100.0, 0.5)   # hp_pct=0.80 ≥ 0.25 → 不累加
	assert_float(DebugMetrics.get_danger_total()).is_equal_approx(0.0, 0.001)

func test_hp_pct_min_tracks_lowest() -> void:
	DebugMetrics._sample_hp(80.0, 100.0, 0.1)
	DebugMetrics._sample_hp(15.0, 100.0, 0.1)
	DebugMetrics._sample_hp(50.0, 100.0, 0.1)
	assert_float(DebugMetrics.get_hp_pct_min()).is_equal_approx(0.15, 0.001)

func test_snapshot_has_both_axes() -> void:
	var snap: Dictionary = DebugMetrics.snapshot()
	# 进攻轴 + 威胁轴关键键齐全
	for key in ["kills_total", "dmg_dealt_total", "dmg_taken_total", "healed_total",
			"danger_total", "hp", "hp_pct", "hp_pct_min", "level", "enemies_alive", "enemies_near"]:
		assert_bool(snap.has(key)).is_true()
