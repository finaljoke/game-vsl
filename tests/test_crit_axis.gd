# tests/test_crit_axis.gd
# 暴击轴：物理标签武器自动可暴 + crit_multiplier 纯函数回归。
extends GdUnitTestSuite

func test_crit_enabled_when_physical_tag() -> void:
	assert_bool(WeaponBase.crit_enabled(false, [&"physical"])).is_true()

func test_crit_enabled_when_can_crit_flag() -> void:
	assert_bool(WeaponBase.crit_enabled(true, [])).is_true()

func test_crit_disabled_for_nonphysical_without_flag() -> void:
	assert_bool(WeaponBase.crit_enabled(false, [&"fire"])).is_false()

func test_crit_multiplier_hits_on_low_roll() -> void:
	assert_float(WeaponBase.crit_multiplier(0.0, 0.5, 0.0, 2.0)).is_equal_approx(2.0, 0.0001)

func test_crit_multiplier_misses_on_high_roll() -> void:
	assert_float(WeaponBase.crit_multiplier(0.99, 0.5, 0.0, 2.0)).is_equal_approx(1.0, 0.0001)

func test_crit_multiplier_distance_bonus_stacks_on_chance() -> void:
	# 长弓矛盾修正：距离 bonus 叠加在全局 crit_chance 上(chance 0.2 + bonus 0.3 = 0.5 > roll 0.4)
	assert_float(WeaponBase.crit_multiplier(0.4, 0.2, 0.3, 2.0)).is_equal_approx(2.0, 0.0001)
