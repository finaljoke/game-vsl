extends GdUnitTestSuite
# Enemy.synergy_multiplier 纯静态乘区单测(无场景)。
# 状态键互斥(冻结只走碎裂、硬直只走处决)、引力增幅吃双通道、其余通道隔离。

func test_no_status_is_identity() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_frozen_direct_shatters() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_frozen_dot_does_not_shatter() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, true, false, 1.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_stun_direct_full_hp_execute_base() -> void:
	# 满血 hp_frac=1.0 → 1 + 0.2 + 0.8*0 = 1.2
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)

func test_stun_direct_near_death_execute_max() -> void:
	# 濒死 hp_frac=0.0 → 1 + 0.2 + 0.8*1 = 2.0
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.0)).is_equal_approx(2.0, 0.0001)

func test_stun_dot_does_not_execute() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, true, 0.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_amp_applies_to_direct() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_amp_applies_to_dot() -> void:
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DOT, false, false, 1.0, 0.25)).is_equal_approx(1.25, 0.0001)

func test_frozen_plus_amp_direct_stacks_multiplicatively() -> void:
	# 1.5 * 1.25 = 1.875
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 1.0, 0.25)).is_equal_approx(1.875, 0.0001)

func test_near_death_stun_plus_amp_direct_stacks() -> void:
	# 2.0 * 1.25 = 2.5
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 0.0, 0.25)).is_equal_approx(2.5, 0.0001)

func test_frozen_only_excludes_execute() -> void:
	# 仅冻结(非硬直)即便残血,只 ×1.5,不含处决项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, true, false, 0.0, 0.0)).is_equal_approx(1.5, 0.0001)

func test_stun_only_excludes_shatter() -> void:
	# 仅硬直(非冻结)满血,只 ×1.2,不含碎裂项
	assert_float(Enemy.synergy_multiplier(Enemy.DamageChannel.DIRECT, false, true, 1.0, 0.0)).is_equal_approx(1.2, 0.0001)
